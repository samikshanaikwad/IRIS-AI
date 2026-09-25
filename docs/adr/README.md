# Architecture Decision Records

Architecture Decision Records (ADRs) document durable technical decisions, their context, alternatives, consequences, and status. Create one Markdown file per decision in this directory using a sortable name such as `0001-offline-inference.md`.

Each ADR should contain:

- Title and decision number
- Status: proposed, accepted, superseded, or deprecated
- Date
- Context and constraints
- Decision
- Alternatives considered
- Consequences and trade-offs
- Related requirements, ADRs, or implementation phases

ADRs are append-only historical records. Do not rewrite an accepted decision to hide history; create a new ADR that supersedes it and link both records. Decisions must comply with `AGENTS.md`, especially the real-data, evidence-integrity, provenance, deterministic-physics, and offline-first rules.
