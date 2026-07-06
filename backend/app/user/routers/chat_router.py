"""AI chatbot router."""

import json
import logging

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse

from app.config import get_settings
from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import ChatRequest, ChatResponse
from app.user.services.chat_history_service import persist_chat_turn
from app.user.services.chatbot_service import chat, chat_stream

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/chat", tags=["chat"])


@router.post("", response_model=ChatResponse)
@limiter.limit("30/minute")
async def chat_endpoint(
    request: Request,
    body: ChatRequest,
    user_id: str = Depends(get_user_id),
) -> ChatResponse:
    """Process a farmer chat message and return an AI response.

    HTML tags are stripped and inputs are audit-logged inside the service.
    The turn is then saved to the caller's conversation history — a save
    failure is logged but never breaks the chat response.
    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        response = chat(body, get_settings())
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    try:
        response.conversation_id = persist_chat_turn(
            user_id, body.conversation_id, body.message, response.reply
        )
    except Exception as exc:
        logger.warning("Conversation persistence failed uid=%s: %s", user_id, exc)

    return response


@router.post("/stream")
@limiter.limit("30/minute")
async def chat_stream_endpoint(
    request: Request,
    body: ChatRequest,
    user_id: str = Depends(get_user_id),
) -> StreamingResponse:
    """Stream a chat reply as Server-Sent Events.

    Wire format: 'data: <json>\\n\\n' per event, terminated by
    'data: [DONE]\\n\\n'. Event types: text | metadata | error. History
    persistence and the [STREAM COMPLETE] audit log happen inside the
    service after the full reply is assembled. The non-streaming
    POST /api/chat endpoint is unchanged and remains the fallback.
    Requires valid Firebase JWT. Rate limited: 30 req/min per IP.
    """

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
