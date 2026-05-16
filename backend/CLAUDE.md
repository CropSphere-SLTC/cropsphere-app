I am building CropSphere — a Sri Lankan agricultural intelligence
web and mobile app for my final year project. Scaffold the complete
backend project from scratch following Agile methodology and
DevSecOps (shift-left) principles.

## Agile + DevSecOps requirements (apply throughout)

- Structure code as Sprint-ready vertical slices — each endpoint
must be independently testable the moment it is created
- Shift-left security: embed security controls in the code itself,
not as an afterthought. Every endpoint must have input validation,
auth check, and rate limiting from the first line, not added later
- Every service must have a corresponding pytest test file created
alongside it (not after)
- No secrets in code — all configuration via environment variables
from day one
- Dockerfile and docker-compose.yml must be production-ready from
the start, not development placeholders
- GitHub Actions CI pipeline must run lint (flake8) + tests (pytest)
    - security scan (bandit) on every push before any deploy step
- All functions must have docstrings explaining inputs, outputs,
and security assumptions
- Log all prediction requests with user_id and timestamp to Firestore
for audit trail (DevSecOps requirement)

## Project Overview

CropSphere serves Sri Lankan farmers with 6 ML-powered features:

- M1: Crop yield prediction (Random Forest, per-crop models)
- M2: Weather impact forecasting (LSTM)
- M3: Market & farmgate price prediction (LSTM, per crop)
- M4: Consumer demand prediction (XGBoost, per crop)
- M5: Crop recommendation (Random Forest classifier)
- M6: AI chatbot with RAG (LLaMA 3 via Groq API)

## Architecture

- Modular monolith (NOT microservices)
- Backend: FastAPI (Python 3.11) deployed on Railway
- Frontend: Flutter (web + Android) deployed on Firebase Hosting
- Database: Firebase Firestore
- Auth: Firebase Auth + JWT (with 2FA support)
- ML serving: all models loaded in-memory on FastAPI startup
- Container: Docker

## Team

- Shifan: backend + DevOps (me)
- Supun: Flutter frontend
- Keshan: cybersecurity (JWT middleware, input validation,
rate limiting)

## Crops covered

Carrot, Maize, Green gram, Cowpea, Finger millet, Groundnut

## Districts covered

Nuwara Eliya, Badulla, Anuradhapura, Monaragala, Ampara,
Hambantota, Batticaloa, Jaffna

## Folder structure to create

