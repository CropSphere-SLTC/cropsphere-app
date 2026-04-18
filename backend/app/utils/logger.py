"""Logging configuration for CropSphere backend."""
import logging
import sys


def setup_logging(level: str = "INFO") -> None:
    """Configure root logger to stdout with a structured format."""
    logging.basicConfig(
        stream=sys.stdout,
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


def get_logger(name: str) -> logging.Logger:
    """Return a named logger."""
    return logging.getLogger(name)
