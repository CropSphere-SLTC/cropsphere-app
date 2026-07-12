"""AI chatbot service — LLaMA 3 via Groq API with RAG.

New features:
- Model selection: "fast" (llama-3.1-8b-instant) or "accurate" (llama-3.3-70b-versatile)
- Language detection: auto-detects Sinhala, Tamil, English
- Prompt injection strategy: LLaMA instructed to respond in user's language directly
- Translation cache: repeated phrases served instantly from memory
"""

import hashlib
import logging
import os
import random
import re
import threading
import time

from html.parser import HTMLParser

from app.models.loader import model_loader
from app.models.schemas import ChatRequest, ChatResponse
from app.user.services.analytics_service import log_chat_interaction
from app.utils.firestore import audit_log

logger = logging.getLogger(__name__)

_MAX_LEN = 500
# Cosine-similarity floor for a chunk to count as "relevant".
# Empirically calibrated (2026-07-05, all-MiniLM-L6-v2, 69 chunks):
#   in-scope English questions score 0.68-0.85; the app's own suggested
#   follow-up "How can I improve my soil quality?" scores 0.29; junk/uncovered
#   queries ("weather on Mars" 0.22, "weather in Galle" 0.24) cluster below.
# 0.26 passes every legitimate English query while still blocking junk.
# KNOWN LIMIT: Sinhala/Tamil in-scope queries score 0.10-0.25 with this
# English-only encoder — no threshold can rescue them; needs a multilingual
# encoder + chunk re-embedding (tracked separately).
_MIN_RELEVANCE = 0.26
_TOP_K = 3  # number of chunks retrieved per query
# Ranking bonus per matching UI filter. District match = +0.15, crop match
# = +0.15, both = +0.30. Ranking signal ONLY — never affects the relevance
# floor or the confidence label, which use raw cosine scores.
_METADATA_BOOST = 0.15
# Sliding window: only the last N history messages are sent to Groq
# (3 user + 3 assistant turns). System prompt and RAG context are outside
# the window and never trimmed. The Pydantic schema still caps incoming
# history at 10; this trims further at the Groq boundary.
_MAX_HISTORY_MESSAGES = 6
# Weight of the current message vs. recent-history context in the blended
# retrieval embedding. Higher = topic switches win; lower = follow-ups
# inherit more context. 0.7 verified against both scenarios (2026-07-06).
_QUERY_WEIGHT = 0.7
_OUT_OF_SCOPE_REPLY = (
    "I don't have relevant agricultural data to answer that question. I can help "
    "with Sri Lankan crop recommendations, weather patterns, yield predictions, "
    "and market prices."
)
# Substring that identifies an LLM-level refusal in a generated reply. Must
# stay in sync with _OUT_OF_SCOPE_REPLY above and the refusal instruction in
# _system_prompt() — the model is told to emit exactly that text when the
# provided context can't answer the question.
_OUT_OF_SCOPE_MARKER = "I don't have relevant agricultural data"
# Substring that identifies a clarifying-question reply (see
# _build_clarification). Used only for loop prevention — never ask a
# clarifying question right after asking one. NOT added to
# _NON_TOPIC_SIGNATURES: a clarification isn't a refusal, so the user's
# original vague question must stay eligible as retrieval context.
_CLARIFICATION_MARKER = "Could you tell me which crop and district"
# Style/formatting rules, injected as their own system message by
# _build_messages() (after the RAG context, before history) rather than
# folded into _system_prompt(). Kept as a module-level constant — built
# once, not rebuilt per request — and separate from the safety-critical
# rules in _system_prompt() so the LLM is less likely to skip either set.
_FORMATTING_RULES = (
    "FORMATTING RULES:\n"
    "- Use simple language a farmer would understand. Say 'selling price "
    "at the farm' not 'farmgate price'. Say 'amount you can harvest' not "
    "'yield per hectare'. When you must use a technical term, explain it "
    "in parentheses the first time.\n"
    "- For multiple data points, use a dash (-) list. For single points, "
    "use a normal sentence.\n"
    "- Use thousands separators (20,169 not 20169).\n"
    "- When the user specifies their land unit (e.g. 'I have 2 acres'), "
    "answer using ONLY that unit. Do not show hectares or perches — the "
    "farmer told you what they use.\n"
    "- When the user asks a general question WITHOUT mentioning a land "
    "size (e.g. 'what is the yield for carrots in Badulla'), show all "
    "three units: kg/ha, kg/acre, kg/perch. Format: '20,169 kg/ha "
    "(8,162 kg/acre; 51 kg/perch)'.\n"
    "- Conversion factors: 1 ha = 2.471 acres; 1 acre = 160 perches; "
    "1 ha = 395.37 perches.\n"
    "- Only ask which unit if the user gives a number without any unit "
    "word.\n"
    "- After answering a yield or price question, add one short sentence "
    "offering to estimate earnings if the farmer tells you their land "
    "size. Example: 'Want me to estimate your earnings? Just tell me "
    "your land size in acres or perches.' Only offer this once per "
    "topic — if you already gave an earnings estimate or the farmer "
    "already asked about earnings, don't repeat the offer.\n"
    "- When the farmer mentioned their location or crop earlier in the "
    "conversation, reference it naturally in your answer. Say 'In your "
    "area of Jaffna' or 'For your carrots in Badulla' instead of just "
    "stating the district name. This makes the answer feel personal. "
    "Only do this when the context is clear from conversation history — "
    "don't assume a location the farmer never mentioned."
)
# ── Knowledge-level detection ─────────────────────────────────────────────────
# _detect_knowledge_level classifies how the farmer phrases a question so the
# LLM can match response depth: a beginner asking "what is yield?" needs plain
# language and practical framing; an expert asking to "compare inter-season
# yields across upcountry districts" wants concise, data-dense answers. The
# chosen instruction is injected by _build_messages() as its own system message
# (after _FORMATTING_RULES, so it overrides conflicting style rules) and logged
# to analytics.

# Per-message signals (Step 2). 2+ on a side wins that side; advanced breaks
# ties (advanced phrasing is far more diagnostic of expertise, and we avoid
# over-detecting "beginner").
_BEGINNER_DEFINITION_PATTERNS = (
    "what is",
    "what's",
    "what does",
    "what do you mean",
    "meaning of",
    "define ",
    "wat is",
)
_BEGINNER_SIMPLE_PATTERNS = (
    "tell me about",
    "what should i do",
    "what can i",
    "help me",
)
# Text-speak / broken English — matched as whole tokens.
_BEGINNER_INFORMAL_TOKENS = frozenset(
    {"wat", "pls", "plz", "hw", "gimme", "wanna", "dunno", "thx"}
)
_ADVANCED_TERMS = (
    "inter-season",
    "per-hectare",
    "per hectare",
    "cultivation",
    "farmgate",
    "soil ph",
)
_ADVANCED_COMPARISON_PATTERNS = (
    "compare",
    "comparison",
    "difference between",
    "which is better",
    "better than",
    "versus",
    " vs ",
)
_ADVANCED_DATA_PATTERNS = (
    "kg/",
    "/kg",
    "/ha",
    "/acre",
    "/perch",
    "percentage",
    "percent",
)
# Named growing seasons — a beginner "no names mentioned" negative signal and
# an advanced positive signal. Whole-token match ("inter" from "inter-season",
# never inside "interesting").
_SEASON_NAME_TOKENS = frozenset({"maha", "yala", "inter"})
# Topic words that, when 2+ appear joined by "and", flag a multi-part question.
_KNOWLEDGE_TOPIC_KEYWORDS = (
    "yield",
    "price",
    "season",
    "harvest",
    "earn",
    "cost",
    "demand",
    "rainfall",
    "weather",
    "fertilizer",
    "fertiliser",
)
_LEVEL_INSTRUCTIONS = {
    "beginner": (
        "The farmer is a beginner. Follow these rules:\n"
        "- Use the simplest possible language\n"
        "- Define every farming term when you first use it\n"
        "- Give practical advice, not just numbers\n"
        "- After giving data, add one sentence explaining what it means "
        "practically (e.g. 'This means you can fill about 160 bags of 50kg "
        "each from one hectare')\n"
        "- Keep answers short — 3-4 sentences maximum\n"
        "- Don't show all three units — show only acres (most common for "
        "small farmers)"
    ),
    "advanced": (
        "The farmer is experienced. Follow these rules:\n"
        "- Be concise and data-focused\n"
        "- Skip basic term explanations\n"
        "- Include comparative data when available\n"
        "- Show all three units (ha, acres, perches)\n"
        "- Use technical terms freely (yield, farmgate, cultivation)\n"
        "- Longer, more detailed answers are fine"
    ),
    "intermediate": (
        "The farmer has some farming knowledge. Follow these rules:\n"
        "- Explain technical terms only the first time\n"
        "- Balance data with practical advice\n"
        "- Show all three units (ha, acres, perches)\n"
        "- Medium-length answers — enough detail without overwhelming"
    ),
}
# Client-safe error messages for streaming failures. Technical detail
# (status codes, exception types) is logged server-side only.
_STREAM_ERROR_MESSAGES = {
    "rate_limit": (
        "The AI service is busy right now. Please wait a moment and try again."
    ),
    "server_error": "The AI service is temporarily unavailable. Try again shortly.",
    "stream_interrupted": "Response was interrupted.",
    "empty_response": "No response received. Try rephrasing your question.",
}
# Substrings identifying assistant replies that carry no crop/district topic
# (refusals in any template shape, and capability summaries). Consumed by the
# retrieval-context history filter so a refused/administrative turn never
# steers the next question's retrieval. MUST stay in sync with the templates
# in _build_refusal() and _capability_reply().
_NON_TOPIC_SIGNATURES = (
    _OUT_OF_SCOPE_MARKER,  # canned LLM-side refusal
    "but not for that district",  # near-miss refusal: crop covered
    "but not that crop",  # near-miss refusal: district covered
    "outside my dataset",  # generic refusal template 1
    "I don't have data on that yet",  # generic refusal template 2
    "beyond my data for now",  # generic refusal template 3
    "I currently have data on",  # capability summary
)
# Case-insensitive patterns that route a message to the capability summary
# (no retrieval, no Groq). Deliberately NOT the bare "what can you" — that
# would hijack real questions like "what can you tell me about carrots".
_CAPABILITY_PATTERNS = (
    "what crops",
    "which crops",
    "what districts",
    "which districts",
    "what can you do",
    "what can you help",
    "what do you cover",
)
# Phrases that identify the bot's own clarifying question about land units
# ("Is that X acres, X hectares, or X perches?" — see _system_prompt) and the
# unit words that identify a bare follow-up reply to it (e.g. "perches").
_UNIT_CLARIFICATION_PHRASE = "is that"
_UNIT_KEYWORDS = ("acre", "hectare", "perch", "ha")
# Marks the bot's earnings-offer line from _FORMATTING_RULES ("Want me to
# estimate your earnings? Just tell me your land size...") — the other
# trigger (besides the clarifying question above) for rebuilding a reply.
_EARNINGS_OFFER_PHRASE = "tell me your land size"
# Phrases that ask about every crop at once rather than one specific crop —
# top-k retrieval only surfaces 2-3 crops for these, so the full list is
# injected separately (see _build_messages).
_ALL_CROPS_PATTERNS = ("all crops", "every crop", "all the crops")
# Combo patterns: verb + any qualifier — requires BOTH so a real question
# like "explain carrot yield" (has agricultural content) doesn't match.
_REFORMULATION_PATTERNS = (
    ("show", ("simply", "simpler", "simple")),
    ("explain", ("again", "clearly", "better", "more")),
)
# Standalone phrases that always mean "rephrase/simplify the previous
# answer", regardless of what else is in the message.
_REFORMULATION_PHRASES = (
    "rephrase",
    "reword",
    "say it again",
    "not clear",
    "don't understand",
    "confused",
    "what do you mean",
    "what does that mean",
    "simplify",
    "make it simpler",
    "in simple words",
    "in easy words",
)
# Standalone keywords that specifically ask for calculation steps rather
# than a simpler rewrite — used by _reformulation_type to pick which
# instruction _build_reformulation_messages sends to Groq. Broader than
# exact phrase matching: e.g. "explain the formula" now qualifies too.
_MATH_REFORMULATION_PHRASES = (
    "math",
    "calculation",
    "formula",
    "step by step",
    "break it down",
    "break down",
    "how did you calculate",
)
# On-request formal/scientific notation instead of the step-by-step
# breakdown — negative exponents and center-dot notation, the style
# preferred in advanced science/engineering. Checked BEFORE
# _MATH_REFORMULATION_PHRASES in _reformulation_type, since phrases like
# "standard mathematical format" also contain "math" and would otherwise
# be misclassified as the regular step-by-step type.
_FORMAL_MATH_PHRASES = (
    "standard format",
    "scientific format",
    "formal notation",
    "standard math",
    "standard mathematical format",
    "mathematical format",
)
# Words/phrases that signal a farming-related question even without a
# named crop or district — distinguishes "how much can I earn?" (worth a
# clarifying question) from an unrelated query that also scored low
# (weather on Mars, a joke — still refused as out of scope).
_AGRICULTURAL_INTENT_PHRASES = (
    "earn",
    "income",
    "money",
    "profit",
    "revenue",
    "plant",
    "grow",
    "cultivate",
    "harvest",
    "yield",
    "crop",
    "season",
    "price",
    "cost",
    "which crop",
    "best crop",
    "recommend",
)
# Phrases that signal the farmer is introducing themselves/their context
# ("I'm from Jaffna", "I'm growing groundnut in Hambantota") rather than
# asking a question — the bot should acknowledge and wait, not run
# retrieval/Groq on a statement with nothing to answer.
_CONTEXT_STATEMENT_PHRASES = (
    "i'm from",
    "i am from",
    "i live in",
    "i'm growing",
    "i am growing",
    "i grow",
    "i'm a farmer",
    "i am a farmer",
    "my farm is in",
    "my land is in",
    "i have land in",
    "i have a farm in",
)
# Keywords used by _question_type to classify what kind of question was
# just answered, so _smart_followups can suggest a natural next step.
# "earn"/"money" are their own bucket, not folded into price, so the
# EARNINGS follow-up set below is actually reachable.
_YIELD_TYPE_KEYWORDS = ("yield", "harvest", "grow")
_EARNINGS_TYPE_KEYWORDS = ("earn", "money")
_PRICE_TYPE_KEYWORDS = ("price", "cost", "sell")
_SEASON_TYPE_KEYWORDS = ("season", "plant", "when")
_capabilities_cache: dict | None = None
# Common Sri Lankan crops/districts NOT in our dataset. Lets a near-miss be
# caught proactively even when retrieval finds semantically-similar covered
# chunks (e.g. "carrot price in Galle" retrieves carrot chunks for other
# districts). Finite by design — unlisted unknowns still fall through to the
# normal retrieval/grounding path. Matched by whole-word token, never
# substring ("rice" must not hit inside "price"; "tea" not inside "instead").
_UNCOVERED_DISTRICTS = frozenset(
    {
        "colombo",
        "gampaha",
        "kalutara",
        "kandy",
        "matale",
        "galle",
        "matara",
        "kurunegala",
        "puttalam",
        "kegalle",
        "ratnapura",
        "trincomalee",
        "polonnaruwa",
        "vavuniya",
        "mannar",
        "mullaitivu",
        "kilinochchi",
    }
)
_UNCOVERED_CROPS = frozenset(
    {
        "rice",
        "paddy",
        "tea",
        "rubber",
        "coconut",
        "banana",
        "mango",
        "onion",
        "potato",
        "cabbage",
        "tomato",
        "chili",
        "chilli",
        "pepper",
    }
)
_encoder = None  # SentenceTransformer singleton — loaded once on first chat request
# Baked into the image at build time (see Dockerfile); loaded fully offline so
# no HuggingFace download ever happens in the request path. Overridable via env.
_HF_CACHE = os.environ.get("SENTENCE_TRANSFORMERS_HOME", "/app/hf_cache")

