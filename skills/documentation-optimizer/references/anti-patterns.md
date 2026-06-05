# Anti-Patterns to Avoid

Common mistakes when optimizing documentation that reduce clarity or break executability.

## Clarity Violations

### ❌ Converting Vertical Lists to Comma-Separated Concatenations

**DON'T DO THIS:**

Before (Good):

```markdown
Prohibited phrases:

- "TODO: implement"
- "For now we'll just"
- "In the meantime, simulate"
- "This is a placeholder"
```

After (Bad):

```markdown
Prohibited phrases: "TODO: implement", "For now we'll just", "In the meantime, simulate", "This is a placeholder"
```

**Why it's bad**: Vertical lists are easier to scan and count. Comma-separated lists reduce scannability.

### ❌ Converting Checkmarked Action Items to Prose

**DON'T DO THIS:**

Before (Good):

```markdown
Before committing:

- ✅ Run all tests
- ✅ Check for linting errors
- ✅ Review diff
- ✅ Verify no sensitive data
```

After (Bad):

```markdown
Before committing, run all tests, check for linting errors, review diff, and verify no sensitive data.
```

**Why it's bad**: Checkmarks provide visual pattern recognition. Prose format loses the actionable checklist structure.

### ❌ Removing Section Headers That Aid Navigation

**DON'T DO THIS:**

Before (Good):

```markdown
## Success Criteria

- All tests pass
- No linting errors

## Execution Steps

1. Run tests
2. Review output
```

After (Bad):

```markdown
All tests must pass with no linting errors. Run tests and review output.
```

**Why it's bad**: Section headers enable quick navigation and scanning. Merged prose makes it harder to find specific information.

### ❌ Consolidating Distinct Concepts into Run-On Sentences

**DON'T DO THIS:**

Before (Good):

```markdown
**Lock Acquisition**: Try to acquire lock before starting task.

**Lock Failure**: If acquisition fails, select alternative task.

**Lock Deletion**: Never delete lock files manually.
```

After (Bad):

```markdown
Try to acquire lock before starting task, and if acquisition fails, select alternative task, but never delete lock files manually.
```

**Why it's bad**: Distinct concepts are clearer when separated. Run-on sentences reduce clarity and make it harder to reference specific rules.

## Semantic Equivalence Violations

### ❌ Replacing with Non-Equivalent References

**DON'T DO THIS:**

Before:

```markdown
**Goals**: A, B, C
```

After:

```markdown
See **Priority** section (which says: C > B > A)
```

**Why it's bad**: "Goals: A, B, C" and "Priority: C > B > A" are not semantically equivalent. Goals list what to achieve; priority ranks them. Both serve different purposes.

### ❌ Replacing Quick-Reference Lists with Detailed Sections

**DON'T DO THIS:**

Before:

```markdown
## Quick Reference

Content to keep:

- Commands
- Formats
- Success criteria
- Boundary demos

[Later in document: detailed section with tests, examples, edge cases for each]
```

After:

```markdown
## Quick Reference

See detailed section below for content to keep.

[Detailed section with tests, examples, edge cases]
```

**Why it's bad**: Quick-reference lists serve a different purpose than detailed sections. Users need both: quick lookup AND deep understanding.

## Workflow Interruption

### ❌ Replacing Inline Workflow Criteria with "See Section X"

**DON'T DO THIS:**

Before (Good):

```markdown
1. Run tests
2. Verify all pass (exit code 0, no failures in output)
3. Commit changes
```

After (Bad):

```markdown
1. Run tests
2. Verify all pass (see "Success Criteria" section)
3. Commit changes
```

**Why it's bad**: Users are mid-workflow and need criteria inline. Forcing them to jump to another section breaks execution flow.

### ❌ Removing Context from Sequential Steps

**DON'T DO THIS:**

Before (Good):

```markdown
1. Complete SYNTHESIS phase
2. Present plan to user
3. Update lock: `jq '.state = "SYNTHESIS_AWAITING_APPROVAL"'`
4. STOP - wait for user approval
5. On approval: Update lock to `CONTEXT` and proceed
```

After (Bad):

