# syntax=docker/dockerfile:1 is removed — using default BuildKit

# ──────────────────────────────────────────────────────────
# STAGE 1 — Builder (gcc, build tools, pip cache — discarded after build)
# ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Build into a virtualenv, NOT --prefix. pip treats sys.prefix (/usr/local) as
# "the environment" and refuses to uninstall anything outside it — with
# --prefix=/install it logged "Not uninstalling <pkg>, outside environment"
# and wrote new files OVER the old ones. The stale .dist-info survived (its
# name carries the version, so it never collides), leaving ~24 packages with
# two metadata dirs each and a Frankenstein mix of files on disk. That is the
# same corruption that killed RAG (see the torch note below), and it also
# failed the Trivy gate on a keras version we never pinned. Inside a venv pip
# owns the tree and uninstalls properly: exactly one version per package.
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN --mount=type=cache,id=s/2ce5633d-e682-472f-86d7-3393212b702a-/root/.cache/pip,target=/root/.cache/pip \
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

# The venv is on PATH, so every layer below sees what the earlier layers
# installed and reports them as already satisfied instead of re-downloading
# (numpy, pandas, scipy, sklearn, xgboost, sentence-transformers...).
#
# About the cache mount id below — "s/<service-id>-<target-path>". Railway's
# builder rejects any cache mount whose id lacks that service-scoped prefix
# ("missing the cacheKey prefix from its id"), and the prefix cannot come from
# a build arg: BuildKit does no variable expansion inside mount flags, so the
# service UUID has to be literal. To every other builder (GitHub CI, local)
# the id is just an opaque string, so ONE Dockerfile caches everywhere.
# All five layers share one target, hence one id — that is a single shared
# pip cache, which is what we want.
#
# Worth keeping: a766968 recorded a Railway build dying on the 191MB torch
# wheel with IncompleteRead after ~20 minutes. pip cannot resume a partial
# body and --retries does not cover it, so a warm pip cache is the mitigation.

# Layer 1 — torch (CPU-only, cached across builds)
#
# The install is wrapped in a shell retry loop, not just "pip install".
# --retries only covers connection-level failures; it does NOT cover a
# ProtocolError/IncompleteRead where the stream dies mid-download (seen on
# both this wheel and the tensorflow one below, on slow/flaky local
# connections — see the note above). pip has no resume for a partial body,
# so the only recourse is to re-run pip and let it re-download from scratch.
# A clean success on Railway's datacenter network is unaffected either way.
RUN --mount=type=cache,id=s/2ce5633d-e682-472f-86d7-3393212b702a-/root/.cache/pip,target=/root/.cache/pip \
    for i in 1 2 3 4 5; do \
        pip install --timeout 600 --retries 10 \
            torch==2.13.0 --index-url https://download.pytorch.org/whl/cpu \
        && break; \
        echo "torch install failed (attempt $i/5), retrying in 10s..."; \
        sleep 10; \
        [ "$i" -eq 5 ] && exit 1; \
    done

# Layer 2 — tensorflow CPU-only (no CUDA bloat)
RUN --mount=type=cache,id=s/2ce5633d-e682-472f-86d7-3393212b702a-/root/.cache/pip,target=/root/.cache/pip \
    for i in 1 2 3 4 5; do \
        pip install --timeout 600 --retries 10 \
            tensorflow-cpu==2.21.0 \
        && break; \
        echo "tensorflow-cpu install failed (attempt $i/5), retrying in 10s..."; \
        sleep 10; \
        [ "$i" -eq 5 ] && exit 1; \
    done

# Layer 3 — heavy ML deps (cached across builds)
RUN --mount=type=cache,id=s/2ce5633d-e682-472f-86d7-3393212b702a-/root/.cache/pip,target=/root/.cache/pip \
    for i in 1 2 3 4 5; do \
        pip install --timeout 600 --retries 10 \
            sentence-transformers==5.4.1 \
            scikit-learn==1.8.0 \
            xgboost==3.2.0 \
            numpy==2.4.4 \
            pandas==3.0.2 \
            scipy==1.17.1 \
        && break; \
        echo "ML deps install failed (attempt $i/5), retrying in 10s..."; \
        sleep 10; \
        [ "$i" -eq 5 ] && exit 1; \
    done

# Layer 4 — remaining app dependencies
COPY requirements.txt .
RUN --mount=type=cache,id=s/2ce5633d-e682-472f-86d7-3393212b702a-/root/.cache/pip,target=/root/.cache/pip \
    for i in 1 2 3 4 5; do \
        pip install --timeout 600 --retries 10 -r requirements.txt \
        && break; \
        echo "requirements.txt install failed (attempt $i/5), retrying in 10s..."; \
        sleep 10; \
        [ "$i" -eq 5 ] && exit 1; \
    done

# NOTE: the old "re-force CPU torch" step that lived here was the root cause
# of a corrupted install (torch 2.1.0+cpu files under torch 2.12.1 metadata,
# which silently killed RAG at runtime). The PIP_CONSTRAINT above makes every
# layer resolve the same CPU torch, so no force-reinstall is needed.