# Groq model mapping
_GROQ_MODELS = {
    "fast": "llama-3.1-8b-instant",  # 3–5 seconds
    "accurate": "llama-3.3-70b-versatile",  # 15–25 seconds
}


def chat(req: ChatRequest, settings) -> ChatResponse:
    """Process a farmer chat message and return an AI response.

    Security controls (shift-left):
    - HTML tags stripped before any processing.
    - Message truncated at 500 chars even if Pydantic somehow passed a longer one.
    - Input hash logged to Firestore for prompt-injection monitoring.
    - Stack traces never exposed to the client.

    Language features:
    - Auto-detects Sinhala, Tamil, English from input text.
    - Injects language instruction into LLaMA system prompt.
    - LLaMA responds in the user's language directly (no input translation needed).
    - Translation cache serves repeated phrases instantly.

    Inputs: ChatRequest (Pydantic-validated), Settings instance.
    Outputs: ChatResponse with reply, sources, and follow-up suggestions.
    Security assumption: user_id verified by JWT middleware before this is called.
    """
    start = time.monotonic()
    clean = _strip_html(req.message)[:_MAX_LEN]

    _safe_audit(req.user_id, clean)

    # Bare land-unit reply to the bot's own clarifying question (e.g. the
    # user just replies "perches") — rebuilt into a real query for retrieval
    # only, before any capability/gazetteer check or retrieval itself runs.
    # See _expand_clarifying_reply for why this is needed.
    retrieval_query = _expand_clarifying_reply(clean, req.conversation_history)

    # ── Language detection ──────────────────────────────────────────────────
    # If user specified language explicitly, use it; otherwise auto-detect

    # ── Model selection ─────────────────────────────────────────────────────
    groq_model = _GROQ_MODELS.get(req.model, _GROQ_MODELS["accurate"])
    logger.info(f"Using model: {groq_model} (requested: {req.model})")

    try:
        # Introductory/context-setting statement ("I'm from Jaffna", "I'm
        # growing groundnut in Hambantota") — the farmer is providing
        # context, not asking a question. Acknowledge and prompt for a
        # real question instead of running retrieval/Groq on a statement
        # with nothing to answer. Runs before every other check, including
        # the gazetteer, so naming an uncovered district here is just
        # small talk, not a refusal.
        if _is_context_statement(clean):
            reply, cq_followups = _build_context_ack(clean)
            _emit_analytics(req, clean, "context_ack", "High confidence", None, start)
            return ChatResponse(
                reply=reply,
                sources_used=[],
                suggested_followups=cq_followups,
                confidence="High confidence",
            )

        # Capability question ("what crops do you cover?") — answered from
        # our own dataset metadata. No retrieval, no Groq; deterministic and
        # always in scope. Runs after audit (so it is logged) but before
        # retrieval, so it never pollutes the retrieval path.
        if _is_capability_question(clean):
            reply, followups = _capability_reply()
            _emit_analytics(req, clean, "capability", "High confidence", None, start)
            return ChatResponse(
                reply=reply,
                sources_used=[],
                suggested_followups=followups,
                confidence="High confidence",
            )

        # Explicit near-miss: the user named a crop/district we don't cover
        # (gazetteer match). Refuse with a friendly pointer before retrieval
        # or Groq — retrieval would otherwise surface semantically-similar
        # chunks for the wrong location and answer from them.
        miss = _explicit_miss(clean)
        if miss:
            _emit_analytics(
                req,
                clean,
                "near_miss",
                "Out of scope",
                None,
                start,
                near_miss_type=miss[0],
            )
            return ChatResponse(
                reply=_build_refusal(clean, near=miss),
                sources_used=[],
                suggested_followups=_refusal_followups(clean, near=miss),
                confidence="Out of scope",
            )

        # Reformulation request ("show them simply", "explain that again")
        # — rewrite the previous answer instead of running retrieval. These
        # carry no agricultural keywords, so retrieval would otherwise come
        # back empty and get wrongly refused as out of scope.
        if _is_reformulation_request(clean):
            previous_reply = _last_assistant_reply(req.conversation_history)
            if previous_reply:
                from groq import Groq  # type: ignore

                client = Groq(api_key=settings.GROQ_API_KEY)
                rtype = _reformulation_type(clean)
                messages = _build_reformulation_messages(
                    _system_prompt(req), previous_reply, req, clean, rtype
                )
                response = client.chat.completions.create(
                    model=groq_model,
                    messages=messages,
                    max_tokens=512,
                    temperature=0.7,
                )
                _emit_analytics(
                    req, clean, "reformulation", "Moderate confidence", None, start
                )
                return ChatResponse(
                    reply=response.choices[0].message.content,
                    sources_used=[],
                    suggested_followups=_default_followups(req),
                    confidence="Moderate confidence",
                )
            # No previous assistant turn to reformulate — fall through to
            # the normal retrieval path below.

        # RAG retrieval always uses English-normalised query for best results.
        # The UI's optional district/crop filters boost matching chunks in
        # the ranking (never in the relevance floor or confidence label).
        context = _rag_context(
            retrieval_query,
            district=req.district.value if req.district else "",
            crop=req.crop.value if req.crop else "",
            history=req.conversation_history,
        )
        confidence = _confidence_label(context)

        # Vague-but-agricultural query ("how much can I earn?") — ask a
        # clarifying question instead of refusing as out of scope. Runs
        # BEFORE the grounding guard so a real, answerable question never
        # hits the flat refusal below just because it named no crop or
        # district. Non-agricultural queries (Mars, jokes) still fall
        # through to that refusal, since _has_agricultural_intent is False
        # for those.
        if _is_vague_agricultural_query(clean, context, req.conversation_history):
            reply, cq_followups = _build_clarification(
                clean, context, req.conversation_history
            )
            _emit_analytics(
                req, clean, "clarification", "Moderate confidence", context, start
            )
            return ChatResponse(
                reply=reply,
                sources_used=[],
                suggested_followups=cq_followups,
                confidence="Moderate confidence",
            )

        # Grounding guard (primary defence): if nothing in our agricultural
        # dataset matched above the relevance floor, refuse deterministically
        # with a friendly, dataset-aware message. The query never reaches the
        # LLM, so it cannot answer from its own general knowledge (e.g.
        # "what's the weather on Mars").
        if not context["chunks"]:
            _emit_analytics(req, clean, "refusal", confidence, context, start)
            return ChatResponse(
                reply=_build_refusal(clean),
                sources_used=[],
                suggested_followups=_refusal_followups(clean),
                confidence=confidence,
            )

        # Ambiguous query: retrieval found something, but it's a weak,
        # multi-topic match and the user never named a crop/district — ask
        # a clarifying question instead of guessing. Deterministic
        # template; never calls Groq; not a refusal (doesn't set "Out of
        # scope" and stays eligible as retrieval context on the next turn).
        if _is_ambiguous_query(clean, context, req.conversation_history):
            reply, cq_followups = _build_clarification(
                clean, context, req.conversation_history
            )
            _emit_analytics(
                req, clean, "clarification", "Moderate confidence", context, start
            )
            return ChatResponse(
                reply=reply,
                sources_used=[],
                suggested_followups=cq_followups,
                confidence="Moderate confidence",
            )

        from groq import Groq  # type: ignore

        client = Groq(api_key=settings.GROQ_API_KEY)

        # Build messages with language instruction injected into system prompt
        messages = _build_messages(_system_prompt(req), context, req, clean)

        response = client.chat.completions.create(
            model=groq_model,
            messages=messages,
            max_tokens=512,
            temperature=0.7,
        )
        reply = response.choices[0].message.content

        # LLM-level refusal: retrieval cleared the relevance floor but the
        # chunks didn't actually answer the question (e.g. rice query,
        # carrot chunks), so the model used the canned refusal. Override
        # the retrieval-derived confidence and drop the unhelpful sources
        # so the XAI badge and chips stay truthful.
        if reply and _OUT_OF_SCOPE_MARKER in reply:
            confidence = "Out of scope"
            context["sources"] = []

        # Cache the reply for future repeated questions

        _emit_analytics(req, clean, "answer", confidence, context, start)
        return ChatResponse(
            reply=reply,
            sources_used=context["sources"],
            suggested_followups=_smart_followups(context, clean, req),
            confidence=confidence,
        )
    except Exception as exc:
        logger.error("Chatbot error user=%s: %s", req.user_id, type(exc).__name__)
        raise RuntimeError("Chatbot unavailable") from exc


