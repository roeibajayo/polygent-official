# The Execution Test - Detailed Decision Framework

This document provides detailed guidance on applying the Execution Test to determine what content to keep or remove during documentation optimization.

## Core Decision Framework

Before removing ANY content, apply these questions in order:

### Question 1: Can Claude execute the instruction CORRECTLY without this content?

**If NO** → KEEP (execution-critical)
**If YES** → Proceed to question 2

This is the most important question. If removing content would cause incorrect execution, the content is execution-critical and must be kept.

**Examples of execution-critical content:**

- Success criteria that define what "correct" looks like
- Specific file paths, line numbers, or command outputs
- Exact patterns showing correct vs incorrect approaches
- Commands with specific flags or options that affect behavior

### Question 2: Does this content explain WHY (rationale/educational)?

**If YES** → REMOVE (not needed for execution)
**If NO** → KEEP (operational detail)

Rationale and educational content helps humans understand but doesn't affect execution. Claude doesn't need to know why something works, only what to do.

**Examples to REMOVE:**

```markdown
**RATIONALE**: Git history rewriting can silently drop commits or changes,
especially during interactive rebases where "pick" lines might be accidentally
deleted or conflicts might be resolved incorrectly. Manual verification is the
only reliable way to ensure no data loss occurred.
```

→ Claude doesn't need to know why; just needs to know to verify.

### Question 3: Does this content show WHAT "correct" looks like (success criteria)?

**If YES** → KEEP (execution-critical)
**If NO** → Proceed to question 4

Success criteria are execution-critical because they define the target state. Without them, Claude cannot verify correctness.

**Examples to KEEP:**

```markdown
**ARCHIVAL SUCCESS CRITERIA**:

- `git diff todo.md` shows ONLY deletions
- `git diff changelog.md` shows ONLY additions under today's date
- Both files in SAME commit
- `grep task-name todo.md` returns no matches
```

→ Specifies exactly what success looks like; needed for correct execution.

### Question 4: Does this content extract a general decision rule from a specific example?

**If YES** → KEEP (pattern extraction for future cases)
**If NO** → May remove if redundant

Pattern extraction annotations teach how to apply reasoning to new cases not covered in the document. These are valuable for generalizing from specific examples.

**Examples to KEEP:**

```markdown
[Specific example code block]
→ Shows that "delete" means remove lines, not change checkbox.
```

The arrow extracts the general principle (what "delete" means) from the specific example.

**Examples to REMOVE:**

```markdown
[Example code block]
→ This is a good practice to follow.
```

Generic praise without extracting a reusable decision rule.

## Execution-Critical Content Categories

### 1. Concrete Examples Defining "Correct"

Examples showing EXACT correct vs incorrect patterns when instruction uses abstract terms.

**KEEP when instruction says "delete" but example shows this means "remove entire entry, not mark complete":**

```bash
# ❌ WRONG: Marking complete in todo.md
vim todo.md  # Changed - [ ] to - [x]
git commit -m "..." todo.md  # Result: Still in todo.md

# ✅ CORRECT: Delete from todo.md, add to changelog.md
vim todo.md  # DELETE entire task entry
vim changelog.md  # ADD under ## 2025-10-08
```

**REMOVE if instruction already says "remove entire entry" explicitly** - example becomes redundant.

### 2. Sequential Steps for State Machines

Numbered workflows where order matters for correctness. State transition sequences where skipping/reordering causes failures.

**KEEP numbered sequence** when order is mandatory:

```markdown
1. Complete SYNTHESIS phase
2. Present plan to user
3. Update lock: `jq '.state = "SYNTHESIS_AWAITING_APPROVAL"'`
4. STOP - wait for user
5. On approval: Update lock to `CONTEXT` and proceed
```

**REMOVE numbering** if steps are independent checks that can run in any order.

### 3. Inline Comments That Specify WHAT to Verify

Comments explaining what output to expect or check. Annotations specifying exact conditions for success/failure.

**KEEP comments specifying criteria:**

```bash
# Before rewriting: git rev-list --count HEAD
# After rewriting: git rev-list --count HEAD
# Compare counts - should match unless you explicitly intended to drop commits
```

**REMOVE comments explaining WHY** (e.g., "This prevents data loss because..." is educational, not operational).

### 4. Disambiguation Examples

Multiple examples showing boundary between prohibited/permitted when rule uses subjective terms.

**KEEP examples that clarify ambiguous instructions**.
**REMOVE examples that just restate clear instructions**.

### 5. Pattern Extraction Rules

Annotations that generalize specific examples into reusable decision principles. Text that teaches how to apply the same reasoning to future cases.

**Critical Distinction:**

- ✅ **KEEP**: "→ Specifies exactly what success looks like" (teaches pattern recognition)
- ❌ **REMOVE**: "This example helps you understand the concept" (generic educational)
- ✅ **KEEP**: "→ Claude doesn't need to know why" (generalizes when to remove content)
- ❌ **REMOVE**: "This is important because it prevents errors" (explains WHY, not WHAT)

