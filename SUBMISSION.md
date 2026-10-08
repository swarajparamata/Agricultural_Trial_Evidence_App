# AgriEvidence – assessment submission

**Code:** <https://github.com/swarajparamata/Agricultural_Trial_Evidence_App>. Clone with `--recursive`, then:
- macOS / Linux: `./setup.sh` and `./start-demo.sh`;
- Windows: `setup.cmd` and `start-demo.cmd`.

Setup, the demo accounts, the offline demo and model configuration are in the [README](README.md). How it works is in [OVERVIEW.md](OVERVIEW.md).

---

## 1. Understanding of the business problem

An agricultural products company runs hundreds of crop trials a year. The results sit in spreadsheets and reports with inconsistent names, units and formats, so earlier work is hard to find and reuse. Two groups pay for that:

- **Agronomists**, before planning a trial, need to see what has already been tested for a product, crop, country, year and trial type, and what it showed. Otherwise trials get repeated, or designed without the earlier lessons.
- **Commercial teams** need evidence behind product claims such as "Harvest Plus improves wheat yield". They also need to know how strong that evidence is: how many trials, which kind, and whether the sources agree.

So the core problem isn't storage but **trust and findability**. What's needed is:
- one record per trial, built from every source;
- honesty about where sources disagree or values are missing;
- a fast way to search and compare;
- answers that always point back to the original files.

The supplied data shows each difficulty in miniature:

| Issue | Example in the sample data |
| --- | --- |
| Different layouts | Two CSVs with different headers; four free-text reports |
| Inconsistent names | `Harvest Plus` / `HarvestPlus` / `HARVESTPLUS`, `potato` / `potatoes`, `FR` / `DE` / `ES` |
| Units | `7800 kg/ha` in one file, `7.8 t/ha` in another |
| Duplicates | T01 appears in both CSVs |
| Missing values | T05 has no control yield |
| Conflicting results | T03's treated yield: 42 t/ha (CSV) vs 44 t/ha (report). The report itself says neither is final |
| Weak evidence | Single-source T06; undocumented replication and statistics |

### How the brief is covered

| Required outcome | Where |
| --- | --- |
| Import the CSVs and reports into usable records | Imported on first start, or uploaded with a preview (Add New Trial → Upload files; Settings → Trials & data). Rules-based parsing, with a validated LLM extraction loop for reports the rules can't read |
| Find trials by crop, product, country, year and type; compare results | Dashboard filters, insight tiles and charts; Compare view with charts, warnings and a field table |
| Access to the original sources behind records and answers | Every trial lists each source's values; source files open in a viewer from trials and from assistant answers |
| Inconsistent names, units, duplicates, missing values, conflicts | Configurable vocabulary, aliases and units; per-trial reconciliation keeps both conflicting values, shows the uplift range, flags gaps; admins can resolve with a reason |
| LLM agent that uses tools, chooses next actions from results, with inspectable activity and status | A LangGraph agent with six tools. Its **tool loop** decides the next call from the last results; its **reflection loop** fact-checks drafts and sends failures back. The **Inspection** tab streams every step and the final status |
| Browser interface for the workflow | React app with admin and viewer roles |

The five example requests, run through the app's agent:

| Request | Answer |
| --- | --- |
| Show all wheat trials involving Harvest Plus | T01, T02, T05, T06, with sources and caveats (T05: no control) |
| Compare Harvest Plus wheat results in France and Germany | France (T01) +5.0% vs Germany +4.0% (T02); T05 has no control |
| What evidence supports Root Boost improving potato yields? | Weak and mixed: T03 +5.0% (+10.0% by the report; the sources conflict) and T04 0.0% in the scientific trial; no significance reported |
| Which scientific wheat trials ran from 2021 through 2025? | T01 (2023) and T06 (2021) |
| Is there evidence for Harvest Plus improving rice yields? | No: there are no rice trials, and Harvest Plus has only been tested on wheat (4 trials) |

