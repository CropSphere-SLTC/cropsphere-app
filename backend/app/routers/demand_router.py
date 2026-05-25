"""Demand prediction router."""

from fastapi import APIRouter, Depends, HTTPException, Request

from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import DemandPredictRequest, DemandPredictResponse
from app.services.demand_service import predict_demand
from app.utils.firestore import audit_log

router = APIRouter(prefix="/api/demand", tags=["demand"])


@router.post("/predict", response_model=DemandPredictResponse)
@limiter.limit("30/minute")
async def demand_predict(
    request: Request,
    body: DemandPredictRequest,
    user_id: str = Depends(get_user_id),
) -> DemandPredictResponse:
    """Predict consumer demand index and trend for the given crop.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    audit_log(
        user_id=user_id, endpoint="/api/demand/predict", input_data=body.model_dump()
    )
    try:
        return predict_demand(body, user_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
