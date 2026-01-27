---
description: Initialize and create the feature specification from a natural language feature description. This is the primary initialization point for new features.
handoffs:
  - label: Build Technical Plan
    agent: speckit.plan
    prompt: Create a plan for the spec. I am building with...
  - label: Clarify Spec Requirements
    agent: speckit.clarify
    prompt: Clarify specification requirements
    send: true
---

# # User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

# # Outline

The text the user typed after `/speckit.specify` in the triggering message **is** the feature description. Assume you always have it available in this conversation even if `$ARGUMENTS` appears literally below. Do not ask the user to repeat it unless they provided an empty command.

Given that feature description, do this:

1. **Generate a concise short name** (2-4 words) for the branch:
   - Analyze the feature description and extract the most meaningful keywords
   - Create a 2-4 word short name that captures the essence of the feature
   - Use action-noun format when possible (e.g., "add-user-auth", "fix-payment-bug")
   - Preserve technical terms and acronyms (OAuth2, API, JWT, etc.)
   - Keep it concise but descriptive enough to understand the feature at a glance
   - Examples:
     - "I want to add user authentication" → "user-auth"
     - "Implement OAuth2 integration for the API" → "oauth2-api-integration"
     - "Create a dashboard for analytics" → "analytics-dashboard"
     - "Fix payment processing timeout bug" → "fix-payment-timeout"