These are offline-planner answers and are automated tests (`tests/test_client_brief.py`). For how the real 1.7B model did on the same questions, see [§5](#5-checks-performed).

## 2. Assumptions

- **Trial identity:**
  - A trial ID (e.g. `T03`) identifies one trial across all files.
  - Rows and reports with the same ID describe the same trial.
- **Outcome:**
  - Yield uplift against the untreated control, (treated − control) ÷ control, is the primary outcome.
  - Yields are per hectare and shown in t/ha (configurable), with 1 t/ha = 1000 kg/ha.
- **Conflicts:**
  - No source is assumed right. Both values are kept and the trial is flagged.
  - By default the spreadsheet value is shown (the source priority is configurable), with the range of uplift the sources allow.
  - An admin can choose a value, with a reason.
- **Tolerance:** values within 0.5% are treated as the same reading (rounding). This is configurable.
- **No statistics:** the data has no significance or replicate data, so uplifts are presented as indicative, and the app says so.
- **Volume:** hundreds of trials a year. SQLite and sending the reconciled dataset with each assistant question are enough for this stage.
- **Report layout:** most reports use "Label: value." sentences. Others go to LLM extraction, which is validated against the text.
- **Hosting:**
  - Data should stay in-house, so the LLM runs locally through Ollama.
  - Qwen 3.6 is the intended model; smaller Qwen 3 models are acceptable on smaller hardware.
- **Users:** two roles, admin and viewer, are enough. Local accounts are used, with no SSO yet.
- **Sample data:** it is fictional, in English, and holds no personal data.

## 3. Questions for the client

1. **Conflicts.** Who decides which value is final when sources disagree, as with T03? Should one source type win by default, and should resolutions need approval?
2. **Trial identity.** Are trial IDs unique across years, regions and programmes? Is there a master trial register to match against?
3. **Evidence standard for claims.** What makes a claim supportable: a number of scientific trials, significance, regional coverage? Do commercial teams need an exportable evidence pack?
4. **Outcomes and statistics.** Which measures matter besides yield (quality, disease, return on investment)? Are replicates, variance or p-values available in the sources?
5. **Sources and volume.** Which formats exist besides CSV and text (Excel, PDF, exports from a trial management system)? How many files a year, and is there history to back-load?
6. **Vocabulary ownership.** Is there a master list of products, crops and countries, and who maintains it?
7. **Access.** Do regions or confidential trials need restricted visibility? Is single sign-on required?
8. **Hosting and LLM.** Cloud or on-premises? May trial data go to a hosted LLM, or must models run in-house, and is GPU capacity available?
9. **Audit and retention.** Are there regulatory requirements for claims (audit trail, retention, sign-off)?
10. **Success measures.** How should success be measured: time to find prior trials, duplicated trials avoided, claims substantiated?

## 4. Technical choices and tradeoffs

| Choice | Why | Tradeoff |
| --- | --- | --- |
| **Three services:** React, a FastAPI backend that owns data and auth, and a stateless FastAPI LLM service | Clear ownership; the LLM stack is isolated and can move to a GPU host; each part is tested alone | More moving parts than one app; three repos |
| **Reconcile on import**, keeping the raw source records and admin overrides separately | Full provenance; rule changes re-process stored files; admin decisions survive re-imports | Rebuilds re-process everything, fine for thousands of trials; incremental rebuilds would be needed at larger scale |
| **Rules first, LLM second for parsing**, with LLM extraction validated against the text in a retry loop | Deterministic, testable and cheap; the LLM can't invent yields | Unusual layouts need header aliases (configurable in Settings) |
| **Everything configurable in Settings:** vocabulary, aliases, units, tolerance, conflict strategy, caveat rules, custom fields | Business users adapt the system without code | More UI and validation to maintain |
| **Agent:** a LangGraph state machine with a bounded tool loop and a deterministic reflection loop (fact-checker) | Transparent (every step is inspectable) and grounded (numbers, IDs, conflicts and caveats are checked against tool results) | The checks are heuristics: they can't judge every qualitative claim. Revisions add latency |
| **Agent tools over a per-question snapshot** of the reconciled data, rather than text-to-SQL | Safe; tools return compact JSON with provenance; no SQL injection surface | Doesn't scale to very large datasets; next step is database-backed tools |
| **Local models through Ollama** | Data stays in-house; the model is switchable in Settings | Quality depends on model size; Qwen 3.6 needs ~17–24 GB |
| **Offline planner:** a rule-based chat model running in the same graph | Demos and tests work anywhere; it also serves as the fallback when the LLM fails | It's not an LLM; it covers anticipated question types only |
| **Guards for small models:** parser hint; refusals of invented IDs, filters and fields; checks for caveats given to the wrong trial | Made `qwen3:1.7b` usable on a laptop | Couples the agent to rule-based parsing; a guard can refuse a legitimate unusual call (the corrective message lets the model retry) |
| **SQLite** | Zero setup for reviewers | Single writer; `DATABASE_URL` can point to PostgreSQL (not yet tested) |
| **Custom SVG charts** instead of a chart library | Conflict whiskers, one axis per crop, table views, small bundle | More code to own |
| **JWT and argon2, roles enforced in the API** | Standard and simple | No SSO or refresh tokens; the token is kept in browser storage |

## 5. Checks performed

- **Automated tests:**
  - **LLM service, 86 tests.** They cover:
    - the tool and reflection loops, driven by a scripted chat model;
    - fallback when the model is down or fails mid-run;
    - the small-model guards and the fact-check rules;
    - the HTTP API, including streaming and the API key;
    - the extraction loop;
    - the brief's five example requests.
  - **Backend, 65 tests.** They cover:
    - import and reconciliation of the sample data: aliases, codes, units, duplicates, conflict range and caveats;
    - roles and auth guards;
    - trial edits, overrides, conflict resolution, delete and restore;
    - settings that trigger a rebuild;
    - comparison, including ties;
    - the assistant relay and demo reset.
  - **Frontend:** type-check, lint and production build.
- **Browser end to end:** Playwright drove headless Chrome against all three services, with zero console errors.
  - Admin flows: add a trial by form and by file upload, including the preview; duplicate ID rejected; conflict resolution; custom field; reset demo.
  - Viewer restrictions.
  - The offline demo.
- **Real LLM:** `qwen3:1.7b` in Ollama on a laptop CPU, with the brief's five questions run end to end through the app.
  - Three answers were fully correct.
  - One overstated its conclusion.
  - One was flagged by the fact-check and shown with a warning.
  - Each answer took 1.0–4.4 minutes. The failures led to the small-model guards (§4).
- **Data:** the six reconciled trials were checked by hand against the raw files.
- **Charts:** the palette was checked for colour-vision deficiency. Statuses use an icon and text, never colour alone, and every chart has a table view.
- **Scripts:**
  - The Windows scripts ran on Windows.
  - `setup.sh` and `start-demo.sh` ran under bash (Git Bash), in full and offline modes, and passed ShellCheck.
  - They have not been run on a Mac.

## 6. Known limitations

- **Qwen 3.6 hasn't been run.** The development laptop has 7.3 GB of RAM, and the model needs ~17–24 GB.
- **Small models are slow on a CPU and less reliable.** `qwen3:1.7b` takes 1–4 minutes per answer and can overstate a conclusion. The fact-checks catch numbers, IDs, disclosures and caveats, not every qualitative claim.
- **The offline planner** handles anticipated question types only.
- **The assistant receives the whole reconciled dataset** with each question. That's fine for this volume; thousands of trials need database-backed tools or retrieval.
- **Import** reads CSV, TSV, TXT and MD only: no Excel, PDF (no OCR) or ZIP.
- **No statistical analysis**, since the data has none.
- **Not production-hardened:**
  - single SQLite instance;
  - no SSO, rate limiting or CI;
  - demo accounts with published passwords (demo mode only).
- **The macOS scripts** haven't been run on a Mac (see §5).

## 7. Proposed next milestone: a pilot with real data

**Goal:** a small group of agronomists and commercial users uses the app on one region's real trial history, and the assistant's answers are measured.

1. **Ingestion at real scale:**
   - Excel and PDF import, with extraction into a human review queue;
   - ZIP and batch upload;
   - a scheduled pull from the trial management system;
   - incremental rebuilds.
2. **An assistant that scales and can be measured:**
   - database-backed query tools, with filters and aggregates in SQL;
   - retrieval over report text;
   - an evaluation set of 50–100 real questions with expected answers;
   - Qwen 3.6, or an approved model, on a GPU server;
   - tracking of accuracy, fact-check pass rate and latency.
3. **Evidence for claims:**
   - an exportable evidence pack per claim, with citations;
   - an evidence-strength summary: number of scientific trials, consistency, conflicts;
   - fields for statistics where sources have them.
4. **Governance and operations:**
   - approval of conflict resolutions;
   - SSO and region-level access;
   - PostgreSQL and Docker Compose;
   - CI running the tests and browser flows.

**Success criteria:**
- finding prior trials for a product, crop and country takes under a minute;
- at least 90% of evaluation questions are answered correctly, with citations;
- no unflagged conflicts in answers.