def chat_stream(req: ChatRequest, settings, verified_uid: str):
    """Generator: stream a chat reply as typed events for SSE delivery.

    Reuses chat()'s exact pipeline (sanitise -> audit -> RAG retrieval with
    district/crop filters and metadata boost -> grounding guard -> Groq),
    but calls Groq with stream=True. Yields event dicts:
      {"type": "text", "content": str}   — reply deltas as they arrive
      {"type": "metadata", "confidence", "sources", "suggested_followups",
       "conversation_id"}                — after the stream completes
      {"type": "error", "code", "message"} — client-safe failure marker
    Confidence and sources come from retrieval, so they are computed before
    streaming starts. The full assembled reply is persisted to Firestore
    chat history only AFTER the stream completes; interrupted replies are
    never persisted. This generator never raises — all failures become
    error events.

    Inputs: ChatRequest (Pydantic-validated), Settings, verified_uid.
    Outputs: iterator of event dicts (see above).
    Security assumption: verified_uid is the JWT-verified user id supplied
    by the router; it keys history persistence exactly as the non-streaming
    endpoint does. Technical error detail is logged server-side only.
    """
    start = time.monotonic()
    clean = _strip_html(req.message)[:_MAX_LEN]
    _safe_audit(req.user_id, clean)
    groq_model = _GROQ_MODELS.get(req.model, _GROQ_MODELS["accurate"])

    # Bare land-unit reply to the bot's own clarifying question — rebuilt
    # into a real query for retrieval only. See _expand_clarifying_reply.
    retrieval_query = _expand_clarifying_reply(clean, req.conversation_history)

    def _persist(full_reply: str) -> str:
        """Save the completed turn; failure logs but never breaks the stream."""
        try:
            from app.user.services.chat_history_service import persist_chat_turn

            return persist_chat_turn(
                verified_uid, req.conversation_id, req.message, full_reply
            )
        except Exception as exc:
            logger.warning("Stream persistence failed uid=%s: %s", verified_uid, exc)
            return ""

    # Introductory/context-setting statement — same handling as chat(),
    # adapted to streaming. See chat() for why this runs first.
    if _is_context_statement(clean):
        reply, cq_followups = _build_context_ack(clean)
        yield {"type": "text", "content": reply}
        conv_id = _persist(reply)
        logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(reply))
        yield {
            "type": "metadata",
            "confidence": "High confidence",
            "sources": [],
            "suggested_followups": cq_followups,
            "conversation_id": conv_id,
        }
        _emit_analytics(req, clean, "context_ack", "High confidence", None, start)
        return

    # Capability question — same short-circuit as chat(); no retrieval, no
    # Groq. Runs after audit (logged) but before retrieval. It is persisted
    # to history and later filtered out of retrieval context by
    # _is_non_topic_reply (its text contains "I currently have data on").
    if _is_capability_question(clean):
        reply, cap_followups = _capability_reply()
        yield {"type": "text", "content": reply}
        conv_id = _persist(reply)
        logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(reply))
        yield {
            "type": "metadata",
            "confidence": "High confidence",
            "sources": [],
            "suggested_followups": cap_followups,
            "conversation_id": conv_id,
        }
        _emit_analytics(req, clean, "capability", "High confidence", None, start)
        return

    # Explicit near-miss — same short-circuit as chat(); no retrieval, no Groq.
    miss = _explicit_miss(clean)
    if miss:
        reply = _build_refusal(clean, near=miss)
        yield {"type": "text", "content": reply}
        conv_id = _persist(reply)
        logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(reply))
        yield {
            "type": "metadata",
            "confidence": "Out of scope",
            "sources": [],
            "suggested_followups": _refusal_followups(clean, near=miss),
            "conversation_id": conv_id,
        }
        _emit_analytics(
            req,
            clean,
            "near_miss",
            "Out of scope",
            None,
            start,
            near_miss_type=miss[0],
        )
        return

    # Reformulation request — same rewrite-the-previous-answer handling as
    # chat(), adapted to streaming. See chat() for why this exists.
    if _is_reformulation_request(clean):
        previous_reply = _last_assistant_reply(req.conversation_history)
        if previous_reply:
            reform_parts: list = []
            try:
                from groq import Groq  # type: ignore

                client = Groq(api_key=settings.GROQ_API_KEY)
                rtype = _reformulation_type(clean)
                messages = _build_reformulation_messages(
                    _system_prompt(req), previous_reply, req, clean, rtype
                )
                stream = client.chat.completions.create(
                    model=groq_model,
                    messages=messages,
                    max_tokens=512,
                    temperature=0.7,
                    stream=True,
                )
                for chunk in stream:
                    delta = chunk.choices[0].delta.content if chunk.choices else None
                    if delta:
                        reform_parts.append(delta)
                        yield {"type": "text", "content": delta}
            except Exception as exc:
                code = _stream_error_code(exc, has_partial=bool(reform_parts))
                logger.error(
                    "Chat stream error user=%s code=%s: %s",
                    req.user_id,
                    code,
                    type(exc).__name__,
                )
                yield {
                    "type": "error",
                    "code": code,
                    "message": _STREAM_ERROR_MESSAGES[code],
                }
                return

            full = "".join(reform_parts)
            if not full.strip():
                yield {
                    "type": "error",
                    "code": "empty_response",
                    "message": _STREAM_ERROR_MESSAGES["empty_response"],
                }
                return

            conv_id = _persist(full)
            logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(full))
            yield {
                "type": "metadata",
                "confidence": "Moderate confidence",
                "sources": [],
                "suggested_followups": _default_followups(req),
                "conversation_id": conv_id,
            }
            _emit_analytics(
                req, clean, "reformulation", "Moderate confidence", None, start
            )
            return
        # No previous assistant turn to reformulate — fall through to the
        # normal retrieval path below.

    context = _rag_context(
        retrieval_query,
        district=req.district.value if req.district else "",
        crop=req.crop.value if req.crop else "",
        history=req.conversation_history,
    )
    confidence = _confidence_label(context)
    followups = _smart_followups(context, clean, req)

    def _metadata(conv_id: str) -> dict:
        return {
            "type": "metadata",
            "confidence": confidence,
            "sources": context["sources"],
            "suggested_followups": followups,
            "conversation_id": conv_id,
        }

    # Vague-but-agricultural query — same clarifying-question handling as
    # chat(), adapted to streaming, runs before the grounding guard. See
    # chat() for why this exists.
    if _is_vague_agricultural_query(clean, context, req.conversation_history):
        reply, cq_followups = _build_clarification(
            clean, context, req.conversation_history
        )
        followups = cq_followups
        yield {"type": "text", "content": reply}
        conv_id = _persist(reply)
        logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(reply))
        confidence = "Moderate confidence"
        yield _metadata(conv_id)
        _emit_analytics(
            req, clean, "clarification", "Moderate confidence", context, start
        )
        return

    # Grounding guard — same friendly, dataset-aware refusal as chat(), no
    # Groq call. Reassigning followups here is picked up by the _metadata
    # closure below.
    if not context["chunks"]:
        reply = _build_refusal(clean)
        followups = _refusal_followups(clean)
        yield {"type": "text", "content": reply}
        conv_id = _persist(reply)
        logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(reply))
        yield _metadata(conv_id)
        _emit_analytics(req, clean, "refusal", confidence, context, start)
        return

    # Ambiguous query — same clarifying-question handling as chat(),
    # adapted to streaming. See chat() for why this exists.
    if _is_ambiguous_query(clean, context, req.conversation_history):
        reply, cq_followups = _build_clarification(
            clean, context, req.conversation_history
        )
        followups = cq_followups
        yield {"type": "text", "content": reply}
        conv_id = _persist(reply)
        logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(reply))
        confidence = "Moderate confidence"
        yield _metadata(conv_id)
        _emit_analytics(
            req, clean, "clarification", "Moderate confidence", context, start
        )
        return

    parts: list = []
    try:
        from groq import Groq  # type: ignore

        client = Groq(api_key=settings.GROQ_API_KEY)
        messages = _build_messages(_system_prompt(req), context, req, clean)
        stream = client.chat.completions.create(
            model=groq_model,
            messages=messages,
            max_tokens=512,
            temperature=0.7,
            stream=True,
        )
        for chunk in stream:
            delta = chunk.choices[0].delta.content if chunk.choices else None
            if delta:
                parts.append(delta)
                yield {"type": "text", "content": delta}
    except Exception as exc:
        code = _stream_error_code(exc, has_partial=bool(parts))
        logger.error(
            "Chat stream error user=%s code=%s: %s",
            req.user_id,
            code,
            type(exc).__name__,
        )
        yield {
            "type": "error",
            "code": code,
            "message": _STREAM_ERROR_MESSAGES[code],
        }
        return

    full = "".join(parts)
    if not full.strip():
        yield {
            "type": "error",
            "code": "empty_response",
            "message": _STREAM_ERROR_MESSAGES["empty_response"],
        }
        return

    # LLM-level refusal — same override as chat(); see comment there. The
    # metadata event is emitted after the text, so the corrected label and
    # emptied sources are what the frontend renders.
    if _OUT_OF_SCOPE_MARKER in full:
        confidence = "Out of scope"
        context["sources"] = []

    conv_id = _persist(full)
    logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(full))
    yield _metadata(conv_id)
    _emit_analytics(req, clean, "answer", confidence, context, start)


