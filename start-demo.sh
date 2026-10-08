#!/usr/bin/env bash
# Starts the AgriEvidence demo on macOS or Linux and opens it in the browser. Ctrl+C stops everything.
#
#   ./start-demo.sh                full app: LLM service (8100), backend API (8000), frontend (5173)
#   ./start-demo.sh --offline      frontend only (5174), with the sample trials kept in the browser
#   ./start-demo.sh --no-browser   don't open the browser
#
# Run ./setup.sh once first. Logs go to .demo-logs/. Services whose port is already in use are skipped.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
LLM="$ROOT/Agricultural_Trial_Evidence_App_LLM"
BACKEND="$ROOT/Agricultural_Trial_Evidence_App_Backend"
FRONTEND="$ROOT/Agricultural_Trial_Evidence_App_Frontend"
LOGS="$ROOT/.demo-logs"

OFFLINE=0
BROWSER=1
for arg in "$@"; do
  case "$arg" in
    --offline) OFFLINE=1 ;;
    --no-browser) BROWSER=0 ;;
    -h | --help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (see ./start-demo.sh --help)" >&2
      exit 1
      ;;
  esac
done

venv_python() {
  if [ -x "$1/.venv/bin/python" ]; then echo "$1/.venv/bin/python"; else echo "$1/.venv/Scripts/python.exe"; fi
}
port_in_use() { (: <"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
wait_for() {
  for _ in $(seq 1 90); do
    curl -s -o /dev/null --max-time 2 "$1" && return 0
    sleep 1
  done
  return 1
}
open_url() {
  [ "$BROWSER" -eq 1 ] || return 0
  if command -v open >/dev/null 2>&1; then
    open "$1"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1" >/dev/null 2>&1 &
  fi
}

PIDS=()
cleanup() {
  trap - EXIT INT TERM
  if [ ${#PIDS[@]} -gt 0 ]; then
    echo
    echo "Stopping the demo..."
    kill "${PIDS[@]}" 2>/dev/null
    wait "${PIDS[@]}" 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# start <name> <folder> <port> <command...>: runs the command in the folder, logging to .demo-logs/<name>.log.
start() {
  local name=$1 dir=$2 port=$3
  shift 3
  if port_in_use "$port"; then
    echo "$name: port $port is already in use, so it is probably running. Skipped."
    return 0
  fi
  (cd "$dir" && exec "$@") >"$LOGS/$name.log" 2>&1 &
  PIDS+=($!)
  echo "$name: starting on port $port (log: .demo-logs/$name.log)"
}

mkdir -p "$LOGS"
[ -d "$FRONTEND/node_modules" ] || {
  echo "Run ./setup.sh first." >&2
  exit 1
}

if [ "$OFFLINE" -eq 1 ]; then
  start frontend-offline "$FRONTEND" 5174 ./node_modules/.bin/vite --mode offline --port 5174 --strictPort
  wait_for http://localhost:5174/ || {
    echo "The frontend did not start; see .demo-logs/frontend-offline.log" >&2
    exit 1
  }
  echo
  echo "Offline demo: http://localhost:5174"
  echo "Sign in with any email and password; emails starting with 'admin' get the admin role."
  echo "The six sample trials live in the browser; the assistant, imports and settings need the full app."
  open_url http://localhost:5174
else
  for dir in "$LLM" "$BACKEND"; do
    [ -x "$(venv_python "$dir")" ] || {
      echo "Run ./setup.sh first ($(basename "$dir") has no virtual environment)." >&2
      exit 1
    }
  done
  [ -f "$FRONTEND/.env" ] || cp "$FRONTEND/.env.example" "$FRONTEND/.env"

  # Which model the LLM service uses by default: OLLAMA_MODEL in its .env, else qwen3.6.
  model=qwen3.6
  if [ -f "$LLM/.env" ]; then
    configured=$(sed -n 's/^[[:space:]]*OLLAMA_MODEL[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$LLM/.env" | head -n 1)
    [ -n "$configured" ] && model=$configured
  fi
  tags=$(curl -s --max-time 3 http://127.0.0.1:11434/api/tags || true)
  if [ -z "$tags" ]; then
    echo "Ollama is not running: the assistant will answer with the offline planner."
  elif echo "$tags" | grep -Eq "\"name\":\"$model(:latest)?\""; then
    echo "Ollama is running with $model."
  else
    echo "Ollama is running but $model is not installed (ollama pull $model, or choose an installed model"
    echo "in Settings -> AI assistant). Until then the assistant answers with the offline planner."
  fi

  start llm "$LLM" 8100 "$(venv_python "$LLM")" -m agritrial_llm
  start backend "$BACKEND" 8000 "$(venv_python "$BACKEND")" -m uvicorn app.main:app --host 127.0.0.1 --port 8000
  start frontend "$FRONTEND" 5173 ./node_modules/.bin/vite --port 5173 --strictPort
  if ! wait_for http://127.0.0.1:8000/api/health || ! wait_for http://localhost:5173/; then
    echo "The backend or the frontend did not start; see .demo-logs/" >&2
    exit 1
  fi
  echo
  echo "App:      http://localhost:5173"
  echo "API docs: http://127.0.0.1:8000/docs"
  echo "Sign in:  admin@agrievidence.demo / admin123   or   viewer@agrievidence.demo / viewer123"
  open_url http://localhost:5173
fi

if [ ${#PIDS[@]} -gt 0 ]; then
  echo "Press Ctrl+C to stop."
  wait
fi