# Verify torch is CPU-only AND the ML import chain is consistent — build fails
# loudly here instead of RAG dying silently at runtime (shift-left)
RUN python -c \
    "import torch; assert '+cu' not in torch.__version__, f'CUDA torch detected: {torch.__version__}'; \
import sentence_transformers, transformers, numpy; \
print(f'OK: torch {torch.__version__}, transformers {transformers.__version__}, ST {sentence_transformers.__version__}, numpy {numpy.__version__}')"

# Guard the invariant the venv buys us: exactly ONE .dist-info per package.
# A duplicate means some layer installed over another again, which ships stale
# metadata (Trivy then reports CVEs for a version we never pinned) and mixed
# files on disk. Fail the build here rather than in the container scan.
# Plain shell on purpose — no RUN heredoc, which needs a newer BuildKit
# frontend than Railway is guaranteed to have (we ship no # syntax directive).
RUN dupes=$(ls -d /opt/venv/lib/python3.11/site-packages/*.dist-info \
      | sed 's|.*/||; s|\.dist-info$||; s|-[^-]*$||' \
      | tr '[:upper:]' '[:lower:]' | tr '.' '_' | sort | uniq -d); \
    if [ -n "$dupes" ]; then \
      echo "DUPLICATE .dist-info — a pip layer installed over another:"; \
      echo "$dupes"; exit 1; \
    fi; \
    echo "OK: no duplicate dist-info"

# ──────────────────────────────────────────────────────────
# STAGE 2 — Runtime (clean, no gcc, no build tools — smaller final image)
# ──────────────────────────────────────────────────────────
FROM python:3.11-slim

# ── Security: patch base-image OS CVEs ────────────────────────────────────
# util-linux — CVE-2026-53612/-53613/-53614/-53615, all 4 fixed upstream in
# 2.41.5-0+deb13u1 (this base image ships 2.41-5). Trivy reports this as 36
# findings: 4 CVEs × 9 binary packages built from the same util-linux
# source, not 36 distinct issues.
# openssl — CVE-2026-14456 (HIGH, QUIC server memory growth), fixed in
# 3.5.7-1~deb13u2; the base ships 3.5.6-1~deb13u2. Same shape: 3 binary
# packages from one source, so all three are upgraded together.
# Both are listed explicitly rather than relying on apt to pull the shared
# libs in via the source package's own dependency chain.
# Must run before USER cropsphere below (apt needs root), and nothing later
# in this stage touches apt or these files, so nothing can undo it.
RUN apt-get update && \
    apt-get install -y --only-upgrade \
        util-linux bsdutils mount login \
        libblkid1 libmount1 libsmartcols1 libuuid1 liblastlog2-2 \
        openssl libssl3t64 openssl-provider-legacy && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -r cropsphere && useradd -r -g cropsphere cropsphere

WORKDIR /app

# Copy the whole venv — gcc/python3-dev never enter this image. It lands at the
# same path it was built at, so console-script shebangs (uvicorn) stay valid.
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# ── Security: strip stale, vulnerable build-tool copies ──────────────────
# These live in the BASE image's own site-packages (python:3.11-slim ships
# setuptools 79.0.1, whose _vendor tree carries older pins than the top-level
# ones). The venv no longer merges into /usr/local, so there are no duplicate
# app packages here any more — but the base's vendored copies still ship and
# Trivy still scans them. The running app never imports these:
#   • wheel 0.45.1         → CVE-2026-24049  (top-level wheel 0.46.3 kept)
#   • jaraco.context 5.3.0 → CVE-2026-23949
# Both are vendored inside setuptools.
# Re-verify these paths if the base image bumps its build-tool versions.
RUN cd /usr/local/lib/python3.11/site-packages \
    && rm -rf setuptools/_vendor/wheel-0.45.1.dist-info \
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

# Copy application code, ML model files, and build-time scripts
COPY app/ ./app/
COPY models/ ./models/
# Fail the build if the models did not really arrive. Permanent, not a
# migration aid: a missing model is not a crash but a silent downgrade — the
# loader catches the load error, marks the model unloaded, and the API keeps
# answering 200 with is_mock data that looks like a real prediction. That
# reached production once already, via Git LFS pointer stubs copied in place
# of the models. A file count cannot see it (a stub is still a file); the byte
# total can. Real models are ~68 MB, 22 stubs are ~2.9 KB, so 50 MB sits far
# from both and tolerates models being retrained to different sizes.
RUN total_bytes=$(du -sb /app/models/files/ | cut -f1) \
    && if [ "$total_bytes" -lt 50000000 ]; then \
         echo "ERROR: model files are ${total_bytes} bytes — expected ~68MB." \
              "Likely LFS pointer stubs or an incomplete copy, not real models." >&2; \
         exit 1; \
       fi \
    && echo "Model files verified: ${total_bytes} bytes"
COPY scripts/ ./scripts/
COPY data/ ./data/

RUN chown -R cropsphere:cropsphere /app

USER cropsphere

EXPOSE 8000

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s --retries=3 \
    CMD python -c "import httpx; httpx.get('http://localhost:8000/api/health').raise_for_status()" \
    || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]