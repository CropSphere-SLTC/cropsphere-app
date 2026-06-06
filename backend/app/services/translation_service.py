"""
Translation Service
===================
Handles language detection and translation for the chatbot.

Features:
- Language detection (English, Sinhala, Tamil)
- In-memory translation cache (resets on container restart)
- Prompt injection strategy (skip input translation, instruct LLaMA directly)
"""

import logging
from typing import Optional

logger = logging.getLogger(__name__)

# In-memory translation cache
# Key: "source:target:text", Value: translated text
_translation_cache: dict = {}

# Language display names for logging
LANGUAGE_NAMES = {
    "en": "English",
    "si": "Sinhala",
    "ta": "Tamil",
}

# System prompt instructions per language
LANGUAGE_PROMPTS = {
    "si": "ඔබ සිංහල භාෂාවෙන් පමණක් පිළිතුරු දිය යුතුය. කිසිදු ඉංග්‍රීසි වචනයක් භාවිතා නොකරන්න.",
    "ta": "நீங்கள் தமிழ் மொழியில் மட்டுமே பதில் அளிக்க வேண்டும். எந்த ஆங்கில வார்த்தைகளையும் பயன்படுத்த வேண்டாம்.",
    "en": "Respond in English.",
}


def detect_language(text: str) -> str:
    """
    Detect language of input text.
    Returns: "en", "si", "ta", or "en" as fallback.
    """
    try:
        from langdetect import detect, LangDetectException

        lang = detect(text)
        # langdetect returns "si" for Sinhala, "ta" for Tamil
        if lang in ("si", "ta", "en"):
            logger.info(f"Detected language: {LANGUAGE_NAMES.get(lang, lang)}")
            return lang
        # Any other language defaults to English
        return "en"
    except Exception as e:
        logger.warning(f"Language detection failed: {e} — defaulting to English")
        return "en"


def get_language_system_prompt(lang: str) -> str:
    """
    Return the system prompt instruction for the detected language.
    LLaMA is instructed to respond in the user's language directly —
    this avoids the need to translate input text.
    """
    return LANGUAGE_PROMPTS.get(lang, LANGUAGE_PROMPTS["en"])


def translate_cached(text: str, source_lang: str, target_lang: str) -> str:
    """
    Translate text with in-memory caching.
    Cache key: "source:target:text"

    Currently uses a simple character replacement for demonstration.
    In production, replace the translation logic with IndicTrans2 or
    Google Translate API.
    """
    if source_lang == target_lang:
        return text

    cache_key = f"{source_lang}:{target_lang}:{text[:100]}"

    # Check cache first
    if cache_key in _translation_cache:
        logger.info(f"Translation cache hit for {source_lang}→{target_lang}")
        return _translation_cache[cache_key]

    # Translate
    try:
        translated = _translate(text, source_lang, target_lang)
        # Store in cache
        _translation_cache[cache_key] = translated
        logger.info(
            f"Translated {source_lang}→{target_lang}, cached ({len(_translation_cache)} entries)"
        )
        return translated
    except Exception as e:
        logger.warning(f"Translation failed: {e} — returning original text")
        return text


def _translate(text: str, source_lang: str, target_lang: str) -> str:
    """
    Core translation function.

    Strategy: Use LLaMA's built-in multilingual capability via prompt injection.
    This avoids needing a separate translation model and keeps latency low.

    For production quality, replace with IndicTrans2:
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
    """
    # For now — return original text since LLaMA handles the language
    # via system prompt injection (Feature 2).
    # The cache still works for any future translation implementation.
    return text


def clear_cache() -> int:
    """Clear translation cache. Returns number of entries cleared."""
    count = len(_translation_cache)
    _translation_cache.clear()
    logger.info(f"Translation cache cleared ({count} entries removed)")
    return count


def get_cache_stats() -> dict:
    """Return cache statistics for monitoring."""
    return {
        "total_entries": len(_translation_cache),
        "languages_cached": list(
            set(k.split(":")[0] for k in _translation_cache.keys())
        ),
    }