cropsphere/
backend/
app/
[main.py](http://main.py/)[config.py](http://config.py/)[dependencies.py](http://dependencies.py/)
middleware/
[auth.py](http://auth.py/)

rate_limit.py

services/
yield_service.py
weather_service.py
price_service.py
demand_service.py
recommend_service.py
chatbot_service.py
routers/
yield_router.py
weather_router.py
price_router.py
demand_router.py
recommend_router.py
chat_router.py
health_router.py
models/
[loader.py](http://loader.py/)[schemas.py](http://schemas.py/)
utils/
[firestore.py](http://firestore.py/)[logger.py](http://logger.py/)

tests/
test_yield.py
test_weather.py
test_price.py
test_demand.py
test_recommend.py
test_chat.py
test_auth.py

[conftest.py](http://conftest.py/)
Dockerfile
docker-compose.yml
requirements.txt
.env.example
.flake8
pyproject.toml

.github/
workflows/
ci.yml

deploy.yml

## Schemas — POST /api/yield/predict

Request: crop (enum: Carrot/Maize/Green gram/Cowpea/
Finger millet/Groundnut), district (enum: 8 districts),
season (enum: Maha/Yala/Inter), week_of_year (1-52),
rainfall_mm (0-500), temp_min_c (-5-45), temp_max_c (0-50),
humidity_pct (0-100), wind_speed_kmh (0-100),
solar_radiation_mj (0-35), soil_ph (3.5-9.0),
soil_moisture_pct (0-100), cultivated_area_ha (0.1-500),
seed_variety (string), fertilizer_index (0.0-1.0),
pesticide_index (0.0-1.0), irrigation_type (enum: drip/
sprinkler/flood/rainfed), N_index (0.0-1.0), P_index (0.0-1.0),
K_index (0.0-1.0), prev_crop (string), demand_index (0-200),
inflation_index (0.5-3.0), holiday_flag (0/1), festival_flag (0/1)
Response: predicted_yield_kg_per_ha, crop, district,
confidence (high/medium/low), model_used

## Schemas — POST /api/weather/forecast

Request: district (enum), start_date (YYYY-MM-DD),
weeks_ahead (1-4)
Response: district, forecasts (list of week_number, date,
rainfall_mm, temp_min_c, temp_max_c, humidity_pct)

## Schemas — POST /api/price/predict

Request: crop (enum), district (enum), season (enum),
week_of_year (1-52), inflation_index (0.5-3.0),
fuel_price_index (0.5-3.0), transport_cost_index (0.5-2.0),
supply_index (20-200), demand_index (0-200), holiday_flag (0/1),
festival_flag (0/1), farmgate_price_lag1 (float > 0),
farmgate_price_lag2 (float > 0), farmgate_price_lag4 (float > 0)
Response: crop, district, predicted_farmgate_price_lkr_kg,
predicted_retail_price_lkr_kg, confidence

## Schemas — POST /api/demand/predict

Request: crop (enum), season (enum), week_of_year (1-52),
demand_lag1 (0-200), demand_lag2 (0-200), demand_lag4 (0-200),
retail_price_lkr_kg (float > 0), inflation_index (0.5-3.0),
holiday_flag (0/1), festival_flag (0/1),
consumer_pref_index (0-100), search_trend_index (0-100)
Response: crop, predicted_demand_index,
trend (rising/stable/falling), confidence

## Schemas — POST /api/recommend

Request: district (enum), season (enum), week_of_year (1-52),
rainfall_mm (0-500), temp_min_c (-5-45), temp_max_c (0-50),
humidity_pct (0-100), soil_ph (3.5-9.0),
soil_moisture_pct (0-100), N_index (0.0-1.0),
P_index (0.0-1.0), K_index (0.0-1.0),
irrigation_type (enum), farmgate_price_context (optional float),
demand_context (optional float)
Response: recommendations list of (rank, crop,
confidence_score 0-1, expected_yield_kg_per_ha,
expected_price_lkr_kg, suitability_flags dict)

## Schemas — POST /api/chat

Request: message (string, max 500 chars),
conversation_history (list of role+content, max 10 turns),
user_id (string), district (optional enum), crop (optional enum)
Response: reply (string), sources_used (list),
suggested_followups (list of 3 strings)

## Security requirements (Keshan — shift left)

- JWT middleware: verify Firebase token on every route except
/api/health and /docs. Return 401 with message if missing
or expired. Attach user_id to request.state
- Rate limiting: 30 req/min per IP via slowapi. Return 429
with Retry-After header. Exempt /api/health
- Input validation: Pydantic validators with explicit min/max
on every numeric field. Enum validation on all categorical
fields. Reject with 422 before any model is called
- Chatbot: reject messages over 500 chars, strip HTML tags,
log all inputs for prompt injection monitoring
- CORS: only allow origins from ALLOWED_ORIGINS env variable
- All API keys and secrets: load from environment only, raise
clear error on startup if missing
- Audit logging: every prediction request logged to Firestore
with user_id, timestamp, endpoint, input hash (not raw input)

## Model loader requirements

- Singleton pattern — load once on startup, reuse forever
- Model directory: /app/models/files/ inside container
- File naming: yield_Carrot.pkl, yield_Maize.pkl,
yield_Greengram.pkl, yield_Cowpea.pkl,
yield_Fingermillet.pkl, yield_Groundnut.pkl,
weather_lstm.keras, price_Carrot.keras, price_Maize.keras,
price_Greengram.keras, price_Cowpea.keras,
price_Fingermillet.keras, price_Groundnut.keras,
demand_Carrot.pkl, demand_Maize.pkl, demand_Greengram.pkl,
demand_Cowpea.pkl, demand_Fingermillet.pkl,
demand_Groundnut.pkl, recommend_rf.pkl, rag_artifacts.pkl
- If a model file is missing: log a warning, set that model
to None, service returns mock response with
is_mock: true flag
- Expose get_model(name) and is_loaded(name) methods
- health endpoint must report loaded/missing status per model

## Service requirements

Each service class must:

- Accept the Pydantic request schema as input
- Preprocess inputs identically to how the training data
was prepared (label encoding for categoricals, MinMaxScaler
for numerics — use saved scaler files if present)
- Call the correct model(s) via ModelLoader
- Return mock data with is_mock: true if model not loaded
- Catch all exceptions, log them, return 500 with safe message
(never expose stack traces to client)

## /api/recommend auto-chaining

When /api/recommend is called:

1. Call WeatherService.forecast() for the district
2. Use forecast output as weather input to YieldService
for each of the 6 crops
3. Call PriceService for market context
4. Pass all outputs to RecommendService.recommend()
5. Return ranked crop list in single response
All steps happen server-side. Flutter only calls one endpoint.

## pytest requirements

Each test file must include:

- Test with valid input → expect 200
- Test with missing required field → expect 422
- Test with out-of-range value → expect 422
- Test with no JWT token → expect 401
- Test with expired JWT token → expect 401
- Test mock response when model not loaded → expect 200
with is_mock: true
Use pytest fixtures in [conftest.py](http://conftest.py/) for test client and
mock JWT tokens

## GitHub Actions — ci.yml

Triggers: push and pull_request to main and develop branches
Steps:

1. Checkout code
2. Set up Python 3.11
3. Install dependencies
4. Run flake8 lint check
5. Run bandit security scan (fail on high severity)
6. Run pytest with coverage report
7. Fail PR if coverage below 70%

## GitHub Actions — deploy.yml

Triggers: push to main only (after ci.yml passes)
Steps:

1. Build Docker image
2. Push to Railway using RAILWAY_TOKEN secret

## Dockerfile

- Base: python:3.11-slim
- Create non-root user (security requirement)
- Install only production dependencies
- Copy app code
- Expose 8000
- Healthcheck: GET /api/health every 30s
- CMD: uvicorn app.main:app --host 0.0.0.0 --port 8000
--workers 2

## docker-compose.yml (development only)

- Hot reload enabled
- Mount ./models/files into container
- Load .env file
- Expose port 8000

## requirements.txt — include exact versions

fastapi==0.111.0, uvicorn==0.29.0, pydantic==2.7.0,
firebase-admin==6.5.0, slowapi==0.1.9, scikit-learn==1.4.2,
tensorflow-cpu==2.16.1, xgboost==2.0.3, joblib==1.4.0,
sentence-transformers==2.7.0, groq==0.8.0, pandas==2.2.2,
numpy==1.26.4, python-dotenv==1.0.1, httpx==0.27.0,
pytest==8.2.0, pytest-asyncio==0.23.6, pytest-cov==5.0.0,
flake8==7.0.0, bandit==1.7.8

## After creating all files

1. Run: docker-compose up --build
2. Confirm: GET http://localhost:8000/api/health returns
{"status":"ok","models_loaded":{...},"environment":"development"}
3. Run: pytest tests/ -v
4. Show me the test results

Create all files now. Do not ask clarifying questions —
make reasonable decisions and note them in comments.