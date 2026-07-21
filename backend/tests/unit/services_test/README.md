# services_test

- `test_chatbot_service.py` — unit tests for `app.user.services.chatbot_service`: RAG retrieval scoring, grounding refusal, capability/near-miss short-circuits, streaming generator. Groq and the sentence-transformers encoder are mocked.
- `test_demand_service.py` — unit tests for `app.user.services.demand_service`, exercising `_build_features` and `_infer_trend` directly.
- `test_price_service.py` — unit tests for `app.user.services.price_service`, exercising `_build_sequence` and both scaler/no-scaler branches of `predict_price`.
- `test_weather_service.py` — unit tests for `app.user.services.weather_service`, exercising the LSTM forecast loop (scaler and no-scaler branches) and the mock fallback path.