2. **Create feature branch and folder structure**:

   Run `specs/scripts/create-new-feature.ps1 -Json -ShortName "{SHORT_NAME}" "$ARGUMENTS"`

   **Validation**: After running the script, check the exit code:
   ```pwsh
   if ($LASTEXITCODE -ne 0) {
      throw "create-new-feature.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
   }
   ```
   If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately. Report error with context: script name, exit code, and any error output. Do NOT proceed to next step until error is resolved.

   The script automatically:
   - Fetches latest branches and checks for conflicts
   - Finds highest existing number for this short-name across remote/local branches and specs/ folders
   - Assigns next available number (e.g., if `3-user-auth` exists, creates `4-user-auth`)
   - Creates branch `{CHANGE_ID}` (e.g., `5-user-auth`)
   - Creates folder structure in `specs/changes/{CHANGE_ID}/`
   - Returns JSON with BRANCH_NAME, SPEC_FILE, and FEATURE_DIR paths

   **IMPORTANT**:
   - Run this script **only once** per feature
   - Use the JSON output to get actual paths (don't assume paths)
   - For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot")

   **Example**:
   ```pwsh
   # For "Add user authentication" feature:
   specs/scripts/create-new-feature.ps1 -Json -ShortName "user-auth" "Add user authentication with OAuth2 support"
   # Creates: 5-user-auth (if 1-4 already exist)
   ```

3. **Load project context for tech stack validation**:
   - Read `specs/memory/constitution.md` for governance principles (spec-first, validation gates, quality standards)
   - Read `specs/project.md` for tech stack, architecture patterns, constraints, and external dependencies
   - **Validate feature against tech stack**:
     - Ensure proposed feature is achievable with current Frontend (React/Vue/Next.js, UI libraries like shadcn/ui)
     - Ensure proposed feature is achievable with current Backend (Node.js/Express/tRPC, Database, ORM)
     - Check Technical Constraints (performance, browser support, mobile support)
     - Check Important Constraints (budget, timeline, compliance, security requirements)
     - Flag if feature requires technologies not in project.md (user must decide: add to stack or modify feature)
   - **Apply domain context**:
     - Use Domain-Specific Terminology from project.md in requirements
     - Apply Business Rules from project.md as constraints in scenarios
     - Reference folder structure from project.md for file path clarity

4. **Check if modifying existing capability**:

   Before writing the spec, check if this change MODIFIES an existing capability:

   ```powershell
   # Check for existing capabilities (excluding system folders)
   Get-ChildItem specs -Directory | Where-Object { $_.Name -notmatch '^(changes|templates|scripts|memory)$' }
   ```

   **If `specs/{CAPABILITY}/spec.md` exists and this change affects it**:
   - Create delta directory structure:
     ```powershell
    $changeId = "{CHANGE_ID_FROM_STEP_2}"  # e.g., "5-user-auth"
    $capability = "{CAPABILITY}"       # e.g., "authentication"
     New-Item -ItemType Directory -Path "specs/changes/$changeId/specs/$capability" -Force
     ```
    - Create delta file at: `specs/changes/{CHANGE_ID}/specs/{CAPABILITY}/spec.md`
   - Use delta format with sections:
     - `## ADDED Requirements` - New requirements being introduced
     - `## MODIFIED Requirements` - Existing requirements being changed (include full updated requirement)
     - `## REMOVED Requirements` - Requirements being deprecated (include reason)
   - Reference the original capability spec in the delta header

   **If this is a NEW capability**:
   - Write to standard location: `specs/changes/{CHANGE_ID}/spec.md`
   - Use the standard spec template (not delta format)

5. Load `specs/templates/spec-template.md` to understand required sections.

6. Follow this execution flow:

    1. Parse user description from Input
       If empty: ERROR "No feature description provided"
    2. Extract key concepts from description
       Identify: actors, actions, data, constraints
    3. For unclear aspects:
       - Make informed guesses based on context and industry standards
       - Only mark with [NEEDS CLARIFICATION: specific question] if:
         - The choice significantly impacts feature scope or user experience
         - Multiple reasonable interpretations exist with different implications
         - No reasonable default exists
       - **LIMIT: Maximum 3 [NEEDS CLARIFICATION] markers total**
       - Prioritize clarifications by impact: scope > security/privacy > user experience > technical details
    4. Fill User Scenarios & Testing section
       If no clear user flow: ERROR "Cannot determine user scenarios"
    5. Generate Functional Requirements
       Each requirement must be testable
       Use reasonable defaults for unspecified details (document assumptions in Assumptions section)
    6. Define Success Criteria
       Create measurable, technology-agnostic outcomes
       Include both quantitative metrics (time, performance, volume) and qualitative measures (user satisfaction, task completion)
       Each criterion must be verifiable without implementation details
    7. Identify Key Entities (if data involved)
    8. Return: SUCCESS (spec ready for planning)

7. Write the specification to SPEC_FILE using the template structure, replacing placeholders with concrete details derived from the feature description (arguments) while preserving section order and headings.

8. **Specification Quality Validation**: After writing the initial spec, validate it against quality criteria:

   a. **Create Spec Quality Checklist**: Generate a checklist file at `FEATURE_DIR/checklists/requirements.md` using the checklist template structure with these validation items:

      ```markdown
      # Specification Quality Checklist: [FEATURE NAME]

      **Purpose**: Validate specification completeness and quality before proceeding to planning
      **Created**: [DATE]
      **Feature**: [Link to `specs/changes/{CHANGE_ID}/spec.md`]

      ## Content Quality

      - [ ] No implementation details (languages, frameworks, APIs)
      - [ ] Focused on user value and business needs
      - [ ] Written for non-technical stakeholders
      - [ ] All mandatory sections completed

      ## Requirement Completeness

      - [ ] No [NEEDS CLARIFICATION] markers remain
      - [ ] Requirements are testable and unambiguous
      - [ ] Success criteria are measurable
      - [ ] Success criteria are technology-agnostic (no implementation details)
      - [ ] All acceptance scenarios are defined
      - [ ] Edge cases are identified
      - [ ] Scope is clearly bounded
      - [ ] Dependencies and assumptions identified

      ## Feature Readiness

      - [ ] All functional requirements have clear acceptance criteria
      - [ ] User scenarios cover primary flows
      - [ ] Feature meets measurable outcomes defined in Success Criteria
      - [ ] No implementation details leak into specification

      ## Notes

      - Items marked incomplete require spec updates before `/speckit.clarify` or `/speckit.plan`
      ```

   b. **Run Validation Check**: Review the spec against each checklist item:
      - For each item, determine if it passes or fails
      - Document specific issues found (quote relevant spec sections)

   c. **Handle Validation Results**:

      - **If all items pass**: Mark checklist complete and proceed to step 6

      - **If items fail (excluding [NEEDS CLARIFICATION])**:
        1. List the failing items and specific issues
        2. Update the spec to address each issue
        3. Re-run validation until all items pass (max 3 iterations)
        4. If still failing after 3 iterations, document remaining issues in checklist notes and warn user

      - **If [NEEDS CLARIFICATION] markers remain**:
        1. Extract all [NEEDS CLARIFICATION: ...] markers from the spec
        2. **LIMIT CHECK**: If more than 3 markers exist, keep only the 3 most critical (by scope/security/UX impact) and make informed guesses for the rest
        3. For each clarification needed (max 3), present options to user in this format:

           ```markdown
           ## Question [N]: [Topic]

           **Context**: [Quote relevant spec section]

           **What we need to know**: [Specific question from NEEDS CLARIFICATION marker]

           **Suggested Answers**:

           | Option | Answer | Implications |
           |--------|--------|--------------|
           | A      | [First suggested answer] | [What this means for the feature] |
           | B      | [Second suggested answer] | [What this means for the feature] |
           | C      | [Third suggested answer] | [What this means for the feature] |
           | Custom | Provide your own answer | [Explain how to provide custom input] |

           **Your choice**: _[Wait for user response]_
           ```

        4. **CRITICAL - Table Formatting**: Ensure markdown tables are properly formatted:
           - Use consistent spacing with pipes aligned
           - Each cell should have spaces around content: `| Content |` not `|Content|`
           - Header separator must have at least 3 dashes: `|--------|`
           - Test that the table renders correctly in markdown preview
        5. Number questions sequentially (Q1, Q2, Q3 - max 3 total)
        6. Present all questions together before waiting for responses
        7. Wait for user to respond with their choices for all questions (e.g., "Q1: A, Q2: Custom - [details], Q3: B")
        8. Update the spec by replacing each [NEEDS CLARIFICATION] marker with the user's selected or provided answer
        9. Re-run validation after all clarifications are resolved

   d. **Update Checklist**: After each validation iteration, update the checklist file with current pass/fail status

9. **Validate Generated Artifact**

   Run validation script:
   ```powershell
   $RepoRoot = git rev-parse --show-toplevel
   $validationResult = & "$RepoRoot/specs/scripts/validate.ps1" -Json
   if ($LASTEXITCODE -ne 0) {
       Write-Host "❌ VALIDATION FAILED - Aborting workflow"
       Write-Host $validationResult
       exit 1
   }
   ```

   Parse JSON output:
   - If `status: "FAIL"` → STOP workflow, report errors
   - If `status: "WARNING"` → Log warnings, continue
   - If `status: "PASS"` → Proceed to completion

   Error types:
   - **FAIL**: Missing required sections, constitution violations, broken references
   - **WARNING**: Placeholder markers, style inconsistencies

   **Placeholder Sweep**: After validation passes, run placeholder detection:
   ```powershell
   $featureId = $env:SPECIFY_CHANGE_ID
   if (-not $featureId) {
       $featureId = (git rev-parse --abbrev-ref HEAD) -replace '^feature/', ''
   }
   $placeholders = Select-String -Path "specs/changes/$featureId/*" -Pattern "TBD|TODO|FIXME|\[insert\]|\[placeholder\]|{PLACEHOLDER}" -Exclude "*.log" -ErrorAction SilentlyContinue
   if ($placeholders) {
       Write-Host "❌ PLACEHOLDERS FOUND in generated artifacts:"
       $placeholders | ForEach-Object { Write-Host "  $($_.Path):$($_.LineNumber) - $($_.Line.Trim())" }
       exit 1
   }
   ```

   If placeholders are detected, STOP workflow and report each occurrence with file path and line number.

10. **Update System Context**: Execute `specs/scripts/update-agent-context.ps1 -AgentType copilot` to synchronize the new feature's technology requirements with the AI assistant instructions.

   ```pwsh
   pwsh -File specs/scripts/update-agent-context.ps1 -AgentType copilot
   if ($LASTEXITCODE -ne 0) {
      throw "update-agent-context.ps1 failed with exit code $LASTEXITCODE"
   }
   ```

   If the command fails, stop immediately and surface the error output; do not proceed to handoff.

10. Report completion with branch name, spec file path, checklist results, and readiness for the next phase (`/speckit.clarify` or `/speckit.plan`).

**NOTE:** The script creates and checks out the new branch and initializes the spec file before writing.

# # General Guidelines

# # Quick Guidelines

- Focus on **WHAT** users need and **WHY**.
- Avoid HOW to implement (no tech stack, APIs, code structure).
- Written for business stakeholders, not developers.
- DO NOT create any checklists that are embedded in the spec. That will be a separate command.

## # Section Requirements

- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

## # For AI Generation

When creating this spec from a user prompt:

1. **Make informed guesses**: Use context, industry standards, and common patterns to fill gaps
2. **Document assumptions**: Record reasonable defaults in the Assumptions section
3. **Limit clarifications**: Maximum 3 [NEEDS CLARIFICATION] markers - use only for critical decisions that:
   - Significantly impact feature scope or user experience
   - Have multiple reasonable interpretations with different implications
   - Lack any reasonable default
4. **Prioritize clarifications**: scope > security/privacy > user experience > technical details
5. **Think like a tester**: Every vague requirement should fail the "testable and unambiguous" checklist item
6. **Common areas needing clarification** (only if no reasonable default exists):
   - Feature scope and boundaries (include/exclude specific use cases)
   - User types and permissions (if multiple conflicting interpretations possible)
   - Security/compliance requirements (when legally/financially significant)

**Examples of reasonable defaults** (don't ask about these):

- Data retention: Industry-standard practices for the domain
- Performance targets: Standard web/mobile app expectations unless specified
- Error handling: User-friendly messages with appropriate fallbacks
- Authentication method: Standard session-based or OAuth2 for web apps
- Integration patterns: RESTful APIs unless specified otherwise

## # Success Criteria Guidelines

Success criteria must be:

1. **Measurable**: Include specific metrics (time, percentage, count, rate)
2. **Technology-agnostic**: No mention of frameworks, languages, databases, or tools
3. **User-focused**: Describe outcomes from user/business perspective, not system internals
4. **Verifiable**: Can be tested/validated without knowing implementation details

**Good examples**:

- "Users can complete checkout in under 3 minutes"
- "System supports 10,000 concurrent users"
- "95% of searches return results in under 1 second"
- "Task completion rate improves by 40%"

**Bad examples** (implementation-focused):

- "API response time is under 200ms" (too technical, use "Users see results instantly")
- "Database can handle 1000 TPS" (implementation detail, use user-facing metric)
- "React components render efficiently" (framework-specific)
- "Redis cache hit rate above 80%" (technology-specific)

---

# # Delta Spec Template

When modifying an existing capability, use this format for `specs/changes/{CHANGE_ID}/specs/{CAPABILITY}/spec.md`:

```markdown
# Delta: {CAPABILITY}

**Change ID**: {CHANGE_ID}
**Modifies**: `specs/{CAPABILITY}/spec.md`
**Date**: {DATE}

# # Summary

{CHANGE_SUMMARY}

---

# # ADDED Requirements

## # Requirement: {REQUIREMENT_NAME}

**Description**: {REQUIREMENT_TEXT}

**Acceptance Criteria**:
- {CRITERION_1}
- {CRITERION_2}

---

# # MODIFIED Requirements

## # Requirement: {REQUIREMENT_NAME}

**Original**: (reference to original requirement in `specs/{CAPABILITY}/spec.md`)

**Updated Requirement**:
{FULL_UPDATED_REQUIREMENT_TEXT}

**Acceptance Criteria**:
- {UPDATED_CRITERION_1}
- {UPDATED_CRITERION_2}

**Reason for Change**: {MODIFICATION_REASON}

---

# # REMOVED Requirements

## # Requirement: {REQUIREMENT_NAME}

**Original**: (reference to original requirement in `specs/{CAPABILITY}/spec.md`)

**Reason for Removal**: {REMOVAL_REASON}

**Migration Notes**: {MIGRATION_NOTES}
```


