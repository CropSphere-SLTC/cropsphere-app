"""AI chatbot service — LLaMA 3 via Groq API with RAG."""

import logging

from html.parser import HTMLParser

from app.models.loader import model_loader
from app.models.schemas import ChatRequest, ChatResponse
from app.utils.firestore import audit_log

logger = logging.getLogger(__name__)

_MAX_LEN = 500
_encoder = None  # SentenceTransformer singleton — loaded once on first chat request
_HF_CACHE = (
    "/tmp/hf_cache"  # nosec B108 — intentional, writable by non-root container user
)


def chat(req: ChatRequest, settings) -> ChatResponse:
    """Process a farmer chat message and return an AI response.

    Security controls (shift-left):
    - HTML tags stripped before any processing.
    - Message truncated at 500 chars even if Pydantic somehow passed a longer one.
    - Input hash logged to Firestore for prompt-injection monitoring.
    - Stack traces never exposed to the client.

    Inputs: ChatRequest (Pydantic-validated), Settings instance.
    Outputs: ChatResponse with reply, sources, and follow-up suggestions.
    Security assumption: user_id verified by JWT middleware before this is called.
    """
    clean = _strip_html(req.message)[:_MAX_LEN]

    _safe_audit(req.user_id, clean)

    try:
        from groq import Groq  # type: ignore

        client = Groq(api_key=settings.GROQ_API_KEY)

        context = _rag_context(clean)
        messages = _build_messages(_system_prompt(req), context, req, clean)

        response = client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=messages,
            max_tokens=512,
            temperature=0.7,
        )
        reply = response.choices[0].message.content

        return ChatResponse(
            reply=reply,
            sources_used=context["sources"],
            suggested_followups=_followups(req),
        )
    except Exception as exc:
        logger.error("Chatbot error user=%s: %s", req.user_id, type(exc).__name__)
        raise RuntimeError("Chatbot unavailable") from exc


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
    district = f" The farmer is in {req.district.value}." if req.district else ""
    crop = f" They are asking about {req.crop.value}." if req.crop else ""
    return (
        "You are CropSphere, an agricultural assistant for Sri Lankan farmers. "
        "Provide concise, practical advice about crops, weather, and markets."
        f"{district}{crop}"
    )


def _rag_context(message: str) -> dict:
    """Retrieve the most relevant RAG chunk for the query."""
    rag = model_loader.get_model("rag_artifacts")
    if rag is None:
        return {"text": "", "sources": []}
    try:
        from sentence_transformers import util  # type: ignore

        chunks = rag.get("knowledge_chunks", [])
        metadata = rag.get("chunk_metadata", [])
        embeddings = rag.get("chunk_embeddings")

        if not chunks or embeddings is None:
            return {"text": "", "sources": []}

        encoder = _get_encoder()
        q_emb = encoder.encode(message, convert_to_tensor=True)
        idx = int(util.cos_sim(q_emb, embeddings)[0].argmax())
        source = (
            metadata[idx].get("source", "") if metadata and idx < len(metadata) else ""
        )
        return {"text": chunks[idx], "sources": [source] if source else []}
    except Exception as exc:
        logger.warning("RAG retrieval failed: %s", exc)
        return {"text": "", "sources": []}


def _build_messages(system: str, context: dict, req: ChatRequest, message: str) -> list:
    msgs = [{"role": "system", "content": system}]
    if context["text"]:
        msgs.append(
            {"role": "system", "content": f"Relevant context: {context['text']}"}
        )
    for turn in req.conversation_history[-10:]:
        msgs.append({"role": turn.role, "content": turn.content})
    msgs.append({"role": "user", "content": message})
    return msgs


def _followups(req: ChatRequest) -> list:
    crop = req.crop.value if req.crop else "crops"
    district = req.district.value if req.district else "your area"
    return [
        f"What is the best planting season for {crop} in {district}?",
        f"What are current market prices for {crop}?",
        "How can I improve my soil quality?",
    ]


def _safe_audit(user_id: str, message: str) -> None:
    """Log chat request hash — failure must not interrupt the chat response."""
    try:
        audit_log(
            user_id=user_id, endpoint="/api/chat", input_data={"message": message}
        )
    except Exception as exc:
        logger.warning("Chat audit log failed: %s", exc)
