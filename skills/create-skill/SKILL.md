---
name: create-skill
description: Create, test, evaluate, and iteratively improve agent skills (SKILL.md). Use when users say "create a skill", "make a skill for", "write a SKILL.md", "turn this into a skill", "run evals", "test my skill", "benchmark my skill", "blind comparison", "A/B test my skill". Also triggers on editing an existing skill or reviewing skill quality.
---

# Create Skill

Figure out where the user is in this process and help them progress. If they say "I want to make a skill for X", help narrow down what they mean, write a draft, write the test cases, decide how to evaluate, run the prompts, and repeat. If they already have a draft, go straight to the eval/iterate loop. If they say "just vibe with me, no evals", skip the evaluation machinery.

## Checklist

- [ ] Figure out what the skill is about
- [ ] Run `enhance-skill` to merge in useful community content (skip for domain-specific/internal skills)

## Always prefer scripts for structured/static/batch work

When a task involves **structured or static data, a batch of operations, or schematic/repetitive operations**, ALWAYS reach for a script instead of hand-doing the work or having the model reconstruct boilerplate each run. This is faster, deterministic, and reusable.

Choose the scripting language in this priority order, picking the first one available/appropriate for the environment:

1. **bash**
2. **powershell**
3. **nodejs**
4. **python**

The reason for the order: bash and powershell cover the common shell/file/glue work on their respective platforms with zero extra runtime; nodejs and python are the fallbacks when the logic outgrows a shell script (real data structures, JSON manipulation, schema validation). Within a skill you're authoring, bundle these scripts under `scripts/` and reference them from SKILL.md so every future invocation composes the script rather than re-deriving it.

This applies to your own work while building/evaluating the skill (graders, aggregators, validators, batch test runs) **and** to the scripts you decide to bundle into the skill you're creating.

---

## Creating a skill

### Capture Intent

Start by understanding the user's intent. The current conversation might already contain a workflow the user wants to capture (e.g., they say "turn this into a skill"). If so, extract answers from the conversation history first — the tools used, the sequence of steps, corrections the user made, input/output formats observed. The user may need to fill the gaps, and should confirm before proceeding to the next step.

1. What should this skill enable the agent to do?
2. When should this skill trigger? (what user phrases/contexts)
3. What's the expected output format?
4. **Which use case category does this fall into?**
   - **Document & Asset Creation** — consistent, high-quality output (docs, presentations, code, designs)
   - **Workflow Automation** — multi-step processes benefiting from consistent methodology
   - **MCP Enhancement** — workflow guidance layered on top of MCP tool access
5. Should we set up test cases to verify the skill works? Skills with objectively verifiable outputs (file transforms, data extraction, code generation, fixed workflow steps) benefit from test cases. Skills with subjective outputs (writing style, art) often don't need them. Suggest the appropriate default based on the skill type, but let the user decide.

### Define Success Criteria

Before writing anything, articulate what "working" looks like with the user. Treat these as aspirational targets, not precise thresholds.

- **Quantitative**: Does the skill trigger on ~90% of relevant queries? Does it complete the workflow in fewer tool calls than without? Are there zero failed API calls?
- **Qualitative**: Can a user get through the workflow without needing to redirect the agent? Are results consistent across sessions? Does a new user succeed on their first try?

### Interview and Research

Proactively ask questions about edge cases, input/output formats, example files, success criteria, and dependencies. Wait to write test prompts until you've got this part ironed out.

Check available MCPs — if useful for research (searching docs, finding similar skills, looking up best practices), research in parallel via subagents if available, otherwise inline. Arrive with context already gathered.

### Write the SKILL.md

Based on the user interview, fill in these components:

**Required fields:**

- **name**: Skill identifier (kebab-case only, no spaces or capitals, must match the folder name)
- **description**: The single most important field. It's how the agent decides whether to load the skill. Write it as a **trigger, not a summary**: `[What it does] + [When to use it] + [Key capabilities]`. Keep it under ~1024 characters, no XML tags. Make it assertive — models tend to undertrigger. This is the only discovery text the agent sees before loading, so it must stand alone.
- **the rest of the skill**

### Skill Writing Guide

#### Anatomy of a Skill

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown instructions
└── Bundled Resources (optional)
    ├── scripts/    - Executable code for deterministic/repetitive tasks
    ├── references/ - Docs loaded into context as needed
    └── assets/     - Files used in output (templates, icons, fonts)
```

#### Progressive Disclosure

Skills use a three-level loading system:

1. **Metadata** (name + description) - Always in context (~100 words)
2. **SKILL.md body** - In context whenever skill triggers (<500 lines ideal)
3. **Bundled resources** - As needed (unlimited, scripts can execute without loading)

These word counts are approximate; go longer when needed.

**Key patterns:**

- Keep SKILL.md under 500 lines; if you're approaching this limit, add an additional layer of hierarchy along with clear pointers about where the model using the skill should go next to follow up.
- Reference files clearly from SKILL.md with guidance on when to read them
- For large reference files (>300 lines), include a table of contents

**Domain organization**: When a skill supports multiple domains/frameworks, organize by variant:

```
cloud-deploy/
├── SKILL.md (workflow + selection)
└── references/
    ├── aws.md
    ├── gcp.md
    └── azure.md
