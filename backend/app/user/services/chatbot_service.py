"""AI chatbot service — LLaMA 3 via Groq API with RAG.

New features:
- Model selection: "fast" (llama-3.1-8b-instant) or "accurate" (llama-3.3-70b-versatile)
- Language detection: auto-detects Sinhala, Tamil, English
- Prompt injection strategy: LLaMA instructed to respond in user's language directly
- Translation cache: repeated phrases served instantly from memory
"""

import hashlib
import json
import logging
import os
import random
import re
import threading
import time
from collections import OrderedDict
from datetime import datetime, timezone

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
    "- Frame data as advice, not a report. Bad: 'The predicted yield is "
    "20,169 kg/ha.' Good: 'You can expect to harvest around 20,169 kg from "
    "one hectare.' Bad: 'The average farmgate price is 62 LKR/kg.' Good: "
    "'Farmers are currently getting around 62 LKR per kilogram at the farm.' "
    "Bad: 'Want me to estimate your earnings? Just tell me your land size.' "
    "Good: 'Would you like me to work out how much you could earn? Just tell "
    "me your land size in acres or perches.'\n"
    "- Structure every answer in three sections, separated by blank lines:\n"
    "  (1) ANSWER — the main data and advice the farmer asked for. This is "
    "the core response.\n"
    "  (2) NOTE (optional) — any important caveat, seasonal advice, or "
    "practical tip. Only include if relevant. Start with 'Note:' or a "
    "practical observation.\n"
    "  (3) FOLLOW-UP QUESTION (optional) — any question back to the farmer "
    "(earnings offer, land size question). Always on its own line, "
    "separated by a blank line from the answer.\n"
    "  These section names are structural: never print the numbers or the "
    "words 'ANSWER' and 'FOLLOW-UP QUESTION'. Only the word 'Note:' is "
    "written out, and only when a note applies.\n"
    "  Good structure:\n"
    "  'If you plant carrots in Badulla during the Inter season, you can "
    "expect to harvest around 20,169 kg from one hectare (8,162 kg per "
    "acre; 51 kg per perch).\n\n"
    "  Note: The Maha season typically gives slightly lower yields in this "
    "area.\n\n"
    "  Would you like me to work out how much you could earn? Just tell me "
    "your land size in acres or perches.'\n"
    "  Bad structure (everything merged): 'If you plant carrots in Badulla "
    "during the Inter season you can expect to harvest around 20,169 kg "
    "from one hectare (8,162 kg per acre) the Maha season gives lower "
    "yields would you like me to estimate your earnings just tell me your "
    "land size.'\n"
    "  Always put a blank line before any question to the farmer.\n"
    "- Start answers with the farmer's situation when possible. Bad: 'The "
    "yield is 20,169 kg/ha.' Good: 'If you plant carrots in Badulla during "
    "Inter season, you can expect around 20,169 kg per hectare.'\n"
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
    "- After answering a question specifically about crop YIELD (harvest "
    "amounts, kg/ha) or crop PRICE (selling price, LKR/kg), add one short "
    "sentence offering to estimate earnings if the farmer tells you their "
    "land size. Example: 'Would you like me to work out how much you could "
    "earn? Just tell me your land size in acres or perches.' Do NOT offer "
    "earnings after "
    "questions about growing requirements, planting seasons, weather, "
    "soil, general information, or any non-yield/non-price topic. Only "
    "offer this once per topic — if you already gave an earnings estimate "
    "or the farmer already asked about earnings, don't repeat the offer.\n"
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
# Substrings identifying an assistant reply that refused the question, in any
# template shape. Split out from _NON_TOPIC_SIGNATURES below so the follow-up
# handling can ask the narrower question "was the last turn a refusal?" without
# also matching the capability summary, which is not a refusal. MUST stay in
# sync with the templates in _build_refusal().
_REFUSAL_SIGNATURES = (
    _OUT_OF_SCOPE_MARKER,  # canned LLM-side refusal
    "but not for that district",  # near-miss refusal: crop covered
    "but not that crop",  # near-miss refusal: district covered
    "outside my dataset",  # generic refusal template 1
    "I don't have data on that yet",  # generic refusal template 2
    "beyond my data for now",  # generic refusal template 3
)
# Substrings identifying assistant replies that carry no crop/district topic
# (refusals in any template shape, and capability summaries). Consumed by the
# retrieval-context history filter so a refused/administrative turn never
# steers the next question's retrieval. MUST stay in sync with the templates
# in _build_refusal() and _capability_reply().
_NON_TOPIC_SIGNATURES = _REFUSAL_SIGNATURES + (
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
# Marker the LLM prefixes each suggested follow-up with (see _system_prompt
# Rule 7). Parsed out of the reply by _parse_followups_from_response BEFORE
# the text is shown or persisted — a farmer must never see this token.
_FOLLOWUP_PREFIX = "FOLLOWUP:"
# Chips shown per (user, conversation), so the next turn can detect a tap.
# LLM chips are generated per-reply and cannot be recomputed, so this replaces
# reconstruction on the answer path. Bounded FIFO — see _remember_shown_chips.
_shown_chips: "OrderedDict[str, tuple]" = OrderedDict()
_shown_chips_lock = threading.Lock()
_SHOWN_CHIPS_CAP = 500
_MAX_LLM_FOLLOWUPS = 3
# Upper bound on a generated chip. Rule 7 asks for under 10 words; this is the
# hard stop so a runaway generation can't produce an unusable chip.
_MAX_FOLLOWUP_LEN = 120
# Interrogative opener that precedes the first option in an inline choice
# ("Is that 3 acres, 3 hectares, or 3 perches?") — stripped so the first
# option survives instead of being discarded with the lead-in.
_QUESTION_LEADIN_RE = re.compile(
    r"^(?:is|are|was|were)\s+(?:that|it|these|those)\s+", re.IGNORECASE
)
# Phrases that ask about every crop at once rather than one specific crop —
# top-k retrieval only surfaces 2-3 crops for these, so the full list is
# injected separately (see _build_messages).
_ALL_CROPS_PATTERNS = ("all crops", "every crop", "all the crops")
# ── Follow-up continuation ────────────────────────────────────────────────────
# A short reply like "yes explain", "why?" or "and the price?" carries almost no
# agricultural signal of its own, so retrieval on the message alone scores near
# zero, the grounding guard fires, and the farmer gets "out of scope" one turn
# after a perfectly good answer. _reformulate_query rebuilds the RETRIEVAL query
# from the topic already on screen; the message sent to Groq is never touched.
# The recency blend in _rag_context is not enough on its own — the current
# message carries _QUERY_WEIGHT (0.7) of the embedding, so a contentless one
# drags the blend below the floor no matter how good the context is.
#
# Whole messages (lowercased, punctuation stripped) that are nothing but a
# continuation request. Matched EXACTLY, so a real question that merely contains
# "how" or "more" is never caught here.
_FOLLOWUP_EXACT = frozenset(
    {
        "yes",
        "yes please",
        "yeah",
        "yep",
        "ya",
        "ok",
        "okay",
        "sure",
        "please",
        "go on",
        "go ahead",
        "continue",
        "carry on",
        "more",
        "tell me more",
        "more info",
        "more details",
        "explain",
        "yes explain",
        "explain that",
        "explain it",
        "show me",
        "show me more",
        "why",
        "how",
        "how so",
        "why so",
        "and",
        "and then",
        "then",
        "next",
        "what else",
        "anything else",
        "i see",
    }
)
# Openings that mark a partial follow-up — the farmer is adding a dimension to
# the question they just asked ("and the price?", "for Maize?"), not starting
# over. Only consulted for messages under _FOLLOWUP_MAX_LEN.
_FOLLOWUP_PREFIXES = (
    "and ",
    "what about",
    "how about",
    "but ",
    "also ",
    "or ",
    "for ",
    "in ",
    "about ",
)
# A short message opening with one of these is an assent to whatever the bot
# just offered ("yes explain", "sure tell me more"), not a new question.
_AFFIRMATIVE_TOKENS = frozenset(
    {"yes", "yeah", "yep", "ya", "ok", "okay", "sure", "please"}
)
# "that"/"it" in a short message with no crop or district named can only refer
# back to the previous turn ("how does it work?", "why is that?").
_FOLLOWUP_PRONOUNS = frozenset({"that", "it", "this", "them", "those", "these", "they"})
_WH_TOKENS = frozenset({"why", "how", "what", "when", "where", "which", "who"})
# Length ceiling for the heuristic (not the exact-match) half of the follow-up
# check. Anything longer says enough to stand on its own as a query.
_FOLLOWUP_MAX_LEN = 50
# How much of the inherited question is prepended to the retrieval query. Long
# enough for a full farmer question, short enough that the follow-up's own
# wording still moves the embedding.
_FOLLOWUP_TOPIC_MAX_LEN = 200
# Combo patterns: verb + any qualifier — requires BOTH so a real question
# like "explain carrot yield" (has agricultural content) doesn't match.
_REFORMULATION_PATTERNS = (
    ("show", ("simply", "simpler", "simple")),
    ("explain", ("again", "clearly", "better", "more")),
    ("explain", ("simply",)),
    ("tell", ("simply",)),
    ("say", ("simply", "simpler")),
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
    "put it simply",
)
# Bare "simply" is too weak a signal on its own — it also appears as an
# adverb inside real questions ("which crop simply grows best in Badulla").
# Only treated as a reformulation request when the message is short enough
# to be nothing but the request itself. The other half of the guard — that
# there IS a previous answer to reformulate — is already enforced by the
# call sites, which fall through to retrieval when _last_assistant_reply()
# returns empty.
_BARE_SIMPLY_MAX_LEN = 15
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
# just answered, so _fallback_followups can suggest a natural next step.
# "earn"/"money" are their own bucket, not folded into price, so the
# EARNINGS follow-up set below is actually reachable.
_YIELD_TYPE_KEYWORDS = ("yield", "harvest", "grow")
_EARNINGS_TYPE_KEYWORDS = ("earn", "money")
_PRICE_TYPE_KEYWORDS = ("price", "cost", "sell")
_SEASON_TYPE_KEYWORDS = ("season", "plant", "when")
_capabilities_cache: dict | None = None
# Few-shot examples (thumbs-up answers per question_type), loaded once from the
# JSON file that fewshot_service writes. None = not yet loaded; {} = loaded but
# empty (no file / unreadable) — the chatbot works fine either way.
_fewshot_examples: dict | None = None
# Admin-approved, analytics-derived prompt tuning (see prompt_tuning_service).
# Same None/{} cache semantics as _fewshot_examples; empty = static prompt.
_prompt_tuning: dict | None = None
# Admin-approved routing phrases that SUPPLEMENT the hardcoded lists above (see
# pattern_override_store). Same None/{} cache semantics; empty = hardcoded
# patterns only, which is the behaviour this file had before overrides existed.
_pattern_overrides: dict | None = None
# Which override (if any) routed the turn currently being handled on THIS
# thread. The predicates below are pure boolean functions called from deep
# inside chat()/chat_stream(), so a thread-local is how the match surfaces to
# _emit_analytics without threading a return value through every call site.
# Reset at the top of each turn — FastAPI runs sync endpoints on a shared
# threadpool, so a stale value would otherwise leak into the next request.
_override_match = threading.local()
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
    "fast": "openai/gpt-oss-20b",
    "accurate": "openai/gpt-oss-120b",
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
    _reset_override_match()

    _safe_audit(req.user_id, clean)

    # Load the farmer's saved area/crop only for a brand-new conversation, to
    # confirm ambiguous questions later (see _should_confirm_saved_context).
    saved_crop = saved_district = None
    if not req.conversation_history:
        _prefs = _safe_get_preferences(req.user_id)
        saved_crop = _prefs.get("preferred_crop")
        saved_district = _prefs.get("preferred_district")

    # Context-rebuilt retrieval query: a bare land-unit reply to the bot's own
    # clarifying question ("perches"), or a short follow-up with no
    # agricultural signal of its own ("yes explain", "and the price?"), is
    # rebuilt into a query with real content — for retrieval ONLY, before any
    # capability/gazetteer check or retrieval itself runs. See _retrieval_query.
    retrieval_query = _retrieval_query(clean, req.conversation_history)

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
            _ctx_crop, _ctx_district = _extract_context_terms(clean)
            if _ctx_crop or _ctx_district:
                _save_context_async(req.user_id, _ctx_crop, _ctx_district)
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
                    max_tokens=768,
                    temperature=0.7,
                    reasoning_effort="low",
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

        # Saved-context confirmation — a fresh, dropdown-free query that omits a
        # crop or district our saved profile can fill: confirm ("Do you mean
        # carrot in Jaffna?") rather than silently assuming. Runs before the
        # other clarifications so the saved-context prompt takes precedence.
        if _should_confirm_saved_context(req, clean, saved_crop, saved_district):
            reply, cq_followups = _build_context_confirmation(
                req, clean, saved_crop, saved_district
            )
            _emit_analytics(
                req,
                clean,
                "clarification",
                "Moderate confidence",
                context,
                start,
                used_saved_context=True,
            )
            return ChatResponse(
                reply=reply,
                sources_used=[],
                suggested_followups=cq_followups,
                confidence="Moderate confidence",
            )

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
            # ...unless we already refused the turn before and the farmer is
            # still trying. Repeating the same text teaches them nothing, so
            # ask which crop and district they mean instead. Still no Groq
            # call, so the grounding property is unchanged.
            if _should_retry_after_refusal(clean, req.conversation_history):
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
            max_tokens=768,
            temperature=0.7,
            reasoning_effort="low",
        )
        reply = response.choices[0].message.content

        # Strip the model's FOLLOWUP: lines BEFORE anything else touches the
        # text — everything downstream (the response body, persistence, the
        # refusal marker check) must see only the farmer-facing answer.
        reply, llm_followups = _parse_followups_from_response(reply)

        # LLM-level refusal: retrieval cleared the relevance floor but the
        # chunks didn't actually answer the question (e.g. rice query,
        # carrot chunks), so the model used the canned refusal. Override
        # the retrieval-derived confidence and drop the unhelpful sources
        # so the XAI badge and chips stay truthful.
        if reply and _OUT_OF_SCOPE_MARKER in reply:
            confidence = "Out of scope"
            context["sources"] = []

        # Cache the reply for future repeated questions

        followups, chip_meta = _resolve_followup_chips(
            reply, llm_followups, context, clean, req
        )
        _remember_shown_chips(req, followups, chip_meta)
        _emit_analytics(
            req, clean, "answer", confidence, context, start, chip_meta=chip_meta
        )
        return ChatResponse(
            reply=reply,
            sources_used=context["sources"],
            suggested_followups=followups,
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
    _reset_override_match()
    _safe_audit(req.user_id, clean)
    groq_model = _GROQ_MODELS.get(req.model, _GROQ_MODELS["accurate"])

    # Saved area/crop for a brand-new conversation — same as chat().
    saved_crop = saved_district = None
    if not req.conversation_history:
        _prefs = _safe_get_preferences(req.user_id)
        saved_crop = _prefs.get("preferred_crop")
        saved_district = _prefs.get("preferred_district")

    # Context-rebuilt retrieval query (land-unit reply / short follow-up) —
    # retrieval only, same as chat(). See _retrieval_query.
    retrieval_query = _retrieval_query(clean, req.conversation_history)

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
        _ctx_crop, _ctx_district = _extract_context_terms(clean)
        if _ctx_crop or _ctx_district:
            _save_context_async(req.user_id, _ctx_crop, _ctx_district)
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
                    max_tokens=768,
                    temperature=0.7,
                    reasoning_effort="low",
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
    # Template chips as the starting value. The special-path branches below
    # replace `followups` with their own fixed sets (clarification / refusal /
    # …), and the ANSWER path replaces it again after the stream completes —
    # the LLM's suggestions only exist once the full text has arrived. The
    # closure below reads `followups` at call time, so each path's final
    # assignment is what the metadata event carries.
    followups = _fallback_followups(context, clean, req)
    chip_meta = {
        "source": "template_fallback",
        "generated": 0,
        "validated_count": 0,
        "validated": False,
    }

    def _metadata(conv_id: str) -> dict:
        return {
            "type": "metadata",
            "confidence": confidence,
            "sources": context["sources"],
            "suggested_followups": followups,
            "conversation_id": conv_id,
        }

    # Saved-context confirmation — same as chat(): confirm an ambiguous fresh
    # query against the farmer's saved area/crop instead of assuming it.
    if _should_confirm_saved_context(req, clean, saved_crop, saved_district):
        reply, cq_followups = _build_context_confirmation(
            req, clean, saved_crop, saved_district
        )
        followups = cq_followups
        yield {"type": "text", "content": reply}
        conv_id = _persist(reply)
        logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(reply))
        confidence = "Moderate confidence"
        yield _metadata(conv_id)
        _emit_analytics(
            req,
            clean,
            "clarification",
            "Moderate confidence",
            context,
            start,
            used_saved_context=True,
        )
        return

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
        # Second refusal in a row — ask instead of repeating. See chat().
        if _should_retry_after_refusal(clean, req.conversation_history):
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
            max_tokens=768,
            temperature=0.7,
            reasoning_effort="low",
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

    # The FOLLOWUP: lines arrive at the tail of the stream, so they have
    # already been yielded as text events by the loop above and are briefly
    # visible in the bubble. Strip them from the authoritative copy here:
    # what gets persisted, length-logged and re-rendered by the client on the
    # metadata event is clean. (Future enhancement: buffer trailing deltas and
    # withhold any line starting with the prefix, removing the flicker
    # entirely — Option B. Option A is deliberate for now.)
    full, llm_followups = _parse_followups_from_response(full)

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

    # Rebind before _metadata() is called — the closure reads these at call
    # time, so this is what the client receives.
    followups, chip_meta = _resolve_followup_chips(
        full, llm_followups, context, clean, req
    )
    _remember_shown_chips(req, followups, chip_meta)

    conv_id = _persist(full)
    logger.info("[STREAM COMPLETE] conv=%s len=%d", conv_id, len(full))
    yield _metadata(conv_id)
    _emit_analytics(
        req, clean, "answer", confidence, context, start, chip_meta=chip_meta
    )


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
        f"{district}{crop}\n"
        "Speak like a friendly, experienced agricultural advisor who genuinely "
        "cares about the farmer's success. Use a warm, conversational tone — as "
        "if you're chatting with a neighbor over tea, not writing a government "
        "report. Say 'you can expect' instead of 'the predicted yield is'. Say "
        "'farmers are getting around' instead of 'the average farmgate price "
        "is'. Start answers with context ('If you plant carrots in "
        "Badulla...') not raw data ('The yield is...'). Keep it natural — "
        "never sound like you're reading from a spreadsheet.\n\n"
        "RULES (in priority order):\n"
        "1. Answer ONLY from the 'Relevant context' provided. Never use "
        "general knowledge. Never guess.\n"
        f'2. If no context is provided, reply with exactly: "{_OUT_OF_SCOPE_REPLY}"\n'
        "3. Start every answer with one short sentence: 'Reasoning: ' that "
        "briefly mentions which data you used (e.g. 'Reasoning: CropSphere "
        "data for Carrot in Badulla, Inter season.'). Keep it short and "
        "natural — one line, not a formal citation. Then leave a BLANK LINE "
        "and give your final answer. The blank line after the Reasoning "
        "sentence is required — never put the answer on the very next "
        "line.\n"
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
        "'show me the math', or 'explain the calculation'.\n"
        "6. If the user sends a short follow-up like 'yes', 'explain', or "
        "'tell me more', continue explaining the topic from your previous "
        "response. Do not say you don't have data if you were just "
        "discussing that topic.\n"
        # Numbered 7, not 6: Part A already has a Rule 6 above. Two rules
        # sharing a number is the kind of thing an LLM silently skips.
        f"7. After your answer, suggest exactly 3 short follow-up questions "
        f"the farmer might want to ask next, based on what you just told "
        f"them. Put each on its own line starting with '{_FOLLOWUP_PREFIX}' "
        f"at the very end of your response:\n"
        f"{_FOLLOWUP_PREFIX} Prevention methods for carrot pests\n"
        f"{_FOLLOWUP_PREFIX} How do these pests spread\n"
        f"{_FOLLOWUP_PREFIX} More about carrot diseases in Badulla\n"
        "Rules for followup suggestions:\n"
        "- Must be directly related to your answer content\n"
        "- Must be questions you can answer from the dataset\n"
        "- Keep each under 10 words\n"
        "- All three must be different from each other\n"
        "- Don't suggest what you already answered\n"
        "- Frame as the farmer would ask, not formally"
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


