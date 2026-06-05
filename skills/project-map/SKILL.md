---
name: project-map
description: Generate an ASCII tree diagram showing the project's feature hierarchy.
disable-model-invocation: true
---

# Project Map Command

Generate an ASCII tree diagram showing the project's feature hierarchy.

## Instructions

1. Analyze the project structure to identify:
   - Main modules/feature areas
   - Features within each module
   - Sub-features (up to 3 levels deep from module root)
   - Focus on user-facing features, not implementation details
   - Include comprehensive lists (types, formats, integrations, etc.)

2. Generate an ASCII tree diagram:
   - Create ONE tree PER module (not one combined tree)
   - Each module name is the root of its own tree
   - Level 2: Features per module
   - Level 3: Sub-features
   - Use `├──`, `└──`, and `│` for tree branches

3. Write the diagram to `docs/MAP.md` (CRITICAL: ONLY UPDATE AND DONT CHANGE CONTENT SORTING if it already exists)

4. Ensure the file opens with a header block (before the first module section):
   - An **overview** paragraph: what this file is (a feature map of the project — one ASCII tree per module).
   - A **goal** paragraph: why it exists (fast navigable overview of *what the product does* for onboarding, scoping, and locating modules; describes behavior not implementation).
   - A **"Keeping this file up to date"** `##` section with the maintenance rules: update the affected module tree in place (no duplicate sections), append new module sections at the end, preserve existing section order, describe features not implementation (no code/paths/class names/API routes/event names), list all members of any set (no "etc."), keep depth to 3 levels, and document only implemented features.
   - If the file already exists, add or refresh this header block without disturbing existing module sections or their order.

## Guidelines

- Use short, descriptive labels
- Focus on user-facing features, not implementation details
- NEVER include code, file paths, class/method names, API routes, or event identifiers — use plain feature language
- Document only features that are actually implemented (verify against the codebase, not just other docs)
- Include ALL items in lists (types, formats, integrations, etc.)
- DO NOT limit the number of features or sub-features shown

### CRITICAL: Complete Lists

When a feature contains a list of items (types, providers, formats, integrations, etc.), you MUST include ALL items - never summarize or truncate.

Examples:

- Export Formats → list ALL: PDF, DOCX, HTML, CSV, JSON
- Auth Providers → list ALL: Google, GitHub, Microsoft, SAML, LDAP
- Payment Gateways → list ALL: Stripe, PayPal, Square
- File Types → list ALL: .jpg, .png, .gif, .webp, .svg

Do NOT use "etc.", "and more", or ellipsis (...). Every single item must be listed.

### Anti-Patterns

- Avoid deep nesting beyond 3 levels from module root
- Do not include non-feature nodes (e.g., "Backend", "Database")
- Avoid overly generic labels (e.g., "Miscellaneous")
- Do not include user roles or personas
- Avoid redundancy; each feature should be unique
- Avoid vague labels; be specific
- Do not create cycles; maintain a tree structure
- Do not include non-feature aspects (e.g., performance, security)
- Do NOT create a single combined tree for all modules
- Do NOT nest modules under a project root

## Output Format

```markdown
# <Project-Name> Map

<One-paragraph overview: this file is a feature map of the project — one ASCII tree per module, features nested up to three levels deep.>

<One-paragraph goal: fast navigable overview of what the product does, for onboarding/scoping/locating modules; describes behavior, not implementation — no code or file paths.>

## Keeping this file up to date

<Maintenance rules: update affected tree in place, append new modules at end, preserve order, features-not-implementation, full lists, 3-level depth, implemented-only.>

## <Module-Name>

<Module-Name>
├── Feature
│   ├── Sub-feature
│   └── Sub-feature
└── Feature
    └── Sub-feature
```
