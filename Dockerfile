# ============================================================
# Stage 1 — Builder
# Install all dependencies (including build tools) here.
# Nothing from this stage leaks into the final image except
# the installed Python packages.
# ============================================================
FROM python:3.11-slim AS builder

# System-level build dependencies needed to compile native
# extensions (e.g. numpy, tokenizers, grpcio).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        g++ \
        libffi-dev \
        libssl-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Install into an isolated prefix so we can copy it cleanly.
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /install

# Copy only the dependency manifest first so Docker can cache
# this layer independently of application code changes.
COPY requirements.txt .

# Install all Python dependencies into /install/packages.
# Using --prefix keeps them separate from the system Python
# and makes the COPY in the runtime stage straightforward.
RUN pip install --upgrade pip \
    && pip install \
        --prefix=/install/packages \
        --no-cache-dir \
        -r requirements.txt

# ============================================================
# Stage 2 — Runtime
# Slim base image with only what is needed to run the app.
# Build tools, pip, and compiler artefacts are NOT present.
# ============================================================
FROM python:3.11-slim AS runtime

# Runtime system libraries required by TensorFlow / PyTorch
# (shared objects that are dynamically linked at import time).
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgomp1 \
        libglib2.0-0 \
        libgl1 \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # Tell Python where to find the packages copied from the
    # builder stage.
    PYTHONPATH=/usr/local/lib/python3.11/site-packages

# Pull the compiled packages out of the builder — no build
# tools, no pip cache, no compiler artefacts.
COPY --from=builder /install/packages /usr/local

# Create a non-root user for security.
RUN useradd --create-home --shell /bin/bash appuser

WORKDIR /app

# Copy application source code. This layer is intentionally
# last so that code changes do not invalidate the (expensive)
# dependency layer above.
COPY . .

RUN chown -R appuser:appuser /app
USER appuser

# FastAPI served via Uvicorn on the Railway-standard port.
EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
