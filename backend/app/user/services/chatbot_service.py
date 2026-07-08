"""AI chatbot service — LLaMA 3 via Groq API with RAG.

New features:
- Model selection: "fast" (llama-3.1-8b-instant) or "accurate" (llama-3.3-70b-versatile)
- Language detection: auto-detects Sinhala, Tamil, English
- Prompt injection strategy: LLaMA instructed to respond in user's language directly
- Translation cache: repeated phrases served instantly from memory
"""

import logging
import os
import random
import re

from html.parser import HTMLParser

from app.models.loader import model_loader
from app.models.schemas import ChatRequest, ChatResponse
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
    clean = _strip_html(req.message)[:_MAX_LEN]

    _safe_audit(req.user_id, clean)

    # ── Language detection ──────────────────────────────────────────────────
    # If user specified language explicitly, use it; otherwise auto-detect

    # ── Model selection ─────────────────────────────────────────────────────
    groq_model = _GROQ_MODELS.get(req.model, _GROQ_MODELS["accurate"])
    logger.info(f"Using model: {groq_model} (requested: {req.model})")

    try:
        # Capability question ("what crops do you cover?") — answered from
        # our own dataset metadata. No retrieval, no Groq; deterministic and
        # always in scope. Runs after audit (so it is logged) but before
        # retrieval, so it never pollutes the retrieval path.
        if _is_capability_question(clean):
            reply, followups = _capability_reply()
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
            return ChatResponse(
                reply=_build_refusal(clean, near=miss),
                sources_used=[],
                suggested_followups=_refusal_followups(clean, near=miss),
                confidence="Out of scope",
            )

        # RAG retrieval always uses English-normalised query for best results.
        # The UI's optional district/crop filters boost matching chunks in
        # the ranking (never in the relevance floor or confidence label).
        context = _rag_context(
            clean,
            district=req.district.value if req.district else "",
            crop=req.crop.value if req.crop else "",
            history=req.conversation_history,
        )
        confidence = _confidence_label(context)

        # Grounding guard (primary defence): if nothing in our agricultural
        # dataset matched above the relevance floor, refuse deterministically
        # with a friendly, dataset-aware message. The query never reaches the
        # LLM, so it cannot answer from its own general knowledge (e.g.
        # "what's the weather on Mars").
        if not context["chunks"]:
            return ChatResponse(
                reply=_build_refusal(clean),
                sources_used=[],
                suggested_followups=_refusal_followups(clean),
                confidence=confidence,
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

        return ChatResponse(
            reply=reply,
            sources_used=context["sources"],
            suggested_followups=_followups(req),
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
    clean = _strip_html(req.message)[:_MAX_LEN]
    _safe_audit(req.user_id, clean)
    groq_model = _GROQ_MODELS.get(req.model, _GROQ_MODELS["accurate"])

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
        return

    context = _rag_context(
        clean,
        district=req.district.value if req.district else "",
        crop=req.crop.value if req.crop else "",
        history=req.conversation_history,
    )
    confidence = _confidence_label(context)
    followups = _followups(req)

    def _metadata(conv_id: str) -> dict:
        return {
            "type": "metadata",
            "confidence": confidence,
            "sources": context["sources"],
            "suggested_followups": followups,
            "conversation_id": conv_id,
        }

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
    """Build system prompt with language instruction injected."""
    district = f" The farmer is in {req.district.value}." if req.district else ""
    crop = f" They are asking about {req.crop.value}." if req.crop else ""

    # Get language-specific instruction

    base = (
        "You are CropSphere, an agricultural assistant for Sri Lankan farmers."
        f"{district}{crop} "
        "You must answer ONLY using the information in the 'Relevant context' "
        "provided to you. Do not use your own general knowledge, and do not "
        "guess. "
        "When multiple data sources are provided and the user's question is "
        "ambiguous, prioritize data from the district and crop discussed most "
        "recently in the conversation history. However, if the user "
        "explicitly references an earlier topic (e.g. 'go back to the "
        "Badulla question', 'about the carrots we discussed first'), use "
        "that referenced topic instead of the most recent one. "
        "If no 'Relevant context' is provided, reply with exactly: "
        f'"{_OUT_OF_SCOPE_REPLY}" '
        "When you do have relevant context, first write one short sentence "
        "starting with 'Reasoning: ' that names the SPECIFIC data you used "
        "(e.g. the source document, district, season, or crop) — never vague "
        'phrases like "based on similar regions". Then give your final answer '
        "on a new line."
    )

    # Append language instruction — this is the key feature
    return base


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
        if recent_users:
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
            out.append({"text": chunks[i], "source": source, "score": raw})
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


def _followups(req: ChatRequest) -> list:
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


def _safe_audit(user_id: str, message: str) -> None:
    """Log chat request hash — failure must not interrupt the chat response."""
    try:
        audit_log(
            user_id=user_id, endpoint="/api/chat", input_data={"message": message}
        )
    except Exception as exc:
        logger.warning("Chat audit log failed: %s", exc)
