from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)

        # Prevent clickjacking
        response.headers["X-Frame-Options"] = "DENY"

        # Prevent MIME type sniffing
        response.headers["X-Content-Type-Options"] = "nosniff"

        # Force HTTPS in production
        hsts = "max-age=31536000; includeSubDomains"
        response.headers["Strict-Transport-Security"] = hsts

        # Control referrer information
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

        # Disable browser features not needed
        permissions = "geolocation=(), microphone=(), camera=()"
        response.headers["Permissions-Policy"] = permissions

        # Content Security Policy
        csp = "default-src 'self' 'unsafe-inline' cdn.jsdelivr.net"
        response.headers["Content-Security-Policy"] = csp

        return response
