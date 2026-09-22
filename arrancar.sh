#!/usr/bin/env bash
# Levanta el laboratorio y muestra el link del chat con la clave puesta.
set -euo pipefail
cd "$(dirname "$0")"
set -a; . ./.env; set +a

pgrep -x ollama >/dev/null || { echo "Ollama apagado, arrancando…"; (nohup ollama serve >/tmp/ollama.log 2>&1 &); sleep 3; }
docker compose up -d nucleo-ia
pgrep -f "http.server 8080" >/dev/null || (cd chat && nohup python3 -m http.server 8080 --bind 127.0.0.1 >/tmp/chat-nucleo.log 2>&1 &)

for _ in $(seq 1 15); do curl -sS -o /dev/null -m 3 http://127.0.0.1:4000/health/liveliness 2>/dev/null && break; sleep 4; done

echo
echo "Chat:  http://localhost:8080/?key=$LITELLM_MASTER_KEY"
echo "API:   http://localhost:4000"
echo "Logs:  docker logs -f nucleo-ia"
