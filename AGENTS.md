# Global Guidelines

## Bash tool

- NEVER use `find`/`glob`/`grep` commands, always use `Grep` or `Glob` dedicated tools in those case
- Always use absolute paths (e.g. `cd c:/repos && ...`). Shell state does not persist between Bash calls, so relative `cd` paths will fail

## General Instructions

- CRITICAL: If you are experiencing disk space issues - STOP AND NEVER clear or delete ANY file
- Verify with citations: every claim needs a source. If it can't find one, it should retract the claim
- Use direct quotes (word-for-word) for factual grounding
- Explanations only if non-obvious
- Be concise, clear, and direct in language
- Prefer Tech-English over natural language for technical topics
- ALWAYS choose the most recommended path for issues, DO NOT provide multiple options or paths unless explicitly asked for
