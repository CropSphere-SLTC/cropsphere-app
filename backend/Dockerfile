# syntax=docker/dockerfile:1 is removed — using default BuildKit

# ──────────────────────────────────────────────────────────
# STAGE 1 — Builder (gcc, build tools, pip cache — discarded after build)
# ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc python3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip==26.1.2

# Force CPU-only torch across ALL pip layers below: the PyTorch CPU wheel
# index is consulted on every install, and the constraint pins torch to the
# exact CPU build. This stops sentence-transformers / requirements.txt from
# pulling the multi-GB CUDA torch + nvidia-* wheels as transitive deps
# (which previously exhausted builder disk), and guarantees ONE consistent
# torch version in the final image.
RUN echo "torch==2.13.0+cpu" > /tmp/pip-constraints.txt
ENV PIP_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cpu \
    PIP_CONSTRAINT=/tmp/pip-constraints.txt

# Layer 1 — torch (CPU-only, cached across builds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 --prefix=/install \
    torch==2.13.0 --index-url https://download.pytorch.org/whl/cpu

# Layer 2 — tensorflow CPU-only (no CUDA bloat)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 --prefix=/install \
    tensorflow-cpu==2.21.0

# Layer 3 — heavy ML deps (cached across builds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 --prefix=/install \
    sentence-transformers==5.4.1 \
    scikit-learn==1.8.0 \
    xgboost==3.2.0 \
    numpy==2.4.4 \
    pandas==3.0.2 \
    scipy==1.17.1

# Layer 4 — remaining app dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 --prefix=/install -r requirements.txt

# NOTE: the old "re-force CPU torch" step that lived here was the root cause
# of a corrupted install (torch 2.1.0+cpu files under torch 2.12.1 metadata,
# which silently killed RAG at runtime). The PIP_CONSTRAINT above makes every
# layer resolve the same CPU torch, so no force-reinstall is needed.

# Verify torch is CPU-only AND the ML import chain is consistent — build fails
# loudly here instead of RAG dying silently at runtime (shift-left)
RUN PYTHONPATH=/install/lib/python3.11/site-packages python -c \
    "import torch; assert '+cu' not in torch.__version__, f'CUDA torch detected: {torch.__version__}'; \
import sentence_transformers, transformers, numpy; \
print(f'OK: torch {torch.__version__}, transformers {transformers.__version__}, ST {sentence_transformers.__version__}, numpy {numpy.__version__}')"

# ──────────────────────────────────────────────────────────
# STAGE 2 — Runtime (clean, no gcc, no build tools — smaller final image)
# ──────────────────────────────────────────────────────────
FROM python:3.11-slim

RUN groupadd -r cropsphere && useradd -r -g cropsphere cropsphere

WORKDIR /app

# Copy only the installed packages from builder — gcc/python3-dev never enter this image
COPY --from=builder /install /usr/local

# ── Security: strip stale, vulnerable build-tool copies ──────────────────
# Merging the builder's /install onto python:3.11-slim's own /usr/local leaves
# BOTH patched and older copies of pip build tools side-by-side (their
# version-named .dist-info dirs don't overwrite each other). The running app
# never imports these; remove the vulnerable duplicates so they don't ship —
# the patched versions already present are kept:
#   • wheel 0.45.1         → CVE-2026-24049  (patched wheel 0.46.x kept)
#   • jaraco.context 5.3.0 → CVE-2026-23949  (patched jaraco_context 6.1.x kept)
#     vendored inside setuptools
# Re-verify these paths if the base image bumps its build-tool versions.
RUN cd /usr/local/lib/python3.11/site-packages \
    && rm -rf wheel-0.45.1.dist-info \
              setuptools/_vendor/wheel-0.45.1.dist-info \
              setuptools/_vendor/jaraco.context-5.3.0.dist-info

# Bake the RAG sentence-encoder into the image so it NEVER downloads at
# runtime. The first chat request otherwise fetched all-MiniLM-L6-v2 from
# HuggingFace inside the request path, where the Xet backend (hf_xet) fails
# with "Permission denied" under the non-root user — hanging the single
# uvicorn worker so every endpoint timed out. Download here at build time with
# Xet disabled (plain HTTPS, reliable) and force offline below so the model
# loads from local disk with no network in the request path.
ENV SENTENCE_TRANSFORMERS_HOME=/app/hf_cache
RUN HF_HUB_DISABLE_XET=1 python -c \
    "from sentence_transformers import SentenceTransformer; \
SentenceTransformer('all-MiniLM-L6-v2', cache_folder='/app/hf_cache')"

# Runtime: never reach out to HuggingFace — load the baked model offline so a
# missing/corrupt cache fails fast instead of hanging on a network fetch.
ENV HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1

# Bake the RAG sentence-encoder into the image so it NEVER downloads at
# runtime. Previously the first chat request fetched all-MiniLM-L6-v2 from
# HuggingFace Hub inside the request path, where the new Xet download backend
# (hf_xet) failed with "Permission denied" under the non-root user — hanging
# the single uvicorn worker so every endpoint timed out. We download here at
# build time with Xet disabled (plain HTTPS, reliable) and force offline below
# so the model loads from local disk with no network in the request path.
ENV SENTENCE_TRANSFORMERS_HOME=/app/hf_cache
RUN HF_HUB_DISABLE_XET=1 python -c \
    "from sentence_transformers import SentenceTransformer; \
SentenceTransformer('all-MiniLM-L6-v2', cache_folder='/app/hf_cache')"

# Runtime: never reach out to HuggingFace — load the baked model offline so a
# missing/corrupt cache fails fast instead of hanging on a network fetch.
ENV HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1

# Copy application code, ML model files, and build-time scripts
COPY app/ ./app/
COPY models/ ./models/
COPY scripts/ ./scripts/
COPY data/ ./data/

RUN chown -R cropsphere:cropsphere /app

USER cropsphere

EXPOSE 8000

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/api/health').raise_for_status()" \
    || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]