def _stream_error_code(exc: Exception, has_partial: bool) -> str:
    """Map a Groq/streaming exception to a client-safe error code.

    Inputs: exc (the caught exception), has_partial (True when reply text
    already streamed before the failure).
    Outputs: one of "stream_interrupted", "rate_limit", "server_error".
    Security assumption: the returned code is safe to expose to clients;
    exception detail must be logged separately, never returned.
    """
    if has_partial:
        return "stream_interrupted"
    try:
        from groq import RateLimitError  # type: ignore

        if isinstance(exc, RateLimitError):
            return "rate_limit"
    except ImportError:
        # groq package not installed in this environment (e.g. some test
        # runs) — fall through to the generic server_error classification.
        logger.debug("groq.RateLimitError unavailable — skipping rate-limit check")
    # Groq 5xx / auth / connection problems are all server-side issues
    # from the farmer's perspective.
    return "server_error"


# ── Helpers ───────────────────────────────────────────────────────────────────


def _get_encoder():
    """Return the SentenceTransformer encoder, loading it once and caching it.

    The model is baked into the image (Dockerfile) and loaded fully offline
    from _HF_CACHE — no network fetch in the request path. Forcing offline
    means a missing/corrupt cache raises here (caught by the caller) instead
    of silently blocking the worker on a stalled HuggingFace download.
    """
    global _encoder
    if _encoder is None:
        # Belt-and-braces in case the image was built without the offline ENVs.
        # HF_HUB_OFFLINE avoids any network in the request path; disabling Xet
        # avoids the hf_xet "Permission denied" hang if a download does occur.
        os.environ.setdefault("HF_HUB_OFFLINE", "1")
        os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
        os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
        from sentence_transformers import SentenceTransformer  # type: ignore

        os.makedirs(_HF_CACHE, exist_ok=True)
        _encoder = SentenceTransformer("all-MiniLM-L6-v2", cache_folder=_HF_CACHE)
    return _encoder


class _HTMLStripper(HTMLParser):
    """Remove HTML tags to mitigate prompt injection via markup."""

    def __init__(self):
        super().__init__()
        self._parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self._parts.append(data)

    def get_text(self) -> str:
        return "".join(self._parts).strip()


def _strip_html(text: str) -> str:
    """Remove HTML tags to mitigate prompt injection via markup."""
    stripper = _HTMLStripper()
    stripper.feed(text)
    return stripper.get_text()


def _system_prompt(req: ChatRequest) -> str:
    """Build the core system prompt: identity, grounding, refusal, reasoning,
    ambiguity-priority, and no-calculations rules. Kept short and numbered so
    the LLM doesn't skip rules buried mid-paragraph. Style/formatting rules
    live separately in _FORMATTING_RULES, injected by _build_messages()."""
    district = f" The farmer is in {req.district.value}." if req.district else ""
    crop = f" They are asking about {req.crop.value}." if req.crop else ""

    return (
        "You are CropSphere, an agricultural assistant for Sri Lankan farmers."
        f"{district}{crop}\n\n"
        "RULES (in priority order):\n"
        "1. Answer ONLY from the 'Relevant context' provided. Never use "
        "general knowledge. Never guess.\n"
        f'2. If no context is provided, reply with exactly: "{_OUT_OF_SCOPE_REPLY}"\n'
        "3. Start every answer with one short sentence: 'Reasoning: ' that "
        "names the SPECIFIC data you used (e.g. the source document, "
        'district, season, or crop) — never vague phrases like "based on '
        'similar regions". Then give your final answer on a new line.\n'
        "4. When multiple sources are provided and the question is "
        "ambiguous, prioritize the most recently discussed topic. If the "
        "user references an earlier topic explicitly (e.g. 'go back to the "
        "Badulla question', 'about the carrots we discussed first'), use "
        "that referenced topic instead.\n"
        "5. Show ONLY the final result the farmer needs — never show "
        "intermediate steps, conversion math, per-hectare breakdowns, or "
        "formulas. This especially applies to earnings calculations: say "
        "'You can earn around 522,368 LKR per acre' NOT '8,162 kg/acre * "
        "64 LKR/kg = 522,368 LKR/acre'. Only show calculation steps if "
        "the user explicitly asks with words like 'how', 'calculate', "
        "'show me the math', or 'explain the calculation'."
    )


def _expand_clarifying_reply(message: str, history: list) -> str:
    """Rebuild a land-unit reply into a retrieval query with real content.

    When the bot's last turn asked the land-unit clarifying question ("Is
    that X acres, X hectares, or X perches?" — see _system_prompt) or made
    the earnings-offer ("Want me to estimate your earnings? Just tell me
    your land size..." — see _FORMATTING_RULES), and the user's reply
    contains a unit word — whether that's just "perches" or a longer "10
    perches. What yield can I expect?" — the reply may still have too
    little agricultural content on its own and fail the RAG relevance
    floor, so retrieval wrongly comes back empty and the grounding guard
    refuses it as out of scope. Detect that pattern and prepend the user's
    preceding question so retrieval has real signal to match against,
    regardless of how long the current reply is.

    Only the retrieval query is affected — the message audited, checked for
    capability/near-miss, and sent to Groq as the "user" turn is untouched;
    Groq already sees the full conversation history so it doesn't need the
    rebuilt text.

    Inputs: message (sanitised current user text); history (full
    ConversationTurn list from the request, most recent turn last).
    Outputs: rebuilt query string, or the original message unchanged when
    the clarifying-reply pattern doesn't match.
    """
    if not history:
        return message
    msg_lower = message.lower()
    if not any(kw in msg_lower for kw in _UNIT_KEYWORDS):
        return message

    last_turn = history[-1]
    if last_turn.role != "assistant":
        return message
    last_lower = last_turn.content.lower()
    if _UNIT_CLARIFICATION_PHRASE in last_lower:
        if not any(kw in last_lower for kw in _UNIT_KEYWORDS):
            return message
    elif _EARNINGS_OFFER_PHRASE not in last_lower:
        return message

    # The user turn the clarifying question / earnings offer was responding to.
    for turn in reversed(history[:-1]):
        if turn.role == "user":
            return f"{turn.content} {message}"
    return message


def _is_reformulation_request(message: str) -> bool:
    """True when the message asks the bot to rephrase, simplify, or
    re-explain its PREVIOUS answer — not a new agricultural question.
    Combo patterns (e.g. "explain" + "again") require both words so a real
    question like "explain carrot yield" is never caught here.

    Checks both phrase lists — _REFORMULATION_PHRASES (simplify-style) and
    _MATH_REFORMULATION_PHRASES (math-style) — so this gate never rejects
    a message that _reformulation_type would later classify as "math". A
    single source of truth per category avoids the two lists drifting
    apart, which is exactly what let "show me math" / "break down" fall
    through to a flat refusal instead of the math reformulation path.
    """
    msg = message.lower()
    if any(p in msg for p in _REFORMULATION_PHRASES):
        return True
    if any(p in msg for p in _MATH_REFORMULATION_PHRASES):
        return True
    if any(p in msg for p in _FORMAL_MATH_PHRASES):
        return True
    for verb, qualifiers in _REFORMULATION_PATTERNS:
        if verb in msg and any(q in msg for q in qualifiers):
            return True
    return False


def _reformulation_type(message: str) -> str:
    """Which kind of reformulation this is — "formal_math" (compact
    scientific-notation equation), "math" (step-by-step calculation), or
    "simplify" (rewrite in simpler terms). Only meaningful when
    _is_reformulation_request(message) is already True.
    """
    msg = message.lower()
    if any(p in msg for p in _FORMAL_MATH_PHRASES):
        return "formal_math"
    if any(p in msg for p in _MATH_REFORMULATION_PHRASES):
        return "math"
    return "simplify"


def _last_assistant_reply(history: list) -> str | None:
    """Most recent assistant turn in the conversation, or None."""
    for turn in reversed(history or []):
        if turn.role == "assistant":
            return turn.content
    return None


def _is_previous_clarification(history: list | None) -> bool:
    """True when the bot's last turn was itself a clarifying question —
    prevents asking twice in a row."""
    if not history:
        return False
    last = history[-1]
    return last.role == "assistant" and _CLARIFICATION_MARKER in last.content


def _recent_topic(message: str, history: list | None, caps: dict) -> tuple | None:
    """Most recent (crop, district) pair the user discussed, from the last
    user message whose reply was NOT a refusal/capability summary — mirrors
    the recency filter _rag_context uses for its own context blend.
    """
    turns = history or []
    for i in range(len(turns) - 1, -1, -1):
        turn = turns[i]
        if turn.role != "user":
            continue
        next_turn = turns[i + 1] if i + 1 < len(turns) else None
        if next_turn and _is_non_topic_reply(next_turn.content):
            continue
        msg = turn.content.lower()
        crop = next((c for c in caps["crops"] if c.lower() in msg), None)
        district = next((d for d in caps["districts"] if d.lower() in msg), None)
        if crop and district:
            return (crop, district)
    return None


def _chunk_topics(context: dict) -> list:
    """Distinct (crop, district) pairs from the retrieved chunks, in
    ranked order, deduplicated."""
    seen: list = []
    for ch in context["chunks"]:
        crop, district = ch.get("crop"), ch.get("district")
        if crop and district and (crop, district) not in seen:
            seen.append((crop, district))
    return seen


def _has_agricultural_intent(message: str) -> bool:
    """True when the message is clearly about farming (earnings, planting,
    yields, crop choice, etc.) even without naming a specific crop or
    district — as opposed to an unrelated question (weather on Mars, a
    joke) that just happens to also score low on retrieval.
    """
    msg = message.lower()
    return any(p in msg for p in _AGRICULTURAL_INTENT_PHRASES)


