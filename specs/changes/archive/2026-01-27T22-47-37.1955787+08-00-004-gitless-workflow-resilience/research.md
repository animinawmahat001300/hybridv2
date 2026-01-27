# Research: gitless-workflow-resilience

**Feature**: 004-gitless-workflow-resilience
**Date**: 2026-01-27
**Spec**: spec.md

---

# # Research Summary

| Topic | Decision | Confidence |
|-------|----------|------------|
| Gitless change resolution | Resolve change ID from `SPECIFY_CHANGE_ID` or active `specs/changes/<id>` folder; avoid Git dependency | High |
| Workspace snapshot schema | JSON file with summary metadata, modified/untracked lists, optional Git status block | High |
| Verbosity control | Default to concise phase summaries; detailed output gated by `-Verbose` and `Write-Verbose` | High |
| Archive with dirty workspace | Allow archive; emit warning; fail if snapshot write fails | High |

---

# # Detailed Findings

## # Gitless change resolution

**Question**: How should workflow scripts resolve change ID and repo root when Git is missing?

**Decision**: Resolve the change ID from `SPECIFY_CHANGE_ID` when set, otherwise detect a single active directory under `specs/changes/`. Resolve repo root by walking up from the script path to the `specs/` folder.

**Rationale**: This keeps workflows functional in non-Git environments and aligns with the file-based truth principle.

**Alternatives Considered**:
- Require Git branch name: Rejected because Gitless execution is a primary requirement.
- Require explicit CLI parameter: Rejected because existing scripts use environment and folder conventions.

**Sources**:
- SpecKit scripts (`specs/scripts/common.ps1`) patterns for repo root detection

## # Workspace snapshot schema

**Question**: What minimal data should be captured to preserve workspace state without copying full files?

**Decision**: Create `workspace-snapshot.json` with `schema_version`, `captured_at`, `change_id`, `workspace_root`, `git_available`, `git_status` (optional), `modified_files`, `untracked_files`, and per-file metadata (path, size_bytes, last_write_time).

**Rationale**: Metadata-only capture limits size and runtime while preserving evidence of local changes.

**Alternatives Considered**:
- Full workspace archive: Rejected due to size and performance constraints.
- Git-only status snapshot: Rejected because Git may be unavailable or incomplete.

**Sources**:
- PowerShell `Get-ChildItem` and `Get-Item` metadata fields

## # Verbosity control

**Question**: How should scripts reduce default output while retaining detailed logs for diagnostics?

**Decision**: Emit concise phase start/end summaries and warnings by default. Use `Write-Verbose` for detailed steps gated by `-Verbose` or `$VerbosePreference`.

**Rationale**: This mirrors PowerShell conventions and supports the ≤ 30 line default output requirement.

**Alternatives Considered**:
- New custom logging switch: Rejected because `-Verbose` already provides a standard experience.

**Sources**:
- PowerShell logging guidance for `Write-Verbose`

## # Archive with dirty workspace

**Question**: What should happen when uncommitted changes exist during archive?

**Decision**: Allow archive to continue, emit a warning, and include a workspace snapshot. Fail archive if snapshot write fails.

**Rationale**: Preserves traceability while enforcing snapshot integrity.

**Alternatives Considered**:
- Block archive until clean workspace: Rejected because it prevents WIP preservation.

**Sources**:
- Feature spec requirements REQ-004 and REQ-005

---

# # Resolved Items

| Original | Resolution |
|----------|------------|
| Gitless change ID resolution | Use `SPECIFY_CHANGE_ID` or active `specs/changes/<id>` folder and repo root detection via filesystem. |
| Snapshot format | JSON metadata snapshot with file lists and optional Git status block. |
| Verbosity control | Default summaries + warnings; `-Verbose` for detailed output. |
| Archive behavior with dirty workspace | Allow archive, emit warning, fail on snapshot write error. |

---

# # Remaining Unknowns

None. All technical questions from the spec are resolved for Phase 1 design.





