FROM python:3.11-slim

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
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --timeout 300 --retries 5 -r requirements.txt

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
