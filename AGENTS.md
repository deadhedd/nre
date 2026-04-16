# AGENTS.md

## Purpose

Guidance for automated agents working in this repository.

This file is **advisory only**.
All authoritative behavior is defined in `docs/CONTRACT.md`.

---

## Authority

Order of authority (highest → lowest):

1. `docs/CONTRACT.md`
2. Existing code behavior (only where the contract is silent)
3. This file

If this file conflicts with the contract, **this file is wrong**.

---

## Mandatory Contract References

Agents MUST consult the contract before modifying code.

Key sections:

- **Execution & wrapper model**
  - §3.1 — Execution Contract (job-wrap)

- **Stdout / stderr discipline**
  - §2.1 — Stdout / Stderr Contract
  - §2.1.4 — Silence Is Valid Output

- **Logging ownership**
  - §2.2 — Logging Contract

- **Exit codes**
  - §2.3 — Exit Code Semantics
  - §3.3.7 — Commit Helper Exit Code Semantics
  - §3.4.11 — Status Reporter Exit Code Semantics

- **Freshness & health**
  - §2.4 — Run Cadence & Freshness
  - §3.4.5 — Freshness Model
  - §3.4.6 — Classification Semantics

- **Determinism**
  - §2.6.6 — Time-Based Scripts and Determinism
  - §3.4.8 — Output Contract (Markdown Report)

If uncertain which section applies, do not change behavior.

---

## Preservation Rules

Agents MUST preserve existing behavior unless the contract explicitly permits change.

Agents MUST NOT:

- Change exit code meanings (§2.3, §3.3.7, §3.4.11)
- Add, remove, or reformat stdout output (§2.1)
- Treat WARN or staleness as failure (§3.4.6)
- Tighten intentionally permissive semantics
- Loosen intentionally strict semantics

Preserve behavior over refactoring quality.

---

## Determinism

Determinism requirements are non-negotiable.

Agents MUST NOT introduce:

- Nondeterministic ordering (§3.4.8)
- Time-dependent output unless explicitly required (§2.6.6)
- Filesystem-order-dependent behavior

“Safe to diff” output (§3.4.8) must remain safe to diff.

---

## Logging

Log artifacts and pointers are authoritative.

Agents MUST NOT:

- Scan historical logs (§3.4.5)
- Infer meaning beyond documented rules (§2.2)
- Reorganize log paths (§2.2)
- Bypass `*-latest.log` pointers (§3.4.5)

Vault log copies are presentation artifacts only (§3.4.10).

---

## Environment Constraints

Agents MUST preserve:

- POSIX `sh` compatibility (§2.5.7)
- No bashisms
- No GNU-only flags unless unavoidable
- ASCII-only output where required (§2.2.7)

Portability is a contract constraint, not a style preference.

---

## Non-Goals

Agents MUST NOT:

- Perform style-only refactors
- Introduce abstractions without request
- Normalize behavior across scripts
- Infer roadmap or future intent

---

## When Unsure

If a change may violate the contract:

- Stop
- Ask
- Or make no change

Silence is safer than speculation.
