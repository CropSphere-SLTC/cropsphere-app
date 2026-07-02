"""Crop recommendation router."""

from fastapi import APIRouter, Depends, HTTPException, Request

from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import RecommendRequest, RecommendResponse
from app.services.recommend_service import get_recommendations
from app.utils.firestore import audit_log

router = APIRouter(prefix="/api/recommend", tags=["recommend"])


@router.post("", response_model=RecommendResponse)
@limiter.limit("30/minute")
async def recommend(
    request: Request,
    body: RecommendRequest,
    user_id: str = Depends(get_user_id),
) -> RecommendResponse:
    """Return ranked crop recommendations via auto-chained weather/yield/price analysis.

    Flutter calls this single endpoint; all model chaining is server-side.
    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    audit_log(user_id=user_id, endpoint="/api/recommend", input_data=body.model_dump())
    try:
        return get_recommendations(body, user_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
