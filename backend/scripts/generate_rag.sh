#!/usr/bin/env bash
# Regenerate the M6 RAG knowledge base inside the backend container, where the
# ML models and the baked sentence-transformer cache are available. Output
# lands in ./backend/models/files (mounted into the container).
#
# The scripts/ directory is mounted in (rather than relying on the image) so
# this works without rebuilding and always runs the current script. The encoder
# cache (/app/hf_cache) and HF_HUB_OFFLINE come baked into the image.
set -euo pipefail
cd "$(dirname "$0")/../.."   # repo root (docker-compose.yml lives here)
docker compose run --rm \
  -v "$(pwd)/backend/scripts:/app/scripts" \
  backend python scripts/generate_rag_artifacts.py "$@"
