---
name: grid-debug
description: "Investigate failed or unexpected cells in a Grid worksheet. Use when the user wants to understand why cells failed, produced wrong output, or have unexpected status."
---

# /grid-debug [row-id]

## Purpose

Investigate processing failures and unexpected outputs in a worksheet.

## Behavior

1. Call `get_worksheet_data` to get full state.
2. If no row specified, identify all rows with Failed cells and show a summary:
   - Row ID, column name, status, error message (if available in cell data)
   - Group failures by column to identify systematic issues
3. If a row ID is provided, show detailed cell-by-cell breakdown:
   - Each column's input, output, status
   - For Agent/AgentTest: the conversation trace if available
   - For Evaluation: the score and reasoning
   - For AI: the prompt that was generated (reconstructed from instruction + referenceAttributes)
4. Suggest remediation:
   - If failures are in a single column: suggest config check or reprocessing
   - If failures correlate with specific input patterns: flag the pattern
   - If all cells in a column fail: likely config issue (missing modelConfig, wrong columnType casing, etc.)
5. Offer to run `/grid-run --failed` to retry after fixes.

## Common Failure Patterns

| Pattern | Likely Cause | Fix |
|---------|-------------|-----|
| All cells in column fail | Config error | Check nested config structure, modelConfig, columnType casing |
| Intermittent failures | Rate limiting or transient errors | Reprocess with `/grid-run --failed` |
| Evaluation all zeros | Wrong reference column | Check referenceColumnReference points to correct column |
| Agent timeout | Complex utterances | Simplify inputs or increase timeout |
| Downstream columns all Skipped | Upstream column failed | Fix the upstream column first |
| Deserialization error | Missing `type` field in config | Add `type` field matching the column type |