def _is_vague_agricultural_query(
    message: str, context: dict, history: list | None
) -> bool:
    """True when a clearly-agricultural question can't be pinned to a
    crop/district by retrieval — either nothing passed the relevance floor
    at all, or what did is a weak, multi-topic match. Runs BEFORE the
    grounding guard, so a real question like "how much can I earn?" gets a
    clarifying question instead of a flat refusal.

    Gated on _has_agricultural_intent (as is _is_ambiguous_query below,
    for the same reason): a non-agricultural query that also scores low
    (Mars, a joke) must still fall through to the grounding guard's
    refusal. When chunks DO exist, this duplicates _is_ambiguous_query's
    weak-multitopic condition — not dead code, since this check runs
    BEFORE the grounding guard while _is_ambiguous_query is the catch-all
    that runs after it.
    """
    if not _has_agricultural_intent(message):
        return False
    if _is_all_crops_query(message) or _is_previous_clarification(history):
        return False
    caps = _dataset_capabilities()
    msg = message.lower()
    if any(c.lower() in msg for c in caps["crops"]):
        return False
    if any(d.lower() in msg for d in caps["districts"]):
        return False
    if not context["chunks"]:
        # Even with agricultural wording, a near-zero score means the
        # query has essentially no connection to the dataset at all — let
        # it fall through to the grounding guard's refusal instead of
        # offering a clarification for something unanswerable regardless
        # of which crop/district the user picks.
        return context["score"] >= 0.15
    if not (_MIN_RELEVANCE <= context["score"] < 0.5):
        return False
    crops = {ch.get("crop") for ch in context["chunks"] if ch.get("crop")}
    districts = {ch.get("district") for ch in context["chunks"] if ch.get("district")}
    return len(crops) > 1 or len(districts) > 1


def _is_ambiguous_query(message: str, context: dict, history: list | None) -> bool:
    """True when the query is too vague to answer confidently: no crop or
    district named, a weak retrieval match, AND that weak match itself
    spans multiple crops/districts — the system genuinely can't tell which
    one the user means. A named crop/district, a clear single topic despite
    a low score, an "all crops" query, a reply to a clarification just
    asked, or a query with zero agricultural intent (e.g. "weather on
    Mars" weakly matching unrelated chunks by embedding similarity alone)
    are never treated as ambiguous.
    """
    if not context["chunks"]:
        return False
    if not _has_agricultural_intent(message):
        return False
    if _is_all_crops_query(message) or _is_previous_clarification(history):
        return False
    caps = _dataset_capabilities()
    msg = message.lower()
    if any(c.lower() in msg for c in caps["crops"]):
        return False
    if any(d.lower() in msg for d in caps["districts"]):
        return False
    if not (_MIN_RELEVANCE <= context["score"] < 0.5):
        return False
    crops = {ch.get("crop") for ch in context["chunks"] if ch.get("crop")}
    districts = {ch.get("district") for ch in context["chunks"] if ch.get("district")}
    return len(crops) > 1 or len(districts) > 1


def _default_topic_suggestions(caps: dict, exclude: tuple | None = None) -> list:
    """Fallback (crop, district) suggestions built from the dataset's own
    metadata (one district per crop), used when there are no retrieved
    chunks to derive options from — e.g. a vague agricultural question
    ("how much can I earn?") that scored below the relevance floor."""
    options: list = []
    for crop in caps["crops"]:
        districts = caps["crop_districts"].get(crop) or caps["districts"]
        if not districts:
            continue
        pair = (crop, districts[0])
        if pair != exclude and pair not in options:
            options.append(pair)
        if len(options) >= 3:
            break
    return options


def _build_clarification(message: str, context: dict, history: list | None) -> tuple:
    """Build a friendly clarifying question plus tappable options, when
    _is_ambiguous_query or _is_vague_agricultural_query is True. Never
    calls Groq — deterministic template.
    Outputs: (reply text, suggested_followups — "{crop} in {district}"
    strings, the same options named in the reply, max 3).
    """
    caps = _dataset_capabilities()
    recent = _recent_topic(message, history, caps)
    options: list = []
    if recent:
        options.append(recent)
    chunk_topics = _chunk_topics(context)
    for pair in chunk_topics:
        if len(options) >= 3:
            break
        if pair not in options:
            options.append(pair)
    # No chunks to derive options from (the vague-agricultural, no-match
    # case) — fall back to generic suggestions from the dataset itself.
    if not chunk_topics:
        for pair in _default_topic_suggestions(caps, exclude=recent):
            if len(options) >= 3:
                break
            if pair not in options:
                options.append(pair)

    lines = [
        "I'd like to give you the most accurate answer. Could you tell me "
        "which crop and district you're asking about?"
    ]
    followups = []
    for crop, district in options:
        suffix = " (from your earlier question)" if (crop, district) == recent else ""
        lines.append(f"- {crop} in {district}{suffix}")
        followups.append(f"{crop} in {district}")
    lines.append("- Or tell me a different crop and district")
    return "\n".join(lines), followups


def _rag_context(
    message: str,
    district: str = "",
    crop: str = "",
    history: list | None = None,
) -> dict:
    """Retrieve the top-k most relevant RAG chunks for the query.

    Inputs: message (sanitised user query); optional district/crop from the
    UI dropdown filters; history (full ConversationTurn list, schema-capped
    at 10 — the last 3 USER messages whose assistant reply was not an
    out-of-scope refusal enrich the retrieval embedding, recency-weighted,
    so follow-up questions inherit context like a previously-mentioned
    district; assistant turns and refused topics are excluded as noise).
    Scoring model:
      raw     — cosine similarity; the ONLY quality signal. Gates the
                _MIN_RELEVANCE floor and drives the confidence label.
      boosted — raw + _METADATA_BOOST per matching filter (district, crop;
                both matching doubles it). Ranking priority ONLY.
    Outputs: dict with
      "chunks":  list of {"text", "source", "score"} — score is the RAW
                 cosine similarity; ordered by boosted rank, max _TOP_K,
                 all raw >= _MIN_RELEVANCE (empty = out of scope)
      "sources": ordered unique source labels of returned chunks
      "score":   highest RAW score among returned chunks (best-match score
                 overall when nothing passes — for logging/diagnostics)
    Chunk dicts also carry "crop" and "district" (None when the metadata
    slot is empty or the "all" placeholder) — used by _is_ambiguous_query
    and _build_clarification to detect and resolve vague queries; not
    used anywhere in scoring or filtering.
    Security assumption: district/crop are enum values validated by Pydantic.
    """
    empty = {"chunks": [], "sources": [], "score": 0.0}
    rag = model_loader.get_model("rag_artifacts")
    if rag is None:
        return empty
    try:
        from sentence_transformers import util  # type: ignore

        chunks = rag.get("knowledge_chunks", [])
        metadata = rag.get("chunk_metadata", [])
        embeddings = rag.get("chunk_embeddings")

        if not chunks or embeddings is None:
            return empty

        encoder = _get_encoder()
        # Context-enriched retrieval: recent USER messages nudge the query
        # embedding so follow-ups inherit context ("carrot in jaffna" ->
        # "how much can I earn" still retrieves Jaffna chunks). Enrichment
        # affects ONLY the embedding — the message sent to Groq is unchanged.
        # Context blend input: user messages whose assistant reply was NOT
        # an out-of-scope refusal — a refused topic (e.g. rice) must not
        # steer retrieval for the next question. Filter over the full
        # provided history FIRST, then cap to the last 3 user messages,
        # then recency-weight. A user message with no following assistant
        # turn is kept (its topic was never refused).
        turns = history or []
        recent_users = []
        for i, turn in enumerate(turns):
            if turn.role != "user":
                continue
            next_turn = turns[i + 1] if i + 1 < len(turns) else None
            if next_turn and _is_non_topic_reply(next_turn.content):
                continue  # refused / capability topic — skip from context
            recent_users.append(turn.content)
        recent_users = recent_users[-3:]
        caps = _dataset_capabilities()
        msg_lower = message.lower()
        has_crop = any(c.lower() in msg_lower for c in caps["crops"])
        has_district = any(d.lower() in msg_lower for d in caps["districts"])
        if has_crop and has_district:
            # User named both a crop and a district explicitly — their
            # message alone is the best retrieval query. Blending in
            # history here is what causes "maize price in Anuradhapura"
            # to sometimes retrieve carrot/Badulla chunks instead, when
            # that was the previous topic.
            q_emb = encoder.encode(message, convert_to_tensor=True)
        elif recent_users:
            # Weighted embedding blend: the current message dominates so an
            # explicit topic switch is never hijacked by stale context, while
            # a vague follow-up still inherits district/crop signal.
            e_msg = encoder.encode(message, convert_to_tensor=True)
            # Recency-weighted context: each user message is encoded
            # separately (single batched call) and averaged with linearly
            # increasing weights (oldest=1 .. newest=k), so the most recent
            # message dominates the context — "carrot yield in Badulla"
            # (newest) outweighs "carrots in Nuwara Eliya" (older).
            ctx_embs = encoder.encode(recent_users, convert_to_tensor=True)
            weights = range(1, len(recent_users) + 1)
            e_ctx = sum(w * e for w, e in zip(weights, ctx_embs)) / sum(weights)
            q_emb = _QUERY_WEIGHT * e_msg + (1 - _QUERY_WEIGHT) * e_ctx
        else:
            q_emb = encoder.encode(message, convert_to_tensor=True)
        sims = util.cos_sim(q_emb, embeddings)[0].tolist()

        # Graduated metadata boost: +_METADATA_BOOST per matching filter.
        scored = []  # (boosted, raw, index, meta)
        for i, raw in enumerate(sims):
            meta = metadata[i] if i < len(metadata) else {}
            matches = 0
            if district and meta.get("district") == district:
                matches += 1
            if crop and meta.get("crop") == crop:
                matches += 1
            scored.append((raw + _METADATA_BOOST * matches, raw, i, meta))

        # Filter on RAW score — junk stays junk regardless of metadata
        # match — then rank on BOOSTED score so filter matches jump the
        # queue. Chunks below the floor never reach the LLM.
        eligible = [t for t in scored if t[1] >= _MIN_RELEVANCE]
        eligible.sort(key=lambda t: t[0], reverse=True)
        top = eligible[:_TOP_K]
        if not top:
            best_raw = max(t[1] for t in scored)
            return {"chunks": [], "sources": [], "score": best_raw}

        # chunk_metadata carries {crop, district, season, type} but no
        # 'source' key — synthesize a human-readable source label so the
        # XAI sources_used field reflects the actual chunks retrieved.
        out: list = []
        sources: list = []
        for _boosted, raw, i, meta in top:
            source = meta.get("source") or _source_label(meta)
            crop = meta.get("crop")
            district = meta.get("district")
            out.append(
                {
                    "text": chunks[i],
                    "source": source,
                    "score": raw,
                    "crop": crop if crop and crop.lower() != "all" else None,
                    "district": (
                        district if district and district.lower() != "all" else None
                    ),
                }
            )
            if source not in sources:
                sources.append(source)
        top_raw = max(c["score"] for c in out)
        return {"chunks": out, "sources": sources, "score": top_raw}
    except Exception as exc:
        logger.warning("RAG retrieval failed: %s", exc)
        return empty


def _source_label(meta: dict) -> str:
    """Build a human-readable source name from RAG chunk metadata.

    Inputs: meta (dict with optional crop/district/season/type keys).
    Outputs: non-empty source label string for the XAI sources_used field.
    Security assumption: metadata comes from the trusted rag_artifacts file,
    not from user input, so no sanitisation is required here.
    """
    parts = " — ".join(
        str(p)
        for p in (meta.get("crop"), meta.get("district"), meta.get("season"))
        if p
    )
    kind = meta.get("type", "data")
    if parts:
        return f"CropSphere dataset: {parts} ({kind})"
    return "CropSphere agricultural dataset"


