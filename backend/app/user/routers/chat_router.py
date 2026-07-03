"""AI chatbot router."""

import logging

from fastapi import APIRouter, Depends, HTTPException, Request

from app.config import get_settings
from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import ChatRequest, ChatResponse
from app.user.services.chat_history_service import persist_chat_turn
from app.user.services.chatbot_service import chat

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
