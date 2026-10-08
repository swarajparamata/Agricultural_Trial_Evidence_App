#!/usr/bin/env bash
# One-time setup on macOS or Linux: a Python virtual environment for the LLM service and for the backend, and
# the frontend's npm packages. Safe to run again.
#
#   ./setup.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LLM="$ROOT/Agricultural_Trial_Evidence_App_LLM"
BACKEND="$ROOT/Agricultural_Trial_Evidence_App_Backend"
FRONTEND="$ROOT/Agricultural_Trial_Evidence_App_Frontend"

fail() {
  printf '\033[31m%s\033[0m\n' "$*" >&2
  exit 1
}
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

for dir in "$LLM" "$BACKEND" "$FRONTEND"; do
  [ -f "$dir/README.md" ] || fail "$(basename "$dir") is missing. Clone with --recursive, or run: git submodule update --init"
done

# Python 3.10 or newer; 3.12 and 3.11 are preferred.
PYTHON=""
for candidate in python3.12 python3.11 python3.13 python3.10 python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 \
    && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
    PYTHON="$candidate"
    break
  fi
done
[ -n "$PYTHON" ] || fail "Python 3.10 or newer is required. macOS: brew install python@3.12"
command -v node >/dev/null 2>&1 || fail "Node.js 20 or newer is required. macOS: brew install node"
node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)' \
  || fail "Node.js 20 or newer is required (found $(node --version))."

# The interpreter inside a virtual environment (bin/ on macOS and Linux, Scripts/ on Windows).
venv_python() {
  if [ -x "$1/.venv/bin/python" ]; then echo "$1/.venv/bin/python"; else echo "$1/.venv/Scripts/python.exe"; fi
}

for dir in "$LLM" "$BACKEND"; do
  step "$(basename "$dir"): Python packages ($("$PYTHON" --version))"
  [ -d "$dir/.venv" ] || "$PYTHON" -m venv "$dir/.venv"
  "$(venv_python "$dir")" -m pip install --quiet --disable-pip-version-check -r "$dir/requirements.txt"
done

step "$(basename "$FRONTEND"): npm packages"
if [ -d "$FRONTEND/node_modules" ]; then
  (cd "$FRONTEND" && npm install --no-audit --no-fund)
else
  (cd "$FRONTEND" && npm ci --no-audit --no-fund)
fi
[ -f "$FRONTEND/.env" ] || cp "$FRONTEND/.env.example" "$FRONTEND/.env"

step "Setup complete."
echo "  Full app:            ./start-demo.sh"
echo "  Offline demo only:   ./start-demo.sh --offline"
if ! curl -s --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo
  echo "Optional, for answers from a real LLM: install Ollama (https://ollama.com/download) and pull a model,"
  echo "e.g. 'ollama pull qwen3:4b', then set it in Settings -> AI assistant. Without it the assistant uses"
  echo "its offline planner."
fi