**Test**: If removed, would Claude lose the ability to apply this reasoning to NEW examples not in the document? If YES → KEEP (it's pattern extraction, not commentary).

## Reference-Based Consolidation

### Semantic Equivalence Test

Before replacing content with reference, verify:

1. **Same information**: Referenced section contains EXACT same information
   - ❌ WRONG: Replace "Goals: A, B, C" with reference to "Priority: C > B > A"
   - ✅ RIGHT: Replace duplicate "Goals: A, B, C" with reference to other "Goals: A, B, C"

2. **Same context**: Referenced section serves same purpose
   - ❌ WRONG: Replace "do X" with reference to "when to do X"
   - ✅ RIGHT: Replace "do X" with reference to "do X"

3. **Same level of detail**: No precision lost in referenced content
   - ❌ WRONG: Replace 7-item checklist with reference to 3-item summary
   - ✅ RIGHT: Replace 7-item checklist with reference to same 7-item checklist

### Duplication Taxonomy

**Type 1: Quick-Reference + Detailed** (KEEP BOTH)

- Simple list (3-5 words per item) for fast scanning
- Detailed section with tests, examples, edge cases
- **Purpose**: Different use cases - quick lookup vs deep understanding

**Type 2: Exact Duplication** (CONSOLIDATE)

- Same information, same level of detail, same context
- Appearing in multiple places with no contextual justification
- **Purpose**: Genuine redundancy - consolidate to single source

**Type 3: Pedagogical Repetition** (CONTEXT-DEPENDENT)

- Key rules stated multiple times for emphasis
- Summary + detailed explanation
- **Purpose**: Learning/retention - keep if document is pedagogical, remove if reference doc

### Pre-Consolidation Verification

Before removing ANY content for consolidation:

1. ✅ Content is byte-for-byte duplicate OR semantically equivalent
2. ✅ Replacement reference doesn't interrupt sequential workflow
3. ✅ Referenced section is same level of detail
4. ✅ Consolidation doesn't remove quick-reference value
5. ✅ Verify by test: Can user execute task with reference-based version as easily as inline version?

**If ANY check fails → Keep duplicate inline**

## Priority Hierarchy

When deciding optimizations, use this priority order:

1. **CORRECTNESS** (highest priority)
   - Can Claude execute the instruction correctly without this?
   - Does this resolve ambiguity that would cause wrong execution?

2. **EFFICIENCY** (medium priority)
   - Does removing this make instructions faster to scan?
   - Does condensing reduce cognitive load?

3. **CONCISENESS** (lowest priority)
   - Does this reduce line count?
   - Does this tighten prose?

**Rule**: Never sacrifice correctness for conciseness. Always sacrifice conciseness for correctness.

## Examples Applying the Test

### Example 1: Rationale Content (REMOVE)

```markdown
**RATIONALE**: Git history rewriting can silently drop commits or changes,
especially during interactive rebases where "pick" lines might be accidentally
deleted or conflicts might be resolved incorrectly. Manual verification is the
only reliable way to ensure no data loss occurred.
```

**Decision**: REMOVE

- Question 1: Can execute correctly without this? YES (instruction says to verify)
- Question 2: Explains WHY? YES (explains why verification is needed)
- **Result**: Remove - not needed for execution

### Example 2: Success Criteria (KEEP)

```markdown
**ARCHIVAL SUCCESS CRITERIA**:

- `git diff todo.md` shows ONLY deletions
- `git diff changelog.md` shows ONLY additions under today's date
- Both files in SAME commit
- `grep task-name todo.md` returns no matches
```

**Decision**: KEEP

- Question 1: Can execute correctly without this? NO (defines what "correct" means)
- **Result**: Keep - execution-critical success criteria

### Example 3: Redundant Restatement (REMOVE)

```markdown
When lock acquisition fails, you should not delete the lock file.
Instead, select an alternative task to work on.
```

**Decision**: REMOVE (if instruction already says this clearly)

- Question 1: Can execute correctly without this? YES (if already stated in instruction)
- Question 2: Explains WHY? NO
- Question 3: Shows WHAT "correct" looks like? NO (just restates instruction)
- Question 4: Extracts general rule? NO
- **Result**: Remove - redundant with clear instruction

### Example 4: Disambiguation Example (KEEP)

```bash
# ❌ WRONG: Marking complete in todo.md
vim todo.md  # Changed - [ ] to - [x]

# ✅ CORRECT: Delete from todo.md
vim todo.md  # DELETE entire task entry
```

**Decision**: KEEP

- Question 1: Can execute correctly without this? NO (resolves ambiguity in "delete")
- **Result**: Keep - shows that "delete" means remove lines, not change checkbox

### Example 5: Pattern Extraction (KEEP)

```markdown
[Specific example code block]
→ Shows that "delete" means remove lines, not change checkbox.
```

**Decision**: KEEP

- Question 1: Can execute correctly without this? Possibly YES (if example is clear)
- Question 2: Explains WHY? NO
- Question 3: Shows WHAT "correct" looks like? NO (annotation, not example)
- Question 4: Extracts general rule? YES (teaches what "delete" means for future cases)
- **Result**: Keep - pattern extraction annotation
