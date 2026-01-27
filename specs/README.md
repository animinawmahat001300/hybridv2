# SpecKit Consolidated Specifications

This folder is the **single consolidated SDD folder** containing all specification-driven development artifacts.

# # Structure

```text
specs/
├── project.md                              # Constitution / governance
├── README.md                               # This file
├── memory/
│   └── specs/memory/constitution.md        # Primary governance source
├── scripts/                                # SpecKit PowerShell automation
│   ├── specs/scripts/common.ps1
│   ├── specs/scripts/check-prerequisites.ps1
│   ├── specs/scripts/create-new-feature.ps1
│   ├── specs/scripts/setup-plan.ps1
│   ├── specs/scripts/setup-document.ps1
│   ├── specs/scripts/validate.ps1
│   ├── specs/scripts/archive-feature.ps1
│   ├── specs/scripts/list-features.ps1
│   └── specs/scripts/update-agent-context.ps1
├── templates/                              # SpecKit templates
│   ├── specs/templates/spec-template.md
│   ├── specs/templates/plan-template.md
│   ├── specs/templates/tasks-template.md
│   ├── specs/templates/checklist-template.md
│   ├── specs/templates/proposal-template.example.md  # Reference only, not required
│   └── specs/templates/agent-file-template.md
├── <capability>/                           # TRUTH: deployed specs
│   └── specs/<capability>/spec.md
└── changes/                                # PROPOSALS: active change packages
    ├── README.md
    ├── <change-id>/                        # One folder per change
    │   ├── specs/changes/<change-id>/proposal.md
    │   ├── specs/changes/<change-id>/spec.md
    │   ├── specs/changes/<change-id>/plan.md
    │   ├── specs/changes/<change-id>/tasks.md
    │   └── specs/changes/<change-id>/specs/<capability>/spec.md  # Delta specs
    └── archive/                            # HISTORY: immutable archived changes
        └── YYYY-MM-DD-<change-id>/
```

# # Dual-State Model

- **specs/<capability>/** - Current truth (deployed specifications)
- **specs/changes/** - Active change proposals and work-in-progress

# # Workflow

**Optional Preview Step:**
- `/speckit.document` - Preview workflow guide to console (read-only, informational only)

**Mandatory Execution Order:**

1. **Constitution**: `/speckit.constitution` - Establish governance (run FIRST)
2. **Specify**: `pwsh specs/scripts/create-new-feature.ps1 -Json "Feature description"` or `/speckit.specify`
3. **Clarify**: `/speckit.clarify` - Resolve ambiguities and ensure clarity
4. **Plan**: `/speckit.plan` - Create technical plan
5. **Tasks**: `/speckit.tasks` - Generate implementation checklist
6. **Checklist**: `/speckit.checklist` - Create acceptance criteria checklist
7. **TasksToIssues**: `/speckit.taskstoissues` - Convert tasks to GitHub issues
8. **Analyze**: `/speckit.analyze` - Validate consistency and compliance
9. **Implement**: `/speckit.implement` - Execute tasks and implement code
10. **Archive**: `/speckit.archive` or `pwsh specs/scripts/archive-feature.ps1 -Slug <id>`

# # FAQ

## # Why doesn't speckit.document create files?

The `speckit.document` agent has been refactored to **standalone, read-only mode** to ensure idempotency and avoid side effects. It now outputs workflow guidance to the console only, never creating or modifying files. This prevents accidental overwrites and maintains a clean separation of concerns.

## # How do I save the workflow guide?

Since `speckit.document` outputs to console only, you can:
- Redirect output: `/speckit.document > workflow-guide.txt`
- Copy-paste the guidance manually
- Use the guidance as reference without saving

## # Can I skip speckit.document?

Yes, `speckit.document` is now **optional**. You can proceed directly to `speckit.specify` or run `pwsh specs/scripts/create-new-feature.ps1 -Json "Feature description"` to create your feature structure. The document agent serves as an informational preview only.

## # What's the difference between document and specify?

- **`speckit.document`**: Analyzes your feature request, scans the codebase, checks governance, and outputs workflow guidance to console (read-only preview)
- **`speckit.specify`**: Creates the actual feature structure, generates specification files, and sets up the change package in `specs/changes/`

Document is for planning and guidance, specify is for execution and file creation.

## # Why did the workflow change?

The workflow was updated to make `speckit.document` standalone and read-only:
- **Removed file creation**: No more automatic `workflow.md` generation
- **Eliminated auto-handoff**: No automatic progression to other agents
- **Made optional**: Can be skipped entirely
- **Improved safety**: Idempotent re-runs with no side effects

This change simplifies the workflow while maintaining all functionality through explicit user actions.

# # References

- Constitution: `specs/memory/constitution.md`
- Agents: `.github/agents/` (e.g., `.github/agents/speckit.plan.agent.md`)
- Prompts: `.github/prompts/` (e.g., `.github/prompts/speckit.plan.prompt.md`)
- Migration Guide: `specs/docs/MIGRATION-DOCUMENT-AGENT-STANDALONE.md` (for standalone document agent changes)

# # Reference Audit

Run after documentation or template edits to ensure no missing paths:

```powershell
pwsh specs/scripts/audit-references.ps1 -Roots specs
```

Omit `-Roots specs` to audit the entire repository. If you need to force a different repo root (e.g., nested template), use `-RepoRootOverride <path>`.


