---
name: vaultstream-code-audit
description: Scan the VaultStream repository (FastAPI backend + Flutter frontend) for code line-count distribution and codebase slimness signals, including duplicate code clusters, dead/legacy/fallback markers, and likely hand-rolled utility implementations. Use when Codex needs to produce an actionable Markdown audit report for backend/app and frontend/lib (excluding generated Dart files by default), and outline concrete refactor candidates to reduce redundancy and remove outdated logic.
---

# VaultStream Code Audit Workflow

## Generate Report

1) Run the repo script to produce a Markdown report:

- `python scripts/code_audit_report.py`
- Or set an explicit output path: `python scripts/code_audit_report.py --output docs/code_audit_report_YYYYMMDD.md`

2) Open the generated report in `docs/` and focus on these sections:

- `Core Business LOC`: confirm business scope size (backend/app + frontend/lib; generated `.freezed.dart`/`.g.dart` excluded by default)
- `Duplicate Code Clusters`: pick the largest clusters and decide whether to extract shared helpers/components
- `Potential Dead/Legacy/Fallback Markers`: validate each marker with usage paths, tests, and logs/metrics (if available)
- `Candidate Hand-Rolled Utilities`: treat as hints only; confirm before refactoring

## Triage Checklist (Manual)

1) For each duplicate cluster:
- Confirm it is truly the same business intent (not superficial similarity)
- Decide: extract helper vs keep separate vs delete obsolete branch

2) For each `fallback/legacy` marker:
- Identify why it exists (compat, migration, third-party quirks)
- Add or update tests before deleting logic
- Remove the fallback only after confirming no live callers depend on it

3) For each hand-rolled utility candidate:
- Check whether stdlib or existing deps already cover it (e.g., caching/retry/JSON/date parsing)
- Prefer reducing custom code if behavior matches and observability/errors remain acceptable

## Output Expectations

Produce:
- One Markdown report file under `docs/` (link the exact path)
- A short "Top refactor candidates" list (3-10 items) referencing exact file paths and rationale
