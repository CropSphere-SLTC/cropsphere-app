.PHONY: generate-rag
generate-rag:  ## Rebuild the M6 RAG knowledge base from ML predictions (in Docker)
	./backend/scripts/generate_rag.sh
