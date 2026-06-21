# syntax=docker/dockerfile:1

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

# Layer 1 — torch (CPU-only, cached across builds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 --prefix=/install \
    torch==2.1.0 --index-url https://download.pytorch.org/whl/cpu

# Layer 2 — tensorflow (cached across builds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 --prefix=/install \
    tensorflow==2.21.0 || \
    pip install --timeout 600 --retries 10 --prefix=/install \
    tensorflow-cpu==2.21.0 || \
    echo "TensorFlow install skipped"

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

# Re-force CPU-only torch — MUST be the last pip step. Both sentence-transformers
# and requirements.txt can pull in the CUDA build of torch as a transitive
# dependency; this guarantees the CPU build wins regardless of install order.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 --force-reinstall --no-deps --prefix=/install \
    torch==2.1.0 --index-url https://download.pytorch.org/whl/cpu

# Verify torch is CPU-only — build fails loudly here instead of segfaulting at runtime
RUN PYTHONPATH=/install/lib/python3.11/site-packages python -c \
    "import torch; assert '+cu' not in torch.__version__, f'CUDA torch detected: {torch.__version__}'; print(f'torch OK: {torch.__version__}')"

# ──────────────────────────────────────────────────────────
# STAGE 2 — Runtime (clean, no gcc, no build tools — smaller final image)
# ──────────────────────────────────────────────────────────
FROM python:3.11-slim

RUN groupadd -r cropsphere && useradd -r -g cropsphere cropsphere

WORKDIR /app

# Copy only the installed packages from builder — gcc/python3-dev never enter this image
COPY --from=builder /install /usr/local

# Copy application code and ML model files
COPY app/ ./app/
COPY models/ ./models/

RUN chown -R cropsphere:cropsphere /app

USER cropsphere

EXPOSE 8000

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/api/health').raise_for_status()" \
    || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]