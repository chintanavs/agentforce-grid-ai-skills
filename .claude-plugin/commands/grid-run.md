---
name: grid-run
description: "Execute or reprocess cells in a Grid worksheet. Use when the user wants to run processing, retry failures, refresh stale cells, or reprocess a specific column."
---

# /grid-run [options]

## Purpose

Trigger execution or reprocessing of worksheet cells with fine-grained control.

## Behavior

1. Call `get_worksheet_data` to assess current state.
2. Based on options, determine scope:
   - **No options**: Call `trigger_row_execution` for all rows with New/Stale status.
   - **--failed**: Identify rows with Failed cells, call `reprocess_column` for each affected column, targeting failed rows.
   - **--stale**: Identify Stale cells, call `reprocess_column` for affected columns.
   - **--column <name-or-id>**: Call `reprocess_column` for the specified column only.
   - **--row <row-id>**: Call `trigger_row_execution` for the specific row.
3. After triggering, use `poll_worksheet_status` to monitor progress (polls every 3 seconds, up to 30 attempts by default).
4. On completion, display the updated status summary (same format as `/grid-status`).

## Options

| Flag | Description |
|------|-------------|
| (none) | Run all unprocessed/stale cells |
| `--failed` | Retry only failed cells |
| `--stale` | Reprocess only stale cells |
| `--column <id>` | Reprocess a specific column |
| `--row <id>` | Execute a specific row |