def _normalise_followup(message: str) -> str:
    """Lowercase, drop punctuation, collapse whitespace — the shape the
    follow-up tables above are written in ("Yes, explain!" -> "yes explain")."""
    return " ".join(re.findall(r"[a-z0-9]+", message.lower()))


def _looks_like_followup(message: str) -> bool:
    """True when the message reads as a continuation of the previous turn
    rather than a question that stands on its own.

    Two halves: an exact table of pure continuation requests ("yes explain",
    "tell me more", "go on"), and heuristics for short messages — an
    affirmative opening, a partial-question connector ("and the price?"), a
    pronoun with nothing for it to refer to in the message itself ("why is
    that?"), or a bare wh-word ("how come?"). The heuristics never fire on a
    message that names its own crop or district, since that message already
    carries the retrieval signal it needs.

    History-independent on purpose: _is_followup adds the "there IS a previous
    turn" half, and _followup_context uses this alone to skip past earlier
    follow-ups while walking back to the last real question.
    """
    msg = _normalise_followup(message)
    if not msg:
        return False
    if msg in _FOLLOWUP_EXACT:
        return True
    if len(msg) > _FOLLOWUP_MAX_LEN:
        return False
    words = msg.split()
    if any(msg.startswith(p) for p in _FOLLOWUP_PREFIXES):
        return True
    if words[0] in _AFFIRMATIVE_TOKENS and len(words) <= 4:
        return True
    if any(_extract_context_terms(msg)):
        return False
    if set(words) & _FOLLOWUP_PRONOUNS:
        return True
    return words[0] in _WH_TOKENS and len(words) <= 3


