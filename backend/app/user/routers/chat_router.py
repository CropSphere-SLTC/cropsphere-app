"""AI chatbot router."""

import json
import logging

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse

from app.config import get_settings
from app.middleware.roles import require_user
from app.middleware.rate_limit import limiter
from app.models.schemas import ChatFeedbackRequest, ChatRequest, ChatResponse
from app.user.services.chat_history_service import persist_chat_turn
from app.user.services.chatbot_service import chat, chat_stream
from app.user.services.feedback_service import (
    get_conversation_feedback,
    log_feedback,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/chat", tags=["chat"])


def _with_verified_uid(body: ChatRequest, user_id: str) -> ChatRequest:
    """Replace the client-supplied user_id with the JWT-verified one.

    ChatRequest.user_id arrives in the request BODY, so it is attacker
    controlled: any authenticated caller could put another account's uid
    there. The chat services use req.user_id for audit attribution, for
    reading saved preferences, and for writing preferences back via
    update_user_context — which keys straight off users/{uid}. Left as sent,
    that let one farmer read another's saved crop and district back out of a
    context-confirmation reply, and overwrite them.

    Normalising here rather than at each call site is deliberate: this is the
    single point every chat request passes through, so no present or future
    use of req.user_id downstream can miss it. The field stays required so
    existing clients keep working; its value is simply not trusted.
    """
    if body.user_id != user_id:
        logger.warning(
            "chat body user_id did not match the verified uid — overriding "
            "(endpoint=/api/chat, verified=%s)",
            user_id,
        )
    return body.model_copy(update={"user_id": user_id})


@router.post("", response_model=ChatResponse)
@limiter.limit("30/minute")
async def chat_endpoint(
    request: Request,
    body: ChatRequest,
    user_id: str = Depends(require_user),
) -> ChatResponse:
    """Process a farmer chat message and return an AI response.

    HTML tags are stripped and inputs are audit-logged inside the service.
    The turn is then saved to the caller's conversation history — a save
    failure is logged but never breaks the chat response.
    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    body = _with_verified_uid(body, user_id)
    try:
        response = chat(body, get_settings())
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    try:
        response.conversation_id = persist_chat_turn(
            user_id,
            body.conversation_id,
            body.message,
            response.reply,
            crop=body.crop.value if body.crop else None,
            district=body.district.value if body.district else None,
        )
    except Exception as exc:
        logger.warning("Conversation persistence failed uid=%s: %s", user_id, exc)

    return response


@router.post("/stream")
@limiter.limit("30/minute")
async def chat_stream_endpoint(
    request: Request,
    body: ChatRequest,
    user_id: str = Depends(require_user),
) -> StreamingResponse:
    """Stream a chat reply as Server-Sent Events.

    Wire format: 'data: <json>\\n\\n' per event, terminated by
    'data: [DONE]\\n\\n'. Event types: text | metadata | error. History
    persistence and the [STREAM COMPLETE] audit log happen inside the
    service after the full reply is assembled. The non-streaming
    POST /api/chat endpoint is unchanged and remains the fallback.
    Requires valid Firebase JWT. Rate limited: 30 req/min per IP.
    """

    body = _with_verified_uid(body, user_id)

    def sse():
        try:
            for event in chat_stream(body, get_settings(), user_id):
                yield f"data: {json.dumps(event)}\n\n"
        except Exception as exc:
            # Belt-and-braces: the generator must never 500 mid-stream.
            logger.error("SSE wrapper error uid=%s: %s", user_id, type(exc).__name__)
            err = {
                "type": "error",
                "code": "server_error",
                "message": (
                    "The AI service is temporarily unavailable. " "Try again shortly."
                ),
            }
            yield f"data: {json.dumps(err)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        sse(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@router.post("/feedback")
@limiter.limit("30/minute")
async def chat_feedback_endpoint(
    request: Request,
    body: ChatFeedbackRequest,
    user_id: str = Depends(require_user),
) -> dict:
    """Record a thumbs up/down on a bot reply for quality analytics.

    Fire-and-forget from the client; the write is best-effort and never
    affects chat. Requires a valid Firebase JWT. Rate limited: 30 req/min.
    """
    log_feedback(
        user_id,
        body.conversation_id,
        body.message_index,
        body.feedback,
        body.message_text,
    )
    return {"status": "ok"}


@router.get("/feedback/{conversation_id}")
@limiter.limit("30/minute")
async def get_feedback_endpoint(
    request: Request,
    conversation_id: str,
    user_id: str = Depends(require_user),
) -> dict:
    """Return the caller's thumbs votes for a conversation as
    {message_index: "up"|"down"} so the client can restore feedback state
    after a page reload. JWT-gated, best-effort, rate limited: 30 req/min.
    """
    return {"votes": get_conversation_feedback(user_id, conversation_id)}
