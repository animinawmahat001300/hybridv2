# Quickstart: gitless-workflow-resilience

**Feature**: 004-gitless-workflow-resilience
**Date**: 2026-01-27

---

# # Overview

Enable SpecKit workflow scripts to run without Git, capture workspace snapshots during archive, and keep default output concise while preserving verbose detail on demand.

---

# # Prerequisites

- PowerShell 7.4+ installed
- Access to the workspace folder with `specs/changes/`
- Optional: Git 2.30+ if you want Git metadata in snapshots

---

# # Quick Integration

## # Scenario: Run a workflow without Git

**Goal**: Execute SpecKit scripts in a folder without `.git` using file-based change resolution.

**Steps**:

1. Set the change ID explicitly when Git is unavailable:
   ```powershell
   $env:SPECIFY_CHANGE_ID = "004-gitless-workflow-resilience"
   ```
2. Run the prerequisite check:
   ```powershell
   specs/scripts/check-prerequisites.ps1 -Json
   ```
3. Confirm the JSON output includes `CHANGE_ID` and `FEATURE_SPEC` paths without Git errors.

## # Scenario: Archive with a dirty workspace

**Goal**: Archive a change even when uncommitted files exist and capture a workspace snapshot.

**Steps**:

1. Leave modified or untracked files in the workspace.
2. Run the archive script:
   ```powershell
   specs/scripts/archive-feature.ps1 -ChangeId 004-gitless-workflow-resilience
   ```
3. Verify the archive folder contains `workspace-snapshot.json` with modified and untracked file lists.

---

# # API Reference

| Endpoint | Method | Purpose | Contract |
|----------|--------|---------|----------|
| `/api/workflow/check-prerequisites` | GET | Resolve change ID and environment readiness | `contracts/workflow/check-prerequisites.yaml` |
| `/api/workflow/run` | POST | Run a workflow with summary or verbose output | `contracts/workflow/run.yaml` |
| `/api/workflow/archive` | POST | Archive a change and capture workspace snapshot | `contracts/workflow/archive.yaml` |

---

# # Error Handling

| Error Code | Meaning | Resolution |
|------------|---------|------------|
| WKF-ROOT-NOT-FOUND | Workspace root could not be resolved | Run from within a SpecKit workspace or set `SPECIFY_CHANGE_ID` and verify `specs/` exists. |
| WKF-CHANGEID-MISSING | Change ID could not be resolved without Git | Set `SPECIFY_CHANGE_ID` or ensure a single change folder exists. |
| WKF-SNAPSHOT-WRITE-FAILED | Snapshot file could not be written | Check archive folder permissions and retry. |
| WKF-ARCHIVE-FAILED | Archive aborted due to snapshot failure | Resolve snapshot errors and re-run archive. |

---

# # Testing

```powershell
Describe "Gitless workflow" {
	It "resolves change ID from SPECIFY_CHANGE_ID" {
		$env:SPECIFY_CHANGE_ID = "004-gitless-workflow-resilience"
		$result = & specs/scripts/check-prerequisites.ps1 -Json | ConvertFrom-Json
		$result.data.CHANGE_ID | Should -Be "004-gitless-workflow-resilience"
	}

	It "writes workspace snapshot on archive" {
		$archive = & specs/scripts/archive-feature.ps1 -ChangeId "004-gitless-workflow-resilience" -Json | ConvertFrom-Json
		Test-Path (Join-Path $archive.data.ARCHIVE_DIR "workspace-snapshot.json") | Should -BeTrue
	}
}
```

---

# # Common Issues

- **Gitless mode still reports branch errors**: Ensure the latest scripts are in place and `SPECIFY_CHANGE_ID` is set.
- **Snapshot file missing**: Confirm archive completed successfully and the archive directory is writable.




