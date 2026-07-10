# Unit tests

Tests that call service/utility functions directly, with no HTTP layer.
External dependencies (Firestore, Groq, model files, TensorFlow) are mocked.

- `chat_history_test/` — `app.user.services.chat_history_service`
- `models_test/` — `app.models.loader.ModelLoader`
- `services_test/` — chatbot, demand, price, and weather services
- `utils_test/` — `app.utils.firestore` helpers
