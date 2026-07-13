# middleware_test

- `test_roles.py` — unit tests for `app.middleware.roles` role-based access dependencies. Calls the dependency functions directly (no HTTP layer); Firestore lookups (`is_user_banned`, `get_user_role`) are patched at their point of use.
