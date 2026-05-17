"""NoSQL Injection Prevention — Input Sanitizer."""
import re

# Dangerous characters for Firestore queries
DANGEROUS_PATTERNS = [
    r"\$",           # MongoDB-style operators
    r"\{",           # JSON injection
    r"\}",
    r"__.*__",       # Python dunder attributes
    r"javascript:",  # JS injection
    r"<script",      # XSS
]


def sanitize_string(value: str) -> str:
    """Remove dangerous patterns from string input."""
    if not isinstance(value, str):
        return value

    for pattern in DANGEROUS_PATTERNS:
        if re.search(pattern, value, re.IGNORECASE):
            raise ValueError(f"Potentially malicious input detected: {value}")

    return value.strip()


def sanitize_dict(data: dict) -> dict:
    """Sanitize all string values in a dictionary."""
    sanitized = {}
    for key, value in data.items():
        if isinstance(value, str):
            sanitized[key] = sanitize_string(value)
        else:
            sanitized[key] = value
    return sanitized