def _dataset_capabilities() -> dict:
    """Return crops/districts covered by the loaded RAG dataset (cached).

    Reads chunk_metadata from rag_artifacts ONCE and caches for the process
    lifetime (models load once at startup). Placeholder "all" values are
    excluded. Falls back to the API enums when artifacts are unavailable so
    templates never render empty lists.

    Outputs: {"crops", "districts", "crop_districts", "district_crops"} — the
    two maps power near-miss suggestions ("I cover Carrot in ...").
    Security assumption: metadata comes from the trusted rag_artifacts file.
    """
    global _capabilities_cache
    if _capabilities_cache is not None:
        return _capabilities_cache

    crops: set = set()
    districts: set = set()
    crop_districts: dict = {}
    district_crops: dict = {}

    rag = model_loader.get_model("rag_artifacts")
    metadata = rag.get("chunk_metadata", []) if rag else []
    for meta in metadata:
        crop = meta.get("crop")
        district = meta.get("district")
        real_crop = crop and crop.lower() != "all"
        real_district = district and district.lower() != "all"
        if real_crop:
            crops.add(crop)
        if real_district:
            districts.add(district)
        if real_crop and real_district:
            crop_districts.setdefault(crop, set()).add(district)
            district_crops.setdefault(district, set()).add(crop)

    if not crops or not districts:
        # Artifacts unavailable (dev/mock) — fall back to the API enums.
        from app.models.schemas import CropEnum, DistrictEnum

        crops = {c.value for c in CropEnum}
        districts = {d.value for d in DistrictEnum}
        crop_districts = {}
        district_crops = {}

    _capabilities_cache = {
        "crops": sorted(crops),
        "districts": sorted(districts),
        "crop_districts": {c: sorted(d) for c, d in crop_districts.items()},
        "district_crops": {d: sorted(c) for d, c in district_crops.items()},
    }
    return _capabilities_cache


def _near_miss(message: str, capabilities: dict) -> tuple | None:
    """Detect partially-supported questions for a friendlier refusal.

    Outputs: ("crop_match", crop) when a covered crop is mentioned with no
    covered district; ("district_match", district) for the reverse; None when
    neither side matches — or both do (both-match questions are the normal
    retrieval path's job).
    Security assumption: pure substring matching on already-sanitised text.
    """
    msg = message.lower()
    crops_hit = [c for c in capabilities["crops"] if c.lower() in msg]
    districts_hit = [d for d in capabilities["districts"] if d.lower() in msg]
    if crops_hit and not districts_hit:
        return ("crop_match", crops_hit[0])
    if districts_hit and not crops_hit:
        return ("district_match", districts_hit[0])
    return None


def _explicit_miss(message: str) -> tuple | None:
    """Detect a query that explicitly names an uncovered crop or district.

    Unlike _near_miss (which keys off COVERED terms in the message), this
    checks the uncovered-term gazetteers by whole-word token, so a near-miss
    is caught even when retrieval would return semantically-similar covered
    chunks. Returns a tuple shaped for _build_refusal/_refusal_followups:
      ("crop_match", crop)      covered crop named + uncovered district named
      ("district_match", dist)  covered district named + uncovered crop named
      ("generic", "")           uncovered term named, nothing covered to point to
      None                      no uncovered term named -> normal path
    Security assumption: pure token matching on already-sanitised text.
    """
    tokens = set(re.findall(r"[a-z]+", message.lower()))
    bad_district = bool(tokens & _UNCOVERED_DISTRICTS)
    bad_crop = bool(tokens & _UNCOVERED_CROPS)
    if not (bad_district or bad_crop):
        return None
    caps = _dataset_capabilities()
    msg = message.lower()
    crops_hit = [c for c in caps["crops"] if c.lower() in msg]
    districts_hit = [d for d in caps["districts"] if d.lower() in msg]
    if bad_district and crops_hit:
        return ("crop_match", crops_hit[0])  # have crop, not that district
    if bad_crop and districts_hit:
        return ("district_match", districts_hit[0])  # have district, not that crop
    return ("generic", "")


def _build_refusal(message: str, near: tuple | None = None) -> str:
    """Build a friendly, dataset-aware refusal message. Never calls Groq.

    Near-misses get a specific pointer (covered crop -> its districts,
    covered district -> its crops); everything else rotates through three
    generic templates naming real coverage (max 4 crops, 3 districts).
    Inputs: message (sanitised user query); near (precomputed near-miss from
    _explicit_miss; falls back to _near_miss when None).
    Outputs: a short (<= 2 sentence) refusal string.
    """
    caps = _dataset_capabilities()
    if near is None:
        near = _near_miss(message, caps)
    if near:
        kind, name = near
        if kind == "crop_match":
            districts = caps["crop_districts"].get(name) or caps["districts"]
            shown = ", ".join(districts[:4])
            return (
                f"I have data on {name}, but not for that district. "
                f"I cover {name} in {shown}. Want to try one of those?"
            )
        if kind == "district_match":
            crops = caps["district_crops"].get(name) or caps["crops"]
            shown = ", ".join(crops[:4])
            return (
                f"I have data for {name}, but not that crop. "
                f"In {name} I can help with {shown}. Try one of those?"
            )
        # ("generic", "") — fall through to the generic templates below.

    top_crops = ", ".join(caps["crops"][:4])
    top_districts = ", ".join(caps["districts"][:3])
    templates = [
        (
            "Hmm, that's outside my dataset. I currently cover crops like "
            f"{top_crops} across districts like {top_districts}. "
            "Ask me about any of those!"
        ),
        (
            "I don't have data on that yet. I'm best at questions about "
            f"{top_crops} in Sri Lankan districts like {top_districts}."
        ),
        (
            "That one's beyond my data for now. Try asking about "
            f"{top_crops} — yields, prices, or best seasons!"
        ),
    ]
    return random.choice(templates)  # nosec B311 — UX variety, not crypto


def _refusal_followups(message: str, near: tuple | None = None) -> list:
    """Suggest 3 askable questions after a refusal, built from real coverage.

    Near-miss crop match -> that crop in two covered districts; near-miss
    district match -> covered crops in that district; otherwise generic
    capability questions. Always ends with "What crops do you cover?".
    Inputs: message (sanitised user query); near (precomputed near-miss;
    falls back to _near_miss when None).
    """
    caps = _dataset_capabilities()
    if near is None:
        near = _near_miss(message, caps)
    if near and near[0] == "crop_match":
        crop = near[1]
        districts = caps["crop_districts"].get(crop) or caps["districts"]
        d2 = districts[1] if len(districts) > 1 else districts[0]
        return [
            f"{crop} yield in {districts[0]}",
            f"{crop} price in {d2}",
            "What crops do you cover?",
        ]
    if near and near[0] == "district_match":
        district = near[1]
        crops = caps["district_crops"].get(district) or caps["crops"]
        c2 = crops[1] if len(crops) > 1 else crops[0]
        return [
            f"{crops[0]} yield in {district}",
            f"Best season for {c2} in {district}",
            "What crops do you cover?",
        ]
    crops, districts = caps["crops"], caps["districts"]
    return [
        f"Best season for {crops[0]} in {districts[0]}",
        f"{crops[1 % len(crops)]} yield in {districts[1 % len(districts)]}",
        "What crops do you cover?",
    ]


def _is_context_statement(message: str) -> bool:
    """True when the message is the farmer introducing themselves or their
    situation ("I'm from Jaffna") rather than asking a question."""
    msg = message.lower()
    return any(p in msg for p in _CONTEXT_STATEMENT_PHRASES)


def _build_context_ack(message: str) -> tuple:
    """Build a friendly acknowledgment for a context-setting statement.
    Never calls Groq — deterministic template. Validates any crop+district
    combination against the dataset before promising to "focus on" it, so
    the farmer isn't misled into asking a follow-up that then gets
    refused. Outputs: (reply text, suggested_followups).
    """
    caps = _dataset_capabilities()
    msg = message.lower()
    crop = next((c for c in caps["crops"] if c.lower() in msg), None)
    district = next((d for d in caps["districts"] if d.lower() in msg), None)

    if crop and district:
        crop_districts = caps["crop_districts"].get(crop) or caps["districts"]
        if district in crop_districts:
            reply = (
                f"Great, I'll focus on {crop} in {district}. What would "
                "you like to know — yields, prices, or best planting "
                "seasons?"
            )
            followups = [
                f"{crop} yield in {district}",
                f"Best season for {crop} in {district}",
                f"{crop} price in {district}",
            ]
        else:
            shown = ", ".join(crop_districts)
            reply = (
                f"I'll keep {district} in mind! I don't have {crop} data "
                f"specifically for {district}, but I do have {crop} data "
                f"for {shown}. Want to try one of those?"
            )
            followups = [f"{crop} yield in {d}" for d in crop_districts[:3]]
    elif district:
        reply = (
            f"Got it, I'll keep {district} in mind! What would you like "
            "to know — crop yields, prices, or best planting seasons?"
        )
        followups = []
    elif crop:
        reply = (
            f"Noted, you're interested in {crop}. Which district are you "
            "in? Or just ask me a question!"
        )
        followups = []
    else:
        # No covered crop/district recognized — check for an explicitly
        # named UNCOVERED crop (e.g. "I'm growing rice") so the farmer
        # learns that upfront instead of a generic prompt.
        tokens = set(re.findall(r"[a-z]+", msg))
        uncovered_crop = next((c for c in tokens if c in _UNCOVERED_CROPS), None)
        if uncovered_crop:
            top_crops = ", ".join(caps["crops"][:4])
            reply = (
                f"I don't have data on {uncovered_crop} yet. I cover "
                f"{top_crops}. Want to know about one of those?"
            )
        else:
            reply = (
                "Thanks for sharing! Which crop and district would you "
                "like to know about?"
            )
        followups = []
    return reply, followups


def _is_capability_question(message: str) -> bool:
    """True when the user asks what the bot covers (crops/districts/skills)."""
    msg = message.lower()
    return any(p in msg for p in _CAPABILITY_PATTERNS)


def _capability_reply() -> tuple:
    """Capability summary + 3 example follow-ups, from real metadata.

    No Groq, no retrieval. Caller sets confidence "High confidence" (we are
    describing our own dataset) and sources []. Its text contains the phrase
    "I currently have data on", which _is_non_topic_reply matches so the turn
    is excluded from future retrieval context.
    Outputs: (reply, [3 follow-ups]).
    """
    caps = _dataset_capabilities()
    crops, districts = caps["crops"], caps["districts"]
    reply = (
        f"I currently have data on: {', '.join(crops)} across "
        f"{', '.join(districts)} — covering yields, prices, and growing "
        "seasons. Ask me anything about those!"
    )
    followups = [
        f"Best season for {crops[0]} in {districts[0]}",
        f"{crops[1 % len(crops)]} price in {districts[1 % len(districts)]}",
        f"{crops[2 % len(crops)]} yield in {districts[2 % len(districts)]}",
    ]
    return reply, followups


