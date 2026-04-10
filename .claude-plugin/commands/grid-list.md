---
name: grid-list
description: "List all Grid workbooks and their worksheets in a tree view. Use when the user wants to see what grids exist or find a specific workbook."
---

# /grid-list

## Purpose

Display all workbooks and their worksheets in a hierarchical tree.

## Behavior

1. Call `get_workbooks` MCP tool.
2. For each workbook, call `get_workbook` to retrieve worksheet metadata.
3. Display as a tree:

```
Workbooks
+-- ServiceBot Evaluation (0HxRM00000001)
|   +-- v1-baseline (0HyRM00000001) - 5 columns, 50 rows
|   +-- v2-improved (0HyRM00000002) - 7 columns, 50 rows
+-- Account Enrichment (0HxRM00000002)
|   +-- main (0HyRM00000003) - 3 columns, 200 rows
+-- Flow Testing (0HxRM00000003)
    +-- smoke-tests (0HyRM00000004) - 4 columns, 20 rows
```

4. Include workbook and worksheet IDs for easy copy-paste into other commands.
5. If many workbooks exist, show most recently modified first.
