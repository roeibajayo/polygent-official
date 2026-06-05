# Optimization Examples

Before and after examples demonstrating effective documentation optimization.

## Example 1: Strengthening Vague Instructions

### Before (Vague)

```markdown
## Task Completion

When you finish a task, make sure to update the status appropriately and move on to the next task.
```

**Problem**: "Appropriately" is vague. "Finish" is subjective. No specific steps.

### After (Clear)

```markdown
## Task Completion

Mark task as completed when ALL criteria met:

- ✅ Implementation complete (no TODOs or placeholders)
- ✅ Tests pass (exit code 0)
- ✅ Changes committed to git

Steps:

1. Update task status to "completed" in task tracker
2. Archive task details to changelog with timestamp
3. Proceed to next pending task
```

**Improvements**:

- Explicit completion criteria (measurable)
- Specific steps (numbered, actionable)
- Removed vague term "appropriately"

## Example 2: Removing Redundant Explanations

### Before (Redundant)

```markdown
## Lock File Management

Before starting work on a task, you need to acquire a lock to prevent other agents from working on the same task. This ensures that multiple agents don't conflict with each other. Lock acquisition is important because without it, you might have race conditions where two agents modify the same files simultaneously.

To acquire a lock:

1. Check if lock file exists
2. If exists, verify it's not stale
3. Create lock file with task ID

This process prevents conflicts and ensures data integrity by making sure only one agent works on a task at a time.
```

**Problems**:

- Explains WHY multiple times (educational, not operational)
- Redundant rationale about preventing conflicts
- Verbose introduction restates the same concept

### After (Concise)

```markdown
## Lock File Management

To acquire a lock:

1. Check if lock file exists
2. If exists, verify it's not stale (timestamp < 1 hour)
3. Create lock file: `echo '{"task":"X","ts":"Y"}' > .task-lock.json`
```

**Improvements**:

- Removed all rationale (WHY) content
- Kept operational steps (WHAT to do)
- Added specific details (timestamp threshold, exact command)
- Reduced from 8 lines to 3 lines while increasing clarity

## Example 3: Preserving Execution-Critical Examples

### Before (Clear instruction with example)

````markdown
## Task Deletion

Delete completed tasks from todo.md by removing the entire entry.

Example:

```bash
# ❌ WRONG: Marking as complete
vim todo.md  # Changed - [ ] to - [x]
git commit -m "Complete task" todo.md

# ✅ CORRECT: Deleting entry
vim todo.md  # DELETE entire line "- [ ] Task name"
vim changelog.md  # ADD "- [2025-10-26] Completed: Task name"
git commit -m "Archive completed task" todo.md changelog.md
```
````

````

**Should we remove the example?**

**Analysis**:
- Instruction is clear: "removing the entire entry"
- Example shows WHAT "correct" looks like (success criteria)
- Disambiguates "delete" (remove line vs mark complete)
- Shows two-file workflow (delete from one, add to other)

**Decision**: **KEEP** - Example is execution-critical despite clear instruction
- Prevents common mistake (marking vs deleting)
- Shows exact git workflow
- Defines "delete" precisely

## Example 4: Consolidating Duplicate Content

### Before (Duplicated)

In section "Quick Reference":
```markdown
Content to keep:
- Commands (bash, jq, git)
- Data structures (JSON, schemas)
- Success criteria
````

In section "Detailed Guidelines":

```markdown
## Execution-Critical Content

The following content types must always be preserved:

1. **Commands**: Bash scripts, jq commands, git workflows
2. **Data Structures**: JSON formats, configuration schemas, API contracts
3. **Success Criteria**: Specific definitions of what "correct" looks like
```

**Problem**: Same information appears twice at different levels of detail.

### After (Consolidated)

In section "Quick Reference":

```markdown
Content to keep: Commands, Data structures, Success criteria (see Detailed Guidelines)
```

In section "Detailed Guidelines":

```markdown
## Execution-Critical Content

The following content types must always be preserved:

1. **Commands**: Bash scripts, jq commands, git workflows
2. **Data Structures**: JSON formats, configuration schemas, API contracts
3. **Success Criteria**: Specific definitions of what "correct" looks like
```

**Improvements**:

- Quick reference maintained for scanning
- Detailed section preserved for depth
- Cross-reference added without interrupting workflow
- Both serve different purposes (quick lookup vs deep understanding)

## Example 5: Converting Prose to Structure

### Before (Narrative)

```markdown
## Validation Process

