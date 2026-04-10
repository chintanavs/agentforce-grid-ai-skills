---
name: grid-results
description: "Show evaluation results and cell outputs for a Grid worksheet. Use when the user wants to see scores, outputs, or identify the worst-performing rows."
---

# /grid-results [worksheet-id]

## Purpose

Display evaluation results, AI outputs, and quality metrics from a worksheet.

## Behavior

1. Call `get_worksheet_data` to retrieve all cell data.
2. Identify Evaluation columns and their linked source columns.
3. Default display: summary statistics per evaluation column:
   - Mean score, median, min, max, standard deviation
   - Pass/fail counts (for assertion-type evaluations)
4. With `--summary`: show only the aggregate statistics.
5. With `--bottom N`: show the N lowest-scoring rows with their inputs and outputs, useful for debugging quality issues.
6. Format results as a readable table with row IDs for follow-up investigation.

## Evaluation Type Interpretation

| Type | Score Interpretation |
|------|---------------------|
| COHERENCE, CONCISENESS, FACTUALITY, INSTRUCTION_FOLLOWING, COMPLETENESS | 1-5 scale, higher is better |
| RESPONSE_MATCH, TOPIC_ASSERTION, ACTION_ASSERTION | Pass/Fail |
| BOT_RESPONSE_RATING | 1-5 scale |
| LATENCY_ASSERTION | Pass/Fail with millisecond value |
| EXPRESSION_EVAL | Boolean or computed value |
| CUSTOM_LLM_EVALUATION | Score or text from custom judge |

## Options

| Flag | Description |
|------|-------------|
| (none) | Full results table |
| `--summary` | Aggregate statistics only |
| `--bottom N` | Show N worst-performing rows |
