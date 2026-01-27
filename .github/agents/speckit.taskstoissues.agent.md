---
description: Convert existing tasks into actionable, dependency-ordered GitHub issues for the feature based on available design artifacts.
tools: ['github/github-mcp-server/issue_write']
---

# User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

# Outline

1. Run `specs/scripts/check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks` from repo root.

   **Validation**: After running the script, check the exit code:
   ```pwsh
   if ($LASTEXITCODE -ne 0) {
      throw "check-prerequisites.ps1 failed with exit code $LASTEXITCODE. Review output above for details."
   }
   ```
   If `$LASTEXITCODE -ne 0`, **STOP** workflow immediately. Report error with context: script name, exit code, and any error output. Do NOT proceed to next step until error is resolved.

   Parse FEATURE_DIR, CHANGE_ID, and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

1.5. **Load project context for tech-aware issue generation**:
   - Read `specs/project.md` for tech stack, folder structure, and domain terminology
   - **Apply project context to GitHub issues**:
     - Use correct folder paths from Domain Context section (e.g., `src/components/ui/` not generic paths)
     - Apply Tech Stack naming in issue titles/descriptions (e.g., "shadcn/ui Button", "Prisma schema", "tRPC endpoint")
     - Reference Architecture Patterns in issue acceptance criteria
     - Include Domain-Specific Terminology from project.md for clarity
   - **CRITICAL**: Issues should be immediately understandable by developers familiar with project tech stack

2. From the executed script, extract the path to **tasks**.
3. Get the Git remote by running:

```pwsh
git config --get remote.origin.url
```

> [!CAUTION]
> ONLY PROCEED TO NEXT STEPS IF THE REMOTE IS A GITHUB URL

1. For each task in the list, use the GitHub MCP server to create a new issue in the repository that is representative of the Git remote.

> [!CAUTION]
> UNDER NO CIRCUMSTANCES EVER CREATE ISSUES IN REPOSITORIES THAT DO NOT MATCH THE REMOTE URL



