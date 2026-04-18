"""Weather forecast router."""
from fastapi import APIRouter, Depends, HTTPException, Request

from app.dependencies import get_user_id
from app.middleware.rate_limit import limiter
from app.models.schemas import WeatherForecastRequest, WeatherForecastResponse
from app.services.weather_service import forecast_weather
from app.utils.firestore import audit_log

router = APIRouter(prefix="/api/weather", tags=["weather"])


@router.post("/forecast", response_model=WeatherForecastResponse)
@limiter.limit("30/minute")
async def weather_forecast(
    request: Request,
    body: WeatherForecastRequest,
    user_id: str = Depends(get_user_id),
) -> WeatherForecastResponse:
    """Forecast weekly weather for the given district.

    Requires valid Firebase JWT.  Rate limited: 30 req/min per IP.
    """
    audit_log(user_id=user_id, endpoint="/api/weather/forecast", input_data=body.model_dump())
    try:
        return forecast_weather(body)
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
