# SpecKit Consolidated Change Management

This directory manages all active work through the unified SDD workflow.

# # Directory Structure

```text
specs/changes/
├── README.md                                # This file
├── <change-id>/                             # Each active change (all artifacts together)
│   ├── specs/changes/<change-id>/proposal.md   # Why / What / Impact
│   ├── specs/changes/<change-id>/spec.md       # Feature specification
│   ├── specs/changes/<change-id>/plan.md       # Implementation plan
│   ├── specs/changes/<change-id>/tasks.md      # Task breakdown
│   ├── specs/changes/<change-id>/research.md   # Research notes (optional)
│   ├── specs/changes/<change-id>/data-model.md # Entity definitions (optional)
│   ├── specs/changes/<change-id>/checklists/   # Quality checklists (optional)
│   ├── specs/changes/<change-id>/contracts/    # API contracts (optional)
│   └── specs/changes/<change-id>/specs/        # Delta changes to existing specs
│       └── <capability>/
│           └── spec.md                        # ADDED/MODIFIED/REMOVED requirements
│           └── specs/changes/<change-id>/specs/<capability>/spec.md  # ADDED/MODIFIED/REMOVED requirements (delta)
│           └── specs/changes/<change-id>/spec.md       # Feature specification
│           └── specs/changes/<change-id>/plan.md       # Implementation plan
└── archive/                     # Completed changes (immutable)
    └── YYYY-MM-DD-<change-id>/  # Dated archive folders
```

# # Workflow

## # Creating a Change (via Agents)

```pwsh
# 1. Create feature specification
/speckit.specify Add user authentication with OAuth2

# 2. Resolve ambiguities
/speckit.clarify

# 3. Generate implementation plan
/speckit.plan

# 4. Create quality checklist
/speckit.checklist

# 5. Break into tasks
/speckit.tasks

# 6. Analyze for consistency
/speckit.analyze

# 7. Implement
/speckit.implement

# 8. Validate and archive
pwsh scripts/validate.ps1 -ChangeId [change-id]
/speckit.archive
```

## # Creating a Change (Manual)

1. **Create directory**: `changes/[change-id]/`
   - Use kebab-case, verb-led naming: `add-oauth-support`, `update-user-roles`

2. **Create `specs/changes/{CHANGE_ID}/spec.md`** (feature specification)

3. **Create spec deltas** (if modifying existing specs): `specs/changes/{CHANGE_ID}/specs/<capability>/spec.md`

   ```markdown
   ## ADDED Requirements
   ### Requirement: [Feature Name]
   The system SHALL [behavioral statement].

   #### Scenario: [Success Case]
   - **WHEN** [pre-condition/action]
   - **THEN** [result]
   ```

4. **Create `specs/changes/{CHANGE_ID}/tasks.md`**:

   ```markdown
   ## 1. Implementation
   - [ ] T001 Create database schema
   - [ ] T002 Implement API endpoint
   ```

## # Validation

```powershell
# Validate specific change
pwsh specs/scripts/validate.ps1 -Target [change-id]

# List all changes
pwsh specs/scripts/list-features.ps1
```

# # Delta Operations

| Operation | Usage | Critical Rule |
| --------- | ----- | ------------- |
| ADDED Requirements | New capabilities | Must include scenario |
| MODIFIED Requirements | Changed behavior | Must include FULL text |
| REMOVED Requirements | Deprecated features | Should include reason |

**Critical Warning**: MODIFIED must include complete requirement text. The archiver replaces the entire requirement.

# # Current Changes (Template)

No active change folders are included in this template. Create a new change with:

```powershell
pwsh specs/scripts/create-new-feature.ps1 -Json "Your feature description"
```

# # Commands Reference (PowerShell Scripts)

```powershell
# Create new change
pwsh specs/scripts/create-new-feature.ps1 -Json "Feature description"

# Check prerequisites
pwsh specs/scripts/check-prerequisites.ps1 -Json

# List active changes
pwsh specs/scripts/list-features.ps1

# Validate specific change
pwsh specs/scripts/validate.ps1 -Target [change-id]

# Archive after deployment
pwsh specs/scripts/archive-feature.ps1 -Slug [change-id] -Yes
# OR use agent
/speckit.archive
```


