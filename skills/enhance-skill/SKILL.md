---
name: enhance-skill
description: Enhance a skill by searching skills.sh for related community skills and merging useful content.
argument-hint: <skill-name> [search terms]
---

# Enhance Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding.

## Purpose

Enhance an existing skill by discovering related community skills from multiple directories, extracting useful guidelines and patterns, and merging them into the target skill.

## Steps

- [ ] Identify the target skill and read its SKILL.md
- [ ] Search for related skills
- [ ] Fetch and analyze the most relevant skills
- [ ] Identify gaps and enhancements
- [ ] Apply enhancements to the target skill
- [ ] Summarize changes

## 1. Identify Target Skill

- Parse `<skill-name>` from user input
- Read the skill file at `.claude/skills/<skill-name>/SKILL.md`
- If the skill doesn't exist, inform the user and stop

## 2. Search Skill Directories

Use the fetch-skills script to search both skills.sh and agentskills.guide in a single call:

```bash
node ./scripts/fetch-skills.js search "<search terms>"
```

This returns a JSON array of results from both sources with `name`, `description`, `source`, and `fetchId`.

### Search Strategy

- If the user provided search terms, use those
- Otherwise, derive 2-3 search queries from the skill's name and description
- Run multiple searches with different keyword combinations to maximize coverage
- Example: for `ux-design`, run 3 searches: `ux design`, `user experience`, `design system accessibility`

## 3. Fetch and Analyze

From search results, identify the most relevant skills by reading their `name` and `description` fields.

- IMPORTANT: Select at least 10 unique skills to fetch, with at least 5 from each source
- Skip skills that are API wrappers or tool-specific integrations (not transferable guidelines)
- Focus on skills that contain design principles, guidelines, checklists, or patterns

### Fetching skill content

Use the fetch command with the `fetchId` from search results:

```bash
node ./scripts/fetch-skills.js fetch "<fetchId>"
```

This returns `{ content }` with the raw SKILL.md markdown.

- Use parallel fetches via Bash to maximize throughput (but limit to 3-4 concurrent to avoid errors)
- skills.sh IDs (e.g. `owner/repo/skillId`) resolve via GitHub Trees API → raw SKILL.md
- agentskills IDs (e.g. `agentskills:slug`) resolve via landing page → GitHub raw

## 4. Identify Gaps

Compare fetched skill content against the existing skill:

- List what the existing skill already covers well
- List genuinely new content from community skills (not duplicates or rewordings)
- Prioritize additions that are concrete and actionable (tables, checklists, specific values)
- Skip vague or generic advice already implied by existing content

## 5. Apply Enhancements

Edit the existing SKILL.md to add new content:

- **Preserve** the existing structure and all original content
- **Insert** new sections in logical positions within the existing hierarchy
- **Enhance** existing sections with missing specifics (e.g., add concrete values to vague rules)
- **Do not** duplicate content that already exists in the skill
- **Do not** restructure or rewrite existing content
- Match the existing formatting style (table format, heading levels, list style)

## 6. Summarize

Present a summary table of all changes made:

| Section | What was added | Source     |
| ------- | -------------- | ---------- |
| ...     | ...            | skill name |

## Guidelines

- Prefer concrete, actionable content (specific px values, ratios, hex codes) over generic advice
- Community skills may contain tool-specific instructions (MCP servers, APIs) — skip those
- If search results yield no relevant skills, inform the user instead of forcing changes
- Do not remove or modify any existing content in the skill
