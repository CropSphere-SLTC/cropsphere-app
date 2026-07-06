FROM python:3.11-slim

# in your backend/Dockerfile, find the base image section and add:
RUN apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Security: non-root user
RUN groupadd -r cropsphere && useradd -r -g cropsphere cropsphere

WORKDIR /app

# Install CPU-only torch first to prevent sentence-transformers pulling CUDA (~4 GB)
RUN pip install --no-cache-dir --timeout 300 --retries 5 \
    torch==2.11.0 --index-url https://download.pytorch.org/whl/cpu

# Pre-install tensorflow separately to isolate its large download
RUN pip install --no-cache-dir --timeout 300 --retries 5 tensorflow==2.21.0

# Install app dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir "pip==26.1" && \
    pip install --no-cache-dir --timeout 600 --retries 10 -r requirements.txt

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

# Copy application code and ML model files
COPY app/ ./app/
COPY models/ ./models/

# Set ownership
RUN chown -R cropsphere:cropsphere /app

USER cropsphere

EXPOSE 8000

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/api/health').raise_for_status()" \
    || exit 1

# Railway injects PORT dynamically — use 1 worker on free tier
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]