```

The agent reads only the relevant reference file.

#### Technical Rules & Structural Patterns

Hard technical rules: SKILL.md exact naming/casing, kebab-case folder naming, no XML tags in frontmatter, no reserved vendor names (e.g. a host's own brand) in the skill name. Common structural patterns: Sequential Workflow, Multi-MCP, Iterative Refinement, Context-Aware, Domain-Specific.

Skills must not contain malware, exploit code, or anything that would surprise the user if described. Don't create misleading skills or skills designed to facilitate unauthorized access.

#### Writing Patterns

Prefer using the imperative form in instructions. Be specific and actionable — instead of "Validate the data before proceeding", write specific steps with actual commands and common failure modes. Include error handling for common failures. Reference bundled resources clearly. Bundle scripts for critical validations — code is deterministic, language interpretation isn't (see "Always prefer scripts" above for the language priority order).

**Defining output formats:**

```markdown
## Report structure

ALWAYS use this exact template:

# [Title]

## Executive summary

## Key findings

## Recommendations
```

**Examples pattern** — include examples; format them like this (deviate from the literal "Input"/"Output" labels where they don't fit):

```markdown
## Commit message format

**Example 1:**
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

### Writing Style

Focus on **WHAT** to do. Add a short, concise **why** only when the reason is non-obvious — a capable agent already knows a lot, so explaining obvious rationale is noise. Prefer this over heavy-handed MUSTs. Make skills general, not narrow to specific examples. Draft, then re-review before finalizing.

Key principles: don't state the obvious, build a Gotchas section (highest-signal content), avoid railroading the agent (preserve flexibility), and store scripts so the agent composes rather than reconstructs boilerplate.

### Script vs. Instruct

When designing a skill's architecture, decide what goes into bundled `scripts/` vs. what stays as SKILL.md instructions. Use this as a first-pass heuristic at draft time:

**Script when the work is:**

- Deterministic and repeatable (data transforms, format conversion, file I/O)
- Validatable by a fixed rule or exit code (schema checks, regex, required fields)
- API calls with specific auth/endpoint details
- The kind of boilerplate the agent would otherwise re-derive every run
- Touching structured/static data, a batch of items, or schematic operations (per "Always prefer scripts" above)

**Instruct when the work needs:**

- Judgment (tone, what to include/exclude, how to frame results)
- Context-dependent decisions (which approach fits this user's situation)
- Flexible error recovery (interpreting unexpected results, deciding next steps)
- Workflow orchestration where the sequence may vary

This is a starting point, not the final answer. The strongest signal for what to script comes later, from observing convergence across eval runs — if 2-3 independent runs all reinvent the same helper, that's empirical evidence the logic belongs in a script. Don't over-script upfront; let the convergence signal guide you.

**When you do bundle a script, design it for agent consumption** — non-interactive, `--help`-documented, structured output (JSON/CSV), helpful errors, meaningful exit codes, idempotent by default. A script that works fine for a human can be unusable for an agent.

**Always validate bundled scripts work as expected before finalizing.** Run each script against representative inputs and confirm the output, exit code, and error handling match what SKILL.md claims. Don't ship a script you haven't executed — a broken or mis-documented script is worse than no script.

## Validate Against the Checklist

Before packaging, run through this checklist to catch common issues:

- [ ] Folder named in kebab-case
- [ ] SKILL.md file exists (exact spelling, case-sensitive)
- [ ] YAML frontmatter has `---` delimiters
- [ ] name field: kebab-case, no spaces, no capitals, matches folder name
- [ ] description includes WHAT the skill does and WHEN to use it
- [ ] No XML tags (< >) anywhere in frontmatter
- [ ] No reserved vendor/host brand name in the skill name
- [ ] Instructions are clear and actionable (not vague)
- [ ] Error handling included for likely failure modes
- [ ] Examples provided where helpful
- [ ] References clearly linked from SKILL.md
- [ ] SKILL.md stays under ~500 lines (detailed content in references/)
- [ ] No README.md inside the skill folder

A short validation script (bash → powershell → nodejs → python) that checks the mechanical items above is worth bundling so it can be re-run every iteration.

---

## Enhance with community skills

As the **last step**, once the skill is validated and you and the user are satisfied, invoke the `enhance-skill` skill on it. It searches skills.sh for related community skills and merges in useful content you may have missed.

**Skip this** for domain-specific skills built around internal/proprietary instructions where no community skill could plausibly help (e.g. company-specific workflows, internal APIs, private conventions).

---

## Updating an existing skill

The user might be asking you to update an existing skill, not create a new one. In this case:

- **Preserve the original name.** Note the skill's directory name and `name` frontmatter field — use them unchanged.
- **Copy to a writeable location before editing** if the installed skill path may be read-only. Edit the copy, then put it back.
