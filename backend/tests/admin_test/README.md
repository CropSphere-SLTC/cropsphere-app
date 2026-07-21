# admin_test

- `test_admin_router.py` — integration tests for `/api/admin/*`. Exercises the full HTTP stack (JWT auth, role gating, the 10/minute admin rate limit) with Firestore and psutil mocked.
- `test_admin_service.py` — unit tests for `app.admin.services.admin_service`. Calls the service functions directly; Firestore and psutil are mocked.
