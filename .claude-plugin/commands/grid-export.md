---
name: grid-export
description: "Export Grid worksheet data to CSV or JSON format. Use when the user wants to download, save, or share grid results."
---

# /grid-export [options]

## Purpose

Export worksheet data to a local file in CSV or JSON format.

## Behavior

1. Call `get_worksheet_data` to retrieve all cell data.
2. Build a tabular representation: columns as headers, rows as records.
3. For each cell, extract `displayContent` as the value.
4. Write to file based on format:
   - **CSV** (default): Standard CSV with headers. Write to `./grid-export-{worksheet-id}.csv`
   - **JSON**: Array of objects keyed by column name. Write to `./grid-export-{worksheet-id}.json`
5. Report file path and row/column counts.

## Options

| Flag | Description |
|------|-------------|
| `--format csv` | Export as CSV (default) |
| `--format json` | Export as JSON |
| `--columns <names>` | Export only specific columns (comma-separated) |
| `--status <status>` | Export only rows where all cells match status (Complete, Failed, etc.) |
