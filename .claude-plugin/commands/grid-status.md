---
name: grid-status
description: "Show the current state of a Grid worksheet including column health, cell statuses, and processing progress. Use when the user asks about grid state, progress, or errors."
---

# /grid-status [worksheet-id]

## Purpose

Display a comprehensive status summary of a worksheet's current state.

## Behavior

1. If no worksheet ID provided, call `get_workbooks` then use `get_worksheet_summary` for the most recently modified workbook's first worksheet.
2. Call `get_worksheet_data` to retrieve full state including all columns, rows, and cells.
3. Produce a three-layer display:

**Layer 1 -- Summary Banner:**
```
## [Worksheet Name]
Workbook: [Name] ([ID])  |  Worksheet: [ID]
Columns: N  |  Rows: N  |  Overall: N% complete
Status: [COMPLETE/PROCESSING/FAILED]  |  Failed: N rows
```

**Layer 2 -- Column Strip:**

| Column | Type | Total | Complete | Failed | Stale | InProgress |
|--------|------|-------|----------|--------|-------|------------|
| Utterances | Text | 50 | 50 | 0 | 0 | 0 |
| Agent Output | AgentTest | 50 | 42 | 5 | 3 | 0 |
| Quality Score | Evaluation | 50 | 40 | 0 | 10 | 0 |

4. Flag columns with >10% failure rate as needing attention.
5. If any cells are InProgress, report estimated wait based on completion velocity.

## Options

- No arguments: status of the active/most recent worksheet
- `[worksheet-id]`: status of a specific worksheet
