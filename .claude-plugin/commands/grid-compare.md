---
name: grid-compare
description: "Compare two Grid worksheets side by side, showing differences in structure, evaluation scores, and outputs. Use when the user wants to compare versions or A/B test results."
---

# /grid-compare <worksheet-id-a> <worksheet-id-b>

## Purpose

Compare two worksheets to identify structural and output differences.

## Behavior

1. Call `get_worksheet_data` for both worksheet IDs.
2. Compare structure:
   - Columns present in A but not B (and vice versa)
   - Column config differences (model, instruction, evaluation type)
3. Compare results (matching rows by position or by Text column content):
   - Evaluation score differences (mean, median, per-row delta)
   - Output differences for AI/Agent columns
4. Display a comparison summary:

| Metric | Worksheet A | Worksheet B | Delta |
|--------|------------|------------|-------|
| Coherence (mean) | 0.82 | 0.91 | +0.09 |
| Response Match | 78% | 85% | +7% |
| Failed cells | 5 | 2 | -3 |

5. Highlight rows with the largest score improvements or regressions.
6. Flag any regressions: metrics that dropped > 0.2 points or pass/fail flips.

## Regression Detection

- Any metric that drops > 0.2 points = WARNING
- Any metric that drops > 0.5 points = FAILURE
- Any previously-passing row that now fails = REGRESSION
