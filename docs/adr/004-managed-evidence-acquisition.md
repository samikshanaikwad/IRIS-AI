# ADR 004 — Managed Local Evidence Acquisition

- Status: accepted
- Date: 2026-09-26
- Related phases: 04 Evidence import / integrity

## Context

Camera and gallery sources may expose temporary files or content references that are not durable. IRIS must preserve real evidence bytes, remain offline-first, avoid fabricated metadata, support one or many images, and keep SQLite metadata consistent with application-owned files.

## Decision

IRIS copies each acquired image unchanged into an app-private application-support directory using validated case/evidence IDs. SQLite schema version 2 stores metadata and the managed relative path, with a foreign key to `cases`. SHA-256 is calculated from the managed copy. Exact-byte duplicates are rejected only within the same case.

Imports are atomic per item so valid evidence is retained when another selected file fails. Partial results are reported truthfully. Evidence and case deletion stage files/directories by rename before database deletion, restore them if database deletion fails, and finalize deletion only after the database operation succeeds.

Camera capture uses `camera`; single/multiple gallery selection uses `image_picker`; application-private root discovery uses `path_provider`; hashing uses `crypto`. These dependencies are registered through the generated production MainActivity plugin path and protected by build/runtime diagnostics.

## Alternatives considered

- Retain picker URIs or temporary camera paths: rejected because availability is not durable.
- Store image bytes in SQLite: rejected because large binary data would make the database unsuitable for evidence collections.
- Derive duplicate identity from names/timestamps/dimensions: rejected because those properties do not establish byte equality.
- Batch-atomic multi-import: rejected because one unreadable item would discard other real, valid selections.
- Delete database records first without filesystem staging: rejected because failures could silently leave orphan files or rows pointing at missing files.

## Consequences

- IRIS owns a durable, read-only original copy and can reopen it offline.
- Storage usage increases because source evidence is copied intentionally.
- Filesystem and SQLite cannot share one transaction; staging and rollback reduce inconsistency but final filesystem deletion errors must still be surfaced.
- No AI or analytical meaning is inferred from acquired images in this phase.
