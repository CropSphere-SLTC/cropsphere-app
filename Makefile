.PHONY: generate-rag analyze-conversations

generate-rag:  ## Rebuild the M6 RAG knowledge base from ML predictions (in Docker)
	./backend/scripts/generate_rag.sh

analyze-conversations:  ## Report conversation health from the last 30 days (read-only)
	docker compose exec backend python -c \
	"import json; from app.admin.services.conversation_miner_service import mine_conversation_patterns; \
	print(json.dumps(mine_conversation_patterns(30), indent=2))"
