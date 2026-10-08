# AgriEvidence – Agricultural Trial Evidence App

AgriEvidence imports crop-trial results that arrive as spreadsheets and free-text reports, with inconsistent names, units and formats. It turns them into **one reconciled record per trial**, with every source, conflict and gap kept visible. Users can:
- find and compare trials, with charts;
- open the original source behind every value;
- ask an **Evidence Assistant**: a LangChain/LangGraph agent on Ollama that calls tools, decides its next step from their results, and fact-checks its answers. Each step is shown in an Inspection tab.

| Read this | For |
| --- | --- |
| **[SUBMISSION.md](SUBMISSION.md)** | The assessment write-up: business problem, assumptions, questions for the client, technical choices and tradeoffs, checks, limitations, next milestone, and the 5-minute demo script |
| [OVERVIEW.md](OVERVIEW.md) | How the app works, with diagrams |
| [Slides](https://claude.ai/artifact/57Lv2hURa7h717iLsAErFS) | The presentation deck |

## Repositories

The app is three standalone repos; this repo ties them together as git submodules, with the sample data, docs and start scripts.

| Repo | Contents |
| --- | --- |
| [Agricultural_Trial_Evidence_App](https://github.com/swarajparamata/Agricultural_Trial_Evidence_App) (this one) | Setup and start scripts for macOS, Linux and Windows; `sample-data/`; docs |
| [Agricultural_Trial_Evidence_App_Frontend](https://github.com/swarajparamata/Agricultural_Trial_Evidence_App_Frontend) | React app: dashboard, trial detail, compare charts, assistant with inspection log, settings |
| [Agricultural_Trial_Evidence_App_Backend](https://github.com/swarajparamata/Agricultural_Trial_Evidence_App_Backend) | FastAPI API: auth and roles, import and reconciliation, settings, comparison, assistant relay |
| [Agricultural_Trial_Evidence_App_LLM](https://github.com/swarajparamata/Agricultural_Trial_Evidence_App_LLM) | FastAPI + LangChain/LangGraph agent and report extraction, Ollama client, offline planner |

```
Browser ─▶ Frontend (React, :5173) ─REST/SSE─▶ Backend API (FastAPI + SQLite, :8000) ─HTTP/SSE─▶ LLM service (LangGraph, :8100) ─▶ Ollama (:11434)
```

## Quick start

**You need:** Git, Python 3.10 or newer (developed and tested on 3.10), and Node.js 20.19+ or 22 LTS. Ollama is optional (see [Model configuration](#model-configuration)).

```bash
git clone --recursive https://github.com/swarajparamata/Agricultural_Trial_Evidence_App.git
cd Agricultural_Trial_Evidence_App
```

If you cloned without `--recursive`, run `git submodule update --init`.

| | macOS / Linux | Windows |
| --- | --- | --- |
| One-time setup (virtual environments, npm packages) | `./setup.sh` | double-click `setup.cmd` |
| Start the app (opens <http://localhost:5173>) | `./start-demo.sh` (Ctrl+C stops it) | double-click `start-demo.cmd` (one window per service) |

On macOS, Homebrew provides the tools: `brew install python@3.12 node`. For a real LLM, also `brew install ollama` and start it with `brew services start ollama`, or install the Ollama app instead.

Sign in with a demo account; both are listed on the login page:

| Account | Password | Can |
| --- | --- | --- |
| `admin@agrievidence.demo` | `admin123` | everything: add trials and users, import files, resolve conflicts, change settings |
| `viewer@agrievidence.demo` | `viewer123` | browse, filter, compare, open sources, ask the assistant |

The first start creates the database and imports the six sample trials from `sample-data/`. **Settings → Trials & data → Reset demo** restores that state at any time.

## Seeing only the demo data

1. **Full app, demo data only (default).**
   - The backend runs in demo mode: it imports `sample-data/` (two CSVs and four reports, which become six reconciled trials) and creates the demo accounts.
   - Nothing else is loaded, and Reset demo returns to exactly this.
2. **Offline demo: frontend only, no Python, backend or Ollama.**
   - Run `./start-demo.sh --offline` (macOS/Linux) or `start-demo.cmd -Offline` (Windows). By hand: `cd Agricultural_Trial_Evidence_App_Frontend && npm install && npm run dev:offline`.
   - Open <http://localhost:5174> and sign in with any email; emails starting with `admin` get the admin role.
   - The same six reconciled trials live in the browser, so you can filter, compare and add trials by hand. The assistant, file import and settings need the full app.
3. **The raw files:**
   - `sample-data/` holds the files as supplied.
   - The [backend README](Agricultural_Trial_Evidence_App_Backend/README.md#from-files-to-trials) shows what they reconcile to: T01–T06, including T03's conflict (42 vs 44 t/ha), T05's missing control and single-source T06.

## Model configuration

The assistant needs no model to run.
- **Without Ollama:** answers come from the **offline planner**, a rule-based stand-in that runs the same LangGraph graph, tools and fact-checks. The chat header shows *Offline planner*.
- **With a real LLM:**
  1. Install and start [Ollama](https://ollama.com/download). The app starts it for you; with Homebrew, run `brew install ollama && brew services start ollama`. On Apple Silicon it runs models on the GPU.
  2. Pull a tool-calling model, e.g. `ollama pull qwen3:4b`.
  3. Point the app at it, either way:
     - **In the app:** Settings → AI assistant → *Ollama model* (e.g. `qwen3:4b`), then **Test the model**.
     - **As the default:** copy `Agricultural_Trial_Evidence_App_LLM/.env.example` to `.env`, set `OLLAMA_MODEL=qwen3:4b`, and restart. This default survives Reset demo.

| Model | Download | Fits | Notes |
| --- | --- | --- | --- |
| `qwen3:1.7b` | 1.4 GB | 8 GB RAM | Tested end to end on a laptop CPU (1–4 min per answer); needs the agent's guards and is less reliable |
| `qwen3:4b` | 2.5 GB | 16 GB RAM | Recommended for a MacBook |
| `qwen3.6` (the default) | ~17–24 GB | 32 GB+ RAM or a GPU server | The intended model; set *Ollama address* in Settings to use a remote server |

For predictable answers during a live demo, switch on Settings → AI assistant → **Always use the offline planner**. All settings are described in the [LLM README](Agricultural_Trial_Evidence_App_LLM/README.md#configuration).

## Starting the services by hand

Each in its own terminal, after `./setup.sh` (or `setup.cmd`):

```bash
# macOS / Linux
cd Agricultural_Trial_Evidence_App_LLM      && .venv/bin/python -m agritrial_llm                              # :8100
cd Agricultural_Trial_Evidence_App_Backend  && .venv/bin/python -m uvicorn app.main:app --port 8000           # :8000
cd Agricultural_Trial_Evidence_App_Frontend && npm run dev                                                  # :5173
```

```powershell
# Windows
cd Agricultural_Trial_Evidence_App_LLM;      .venv\Scripts\python -m agritrial_llm
cd Agricultural_Trial_Evidence_App_Backend;  .venv\Scripts\python -m uvicorn app.main:app --port 8000
cd Agricultural_Trial_Evidence_App_Frontend; npm run dev
```

- Interactive API docs: <http://127.0.0.1:8000/docs>; use *Authorize* with a demo account.
- LLM service status: <http://127.0.0.1:8100/health>.

## Running the tests

| | macOS / Linux | Windows |
| --- | --- | --- |
| LLM service (86 tests, no Ollama needed) | `cd Agricultural_Trial_Evidence_App_LLM && .venv/bin/python -m pytest` | `.venv\Scripts\python -m pytest` |
| Backend (65 tests) | `cd Agricultural_Trial_Evidence_App_Backend && .venv/bin/python -m pytest` | `.venv\Scripts\python -m pytest` |
| Frontend | `cd Agricultural_Trial_Evidence_App_Frontend && npm run typecheck && npm run lint && npm run build` | same |

## Troubleshooting

- **`permission denied: ./setup.sh`:** run `chmod +x setup.sh start-demo.sh`, or call them with `bash setup.sh`.
- **A port is already in use:** the start scripts skip a service whose port (8100, 8000, 5173, 5174) is taken. Stop the old process, or use the app that is already running.
- **Assistant badge says *Offline planner*:** either Ollama isn't running, or the configured model isn't pulled. Check <http://127.0.0.1:8100/health>, then `ollama list`.
- **Start fresh:** stop the app, delete `Agricultural_Trial_Evidence_App_Backend/data/`, and start again.
- **macOS blocks Ollama or Python on first run:** allow it in System Settings → Privacy & Security.

## Layout

```
Agricultural_Trial_Evidence_App/
├── setup.sh · start-demo.sh            macOS / Linux
├── setup.cmd/.ps1 · start-demo.cmd/.ps1 Windows
├── SUBMISSION.md · OVERVIEW.md          write-up and explanation
├── docs/diagrams/                       architecture, question flow, pipeline, agent loops, data model (PNG + Mermaid)
├── sample-data/                         the supplied trial files
├── Agricultural_Trial_Evidence_App_Frontend/   (submodule)
├── Agricultural_Trial_Evidence_App_Backend/    (submodule)
└── Agricultural_Trial_Evidence_App_LLM/        (submodule)
```
