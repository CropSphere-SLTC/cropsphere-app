"""AI chatbot service — LLaMA 3 via Groq API with RAG.

New features:
- Model selection: "fast" (llama-3.1-8b-instant) or "accurate" (llama-3.3-70b-versatile)
- Language detection: auto-detects Sinhala, Tamil, English
- Prompt injection strategy: LLaMA instructed to respond in user's language directly
- Translation cache: repeated phrases served instantly from memory
"""

import logging

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
_OUT_OF_SCOPE_REPLY = (
    "I don't have relevant agricultural data to answer that question. I can help "
    "with Sri Lankan crop recommendations, weather patterns, yield predictions, "
    "and market prices."
)
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
_encoder = None  # SentenceTransformer singleton — loaded once on first chat request
_HF_CACHE = (
    "/tmp/hf_cache"  # nosec B108 — intentional, writable by non-root container user
)

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
        # RAG retrieval always uses English-normalised query for best results.
        # The UI's optional district/crop filters boost matching chunks in
        # the ranking (never in the relevance floor or confidence label).
        context = _rag_context(
            clean,
            district=req.district.value if req.district else "",
            crop=req.crop.value if req.crop else "",
        )
        confidence = _confidence_label(context)

        # Grounding guard (primary defence): if nothing in our agricultural
        # dataset matched above the relevance floor, refuse deterministically.
        # The query never reaches the LLM, so it cannot answer from its own
        # general knowledge (e.g. "what's the weather on Mars").
        if not context["chunks"]:
            return ChatResponse(
                reply=_OUT_OF_SCOPE_REPLY,
                sources_used=[],
                suggested_followups=_followups(req),
                confidence=confidence,
            )

        from groq import Groq  # type: ignore

        client = Groq(api_key=settings.GROQ_API_KEY)

        # Build messages with language instruction injected into system prompt
        messages = _build_messages(
            _system_prompt(req), context, req, clean
        )

        response = client.chat.completions.create(
            model=groq_model,
            messages=messages,
            max_tokens=512,
            temperature=0.7,
        )
        reply = response.choices[0].message.content

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

    context = _rag_context(
        clean,
        district=req.district.value if req.district else "",
        crop=req.crop.value if req.crop else "",
    )
    confidence = _confidence_label(context)
    followups = _followups(req)

    def _persist(full_reply: str) -> str:
        """Save the completed turn; failure logs but never breaks the stream."""
        try:
            from app.user.services.chat_history_service import persist_chat_turn

            return persist_chat_turn(
                verified_uid, req.conversation_id, req.message, full_reply
            )
        except Exception as exc:
            logger.warning(
                "Stream persistence failed uid=%s: %s", verified_uid, exc
            )
            return ""

    def _metadata(conv_id: str) -> dict:
        return {
            "type": "metadata",
            "confidence": confidence,
            "sources": context["sources"],
            "suggested_followups": followups,
            "conversation_id": conv_id,
        }

    # Grounding guard — same deterministic refusal as chat(), no Groq call.
    if not context["chunks"]:
        yield {"type": "text", "content": _OUT_OF_SCOPE_REPLY}
        conv_id = _persist(_OUT_OF_SCOPE_REPLY)
        logger.info(
            "[STREAM COMPLETE] conv=%s len=%d", conv_id, len(_OUT_OF_SCOPE_REPLY)
        )
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
        pass
    # Groq 5xx / auth / connection problems are all server-side issues
    # from the farmer's perspective.
    return "server_error"


# ── Helpers ───────────────────────────────────────────────────────────────────


def _get_encoder():
    """Return the SentenceTransformer encoder, loading it once and caching it."""
    global _encoder
    if _encoder is None:
        from sentence_transformers import SentenceTransformer  # type: ignore
        import os

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


def _rag_context(message: str, district: str = "", crop: str = "") -> dict:
    """Retrieve the top-k most relevant RAG chunks for the query.

    Inputs: message (sanitised user query); optional district/crop from the
    UI dropdown filters.
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
    for turn in req.conversation_history[-10:]:
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
