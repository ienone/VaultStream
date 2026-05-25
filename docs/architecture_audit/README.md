# VaultStream Architecture Audit Archive

> Status: historical snapshot.
> Original audit date: 2026-04-07.
> Current roadmap: `docs/architecture/ROADMAP_V2.md`.

These files are preserved as investigation notes, not as current status. Several findings from this audit have since been fixed or narrowed. Before using any item as a task, verify it against current code and `docs/exam/10_implementation_status.md`.

## Files

| File | Use |
|---|---|
| `01_system_overview.md` | Historical module map and workflow inventory. Useful for orientation. |
| `02_chain_flows.md` | Historical data-flow tracing. Recheck current code before acting. |
| `03_smell_catalog.md` | Historical smell catalog. Some entries are already remediated. |
| `04_architecture_diagrams.md` | Historical diagrams. Useful as conceptual reference only. |
| `05_refactor_roadmap.md` | Superseded by `docs/architecture/ROADMAP_V2.md`. |
| `06_frontend_audit.md` | Historical frontend audit. Recheck current Flutter code before using findings. |
| `07_rag_vector_search_implementation.md` | Superseded in part by current semantic-search code and `docs/architecture/VECTOR_SEARCH_EVALUATION.md`. |

## Current Policy

- Use these docs to find old hypotheses and context.
- Do not cite their severity or implementation status without a fresh code check.
- Prefer current code, tests, OpenAPI docs gate, schema gate, and `docs/exam/10_implementation_status.md` for closure decisions.