def _is_non_topic_reply(text: str) -> bool:
    """True when an assistant reply carries no crop/district topic — any
    refusal template or the capability summary. Used by the retrieval context
    filter in _rag_context so these turns never steer the next question."""
    return any(sig in text for sig in _NON_TOPIC_SIGNATURES)


def _confidence_label(context: dict) -> str:
    """Map RAG retrieval output to an explainability confidence label.

    Inputs: context (dict from _rag_context with "text" and "score").
    Outputs: human-readable confidence label for the chat response.
    Security assumption: values are computed server-side, not user input, so
    no sanitisation is required here.

    An empty "chunks" list means retrieval found nothing above the relevance
    floor — the query is out of scope for our agricultural dataset. The label
    is derived from the highest RAW cosine score among returned chunks; the
    metadata ranking boost never inflates confidence.
    """
    if not context["chunks"]:
        return "Out of scope"
    score = context["score"]
    if score > 0.8:
        return "High confidence"
    if score >= 0.5:
        return "Moderate confidence"
    return "Low confidence — please verify with an agricultural officer"


def _is_all_crops_query(message: str) -> bool:
    """True when the user asks about every crop at once (e.g. "what are the
    yields for all crops"), not one specific crop."""
    msg = message.lower()
    return any(p in msg for p in _ALL_CROPS_PATTERNS)


def _build_messages(system: str, context: dict, req: ChatRequest, message: str) -> list:
    """Assemble the Groq message list: system prompt, RAG context, history,
    current message.

    Inputs: system (prompt string), context (dict from _rag_context), req
    (ChatRequest carrying conversation_history), message (sanitised user
    text).
    Outputs: list of {"role", "content"} dicts in Groq chat format. History
    is trimmed to the last _MAX_HISTORY_MESSAGES entries (sliding window);
    the system prompt and RAG context sit outside the window and are always
    included. Used identically by chat() and chat_stream().
    Security assumption: message was already HTML-stripped and truncated by
    the caller; history turns were validated by Pydantic (role pattern,
    max_length).
    """
    msgs = [{"role": "system", "content": system}]
    if context["chunks"]:
        parts = [
            f"--- Source {i}: {ch['source']} (relevance {ch['score']:.2f}) ---\n"
            f"{ch['text']}"
            for i, ch in enumerate(context["chunks"], 1)
        ]
        msgs.append(
            {"role": "system", "content": "Relevant context:\n" + "\n".join(parts)}
        )
    # Style/formatting rules — separate system message so they stay close to
    # the conversation and don't compete with the safety-critical rules in
    # the core prompt (see _FORMATTING_RULES).
    msgs.append({"role": "system", "content": _FORMATTING_RULES})
    # Knowledge-level instruction — its own system message right after the
    # formatting rules and before history, so it sits close to the
    # conversation (well-attended) and OVERRIDES any conflicting Part B rule
    # (e.g. beginner shows only acres, not "all three units"). See
    # _detect_knowledge_level / _LEVEL_INSTRUCTIONS.
    level = _detect_knowledge_level(message, req.conversation_history)
    msgs.append({"role": "system", "content": _LEVEL_INSTRUCTIONS[level]})
    # "All crops" queries: top-k retrieval only surfaces 2-3 crops' worth of
    # chunks, so the LLM can't know the other crops exist at all. Inject the
    # full crop list from our own dataset metadata as extra context so it
    # can name what it knows and point to individual queries for the rest.
    if _is_all_crops_query(message):
        crops_list = ", ".join(_dataset_capabilities()["crops"])
        msgs.append(
            {
                "role": "system",
                "content": f"Available crops in CropSphere dataset: {crops_list}",
            }
        )
    # Sliding window — only the most recent turns reach Groq; the system
    # prompt and RAG context above are never part of the window.
    history = req.conversation_history
    if len(history) > _MAX_HISTORY_MESSAGES:
        logger.info(
            f"[HISTORY] trimmed {len(history)} messages "
            f"to last {_MAX_HISTORY_MESSAGES}"
        )
        history = history[-_MAX_HISTORY_MESSAGES:]
    for turn in history:
        msgs.append({"role": turn.role, "content": turn.content})
    msgs.append({"role": "user", "content": message})
    return msgs


def _build_reformulation_messages(
    system: str, previous_reply: str, req: ChatRequest, message: str, rtype: str
) -> list:
    """Assemble the Groq message list for a reformulation request.

    Same core rules (Part A) and formatting rules (Part B) as
    _build_messages, but the RAG-context slot is replaced with an
    instruction to rewrite the previous answer — no retrieval involved, so
    the model is grounded in the SAME data as before, not new chunks.
    rtype ("math" or "simplify", from _reformulation_type) picks which
    instruction is sent. The math instruction's own formatting rules
    override Rule 5's "no calculations" in Part A for this one exchange —
    it's a later, more specific system message, and the user explicitly
    asked for the math.
    """
    msgs = [{"role": "system", "content": system}]
    msgs.append(
        {
            "role": "system",
            "content": (
                "This is a reformulation of your own previous answer, not "
                "a new grounded answer — do NOT start with 'Reasoning: "
                "...' this time, and do not split your reply into a "
                "reasoning sentence and a separate answer. Just give the "
                "rewritten or calculated answer directly."
            ),
        }
    )
    if rtype == "formal_math":
        instruction = (
            "The user wants the calculation shown in standard/formal "
            "mathematical notation instead of a step-by-step breakdown. "
            "Here is your previous answer: "
            f"{previous_reply}. Represent it as a compact formal "
            "equation:\n\n"
            "FORMAL NOTATION RULES:\n"
            "- Use a negative exponent instead of a slash for the rate "
            "unit: write 'kg·acre⁻¹' not 'kg/acre'\n"
            "- Use a center dot (·) to join a compound unit's parts, "
            "e.g. 'kg·acre⁻¹'\n"
            "- Use '×' (the multiplication sign) for the arithmetic "
            "operation itself, not 'x' or '*'\n"
            "- Example: 8,162 kg·acre⁻¹ × 2 acre = 16,324 kg\n"
            "- Use thousands separators (16,324 not 16324)\n"
            "- Use the farmer's unit (acres/perches), not hectares\n"
            "- End with one plain-language summary sentence: 'So you "
            "can earn around 1,044,736 LKR from your 2 acres.'"
        )
    elif rtype == "math":
        instruction = (
            "The user wants to see how you arrived at the numbers in "
            "your previous answer. Here is your previous answer: "
            f"{previous_reply}. Show the calculation steps clearly and "
            "readably:\n\n"
            "MATH FORMATTING RULES:\n"
            "- Use a clear step-by-step layout with numbered steps\n"
            "- Each step on its own line\n"
            "- Show one operation per step, not everything chained "
            "together\n"
            "- NEVER multiply a rate that still has its unit attached "
            "(like '8,162 kg/acre') by a quantity in that same unit "
            "(like '2 acres') in one expression — it looks like the "
            "units should cancel out but nothing shows that happening, "
            "which is confusing, not clearer. Strip the unit from both "
            "numbers before multiplying, and only attach the unit to "
            "the final result:\n"
            "  Good: Step 3: Total harvest = 8,162 x 2 = 16,324 kg\n"
            "  Bad:  Step 3: Total harvest = 8,162 kg/acre x 2 acres "
            "= 16,324 kg\n"
            "- Use simple labels before each number:\n"
            "  Good:\n"
            "    Step 1: Yield per acre = 8,162 kg\n"
            "    Step 2: Your land = 2 acres\n"
            "    Step 3: Total harvest = 8,162 x 2 = 16,324 kg\n"
            "    Step 4: Price per kg = 64 LKR\n"
            "    Step 5: Total earnings = 16,324 x 64 = 1,044,736 LKR\n"
            "  Bad:\n"
            "    20,169 kg/ha * 2 / 2.471 * 64 = 1,044,736\n"
            "- Use the farmer's unit (acres/perches) not hectares\n"
            "- Use thousands separators (16,324 not 16324)\n"
            "- Use 'x' for multiplication, not '*'\n"
            "- End with a clear summary: 'So you can earn around "
            "1,044,736 LKR from your 2 acres.'"
        )
    else:
        instruction = (
            "The user wants a simpler, clearer version of your previous "
            "answer. Here is your previous answer: "
            f"{previous_reply}. Rewrite it using shorter sentences, "
            "simpler words, and bullet points if it helps. Remove any "
            "unnecessary detail — keep only what the farmer needs to "
            "know. Use the same data — do not add new information."
        )
    msgs.append({"role": "system", "content": instruction})
    msgs.append({"role": "system", "content": _FORMATTING_RULES})
    history = req.conversation_history
    if len(history) > _MAX_HISTORY_MESSAGES:
        history = history[-_MAX_HISTORY_MESSAGES:]
    for turn in history:
        msgs.append({"role": turn.role, "content": turn.content})
    msgs.append({"role": "user", "content": message})
    return msgs


def _default_followups(req: ChatRequest) -> list:
    """Generate follow-up suggestions in the detected language."""
    crop = req.crop.value if req.crop else "crops"
    district = req.district.value if req.district else "your area"

    # English follow-ups — LLaMA will handle translation via system prompt
    followups_en = [
        f"What is the best planting season for {crop} in {district}?",
        f"What are current market prices for {crop}?",
        "How can I improve my soil quality?",
    ]

    return followups_en


def _question_type(message: str) -> str:
    """Classify what kind of question was just answered, from keywords in
    the user's message — drives which template _smart_followups picks."""
    msg = message.lower()
    if any(k in msg for k in _YIELD_TYPE_KEYWORDS):
        return "yield"
    if any(k in msg for k in _EARNINGS_TYPE_KEYWORDS):
        return "earnings"
    if any(k in msg for k in _PRICE_TYPE_KEYWORDS):
        return "price"
    if any(k in msg for k in _SEASON_TYPE_KEYWORDS):
        return "season"
    return "general"


def _raw_level(message: str, is_first: bool) -> str:
    """Score a single message's phrasing as beginner/intermediate/advanced
    from the Step 2 signals, ignoring conversation history. 2+ signals on a
    side wins; advanced breaks ties. History smoothing is layered on top by
    _detect_knowledge_level."""
    msg = message.lower()
    tokens = set(re.findall(r"[a-z]+", msg))
    word_count = len(message.split())
    has_crop = _detect_crop_mention(message) is not None
    has_district = _detect_district_mention(message) is not None
    has_season = bool(tokens & _SEASON_NAME_TOKENS)

    beginner = 0
    if word_count < 6:
        beginner += 1
    if any(p in msg for p in _BEGINNER_DEFINITION_PATTERNS):
        beginner += 1
    if any(p in msg for p in _BEGINNER_SIMPLE_PATTERNS):
        beginner += 1
    if not (has_crop or has_district or has_season):
        beginner += 1
    if is_first:
        beginner += 1
    if tokens & _BEGINNER_INFORMAL_TOKENS:
        beginner += 1

    advanced = 0
    if any(t in msg for t in _ADVANCED_TERMS):
        advanced += 1
    if any(p in msg for p in _ADVANCED_COMPARISON_PATTERNS):
        advanced += 1
    topic_hits = sum(1 for k in _KNOWLEDGE_TOPIC_KEYWORDS if k in msg)
    if topic_hits >= 2 and " and " in msg:
        advanced += 1
    if has_season:
        advanced += 1
    if word_count > 15:
        advanced += 1
    if any(p in msg for p in _ADVANCED_DATA_PATTERNS) or re.search(
        r"\d\s*(kg|lkr|%)", msg
    ):
        advanced += 1

    if advanced >= 2:
        return "advanced"
    if beginner >= 2:
        return "beginner"
    return "intermediate"


