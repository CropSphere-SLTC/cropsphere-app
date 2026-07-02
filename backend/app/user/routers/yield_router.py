"""Yield prediction router."""

from fastapi import APIRouter, Depends, HTTPException, Request

from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import YieldPredictRequest, YieldPredictResponse
from app.services.yield_service import predict_yield
from app.utils.firestore import audit_log

router = APIRouter(prefix="/api/yield", tags=["yield"])


@router.post("/predict", response_model=YieldPredictResponse)
@limiter.limit("30/minute")
async def yield_predict(
    request: Request,
    body: YieldPredictRequest,
    user_id: str = Depends(get_user_id),
) -> YieldPredictResponse:
    """Predict crop yield for the given agronomic inputs.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    Input validated by Pydantic before this handler executes.
    Audit record written to Firestore on every call.
    """
    audit_log(
        user_id=user_id, endpoint="/api/yield/predict", input_data=body.model_dump()
    )
    try:
        return predict_yield(body, user_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
