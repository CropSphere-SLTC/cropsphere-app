FROM python:3.11-slim

# Security: non-root user
RUN groupadd -r cropsphere && useradd -r -g cropsphere cropsphere

WORKDIR /app

<<<<<<< HEAD
# Install CPU-only torch first to prevent sentence-transformers pulling CUDA (~4 GB)
RUN pip install --no-cache-dir torch==2.2.2 --index-url https://download.pytorch.org/whl/cpu

# Install app dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code and ML model files
COPY app/ ./app/
COPY models/ ./models/

# Set ownership
RUN chown -R cropsphere:cropsphere /app
=======
# Install dependencies before copying app code (layer cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Create model directory and set ownership
RUN mkdir -p /app/models/files && chown -R cropsphere:cropsphere /app
>>>>>>> 0c9c358 (chore: initial repository setup)

USER cropsphere

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/api/health').raise_for_status()" \
    || exit 1

<<<<<<< HEAD
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 2"]
=======
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
>>>>>>> 0c9c358 (chore: initial repository setup)