def _is_followup(message: str, history: list | None) -> bool:
    """True when the message is a follow-up AND there is a previous assistant
    turn for it to follow up on. A follow-up shape on the very first turn of a
    conversation is just a vague question — it gets the normal treatment."""
    if not history:
        return False
    if _last_assistant_reply(history) is None:
        return False
    return _looks_like_followup(message)


def _followup_context(history: list | None) -> tuple:
    """The topic a short follow-up is attaching itself to.

    Walks the conversation newest-first and returns (question, crop, district):
      question — the most recent USER message that was a real question (not
                 itself a follow-up), "" when there is none
      crop /
      district — the covered crop/district named in the most recent topical
                 assistant reply, falling back to that question; None when
                 neither names one
    Turns whose assistant reply was a refusal or the capability summary are
    skipped — the same recency filter _rag_context and _recent_topic use. That
    filter is also what stops a repeated "out of scope" loop: the second short
    message reaches back PAST the refusal to the topic that actually worked.
    Newest wins for every field, so a topic switch mid-conversation is not
    overridden by the older question underneath it.

    Inputs: history (ConversationTurn list, most recent turn last).
    Outputs: (question, crop, district) — all empty/None when the history holds
    nothing topical.
    """
    turns = history or []
    question = ""
    crop = district = None
    for i in range(len(turns) - 1, -1, -1):
        turn = turns[i]
        if turn.role == "assistant":
            if _is_non_topic_reply(turn.content):
                continue
            a_crop, a_district = _extract_context_terms(turn.content)
            crop = crop or a_crop
            district = district or a_district
            continue
        nxt = turns[i + 1] if i + 1 < len(turns) else None
        if nxt and nxt.role == "assistant" and _is_non_topic_reply(nxt.content):
            continue  # refused / capability topic — not what the user meant
        if _looks_like_followup(turn.content):
            continue  # a follow-up of its own carries no topic
        if not question:
            question = turn.content
            u_crop, u_district = _extract_context_terms(turn.content)
            crop = crop or u_crop
            district = district or u_district
    return question, crop, district


def _strip_terms(text: str, terms: list) -> str:
    """Remove whole-word occurrences of `terms` from `text` (case-insensitive),
    collapsing the whitespace left behind."""
    out = text
    for term in terms:
        if term:
            out = re.sub(rf"\b{re.escape(term)}\b", " ", out, flags=re.IGNORECASE)
    return " ".join(out.split())


def _reformulate_query(message: str, history: list | None) -> str:
    """Rebuild a short follow-up into a retrieval query with real content.

    "yes explain" has no semantic overlap with any knowledge chunk, so on its
    own it scores below _MIN_RELEVANCE and the grounding guard refuses it one
    turn after a good answer. Prepending the topic the farmer is following up
    on ("how do I test my soil" + crop/district from the last answer) gives
    retrieval something to match, and the follow-up's own words still steer
    which part of that topic wins — "and the price?" pulls price chunks for the
    crop already under discussion.

    Only the dimensions the follow-up did NOT name itself are inherited, and
    the inherited name is stripped from the carried-over question: "tell me
    about Maize" followed by "and Cowpea?" must retrieve Cowpea, not Maize.

    Only the retrieval query is affected — the message audited, routed, and
    sent to Groq as the "user" turn is untouched. Groq already receives the
    conversation history, so it resolves the reference itself.

    Inputs: message (sanitised current user text); history (ConversationTurn
    list from the request, most recent turn last).
    Outputs: the rebuilt query, or the original message when this is not a
    follow-up or the history holds no topic to inherit.
    """
    if not _is_followup(message, history):
        return message
    question, crop, district = _followup_context(history)
    msg_crop, msg_district = _extract_context_terms(message)

    drop = [crop if msg_crop else None, district if msg_district else None]
    topic = _strip_terms(question, drop)[:_FOLLOWUP_TOPIC_MAX_LEN]
    parts = [topic]
    if crop and not msg_crop:
        parts.append(crop)
    if district and not msg_district:
        parts.append(district)
    if not any(parts):
        return message  # nothing topical to inherit — leave the query alone
    parts.append(message)
    return " ".join(p for p in parts if p)[:_MAX_LEN]


