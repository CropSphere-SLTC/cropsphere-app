"""Chat conversation history router — list, load, rename, delete."""

from typing import List

from fastapi import APIRouter, Depends, HTTPException, Request

from app.middleware.roles import require_user
from app.middleware.rate_limit import limiter
from app.models.schemas import (
    ConversationDetail,
    ConversationSummary,
    RenameConversationRequest,
)
from app.user.services.chat_history_service import (
    ConversationNotFound,
    delete_user_conversation,
    get_user_conversation,
    list_user_conversations,
    rename_user_conversation,
)

router = APIRouter(prefix="/api/chat/conversations", tags=["chat-history"])

_NOT_FOUND = HTTPException(status_code=404, detail="Conversation not found")


@router.get("", response_model=List[ConversationSummary])
@limiter.limit("30/minute")
async def conversations_list(
    request: Request,
    user_id: str = Depends(require_user),
) -> List[ConversationSummary]:
    """List the caller's conversations (summaries only), newest first.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return list_user_conversations(user_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/{conversation_id}", response_model=ConversationDetail)
@limiter.limit("30/minute")
async def conversation_get(
    request: Request,
    conversation_id: str,
    user_id: str = Depends(require_user),
) -> ConversationDetail:
    """Return a full conversation with messages.

    Returns 404 when missing OR owned by another user (never 403 —
    prevents conversation-id enumeration).
    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return get_user_conversation(user_id, conversation_id)
    except ConversationNotFound:
        raise _NOT_FOUND
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.patch("/{conversation_id}")
@limiter.limit("30/minute")
async def conversation_rename(
    request: Request,
    conversation_id: str,
    body: RenameConversationRequest,
    user_id: str = Depends(require_user),
):
    """Rename a conversation. Same 404 ownership rule as GET.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return rename_user_conversation(user_id, conversation_id, body)
    except ConversationNotFound:
        raise _NOT_FOUND
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.delete("/{conversation_id}")
@limiter.limit("30/minute")
async def conversation_delete(
    request: Request,
    conversation_id: str,
    user_id: str = Depends(require_user),
):
    """Delete a conversation. Same 404 ownership rule as GET.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    try:
        return delete_user_conversation(user_id, conversation_id)
    except ConversationNotFound:
        raise _NOT_FOUND
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
