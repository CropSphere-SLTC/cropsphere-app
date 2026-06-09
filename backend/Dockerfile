# syntax=docker/dockerfile:1
FROM python:3.11-slim

# Security: non-root user
RUN groupadd -r cropsphere && useradd -r -g cropsphere cropsphere

WORKDIR /app

# Install build tools for compiled packages
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip==26.1.2

# Layer 1 — torch (cached across builds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 \
    torch==2.1.0 --index-url https://download.pytorch.org/whl/cpu

# Layer 2 — tensorflow (cached across builds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 \
    tensorflow==2.21.0 || \
    pip install --timeout 600 --retries 10 \
    tensorflow-cpu==2.21.0 || \
    echo "TensorFlow install skipped"

# Layer 3 — heavy ML deps (cached across builds)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 \
    sentence-transformers==5.4.1 \
    scikit-learn==1.8.0 \
    xgboost==3.2.0 \
    numpy==2.4.4 \
    pandas==3.0.2 \
    scipy==1.17.1

# Layer 4 — remaining app dependencies
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout 600 --retries 10 -r requirements.txt

# Copy application code and ML model files
COPY app/ ./app/
COPY models/ ./models/

# Set ownership
RUN chown -R cropsphere:cropsphere /app

USER cropsphere

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/api/health').raise_for_status()" \
    || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 2"]