def _retrieval_query(message: str, history: list | None) -> str:
    """The query used for RAG retrieval only, never for routing or for Groq.

    Chains the two context rebuilds, most specific first: a bare land-unit
    reply to the bot's own clarifying question (_expand_clarifying_reply), then
    the general short-follow-up case (_reformulate_query). At most one applies
    — a unit reply is already expanded with the question it answers.
    """
    expanded = _expand_clarifying_reply(message, history)
    if expanded != message:
        return expanded
    return _reformulate_query(message, history)


def _last_reply_was_refusal(history: list | None) -> bool:
    """True when the bot's most recent turn refused the question, in any
    refusal template (canned, near-miss, or generic)."""
    last = _last_assistant_reply(history)
    return bool(last) and any(sig in last for sig in _REFUSAL_SIGNATURES)


def _should_retry_after_refusal(message: str, history: list | None) -> bool:
    """True when the grounding guard is about to refuse a message that the bot
    ALREADY refused the turn before — repeating the same "out of scope" text is
    a dead end for the farmer, so the caller asks a clarifying question instead
    and lets _followup_context reach further back for the real topic.

    Deliberately narrow. It fires only for a follow-up ("try again with the
    same intent") or a message with clear agricultural intent; a genuinely
    unrelated question (weather on Mars, a joke) still gets the refusal, twice
    if asked twice. An explicitly uncovered crop/district never reaches here at
    all — _explicit_miss answers that earlier with a specific, useful pointer,
    which is better than a clarifying question.
    """
    if not _last_reply_was_refusal(history):
        return False
    return _looks_like_followup(message) or _has_agricultural_intent(message)


def _resolves_from_followup_context(message: str, history: list | None) -> bool:
    """True when the message is a follow-up whose crop or district we can read
    off the conversation. The vague/ambiguous checks below ask the farmer WHICH
    crop and district they mean; when the previous turn already answered that,
    asking again is a worse response than just answering."""
    if not _is_followup(message, history):
        return False
    _question, crop, district = _followup_context(history)
    return bool(crop or district)


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

    Admin-approved overrides are checked AFTER every hardcoded list and BEFORE
    the bare-"simply" guard: they can only add matches this function would
    otherwise have missed, never suppress one it already makes.
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
    if _match_override_phrases(msg, "reformulation"):
        return True
    if "simply" in msg and len(message.strip()) < _BARE_SIMPLY_MAX_LEN:
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
    if any(p in msg for p in _AGRICULTURAL_INTENT_PHRASES):
        return True
    return _match_override_phrases(msg, "agricultural_intent")


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
    if _resolves_from_followup_context(message, history):
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
    if _resolves_from_followup_context(message, history):
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
    situation ("I'm from Jaffna") rather than asking a question.

    Questions are rejected up front: "What crops can I grow in Anuradhapura?"
    contains the phrase "i grow" but is clearly a question and must reach
    retrieval, not the context-ack short-circuit.
    """
    msg = message.lower().strip()

    if msg.endswith("?"):
        return False
    if any(
        msg.startswith(w)
        for w in (
            "what ",
            "which ",
            "how ",
            "can ",
            "where ",
            "when ",
            "why ",
            "do ",
            "does ",
            "is ",
            "are ",
            "tell ",
            "show ",
            "compare ",
            "wat ",
        )
    ):
        return False

    if any(p in msg for p in _CONTEXT_STATEMENT_PHRASES):
        return True
    # Overrides are checked only after the question guards above, so an
    # admin-added phrase can never turn a real question into a context ack.
    return _match_override_phrases(msg, "context_statement")


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


# ── Saved profile context ─────────────────────────────────────────────────────
# Persist the farmer's explicitly-stated area/crop ("I'm from Jaffna") to their
# profile, and on a fresh conversation use it to CONFIRM an ambiguous question
# ("Do you mean carrot in Jaffna?") rather than silently assuming it. Retrieval
# and the system prompt are deliberately untouched — saved context only powers
# this confirmation and the client's UI personalisation.


def _extract_context_terms(message: str) -> tuple:
    """Covered (crop, district) named in the message — enum values or None.
    The same extraction _build_context_ack uses, factored out so saving and
    confirming stay in sync with what retrieval can actually use."""
    caps = _dataset_capabilities()
    msg = message.lower()
    crop = next((c for c in caps["crops"] if c.lower() in msg), None)
    district = next((d for d in caps["districts"] if d.lower() in msg), None)
    return crop, district


def _save_context_async(user_id: str, crop, district) -> None:
    """Persist explicit context to the user's profile in a daemon thread — the
    write must never slow or break the chat response (fire-and-forget)."""

    def _run():
        try:
            from app.utils.firestore import update_user_context

            update_user_context(
                user_id, preferred_crop=crop, preferred_district=district
            )
        except Exception as exc:
            logger.warning("save context failed: %s", exc)

    try:
        threading.Thread(target=_run, daemon=True).start()
    except Exception as exc:
        logger.warning("save context thread spawn failed: %s", exc)


def _safe_get_preferences(user_id: str) -> dict:
    """Read saved preferences for a fresh conversation. Never raises — returns
    {} on any failure so chat proceeds without saved context."""
    try:
        from app.utils.firestore import get_user_preferences

        return get_user_preferences(user_id) or {}
    except Exception as exc:
        logger.warning("load preferences failed: %s", exc)
        return {}


def _should_confirm_saved_context(req, message, saved_crop, saved_district) -> bool:
    """True when a fresh, dropdown-free query omits a crop OR district that the
    saved profile can supply — so we confirm ("Do you mean … in Jaffna?")
    instead of silently assuming. Dropdown selections always win, so a
    dimension the user set in the dropdown is never filled from saved context.
    """
    eff_saved_crop = None if req.crop else saved_crop
    eff_saved_district = None if req.district else saved_district
    if not (eff_saved_crop or eff_saved_district):
        return False
    msg_crop, msg_district = _extract_context_terms(message)
    crop = (req.crop.value if req.crop else None) or msg_crop or eff_saved_crop
    district = (
        (req.district.value if req.district else None)
        or msg_district
        or eff_saved_district
    )
    filled = (not (req.crop or msg_crop) and eff_saved_crop) or (
        not (req.district or msg_district) and eff_saved_district
    )
    return bool(crop and district and filled and _has_agricultural_intent(message))


def _build_context_confirmation(req, message, saved_crop, saved_district) -> tuple:
    """Confirmation reply + a tappable resolved-topic chip. Deterministic; no
    Groq. Precedence for each dimension: dropdown, then message, then saved."""
    msg_crop, msg_district = _extract_context_terms(message)
    crop = (req.crop.value if req.crop else None) or msg_crop or saved_crop
    district = (
        (req.district.value if req.district else None) or msg_district or saved_district
    )
    reply = (
        f"Do you mean {crop} in {district}? I've used what you told me "
        "earlier — tap to confirm, or type a different crop or district."
    )
    return reply, [f"{crop} in {district}", "A different crop or district"]


def _is_capability_question(message: str) -> bool:
    """True when the user asks what the bot covers (crops/districts/skills)."""
    msg = message.lower()
    if any(p in msg for p in _CAPABILITY_PATTERNS):
        return True
    return _match_override_phrases(msg, "capability")


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


def _load_fewshot_examples() -> dict:
    """Load few-shot examples from the JSON file, cached for the process
    lifetime. Returns {} if the file is missing or unreadable — the chatbot
    works fine without examples, just less consistently."""
    global _fewshot_examples
    if _fewshot_examples is None:
        try:
            from app.user.services.fewshot_service import FEWSHOT_PATH

            _fewshot_examples = (
                json.loads(FEWSHOT_PATH.read_text()) if FEWSHOT_PATH.exists() else {}
            )
        except Exception as exc:
            logger.warning("few-shot load failed: %s", exc)
            _fewshot_examples = {}
    return _fewshot_examples


def _reload_fewshot_examples() -> dict:
    """Drop the cache and reload — called by the admin rebuild endpoint after
    fewshot_service rewrites the file."""
    global _fewshot_examples
    _fewshot_examples = None
    return _load_fewshot_examples()


def _load_pattern_overrides() -> dict:
    """Load admin-approved pattern overrides, cached for the process lifetime.

    Outputs: {category: {"phrases": [(phrase, id)], "patterns": [((verb,
    quals), id)]}} for the four routing categories — the compiled form the
    predicates below consume, not the raw file. Returns {} if the file is
    missing or unreadable, in which case every predicate falls back to its
    hardcoded lists alone.

    Cached because it sits on the chat hot path: one file read per process, and
    the check itself is a substring scan over a handful of short strings.
    """
    global _pattern_overrides
    if _pattern_overrides is None:
        try:
            from app.user.services.pattern_override_store import compile_overrides

            _pattern_overrides = compile_overrides()
        except Exception as exc:
            logger.warning("pattern-override load failed: %s", exc)
            _pattern_overrides = {}
    return _pattern_overrides


def _reload_pattern_overrides() -> dict:
    """Drop the cache and reload — called by the admin apply/revoke/restore/
    delete endpoints after pattern_override_store rewrites the file."""
    global _pattern_overrides
    _pattern_overrides = None
    return _load_pattern_overrides()


def _reset_override_match() -> None:
    """Clear this thread's override-match slot at the start of a turn."""
    _override_match.value = None


