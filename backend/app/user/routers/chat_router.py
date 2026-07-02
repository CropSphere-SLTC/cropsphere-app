"""AI chatbot router."""

from fastapi import APIRouter, Depends, HTTPException, Request

from app.config import get_settings
from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import ChatRequest, ChatResponse
from app.services.chatbot_service import chat

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
    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return chat(body, get_settings())
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
