---
name: competition-research
description: Generate a comprehensive competitive analysis report for a specified competitor
argument-hint: <name> <url> <local-path>
disable-model-invocation: true
---

# Competition Research

## Instructions

1. Analyze the competition platform to identify:
   - Identify the competitor and verify company information
   - Research company background (founding, location, size, funding)
   - Analyze product/service portfolio
   - Document pricing and packaging
   - Examine go-to-market strategy (sales model, channels, partnerships)
   - Research key executives and leadership team
   - Identify competitive positioning and messaging
   - Track recent news, announcements, and changes

2. Generate an Overview file:
   Create `docs/competitions/<name>/OVERVIEW.md` (UPPERCASE NAME, update if it already exists), STRICTLY following the format below

3. Generate an ASCII tree diagram:
   Write the diagram to `docs/competitions/<name>/MAP.md` (UPPERCASE NAME, update if it already exists), STRICTLY following the format below

   **Tree Includes:**
   - Main modules/feature areas
   - Features within each module
   - Sub-features (up to 3 levels deep from module root)
   - Include comprehensive lists (types, formats, integrations, etc.)

   **Guidelines for the Tree Diagram:**
   - Focus on user-facing features, not implementation details
   - Create ONE tree PER module (not one combined tree)
   - Each module name is the root of its own tree
   - Level 2: Features per module
   - Level 3: Sub-features
   - Use `├──`, `└──`, and `│` for tree branches

## Information Gathering Methods

**Method 1: Public Sources**

- **Sources:** Company websites, blogs, press releases, social media
- **Tools:** WebSearch, WebFetch
- **Approach:** Systematic monitoring of official channels
- **Frequency:** Weekly or as needed

**Method 2: Customer Feedback**

- **Sources:** Review sites (G2, Capterra, TrustRadius), forums, Reddit
- **Tools:** WebSearch for review aggregation
- **Approach:** Extract strengths/weaknesses from user reviews
- **Focus:** Look for recurring themes in feedback

**Method 3: Product Analysis**

- **Sources:** Product trials, documentation, demo videos
- **Tools:** Hands-on testing when possible
- **Approach:** Feature-by-feature comparison
- **Documentation:** Screenshots, notes, feature inventory

**Method 4: Market Intelligence**

- **Sources:** Industry analysts, reports, news coverage
- **Tools:** WebSearch for analyst mentions
- **Approach:** Third-party validation of positioning
- **Value:** Unbiased perspective on market position

**Method 5: Job Postings Analysis**

- **Sources:** Competitor career pages, LinkedIn jobs
- **Approach:** Infer strategy from roles they're hiring
- **Insights:** New market segments, product directions, tech stack
- **Example:** Hiring enterprise sales in new region = expansion signal

### Information Sources Checklist

- [ ] Company website and product pages
- [ ] Pricing page (screenshot for historical tracking)
- [ ] Blog and announcement feeds
- [ ] Social media (LinkedIn, Twitter)
- [ ] Review sites (G2, Capterra, TrustRadius)
- [ ] Customer case studies and testimonials
- [ ] Press releases and news coverage
- [ ] Product documentation (if public)
- [ ] Demo videos or trial accounts
- [ ] Job postings
- [ ] Analyst reports (Gartner, Forrester)
- [ ] SEC filings (if public company)
- [ ] Patent filings
- [ ] Conference presentations

## Guidelines

- Use short, descriptive labels
- Focus on user-facing features, not implementation details
- Focus on main features only, not minor details or edge cases
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

## MAP Output Format

```markdown
# <Project-Name> Map

## <Module-Name>

<Module-Name>
├── Feature
│   ├── Sub-feature
│   └── Sub-feature
└── Feature
    └── Sub-feature
```

## OVERVIEW Output Format

```markdown
## Company Overview

- Founded: [Year]
- Headquarters: [Location]
- Size: [Employees, Revenue if public]
- Funding: [Total raised, Latest round]
- Status: [Private/Public, Growth stage]

## Products 1

[Description, Target market]

### Pricing Strategy

- Model: [Subscription, Usage-based, etc.]
- Tiers: [Pricing tiers and features]
- Positioning: [Value, Premium, or Budget]

## Go-to-Market

- Sales model: [Self-serve, Sales-led, Hybrid]
- Target customer: [SMB, Mid-market, Enterprise]
- Channels: [Direct, Partners, Resellers]
- Key partnerships: [List]

## Positioning & Messaging

- Core value prop: [Main claim]
- Key differentiators: [What they emphasize]
- Target use cases: [Primary scenarios]

## Recent Activity (Last 6 months)

- [Date]: [Event/announcement]
- [Date]: [Event/announcement]

## Strengths

- [Strength 1]
- [Strength 2]
```
