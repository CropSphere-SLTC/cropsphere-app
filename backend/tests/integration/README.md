# Integration tests

Endpoint tests that go through the full FastAPI HTTP stack via `TestClient`, exercising routing, auth, validation, and business logic together.

- `test_chat.py` — `POST /api/chat`
- `test_demand.py` — `POST /api/demand/predict`
- `test_price.py` — `POST /api/price/predict`
- `test_recommend.py` — `POST /api/recommend`
- `test_weather.py` — `POST /api/weather/forecast`
- `test_yield.py` — `POST /api/yield/predict` (happy path, auth, validation, feature engineering, response shape, rate limiting)