def _detect_knowledge_level(message: str, history: list | None = None) -> str:
    """Detect the farmer's knowledge level — "beginner", "intermediate", or
    "advanced" — from how the CURRENT message is phrased, smoothed by the
    levels of earlier questions in the conversation.

    Each message is scored by _raw_level. History rules (Step 6): default to
    intermediate when unsure; never downgrade to beginner once the farmer has
    shown advanced phrasing (one simple follow-up doesn't make an expert a
    beginner); a consistently-advanced history stabilises an otherwise
    ambiguous turn to advanced so the level doesn't flap. Deterministic in
    (message, history), so the level injected into the prompt and the level
    logged to analytics never diverge.
    """
    user_msgs = [
        t.content for t in (history or []) if getattr(t, "role", None) == "user"
    ]
    current = _raw_level(message, is_first=not user_msgs)
    prior = [_raw_level(m, is_first=(i == 0)) for i, m in enumerate(user_msgs)]

    if "advanced" in prior and current == "beginner":
        return "intermediate"
    if (
        current == "intermediate"
        and len(prior) >= 2
        and all(p == "advanced" for p in prior)
    ):
        return "advanced"
    return current


def _smart_followups(context: dict, message: str, req: ChatRequest) -> list:
    """Generate 3 tappable follow-up chips from what was just answered,
    instead of a fixed template: the top retrieved chunk's crop/district
    (falling back to the UI's dropdown filters, then to the static
    defaults) and the TYPE of question just asked, so chips suggest a
    natural next question rather than a generic one.
    """
    if not context or not context.get("chunks"):
        return _default_followups(req)

    top = context["chunks"][0]
    crop = top.get("crop") or (req.crop.value if req.crop else None)
    district = top.get("district") or (req.district.value if req.district else None)
    if not crop or not district:
        return _default_followups(req)

    caps = _dataset_capabilities()
    crop_districts = caps["crop_districts"].get(crop, [])
    district_crops = caps["district_crops"].get(district, [])
    # The resolved crop/district must actually be a real pairing in the
    # dataset — chunk metadata and the UI's dropdown filters can disagree
    # (e.g. crop from the chunk, district from a stale UI filter) — a
    # mismatched pair would suggest an impossible chip.
    if district not in crop_districts:
        return _default_followups(req)

    qtype = _question_type(message)
    if qtype == "yield":
        chips = [
            f"{crop} price in {district}",
            f"How much can I earn from 1 acre of {crop} in {district}?",
        ]
        if len(crop_districts) > 1:
            chips.append(f"Compare {crop} yield with other districts")
        else:
            chips.append(f"Best season for {crop} in {district}")
        return chips
    if qtype == "price":
        return [
            f"Expected yield for {crop} in {district}",
            f"Best season to plant {crop} in {district}",
            "How much can I earn from 1 acre?",
        ]
    if qtype == "season":
        return [
            f"{crop} yield in {district}",
            f"What's the price for {crop}?",
            f"How much land do I need for {crop}?",
        ]
    if qtype == "earnings":
        chips = []
        if len(district_crops) > 1:
            chips.append(f"Compare earnings with other crops in {district}")
        else:
            chips.append(f"{crop} price in {district}")
        chips.append(f"Best season for {crop} in {district}?")
        chips.append(f"{crop} yield across all seasons")
        return chips
    chips = [f"Tell me more about {crop} in {district}"]
    if len(crop_districts) > 1:
        chips.append("Compare with other districts")
    else:
        chips.append(f"Best season for {crop} in {district}")
    chips.append("What crops do you cover?")
    return chips


def _safe_audit(user_id: str, message: str) -> None:
    """Log chat request hash — failure must not interrupt the chat response."""
    try:
        audit_log(
            user_id=user_id, endpoint="/api/chat", input_data={"message": message}
        )
    except Exception as exc:
        logger.warning("Chat audit log failed: %s", exc)


# ── Analytics ─────────────────────────────────────────────────────────────────
# One chat_analytics document per interaction (questioning patterns, refused
# topics, usage). Best-effort throughout: _emit_analytics runs the whole
# record build + Firestore write in a daemon thread, and every function here
# swallows its own errors, so analytics can never break or slow a chat reply.
# See app.user.services.analytics_service.log_chat_interaction.


def _anonymize_uid(user_id: str) -> str:
    """One-way hash of the Firebase uid so analytics can count distinct users
    and sessions without storing the raw uid (privacy / DevSecOps posture,
    consistent with audit_log hashing prediction inputs)."""
    return hashlib.sha256((user_id or "").encode()).hexdigest()[:16]


def _detect_crop_mention(message: str) -> str | None:
    """Return the crop named in `message`, checking BOTH covered crops
    (_dataset_capabilities) and known-uncovered crops (_UNCOVERED_CROPS), or
    None. Covered crops use substring match (as _near_miss does); uncovered
    crops use whole-word tokens so 'rice' never matches inside 'price'."""
    msg = message.lower()
    for crop in _dataset_capabilities()["crops"]:
        if crop.lower() in msg:
            return crop
    tokens = set(re.findall(r"[a-z]+", msg))
    for crop in sorted(_UNCOVERED_CROPS):
        if crop in tokens:
            return crop
    return None


def _detect_district_mention(message: str) -> str | None:
    """Return the district named in `message`, checking BOTH covered districts
    (_dataset_capabilities) and known-uncovered districts (_UNCOVERED_DISTRICTS),
    or None. Same matching rules as _detect_crop_mention."""
    msg = message.lower()
    for district in _dataset_capabilities()["districts"]:
        if district.lower() in msg:
            return district
    tokens = set(re.findall(r"[a-z]+", msg))
    for district in sorted(_UNCOVERED_DISTRICTS):
        if district in tokens:
            return district
    return None


def _detect_if_chip_tapped(message: str, previous_followups: list) -> bool:
    """True when `message` matches one of the previous turn's
    suggested_followups (whitespace/case-insensitive) — i.e. the farmer tapped
    a suggestion chip instead of typing a new question."""
    if not previous_followups:
        return False
    norm = message.strip().lower()
    return any(norm == (f or "").strip().lower() for f in previous_followups)


def _reconstruct_previous_followups(req: ChatRequest) -> list:
    """Recompute the suggested_followups the PREVIOUS assistant turn showed.

    The API never persists or echoes suggested_followups, so to tell whether
    the current message was a tapped chip we replay the previous USER turn
    through the same path selection chat() uses and rebuild its followups —
    re-running RAG retrieval for the retrieval-based paths. Called ONLY from
    the _emit_analytics background thread, so the extra retrieval never adds
    latency to the live response. Returns [] when there is no prior user turn
    or reconstruction fails.
    """
    try:
        history = req.conversation_history or []
        prev_idx = next(
            (i for i in range(len(history) - 1, -1, -1) if history[i].role == "user"),
            None,
        )
        if prev_idx is None:
            return []
        prev_msg = _strip_html(history[prev_idx].content)[:_MAX_LEN]
        prior = history[:prev_idx]
        district = req.district.value if req.district else ""
        crop = req.crop.value if req.crop else ""

        if _is_context_statement(prev_msg):
            return _build_context_ack(prev_msg)[1]
        if _is_capability_question(prev_msg):
            return _capability_reply()[1]
        miss = _explicit_miss(prev_msg)
        if miss:
            return _refusal_followups(prev_msg, near=miss)
        if _is_reformulation_request(prev_msg) and _last_assistant_reply(prior):
            return _default_followups(req)

        retrieval_query = _expand_clarifying_reply(prev_msg, prior)
        context = _rag_context(
            retrieval_query, district=district, crop=crop, history=prior
        )
        if _is_vague_agricultural_query(prev_msg, context, prior):
            return _build_clarification(prev_msg, context, prior)[1]
        if not context["chunks"]:
            return _refusal_followups(prev_msg)
        if _is_ambiguous_query(prev_msg, context, prior):
            return _build_clarification(prev_msg, context, prior)[1]
        return _smart_followups(context, prev_msg, req)
    except Exception as exc:
        logger.debug("followup reconstruction failed: %s", exc)
        return []


def _emit_analytics(
    req: ChatRequest,
    message: str,
    response_type: str,
    confidence: str,
    context: dict | None,
    start: float,
    near_miss_type: str | None = None,
) -> None:
    """Fire-and-forget: record one chat_analytics document for this turn.

    Runs in a daemon thread for two reasons — analytics must add no latency to
    the chat response, and chip-tap detection reconstructs the previous turn's
    followups which may re-run RAG retrieval (too heavy for the hot path).
    response_time_ms is sampled HERE (just before the caller returns / finishes
    the stream) so it reflects end-to-end handling. Never raises.
    """
    elapsed_ms = int((time.monotonic() - start) * 1000)
    try:
        threading.Thread(
            target=_run_analytics,
            args=(
                req,
                message,
                response_type,
                confidence,
                context,
                near_miss_type,
                elapsed_ms,
            ),
            daemon=True,
        ).start()
    except Exception as exc:  # spawning the thread must never bubble up
        logger.warning("analytics thread spawn failed: %s", exc)


def _run_analytics(
    req: ChatRequest,
    message: str,
    response_type: str,
    confidence: str,
    context: dict | None,
    near_miss_type: str | None,
    elapsed_ms: int,
) -> None:
    """Background-thread body: reconstruct chip context, assemble the record,
    hand it to log_chat_interaction. Errors are swallowed."""
    try:
        ctx = context or {}
        data = {
            "user_id": _anonymize_uid(req.user_id),
            "question": message[:200],
            "question_type": _question_type(message),
            # Recomputed here (deterministic) — matches the level
            # _build_messages injected into the prompt for this same turn.
            "knowledge_level": _detect_knowledge_level(
                message, req.conversation_history
            ),
            "response_type": response_type,
            "confidence": confidence,
            "retrieval_score": float(ctx.get("score", 0.0) or 0.0),
            "sources_used": list(ctx.get("sources", []) or []),
            "crop_mentioned": _detect_crop_mention(message),
            "district_mentioned": _detect_district_mention(message),
            "near_miss_type": near_miss_type,
            "followup_chip_tapped": _detect_if_chip_tapped(
                message, _reconstruct_previous_followups(req)
            ),
            "session_message_count": len(req.conversation_history) + 1,
            "model_used": req.model,
            "response_time_ms": elapsed_ms,
        }
        log_chat_interaction(data)
    except Exception as exc:
        logger.warning("analytics assembly failed: %s", exc)