```markdown
1. Complete SYNTHESIS phase
2. Present plan to user
3. Update lock state
4. Wait for approval
5. Proceed to CONTEXT
```

**Why it's bad**: Removing the exact command and state values breaks executability. Users need specific details inline in sequential workflows.

## Over-Consolidation

### ❌ Removing Examples That Define Ambiguous Terms

**DON'T DO THIS:**

Before (Good):

````markdown
Delete completed tasks from todo.md

Example:

```bash
# ❌ WRONG: Marking complete
vim todo.md  # Changed - [ ] to - [x]

# ✅ CORRECT: Delete entry
vim todo.md  # DELETE entire task entry
```
````

````

After (Bad):
```markdown
Delete completed tasks from todo.md (remove entire entry, not mark as complete)
````

**Why it might fail**: If "delete" is commonly misunderstood, the example provides clearer guidance than additional words. Keep the example until you're confident the instruction is unambiguous.

### ❌ Removing Pattern Extraction Annotations

**DON'T DO THIS:**

Before (Good):

```markdown
[Specific example code block]
→ Shows that "delete" means remove lines, not change checkbox.
```

After (Bad):

```markdown
[Specific example code block]
```

**Why it's bad**: The annotation extracts a general principle from the specific example, teaching how to apply the reasoning to new cases. Without it, users might not grasp the generalizable rule.

## Execution-Critical Content Removal

### ❌ Removing Success Criteria

**DON'T DO THIS:**

Before (Good):

```markdown
**ARCHIVAL SUCCESS CRITERIA**:

- `git diff todo.md` shows ONLY deletions
- `git diff changelog.md` shows ONLY additions under today's date
- Both files in SAME commit
- `grep task-name todo.md` returns no matches
```

After (Bad):

```markdown
Verify archival completed successfully.
```

**Why it's bad**: "Successfully" is vague without specific criteria. The original list defines exactly what success looks like, which is execution-critical.

### ❌ Removing Command-Specific Flags

**DON'T DO THIS:**

Before (Good):

```bash
git log --format='%an %ae' -1
```

After (Bad):

```bash
git log
```

**Why it's bad**: The specific format and `-1` flag are critical for getting the correct output. Generic commands don't provide execution-critical details.

### ❌ Removing Boundary Demonstrations

**DON'T DO THIS:**

Before (Good):

```markdown
Prohibited patterns:

- ❌ `TODO: implement later`
- ❌ `For now, we'll just mock this`
- ✅ `[Complete implementation without placeholders]`
```

After (Bad):

```markdown
Don't use placeholder comments. Implement fully.
```

**Why it's bad**: Specific prohibited patterns help users recognize violations in their own code. Generic instructions are less effective at preventing common mistakes.

## Correctness vs Conciseness Trade-offs

### ❌ Choosing Conciseness Over Correctness

**DON'T DO THIS:**

Before (Good):

```markdown
1. Check if lock exists: `test -f .task-lock.json`
2. If lock exists, read contents: `cat .task-lock.json`
3. Verify lock is not stale (timestamp < 1 hour old)
4. If stale, delete lock: `rm .task-lock.json`
5. Create new lock: `echo '{"task":"X","ts":"Y"}' > .task-lock.json`
```

After (Bad):

```markdown
Manage lock file as needed.
```

**Why it's bad**: The specific steps are execution-critical. The concise version sacrifices correctness for brevity.

**Remember**: Never sacrifice correctness for conciseness. Always sacrifice conciseness for correctness.

## Preservation Guidelines

When in doubt, preserve:

1. **Scannability**: Vertical lists over concatenations
2. **Pattern Recognition**: Checkmarks/bullets over prose
3. **Explicit Criteria**: "ALL", "at least ONE", "NEVER"
4. **Measurable Thresholds**: Counts, file paths, exact strings
5. **Prevention Patterns**: Prohibited vs required examples
6. **Error Condition Definitions**: Specific failure modes
7. **Sequential Context**: Inline details in ordered workflows
8. **Success Criteria**: Exact definitions of "correct"
9. **Executable Commands**: Complete commands with all flags
10. **Boundary Demonstrations**: Wrong vs right pattern examples