def _note_override_match(category: str, pattern_id: str, phrase: str) -> None:
    """Record that an override — not a hardcoded pattern — routed this turn.

    First match wins: a message can satisfy several predicates as it falls
    through the pipeline, but only the one that actually decided the branch is
    worth attributing a later thumbs vote to. Writes nothing to disk; the hit
    is persisted later by _run_analytics on its background thread.
    """
    if getattr(_override_match, "value", None) is None:
        _override_match.value = {
            "category": category,
            "pattern_id": pattern_id,
            "phrase": phrase,
        }


def _current_override_match() -> dict | None:
    """This thread's override match for the current turn, or None."""
    return getattr(_override_match, "value", None)


def _match_override_phrases(msg: str, category: str) -> bool:
    """Shared override check for the four routing predicates.

    Inputs: msg — the already-lowercased message. category — which override
    bucket to consult.
    Outputs: True when an active override phrase (or combo pattern) matches, in
    which case the match is noted for hit tracking. Never raises — a broken
    override file must not break routing.
    """
    extra = _load_pattern_overrides().get(category) or {}
    for phrase, pattern_id in extra.get("phrases", []):
        if phrase in msg:
            _note_override_match(category, pattern_id, phrase)
            return True
    for (verb, qualifiers), pattern_id in extra.get("patterns", []):
        if verb in msg and any(q in msg for q in qualifiers):
            _note_override_match(category, pattern_id, verb)
            return True
    return False


def _load_prompt_tuning() -> dict:
    """Load the prompt-tuning store, cached for the process lifetime.

    Returns the full store dict ({active, trash, audit_log}) so the trial
    check below can read lifecycle dates without a second disk hit. Returns an
    empty store if the file is missing or unreadable — the chatbot runs on its
    static prompt, which is the intended graceful default.
    """
    global _prompt_tuning
    if _prompt_tuning is None:
        try:
            from app.user.services.prompt_tuning_store import load as _load_store

            _prompt_tuning = _load_store()
        except Exception as exc:
            logger.warning("prompt-tuning load failed: %s", exc)
            _prompt_tuning = {}
    return _prompt_tuning


def _reload_prompt_tuning() -> dict:
    """Drop the cache and reload — called by the admin lifecycle endpoints and
    by the validation pass after the store changes on disk."""
    global _prompt_tuning
    _prompt_tuning = None
    return _load_prompt_tuning()


def _check_prompt_tuning_trials(store: dict) -> None:
    """Fire the auto-validation pass if a trial has run its course.

    Deliberately cheap: the due-check is a date comparison against the store
    dict already in memory (no I/O), and the pass itself is throttled and runs
    on a background thread — this is on the chat request path and must never
    add latency. Any failure is swallowed for the same reason.
    """
    try:
        from app.admin.services.tuning_validation_service import maybe_run_validations

        maybe_run_validations(store)
    except Exception as exc:
        logger.debug("tuning validation check skipped: %s", exc)


def _format_prompt_tuning_injection() -> str:
    """Render live tuning adjustments into one supplementary system message,
    or "" when there are none.

    Only adjustments with status "trial" or "permanent" are injected —
    anything trashed or auto-removed is skipped. ONLY the fixed-template
    instruction strings are emitted: tuning can add guidance but never alters
    Part A rules, the refusal text, the 'Reasoning:' prefix, the no-calc rule,
    or the earnings anchor (see prompt_tuning_service safety notes). Admin
    comments and trigger text never reach the prompt.
    """
    from app.user.services.prompt_tuning_store import LIVE_STATUSES

    store = _load_prompt_tuning()
    _check_prompt_tuning_trials(store)
    lines = [
        a["instruction"]
        for a in store.get("active", [])
        if isinstance(a, dict)
        and a.get("status") in LIVE_STATUSES
        and isinstance(a.get("instruction"), str)
        and a["instruction"].strip()
    ]
    if not lines:
        return ""
    return "SYSTEM ADJUSTMENTS (based on recent usage patterns):\n" + "\n".join(
        f"- {line}" for line in lines
    )


