# SpecKit Templates

This directory contains templates for the SpecKit consolidated workflow.

# # Template Files

| Template | Purpose | Used By | Status |
|----------|---------|---------|--------|
| `spec-template.md` | Feature specification structure | `/speckit.specify`, `/speckit.constitution` | Active |
| `plan-template.md` | Implementation plan structure | `/speckit.plan`, `/speckit.constitution` | Active |
| `tasks-template.md` | Task breakdown structure | `/speckit.tasks`, `/speckit.plan`, `/speckit.constitution` | Active |
| `checklist-template.md` | Quality checklist structure | `/speckit.checklist`, `/speckit.specify` | Active |
| `research-template.md` | Technical research findings | `/speckit.plan` | Active |
| `data-model-template.md` | Entity and relationship definitions | `/speckit.plan` | Active |
| `quickstart-template.md` | Feature integration guide | `/speckit.plan` | Active |
| `delta-template.md` | Incremental change tracking | *None* | Inactive |
| `agent-file-template.md` | Template for creating new agent files | Manual | Manual |
| `proposal-template.example.md` | Change proposal example | Reference Only | Example |

# # Manual Templates

## # agent-file-template.md

The `agent-file-template.md` file is a **manual template** for creating new agent files in `.github/agents/`.

**When to use**: When creating a new agent definition file.

**Usage**: Copy the template to `.github/agents/{AGENT_NAME}.agent.md` and customize the sections for your agent's specific purpose.

**Note**: This is not part of the automated SpecKit workflow - it's used for project infrastructure development.

# # Proposal Template Note

The `proposal-template.example.md` file is preserved as a **reference example** only. It is NOT required for standard SpecKit workflows. The file was renamed from `proposal-template.md` to clarify its optional status.

**When to use**: Only if you need a formal change proposal format outside the standard SpecKit agent workflow.

**Standard workflow**: Use `/speckit.specify` to create specifications directly - no proposal required.

# # Usage

Templates are automatically copied to `specs/changes/{CHANGE_ID}/` when creating new features:

```pwsh
# Creates spec.md from specs/templates/spec-template.md
pwsh specs/scripts/create-new-feature.ps1 -Json "Feature description"

# Creates plan.md from specs/templates/plan-template.md
/speckit.plan
```

# # Customization

Modify these templates to match your project's standards. The templates include:

- Placeholder markers in `{FIELD}` format for required fields
- `{NEEDS_CLARIFICATION_QUESTION}` markers for unresolved items
- HTML comments with concise completion instructions

# # Validation

Templates must follow constitution requirements:

- Every requirement MUST have at least one testable scenario
- Use MUST/SHALL for normative language
- Scenarios use WHEN/THEN format
- Maximum 3 `{NEEDS_CLARIFICATION}` markers per spec

See `specs/memory/constitution.md` for full governance rules.





