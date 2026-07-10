# utils_test

- `test_firestore.py` — unit tests for `app.utils.firestore` helpers. `get_db()` is patched at module level so no real Firestore connection is needed; `init_firestore()` tests patch `firebase_admin` directly.