def _format_prediction_context(pc) -> str:
    """Render a PredictionContext as one plain-text context block for the LLM.

    Inputs: pc (schemas.PredictionContext or None) — the yield OR price
    prediction the farmer tapped "Ask AI about this" on. The two share
    crop/district/season and are otherwise disjoint; only the fields actually
    set are rendered, so one block serves both without either screen's
    numbers leaking into the other's conversation.
    Outputs: a system-message body, or "" when there is nothing to say (pc is
    None, or every field was left unset) so the caller can skip the message
    entirely.

    Security assumption: every field on PredictionContext is an enum, a
    Literal, a bool, or a bounded float (see schemas.PredictionContext), so
    nothing
    client-authored reaches the prompt as free text. No sanitising is needed
    here and none is done — if a free-text field is ever added to that model,
    it must be run through _strip_html before being interpolated below.
    """
    if pc is None:
        return ""

    facts = []
    if pc.crop:
        facts.append(f"- Crop: {pc.crop.value}")
    if pc.district:
        facts.append(f"- District: {pc.district.value}")
    if pc.season:
        facts.append(f"- Season: {pc.season.value}")
    if pc.irrigation:
        facts.append(f"- Irrigation: {pc.irrigation.value}")
    if pc.area_perches is not None:
        area = f"- Cultivated area: {pc.area_perches:,.0f} perches"
        if pc.area_hectares is not None:
            area += f" ({pc.area_hectares:.3f} ha)"
        facts.append(area)
    elif pc.area_hectares is not None:
        facts.append(f"- Cultivated area: {pc.area_hectares:.3f} ha")
    if pc.predicted_yield_kg_per_ha is not None:
        facts.append(f"- Predicted yield: {pc.predicted_yield_kg_per_ha:,.0f} kg/ha")
    if pc.average_yield_kg_per_ha is not None:
        facts.append(
            f"- District average yield: {pc.average_yield_kg_per_ha:,.0f} kg/ha"
        )
    # The gap is the single number most questions about a prediction are
    # really about ("is this good?", "how do I improve it?"), and the model
    # is instructed elsewhere not to calculate — so state it outright rather
    # than leaving it to be derived from the two figures above.
    if pc.predicted_yield_kg_per_ha is not None and pc.average_yield_kg_per_ha:
        delta = (
            (pc.predicted_yield_kg_per_ha - pc.average_yield_kg_per_ha)
            / pc.average_yield_kg_per_ha
            * 100
        )
        direction = "above" if delta >= 0 else "below"
        facts.append(f"- Difference: {abs(delta):.0f}% {direction} the average")
    # ── Price-side facts ─────────────────────────────────────────────────────
    if pc.predicted_price_lkr_kg is not None:
        facts.append(
            f"- Predicted farmgate price: Rs. {pc.predicted_price_lkr_kg:,.0f}/kg"
        )
    if pc.average_price_lkr_kg is not None:
        line = f"- Average farmgate price for this crop: Rs. {pc.average_price_lkr_kg:,.0f}/kg"
        # Provenance travels WITH the number. A null source means the client
        # showed no baseline and stated nothing about where one came from;
        # the assistant must not be handed one either.
        if pc.average_price_source == "real":
            line += " (from real market data)"
        elif pc.average_price_source == "synthetic":
            line += " (estimated from modelled data)"
        facts.append(line)
    # Same reasoning as the yield gap above: state the comparison outright
    # rather than leaving the model to derive it from two figures.
    if pc.predicted_price_lkr_kg is not None and pc.average_price_lkr_kg:
        delta = (
            (pc.predicted_price_lkr_kg - pc.average_price_lkr_kg)
            / pc.average_price_lkr_kg
            * 100
        )
        direction = "above" if delta >= 0 else "below"
        facts.append(f"- Difference: {abs(delta):.0f}% {direction} the average")
    if pc.quantity_kg is not None:
        qty = f"- Quantity the farmer plans to sell: {pc.quantity_kg:,.0f} kg"
        if pc.estimated_earnings_lkr is not None:
            qty += f" (estimated Rs. {pc.estimated_earnings_lkr:,.0f} total)"
        facts.append(qty)
    if pc.supply_level:
        facts.append(f"- Market supply: {pc.supply_level}")
    if pc.demand_level:
        facts.append(f"- Buyer demand: {pc.demand_level}")
    if pc.holiday_week:
        facts.append("- This is a holiday week")
    if pc.festival_week:
        facts.append("- This is a festival week")

    if pc.confidence:
        facts.append(f"- Model confidence: {pc.confidence.value}")

    if pc.weather:
        w = pc.weather
        bits = []
        if w.rainfall_mm is not None:
            bits.append(f"rainfall {w.rainfall_mm:.0f} mm")
        if w.temp_min_c is not None and w.temp_max_c is not None:
            bits.append(f"temperature {w.temp_min_c:.0f}-{w.temp_max_c:.0f} C")
        if w.humidity_pct is not None:
            bits.append(f"humidity {w.humidity_pct:.0f}%")
        if w.wind_speed_kmh is not None:
            bits.append(f"wind {w.wind_speed_kmh:.0f} km/h")
        if w.solar_radiation_mj is not None:
            bits.append(f"solar radiation {w.solar_radiation_mj:.0f} MJ")
        if bits:
            facts.append(f"- Weather used: {', '.join(bits)}")

    if not facts:
        return ""

    # Name the right kind of prediction. The block used to say "yield"
    # unconditionally; with price contexts sharing this model, telling the
    # assistant a farmer is asking about a yield prediction while handing it
    # Rs./kg figures invites it to answer the wrong question.
    if pc.predicted_yield_kg_per_ha is not None:
        kind = "yield prediction"
    elif pc.predicted_price_lkr_kg is not None:
        kind = "price prediction"
    else:
        kind = "prediction"

    return (
        f"The farmer is asking about a {kind} CropSphere just "
        "produced for them. Ground your answer in THESE figures — they "
        "override any general dataset averages you were given above:\n"
        + "\n".join(facts)
    )


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
    # Yield-prediction context (optional) — set when the farmer arrived here
    # from "Ask AI about this" on a prediction result, so the answer must be
    # about THOSE numbers rather than generic dataset averages.
    #
    # Position: immediately after the RAG chunks and before _FORMATTING_RULES.
    # It belongs with the chunks because it is the same KIND of message —
    # grounding facts, not instructions — and slotting it there leaves every
    # existing message in its existing relative order: formatting rules,
    # knowledge level, few-shot, prompt tuning, all-crops, history and the
    # user message all still follow one another exactly as before.
    #
    # It is a SEPARATE system message and is never merged into `message`.
    # That is what keeps analytics clean: _run_analytics logs `message[:200]`
    # as chat_analytics.question, and `message` is the caller's sanitised
    # user text, which this function does not touch.
    _prediction = _format_prediction_context(getattr(req, "prediction_context", None))
    if _prediction:
        msgs.append({"role": "system", "content": _prediction})
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
    # Few-shot examples — thumbs-up answers of the SAME question type, so the
    # model matches a style farmers already approved. Injected as its own
    # system message right after the level instruction. Skipped entirely when
    # there are no examples for this type (identical to prior behaviour). See
    # _load_fewshot_examples / fewshot_service.
    _examples = (
        _load_fewshot_examples().get("examples", {}).get(_question_type(message), [])
    )
    if _examples:
        _parts = [
            "Here are examples of answers that farmers found helpful. "
            "Match this style:\n"
        ]
        for _i, _ex in enumerate(_examples[:2], 1):
            _parts.append(
                f"\nExample {_i}:\nQ: {_ex.get('question', '')}\n"
                f"A: {_ex.get('answer', '')}"
            )
        msgs.append({"role": "system", "content": "".join(_parts)})
    # Prompt tuning adjustments — admin-approved, analytics-derived supplementary
    # instructions (see prompt_tuning_service). Its own system message AFTER the
    # few-shot examples and BEFORE the all-crops injection. Only ADDS guidance;
    # never modifies Part A rules, the refusal text, the 'Reasoning:' prefix, the
    # no-calc rule, or the earnings anchor. Skipped entirely when the tuning file
    # is empty or missing.
    _tuning = _format_prompt_tuning_injection()
    if _tuning:
        msgs.append({"role": "system", "content": _tuning})
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
            "The user wants a much simpler version of your previous "
            "answer. Here is your previous answer: "
            f"{previous_reply}.\n\n"
            "Rewrite it so a farmer with no formal education can "
            "understand:\n"
            "- Remove ALL numbers except the ONE most important number "
            "(e.g. just the total yield, not per-hectare breakdowns)\n"
            "- Remove all unit conversions — always use acres, the unit "
            "small farmers actually use. Only use hectares or perches if "
            "the farmer specifically asked for that unit.\n"
            "- Use only very basic words — 'grow' not 'harvest', 'money' "
            "not 'earnings', 'sell' not 'farmgate price'\n"
            "- Maximum 2-3 short sentences\n"
            "- Give the practical takeaway, not the data\n"
            "- Remove the Note section if it exists\n"
            "- Remove the earnings offer question\n\n"
            "Example simplifications (vary your style — never repeat the "
            "same pattern):\n"
            "  Before: 'If you plant carrots in Badulla, you can expect "
            "to harvest around 19,769 kg from one hectare (8,015 kg per "
            "acre; 50 kg per perch). Note: The Yala season usually gives "
            "the highest yields. Would you like me to work out how much "
            "you could earn? Just tell me your land size.'\n\n"
            "  Style 1 (practical advice):\n"
            "  'In Badulla, you can grow about 8,000 kg of carrots per "
            "acre. Yala season is your best bet for planting.'\n\n"
            "  Style 2 (farmer-focused):\n"
            "  'Good news — Badulla is great for carrots! One acre can "
            "give you around 8,000 kg, especially if you plant in the "
            "Yala season.'\n\n"
            "  Style 3 (direct and warm):\n"
            "  'Carrots do really well in Badulla. You're looking at "
            "about 8,000 kg from one acre. Try planting in the Yala "
            "season for the best results.'\n\n"
            "  Style 4 (conversational):\n"
            "  'If you've got an acre in Badulla, you could pull in "
            "around 8,000 kg of carrots. The Yala season is when they "
            "grow best there.'\n\n"
            "- Pick a DIFFERENT style each time — never use the same "
            "sentence structure twice in a row. Do not default to "
            "Style 1.\n"
            "- Address the farmer directly — use 'you' and 'your', not "
            "just stating facts\n"
            "- Add one encouraging or practical word where natural: "
            "'good news', 'you're looking at', 'that's a solid harvest', "
            "'not bad at all'. Only when the data actually supports it — "
            "never call a poor yield good news.\n"
            "- End with something useful, not just data — a tip, a "
            "season suggestion, or a gentle nudge to ask more\n\n"
            "These simplification rules OVERRIDE the general formatting "
            "rules for this one reply: ignore the three-section "
            "structure, ignore the show-all-three-units rule, and do NOT "
            "add the earnings offer.\n"
            "Use the same data — do not add new information."
        )
    # Simplify is the one reformulation that must CONTRADICT the standing
    # formatting rules (three sections, all three units, the earnings
    # offer), so its instruction goes AFTER them — the later, more
    # specific system message wins. math/formal_math keep their original
    # position: their rules don't conflict with Part B.
    if rtype in ("math", "formal_math"):
        msgs.append({"role": "system", "content": instruction})
        msgs.append({"role": "system", "content": _FORMATTING_RULES})
    else:
        msgs.append({"role": "system", "content": _FORMATTING_RULES})
        msgs.append({"role": "system", "content": instruction})
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
    the user's message — drives which template _fallback_followups picks."""
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