You should first check that all the required fields are present, and then you need to verify that the data types are correct. After that, make sure the values are within acceptable ranges. Finally, ensure there are no duplicate entries.
```

**Problems**:

- Narrative format (harder to scan)
- Sequential steps hidden in prose
- No clear completion criteria

### After (Structured)

```markdown
## Validation Process

Execute in order:

1. Verify required fields present (name, id, type)
2. Check data types match schema
3. Validate value ranges:
   - id: positive integer
   - name: non-empty string
   - type: enum [A, B, C]
4. Ensure no duplicate IDs

Success: All checks pass, exit code 0
```

**Improvements**:

- Numbered steps (sequential, scannable)
- Specific field names and criteria
- Explicit value ranges
- Success criteria added

## Example 6: Pattern Extraction Annotations

### Before (Just example)

````markdown
## Commit Message Format

```bash
git commit -m "$(cat <<'EOF'
Implement user authentication

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```
````

````

**Missing**: What principle does this demonstrate?

### After (Example with annotation)

```markdown
## Commit Message Format

```bash
git commit -m "$(cat <<'EOF'
Implement user authentication

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
````

→ Use HEREDOC for multi-line commit messages to preserve formatting

````

**Improvement**: Annotation extracts general rule (use HEREDOC for multi-line messages) that applies to all future commits.

## Example 7: Removing Educational Content

### Before (Educational)

```markdown
## Testing Requirements

All changes must include tests. This is important because:
- Tests prevent regressions
- Tests document expected behavior
- Tests enable confident refactoring
- Tests improve code quality

Writing tests early helps catch bugs before they reach production.

To run tests: `npm test`
````

**Problems**:

- Lists benefits (WHY) - educational
- Includes general advice about test writing
- Operational content (how to run tests) buried

### After (Operational)

```markdown
## Testing Requirements

Before committing:

1. Add tests for new functionality
2. Run tests: `npm test`
3. Verify exit code 0 (all tests pass)

Required: All tests pass before commit.
```

**Improvements**:

- Removed all WHY content (benefits, rationale)
- Kept only WHAT to do (specific steps)
- Added success criteria (exit code 0)
- Made operational content prominent

## Example 8: Strengthening Subjective Terms

### Before (Subjective)

```markdown
## Code Review

Ensure code is properly formatted and clearly written with appropriate comments.
```

**Problems**:

- "Properly" - undefined
- "Clearly" - subjective
- "Appropriate" - vague

### After (Explicit)

```markdown
## Code Review

Verify ALL criteria:

- ✅ Code passes formatter: `npm run format` (no changes)
- ✅ No linting errors: `npm run lint` (exit code 0)
- ✅ Public functions have JSDoc comments (params, returns, description)
- ✅ Complex logic (>10 lines) includes inline explanation comments

Success: All checks pass
```

**Improvements**:

- Replaced "properly formatted" with specific command
- Replaced "clearly written" with measurable criteria
- Replaced "appropriate comments" with explicit rules (public functions, complex logic)
- Added success criteria

## Summary of Optimization Patterns

| Pattern            | Before                      | After                                   | Principle                        |
| ------------------ | --------------------------- | --------------------------------------- | -------------------------------- |
| Strengthen vague   | "Update appropriately"      | "Set status='completed' in task.json"   | Replace subjective with explicit |
| Remove redundancy  | Multiple "why" explanations | Single operational instruction          | Keep WHAT, remove WHY            |
| Preserve examples  | Clear instruction + example | Keep both if example shows "correct"    | Apply Execution Test             |
| Consolidate        | Same info in 2+ places      | Reference or merge if semantically safe | Check semantic equivalence       |
| Convert prose      | Narrative paragraphs        | Numbered steps or bulleted lists        | Structure over prose             |
| Add annotations    | Raw example                 | Example + extracted principle           | Enable pattern recognition       |
| Remove educational | Benefits, rationale, advice | Only operational steps                  | Focus on execution               |
| Replace subjective | "Clearly", "properly"       | Specific commands, measurable criteria  | Make testable                    |

## Key Takeaways

1. **Vague → Explicit**: Replace subjective terms with measurable criteria
2. **WHY → WHAT**: Remove rationale, keep operational instructions
3. **Prose → Structure**: Use lists, steps, tables for scannability
4. **Preserve Critical**: Keep examples that show "correct" or prevent errors
5. **Annotate Examples**: Extract general principles from specific cases
6. **Test Everything**: Apply Execution Test before removing content
