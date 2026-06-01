"""Price prediction router."""

from fastapi import APIRouter, Depends, HTTPException, Request

from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import PricePredictRequest, PricePredictResponse
from app.services.price_service import predict_price
from app.utils.firestore import audit_log

router = APIRouter(prefix="/api/price", tags=["price"])


@router.post("/predict", response_model=PricePredictResponse)
@limiter.limit("30/minute")
async def price_predict(
    request: Request,
    body: PricePredictRequest,
    user_id: str = Depends(get_user_id),
) -> PricePredictResponse:
    """Predict farmgate and retail crop prices.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    audit_log(
        user_id=user_id, endpoint="/api/price/predict", input_data=body.model_dump()
    )
    try:
        return predict_price(body, user_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