def _parse_followups_from_response(reply: str) -> tuple:
    """Split an LLM reply into its answer text and its FOLLOWUP: suggestions.

    Rule 7 of _system_prompt tells the model to append up to 3 lines prefixed
    with _FOLLOWUP_PREFIX. This strips them out.

    Inputs: reply — the raw generated text.
    Outputs: (clean_reply, followups). With no FOLLOWUP lines, returns the
    reply unchanged and []. Bounded to _MAX_LLM_FOLLOWUPS; over-long or blank
    suggestions are dropped rather than shown.
    Security assumption: the caller MUST use clean_reply for anything the
    farmer sees or that is persisted — the raw reply still contains the
    marker tokens, which are an internal protocol, not content.
    """
    if not reply:
        return reply, []

    followups: list = []
    answer_lines: list = []
    for line in reply.split("\n"):
        stripped = line.strip()
        if stripped.startswith(_FOLLOWUP_PREFIX):
            # Drop the line from the answer either way — a malformed or
            # surplus suggestion must still never reach the chat bubble.
            candidate = stripped[len(_FOLLOWUP_PREFIX) :].strip()
            if candidate and len(candidate) <= _MAX_FOLLOWUP_LEN:
                if len(followups) < _MAX_LLM_FOLLOWUPS:
                    followups.append(candidate)
        else:
            answer_lines.append(line)

    return "\n".join(answer_lines).strip(), followups


def _validate_followup_chips(followups: list) -> list:
    """Drop generated chips the chatbot could not actually answer.

    A suggestion the farmer taps becomes their next question, so an
    ungrounded chip is a refusal waiting to happen. Each is scored against
    the RAG corpus and kept only if it clears _MIN_RELEVANCE — the same floor
    the live grounding guard uses.

    Inputs: followups — parsed suggestion strings.
    Outputs: the subset that is answerable, order preserved.
    All three are encoded in ONE batch call, so validation costs a single
    forward pass on the cached encoder rather than three.
    Fails OPEN: if the RAG artifacts or encoder are unavailable the
    suggestions are returned as-is — losing every chip to a transient model
    problem is worse than showing one that may miss.
    """
    if not followups:
        return []
    rag = model_loader.get_model("rag_artifacts")
    if rag is None:
        return followups
    try:
        from sentence_transformers import util

        embeddings = rag.get("chunk_embeddings")
        if embeddings is None:
            return followups
        encoder = _get_encoder()
        q_embs = encoder.encode(followups, convert_to_tensor=True)
        sims = util.cos_sim(q_embs, embeddings)
        return [
            followup
            for i, followup in enumerate(followups)
            if float(sims[i].max()) >= _MIN_RELEVANCE
        ]
    except Exception as exc:
        logger.debug("followup validation skipped: %s", exc)
        return followups


def _extract_bot_question_options(reply: str) -> list | None:
    """Turn a question the bot asked the FARMER into tappable answer chips.

    When the reply ends by asking the farmer to choose, the useful next action
    is answering that question — not asking a new one — so these options take
    priority over generated suggestions (see _resolve_followup_chips).

    Detects: an inline "X, Y, or Z?" choice (covers both the land-unit
    clarification and crop/district selection), a bulleted option list, and a
    genuine yes/no question.

    DELIBERATE EXCLUSION: the earnings offer (_EARNINGS_OFFER_PHRASE, "tell me
    your land size") is a soft suggestion the farmer can ignore, not a choice
    they must make. _FORMATTING_RULES asks for it on most answers, so treating
    it as a question would replace the contextual chips nearly every turn.

    Inputs: reply — the cleaned answer text.
    Outputs: a list of chip strings, or None when the bot asked nothing that
    needs answering. Never raises.
    """
    if not reply:
        return None
    try:
        # Only the last few lines can carry the closing question; scanning the
        # whole answer would match rhetorical questions inside the advice.
        tail = "\n".join([ln for ln in reply.strip().split("\n") if ln.strip()][-3:])
        lowered = tail.lower()

        # The earnings offer is never a bot question — bail before anything
        # else can match it (its "Would you like me to..." would hit Pattern 4).
        if _EARNINGS_OFFER_PHRASE in lowered:
            return None

        # Pattern 3: a bulleted option list ("- Carrot\n- Maize\n- Cowpea").
        bullets = [
            re.sub(r"^[-*•]\s*", "", ln).strip().rstrip(".")
            for ln in reply.strip().split("\n")
            if re.match(r"^\s*[-*•]\s+\S", ln)
        ]
        bullets = [b for b in bullets if 0 < len(b) <= _MAX_FOLLOWUP_LEN]
        if len(bullets) >= 2 and "?" in lowered:
            return bullets[:_MAX_LLM_FOLLOWUPS]

        question = next(
            (s for s in reversed(re.split(r"(?<=[.?!])\s+", tail)) if "?" in s),
            "",
        ).strip()
        if not question:
            return None

        # Patterns 1 + 2: "Is that X, Y, or Z?" / "Which crop — X, Y, or Z?".
        # Take the text after the last dash/colon when present so the lead-in
        # ("Which crop are you asking about —") doesn't become an option.
        body = (
            re.split(r"[—:–-]", question)[-1]
            if re.search(r"[—:–]", question)
            else question
        )
        body = body.strip().rstrip("?").strip()
        if re.search(r",.*\bor\b", body, re.IGNORECASE):
            parts = [
                p.strip().strip(".").strip()
                for p in re.split(r",|\bor\b", body, flags=re.IGNORECASE)
            ]
            options = []
            for i, part in enumerate(parts):
                # The first segment carries the interrogative lead-in ("Is
                # that 3 acres"). Strip the lead-in rather than dropping the
                # segment — the option is the part after it.
                if i == 0:
                    part = _QUESTION_LEADIN_RE.sub("", part).strip()
                if not part or len(part) > _MAX_FOLLOWUP_LEN:
                    continue
                # Anything still opening with an interrogative is lead-in
                # prose, not a choice the farmer can tap.
                if re.match(
                    r"^(is|are|was|which|what|do|does|would|shall)\b", part, re.I
                ):
                    continue
                options.append(part)
            if len(options) >= 2:
                return options[:_MAX_LLM_FOLLOWUPS]

        # Pattern 4: a genuine yes/no question. The earnings offer already
        # returned above, so what reaches here is a real either/or.
        if re.search(
            r"\b(would you like|do you want|shall i|should i|can i)\b", question, re.I
        ):
            return ["Yes please", "No thanks"]
        return None
    except Exception as exc:  # chips must never break a reply
        logger.debug("bot-question extraction failed: %s", exc)
        return None


def _resolve_followup_chips(
    reply: str,
    llm_followups: list,
    context: dict,
    message: str,
    req: ChatRequest,
) -> tuple:
    """Pick which follow-up chips this turn shows (Step 7).

    Priority:
      1. Bot-question options — the farmer needs to answer, not branch away.
      2. RAG-validated LLM suggestions — contextual to the actual answer.
      3. _fallback_followups — the template safety net.

    Inputs: the CLEANED reply (FOLLOWUP lines already stripped), the parsed
    suggestions, the RAG context, the user message and the request.
    Outputs: (chips, meta) where meta feeds the analytics fields in Step 9 —
    source, how many were generated, and how many survived validation.
    Never raises: any failure lands on the template fallback.
    """
    bot_options = _extract_bot_question_options(reply)
    if bot_options:
        return bot_options, {
            "source": "bot_question",
            "generated": len(llm_followups),
            "validated_count": 0,
            "validated": False,
        }

    if llm_followups:
        validated = _validate_followup_chips(llm_followups)
        if validated:
            return validated, {
                "source": "llm_generated",
                "generated": len(llm_followups),
                "validated_count": len(validated),
                "validated": True,
            }

    return _fallback_followups(context, message, req), {
        "source": "template_fallback",
        "generated": len(llm_followups),
        "validated_count": 0,
        "validated": bool(llm_followups),
    }


def _fallback_followups(context: dict, message: str, req: ChatRequest) -> list:
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


def _tapped_chip(message: str, previous: tuple) -> dict | None:
    """Identify WHICH chip the farmer tapped, not just that they tapped one.

    Inputs: the current message and (chips, meta) — from _recall_shown_chips
    when available, else _reconstruct_previous_followups.
    Outputs: {"template", "source"} for the matched chip, or None when the
    message wasn't a chip tap. Chips are now generated per reply rather than
    rendered from a template, so "template" carries the chip text itself and
    "source" says how it was produced (llm_generated / bot_question /
    template_fallback).
    """
    chips, meta = previous
    if not _detect_if_chip_tapped(message, chips):
        return None
    norm = message.strip().lower()
    matched = next((c for c in chips if (c or "").strip().lower() == norm), None)
    return {
        "template": matched or message[:200],
        "source": (meta or {}).get("source") or "template_fallback",
    }


