# Security tests

Tests focused on a specific security control rather than general business logic — some go through `TestClient`, some call the underlying function directly.

- `test_audit_logging.py` — audit log entries carry an HMAC signature
- `test_auth.py` — JWT authentication middleware behaviour on protected endpoints
- `test_env_variables.py` — required env vars exist and secrets aren't hardcoded
- `test_https_enforcement.py` — HSTS header presence and value
- `test_input_validation.py` — Pydantic input models (`PredictionInput`, `PriceInput`) reject malformed input
- `test_jwt_expiry.py` — requests with missing/invalid/expired tokens are rejected
- `test_nosql_injection.py` — sanitizer blocks MongoDB-style (`$...`) injection payloads
- `test_rate_limiting.py` — rate-limiting middleware is active
- `test_security_headers.py` — security response headers (X-Frame-Options, X-Content-Type-Options, Referrer-Policy)
- `test_security_logging.py` — unauthorized access / suspicious input / rate-limit events are logged
- `middleware_test/` — role-based access control (RBAC) dependencies