def _season_for_now() -> str:
    """The active Sri Lankan cultivation season, from today's date.

    Nov 1 - Mar 31 Maha, Apr 1 - Aug 31 Yala, Sep 1 - Oct 31 Inter. Stamped on
    every analytics document so conversation analysis can slice by season
    without re-deriving it from timestamps later.
    """
    month = datetime.now(timezone.utc).month
    if month in (11, 12, 1, 2, 3):
        return "Maha"
    if 4 <= month <= 8:
        return "Yala"
    return "Inter"


def _shown_key(req: ChatRequest) -> str:
    """Cache key for the chips a farmer was last shown: their anonymised uid
    plus the conversation when known (None on a conversation's first turn, so
    the uid alone has to carry it)."""
    return f"{_anonymize_uid(req.user_id)}|{req.conversation_id or ''}"


def _remember_shown_chips(req: ChatRequest, chips: list, meta: dict) -> None:
    """Record the chips this turn is about to show, so the NEXT turn can tell
    whether the farmer tapped one.

    LLM-generated chips cannot be reconstructed after the fact — replaying the
    turn would need a fresh, non-deterministic Groq call — so tap detection
    reads this instead of recomputing. Bounded and in-process: a restart or an
    eviction simply means one turn's tap goes uncounted, consistent with
    analytics being best-effort everywhere else. Never raises.
    """
    try:
        with _shown_chips_lock:
            _shown_chips[_shown_key(req)] = (list(chips or []), dict(meta or {}))
            while len(_shown_chips) > _SHOWN_CHIPS_CAP:
                _shown_chips.popitem(last=False)  # evict oldest
    except Exception as exc:
        logger.debug("chip memo failed: %s", exc)


def _recall_shown_chips(req: ChatRequest) -> tuple:
    """The (chips, meta) shown on the previous turn, or ([], {}) on a miss."""
    try:
        with _shown_chips_lock:
            return _shown_chips.get(_shown_key(req), ([], {}))
    except Exception:
        return ([], {})


def _reconstruct_previous_followups(req: ChatRequest) -> tuple:
    """Recompute the suggested_followups the PREVIOUS assistant turn showed.

    Used only when _recall_shown_chips misses (process restart, cache
    eviction, or a conversation id that appeared between turns). Replays the
    previous USER turn through the same path selection chat() uses — which
    reproduces the FIXED-chip paths exactly (refusal / clarification /
    capability / context ack).

    The normal answer path is NOT reconstructable any more: its chips come
    from the LLM's own suggestions for that specific reply. It therefore
    returns the template fallback, which is what that turn would have shown
    had generation produced nothing — a lower bound, never a false positive
    on some other chip set.

    Called ONLY from the _emit_analytics background thread, so the extra
    retrieval never adds latency to the live response.
    Returns ([], {}) when there is no prior user turn or reconstruction fails.
    """
    empty: tuple = ([], {})
    try:
        history = req.conversation_history or []
        prev_idx = next(
            (i for i in range(len(history) - 1, -1, -1) if history[i].role == "user"),
            None,
        )
        if prev_idx is None:
            return empty
        prev_msg = _strip_html(history[prev_idx].content)[:_MAX_LEN]
        prior = history[:prev_idx]
        district = req.district.value if req.district else ""
        crop = req.crop.value if req.crop else ""

        if _is_context_statement(prev_msg):
            return _build_context_ack(prev_msg)[1], {}
        if _is_capability_question(prev_msg):
            return _capability_reply()[1], {}
        miss = _explicit_miss(prev_msg)
        if miss:
            return _refusal_followups(prev_msg, near=miss), {}
        if _is_reformulation_request(prev_msg) and _last_assistant_reply(prior):
            return _default_followups(req), {}

        retrieval_query = _retrieval_query(prev_msg, prior)
        context = _rag_context(
            retrieval_query, district=district, crop=crop, history=prior
        )
        if _is_vague_agricultural_query(prev_msg, context, prior):
            return _build_clarification(prev_msg, context, prior)[1], {}
        if not context["chunks"]:
            if _should_retry_after_refusal(prev_msg, prior):
                return _build_clarification(prev_msg, context, prior)[1], {}
            return _refusal_followups(prev_msg), {}
        if _is_ambiguous_query(prev_msg, context, prior):
            return _build_clarification(prev_msg, context, prior)[1], {}
        return _fallback_followups(context, prev_msg, req), {
            "source": "template_fallback",
            "generated": 0,
            "validated_count": 0,
            "validated": False,
        }
    except Exception as exc:
        logger.debug("followup reconstruction failed: %s", exc)
        return empty


def _emit_analytics(
    req: ChatRequest,
    message: str,
    response_type: str,
    confidence: str,
    context: dict | None,
    start: float,
    near_miss_type: str | None = None,
    used_saved_context: bool = False,
    chip_meta: dict | None = None,
) -> None:
    """Fire-and-forget: record one chat_analytics document for this turn.

    Runs in a daemon thread for two reasons — analytics must add no latency to
    the chat response, and chip-tap detection reconstructs the previous turn's
    followups which may re-run RAG retrieval (too heavy for the hot path).
    response_time_ms is sampled HERE (just before the caller returns / finishes
    the stream) so it reflects end-to-end handling. Never raises.

    chip_meta is what _resolved_followups returned for THIS turn (source +
    context of the chips being shown), passed by the answer paths only. It is
    what makes per-context chip tap rates computable later: the shown context
    is the denominator, the tapped chip the numerator.

    The override match is read HERE too, on the request thread, because it is
    thread-local: reading it inside the analytics thread would always see None.
    """
    elapsed_ms = int((time.monotonic() - start) * 1000)
    override_match = _current_override_match()
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
                used_saved_context,
                override_match,
                chip_meta,
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
    used_saved_context: bool = False,
    override_match: dict | None = None,
    chip_meta: dict | None = None,
) -> None:
    """Background-thread body: detect a chip tap, assemble the record, hand it
    to log_chat_interaction, and persist any override pattern hit.
    Errors are swallowed."""
    try:
        ctx = context or {}
        # Prefer what was actually shown last turn; fall back to replaying the
        # previous turn only on a cache miss (see _reconstruct_previous_followups).
        previous = _recall_shown_chips(req)
        if not previous[0]:
            previous = _reconstruct_previous_followups(req)
        tapped = _tapped_chip(message, previous)
        shown = chip_meta or {}
        data = {
            "user_id": _anonymize_uid(req.user_id),
            # Present from turn 2 onwards; None on a conversation's first turn,
            # since the server mints the id in persist_chat_turn only after
            # chat() returns. conversation_miner_service._stitch_orphans
            # reattaches those heads when it reconstructs conversations.
            "conversation_id": req.conversation_id or None,
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
            # Cultivation season this turn happened in — stored rather than
            # derived later so an analytics run over old data stays stable
            # even if the season boundaries are ever retuned.
            "season": _season_for_now(),
            "followup_chip_tapped": tapped is not None,
            # Which chip text was tapped, and where that chip came from.
            "tapped_chip_template": (tapped or {}).get("template"),
            "tapped_chip_source": (tapped or {}).get("source"),
            # How this turn's chips were produced (Step 9): llm_generated /
            # bot_question / template_fallback, plus how many the model
            # suggested and how many survived RAG validation.
            "followup_source": shown.get("source"),
            "followup_validated": bool(shown.get("validated")),
            "followups_generated": int(shown.get("generated") or 0),
            "followups_validated": int(shown.get("validated_count") or 0),
            "session_message_count": len(req.conversation_history) + 1,
            "model_used": req.model,
            "response_time_ms": elapsed_ms,
            "used_saved_context": used_saved_context,
            # Which admin-approved override (if any) routed this turn — null
            # for the hardcoded path, which is the vast majority of turns.
            "matched_override_pattern": (
                (override_match or {}).get("pattern_id") or None
            ),
        }
        log_chat_interaction(data)
        _record_pattern_hit(override_match, req, message)
    except Exception as exc:
        logger.warning("analytics assembly failed: %s", exc)


def _record_pattern_hit(
    override_match: dict | None, req: ChatRequest, message: str
) -> None:
    """Persist one override pattern hit (Step 5). Never raises.

    Already on the analytics background thread, so the file write costs the
    chat response nothing. The conversation id is passed through for feedback
    attribution but is only a tie-breaker — it is None on a conversation's
    first turn, since the server mints it in persist_chat_turn afterwards.
    """
    if not override_match:
        return
    try:
        from app.user.services.pattern_override_store import record_hit

        record_hit(
            override_match["pattern_id"],
            message,
            override_match.get("phrase", ""),
            conversation_id=req.conversation_id,
        )
    except Exception as exc:
        logger.warning("pattern hit record failed: %s", exc)
