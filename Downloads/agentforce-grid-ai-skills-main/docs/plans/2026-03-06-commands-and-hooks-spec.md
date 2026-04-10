> **Status:** ACTIVE | Hooks = Phase 4.1-4.2, Commands = Phase 5.3 | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) Phase 4 (hooks) + Phase 5 (commands)
> **What changed:** Hooks (PreToolUse validate-config, PostToolUse auto-render) are in hybrid plan Phase 4.1-4.2 and can start in parallel with Phase 1. Slash commands reinstated as Phase 5.3 (plugin architecture scope). Authentication uses SF CLI exclusively (sf org login) for all environments.

# Agentforce Grid: Slash Commands & Hooks Specification

**Date:** 2026-03-06
**Status:** ~~Draft~~ Partial: hooks ACTIVE (Phase 4), commands DEFERRED
**Plugin:** Agentforce Grid Claude Code Plugin (57 MCP tools)

---

## Table of Contents

1. [Overview](#overview)
2. [Slash Commands](#slash-commands)
3. [Hooks](#hooks)
4. [hooks.json Registration](#hooksjson-registration)

---

## Overview

This spec defines 10 slash commands and 4 hooks for the Agentforce Grid Claude Code plugin. The slash commands provide shorthand access to common Grid workflows that otherwise require multi-step MCP tool orchestration. The hooks provide automatic guardrails, validation, and quality-of-life automation.

### Design Principles

- Commands call MCP tools internally; they never bypass the MCP layer to hit APIs directly.
- Commands produce structured output (tables, status badges) so Claude can reason about results.
- Hooks are lightweight shell/Python scripts that run in <2s to avoid blocking the user.
- Authentication uses SF CLI exclusively: Requires SF CLI installed (`brew install sf`), org login (`sf org login web --alias <alias> --instance-url <url>`), and `SF_ORG_ALIAS` environment variable set

---

## Slash Commands -- DEFERRED

> **DEFERRED:** Slash commands require the plugin architecture (plugin.json, agent definitions) which is deferred. These specs remain valid for future implementation once the MCP server evolution is complete.

Each command is defined as a skill `.md` file with YAML frontmatter, installed to the plugin's `skills/` directory.

---

### 1. `/grid-new`

**File:** `skills/grid-new/SKILL.md`

```markdown
---
name: grid-new
description: "Create a new Agentforce Grid workbook and worksheet from a natural language description. Use when the user wants to set up a new grid, spreadsheet, or evaluation pipeline."
---

# /grid-new <description>

## Purpose

Create a complete Grid workbook + worksheet + columns from a natural language description.

## Behavior

1. Parse the user's description to identify:
   - Workbook name (infer from description or ask)
   - Column definitions: name, type, and dependencies
   - Data source (Object query, text input, paste data)
2. Call `create_workbook` MCP tool with inferred name.
3. Call `create_worksheet` MCP tool, linking to the new workbook.
4. For each column, call `add_column` with the correct nested config structure:
   - Text columns: `config.type: "Text"` with nested `config.config.autoUpdate: true`
   - AI columns: include `modelConfig`, `instruction`, `referenceAttributes`, `responseFormat`
   - Agent/AgentTest columns: include `agentId`, `inputUtterance` references
   - Evaluation columns: include evaluation `type` and `referenceColumnReference` where required
5. If the description includes test data, call `paste_data` to populate Text columns.
6. Call `get_worksheet_data` to confirm creation and display the resulting grid structure.

## Critical Config Rules

- ALL columns require the nested config structure: `{ type, config: { type, config: { ... } } }`
- Use mixed case for `type` field ("AI", "Text"), UPPERCASE for `columnType` in referenceAttributes ("OBJECT", "TEXT")
- AI/PromptTemplate columns MUST include `modelConfig` with both `modelId` and `modelName`
- When adding columns to a worksheet with existing data, use `queryResponseFormat: { type: "EACH_ROW" }`

## Examples

- `/grid-new agent test pipeline for ServiceBot with 10 utterances and response match evaluation`
- `/grid-new data enrichment grid: query Accounts, generate AI summaries using GPT 4 Omni`
- `/grid-new simple text grid with 3 columns: input, expected output, notes`
```

---

### 2. `/grid-status`

**File:** `skills/grid-status/SKILL.md`

```markdown
---
name: grid-status
description: "Show the current state of a Grid worksheet including column health, cell statuses, and processing progress. Use when the user asks about grid state, progress, or errors."
---

# /grid-status [worksheet-id]

## Purpose

Display a comprehensive status summary of a worksheet's current state.

## Behavior

1. If no worksheet ID provided, call `list_workbooks` then `get_worksheet` for the most recently modified workbook's first worksheet.
2. Call `get_worksheet_data` to retrieve full state including all columns, rows, and cells.
3. Produce a summary table:

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
```

---

### 3. `/grid-run`

**File:** `skills/grid-run/SKILL.md`

```markdown
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
3. After triggering, poll `get_worksheet_data` every 5 seconds (up to 60s) and display progress.
4. On completion, display the updated status summary (same format as `/grid-status`).

## Options

| Flag | Description |
|------|-------------|
| (none) | Run all unprocessed/stale cells |
| `--failed` | Retry only failed cells |
| `--stale` | Reprocess only stale cells |
| `--column <id>` | Reprocess a specific column |
| `--row <id>` | Execute a specific row |
```

---

### 4. `/grid-results`

**File:** `skills/grid-results/SKILL.md`

```markdown
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

## Options

| Flag | Description |
|------|-------------|
| (none) | Full results table |
| `--summary` | Aggregate statistics only |
| `--bottom N` | Show N worst-performing rows |
```

---

### 5. `/grid-add`

**File:** `skills/grid-add/SKILL.md`

```markdown
---
name: grid-add
description: "Add a new column to the active Grid worksheet from a natural language description. Use when the user wants to add an AI column, evaluation, agent test, or any other column type to an existing grid."
---

# /grid-add <description>

## Purpose

Add a column to the current worksheet based on a natural language description.

## Behavior

1. Call `get_worksheet_data` to understand the current grid structure (existing columns, types, IDs).
2. Parse the description to determine:
   - Column type (AI, Evaluation, Agent, AgentTest, Text, Reference, Object, etc.)
   - Column name
   - References to existing columns (for referenceAttributes, inputUtterance, referenceColumnReference)
   - For AI columns: instruction template with `{$N}` placeholders mapped to existing columns
   - For Evaluation columns: evaluation type and reference column
3. Build the column config with the nested structure:
   - `queryResponseFormat: { type: "EACH_ROW" }` (worksheet already has data)
   - Correct UPPERCASE `columnType` in referenceAttributes
   - `modelConfig` for AI/PromptTemplate columns
4. Call `add_column` MCP tool.
5. Verify with `get_worksheet_data` (column creation may return errors but succeed).
6. Display the updated grid structure.

## Examples

- `/grid-add evaluation column for coherence on the Agent Output column`
- `/grid-add AI column "Summary" using GPT 4 Omni: summarize {Account Name} in {Industry}`
- `/grid-add reference column extracting "topic" field from Agent Output`
```

---

### 6. `/grid-debug`

**File:** `skills/grid-debug/SKILL.md`

```markdown
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
```

---

### 7. `/grid-compare`

**File:** `skills/grid-compare/SKILL.md`

```markdown
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
```

---

### 8. `/grid-export`

**File:** `skills/grid-export/SKILL.md`

```markdown
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
```

---

### 9. `/grid-list`

**File:** `skills/grid-list/SKILL.md`

```markdown
---
name: grid-list
description: "List all Grid workbooks and their worksheets in a tree view. Use when the user wants to see what grids exist or find a specific workbook."
---

# /grid-list

## Purpose

Display all workbooks and their worksheets in a hierarchical tree.

## Behavior

1. Call `list_workbooks` MCP tool.
2. For each workbook, call `get_workbook` to retrieve worksheet metadata.
3. Display as a tree:

```
Workbooks
├── ServiceBot Evaluation (0HxRM00000001)
│   ├── v1-baseline (0HyRM00000001) - 5 columns, 50 rows
│   └── v2-improved (0HyRM00000002) - 7 columns, 50 rows
├── Account Enrichment (0HxRM00000002)
│   └── main (0HyRM00000003) - 3 columns, 200 rows
└── Flow Testing (0HxRM00000003)
    └── smoke-tests (0HyRM00000004) - 4 columns, 20 rows
```

4. Include workbook and worksheet IDs for easy copy-paste into other commands.
```

---

### 10. `/grid-models`

**File:** `skills/grid-models/SKILL.md`

```markdown
---
name: grid-models
description: "List available LLM models in the Salesforce org for use in AI and PromptTemplate columns. Use when the user asks what models are available or needs a model name for configuration."
---

# /grid-models

## Purpose

List all available LLM models that can be used in AI and PromptTemplate column configurations.

## Behavior

1. Call `list_llm_models` MCP tool (GET /llm-models endpoint).
2. Display as a table:

| Model Name | Label | Max Tokens | Status |
|------------|-------|------------|--------|
| sfdc_ai__DefaultGPT4Omni | GPT 4 Omni | 16384 | Active |
| sfdc_ai__DefaultGPT41 | GPT 4.1 | 32768 | Active |
| sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet | Claude Sonnet 4 on Amazon | 8192 | Active |
| sfdc_ai__DefaultVertexAIGemini25Flash001 | Google Gemini 2.5 Flash | 65536 | Active |

3. Indicate which models are recommended (high-capability, active).
4. Remind the user that `modelConfig` requires the model `name` for BOTH `modelId` and `modelName` fields.
```

---

## Hooks -- ACTIVE (Phase 4.1-4.2)

> **ACTIVE:** Hooks are incorporated into hybrid plan Phase 4.1 (PreToolUse validation) and Phase 4.2 (PostToolUse ASCII rendering). These can start in parallel with Phases 1-2 since they are independent of MCP server code. Hooks use SF CLI authentication exclusively (via `SF_ORG_ALIAS` environment variable).

Hooks are scripts that run automatically at specific lifecycle points in Claude Code. They are registered in `.claude/hooks.json` and execute shell or Python scripts.

### Authentication Setup

All hooks use SF CLI for accessing the Grid API:

1. **Install SF CLI:**
   ```bash
   brew install sf
   ```

2. **Find your instance URL:**
   - Check your MCP configuration: `~/.claude/.mcp.json`
   - Look for the `INSTANCE_URL` value in the `grid-connect` server config
   - Example: `https://sdb3.test1.pc-rnd.pc-aws.salesforce.com`

3. **Login to your org:**
   ```bash
   sf org login web --alias orgfarm-org --instance-url https://sdb3.test1.pc-rnd.pc-aws.salesforce.com/
   ```

   You'll be prompted to login in your browser with credentials provided by your administrator.

   Example credentials for test environments:
   - Username: `epic.out.a235f1254a9e@orgfarm.salesforce.com`
   - Password: `orgfarm1234`

4. **Set the org alias environment variable:**
   ```bash
   export SF_ORG_ALIAS=orgfarm-org
   ```

5. **Test the connection:**
   ```bash
   sf api request rest /services/data/v66.0/public/grid/workbooks \
     --method GET \
     --target-org orgfarm-org
   ```

---

### 1. SessionStart: `session-init.sh`

**Trigger:** Every time a Claude Code session starts in a project with this plugin.

**Purpose:** Validate that the Salesforce environment is configured correctly before the user starts working.

**File:** `.claude/hooks/session-init.sh`

```bash
#!/usr/bin/env bash
# Hook: SessionStart — validate SF CLI authentication and test Grid API connection
# Exit 0 = success (message shown as info), Exit 1 = failure (message shown as warning)

set -euo pipefail

SF_ORG_ALIAS="${SF_ORG_ALIAS:-}"

# --- Check if SF CLI is installed ---
if ! command -v sf &>/dev/null; then
  echo "Agentforce Grid: SF CLI is not installed."
  echo ""
  echo "Install SF CLI with:"
  echo "  brew install sf"
  echo ""
  echo "Then login to your org:"
  echo "  sf org login web --alias <alias> --instance-url <url>"
  echo "  export SF_ORG_ALIAS=<alias>"
  exit 1
fi

# --- Check if SF_ORG_ALIAS is set ---
if [ -z "$SF_ORG_ALIAS" ]; then
  echo "Agentforce Grid: SF_ORG_ALIAS environment variable is not set."
  echo ""
  echo "Set it to your authenticated org alias:"
  echo "  export SF_ORG_ALIAS=<your-org-alias>"
  echo ""
  echo "To login to an org:"
  echo "  sf org login web --alias <alias> --instance-url <url>"
  echo "  Example: sf org login web --alias orgfarm-org --instance-url https://sdb3.test1.pc-rnd.pc-aws.salesforce.com/"
  exit 1
fi

# --- Verify org is authenticated ---
if ! sf org display --target-org "$SF_ORG_ALIAS" --json &>/dev/null; then
  echo "Agentforce Grid: SF CLI org '$SF_ORG_ALIAS' is not authenticated."
  echo "  Login with: sf org login web --alias $SF_ORG_ALIAS --instance-url <url>"
  exit 1
fi

# --- Test connection to Grid API ---
RESPONSE=$(sf api request rest /services/data/v66.0/public/grid/workbooks \
  --method GET \
  --target-org "$SF_ORG_ALIAS" 2>&1 || echo "ERROR")

if echo "$RESPONSE" | grep -q "ERROR\|error\|Error"; then
  echo "Agentforce Grid: Failed to connect to Grid API using SF CLI."
  echo "  Org: $SF_ORG_ALIAS"
  echo "  Response: $RESPONSE"
  exit 1
fi

ORG_INFO=$(sf org display --target-org "$SF_ORG_ALIAS" --json | jq -r '.result.instanceUrl // "unknown"')
echo "Agentforce Grid: Connected via SF CLI (org: $SF_ORG_ALIAS, instance: $ORG_INFO)"
exit 0
```

---

### 2. PreToolUse: `validate-config.py`

**Trigger:** Before any `add_column` or `edit_column` MCP tool call.

**Purpose:** Catch the three most common column configuration errors before they hit the API and waste a round-trip.

**File:** `.claude/hooks/validate-config.py`

```python
#!/usr/bin/env python3
"""
Hook: PreToolUse — validate column config before add_column / edit_column
Reads tool call context from stdin (JSON with tool_name and tool_input).
Prints error messages to stdout. Exit 0 = allow, Exit 1 = block with message.
"""

import json
import sys

def validate():
    context = json.load(sys.stdin)
    tool_name = context.get("tool_name", "")
    tool_input = context.get("tool_input", {})

    # Only validate column mutation tools
    if tool_name not in ("add_column", "edit_column"):
        sys.exit(0)

    # Parse the config string (tools accept config as JSON string)
    config_str = tool_input.get("config", "{}")
    try:
        config = json.loads(config_str) if isinstance(config_str, str) else config_str
    except json.JSONDecodeError:
        print(f"BLOCK: Column config is not valid JSON.")
        sys.exit(1)

    errors = []

    # --- Check 1: Nested config.config structure ---
    outer_config = config.get("config", {})
    if not outer_config:
        errors.append(
            "Missing nested config structure. ALL columns require: "
            '{ "type": "X", "config": { "type": "X", "config": { ... } } }. '
            "Even Text columns need config.type and config.config.autoUpdate."
        )
    elif "config" not in outer_config and config.get("type") not in ("Text",):
        errors.append(
            "Missing inner config.config object. The nested structure must be: "
            "config.config.{column-specific fields}."
        )

    # --- Check 2: columnType casing in referenceAttributes ---
    inner_config = outer_config.get("config", {}) if outer_config else {}
    ref_attrs = inner_config.get("referenceAttributes", [])
    for i, attr in enumerate(ref_attrs):
        col_type = attr.get("columnType", "")
        if col_type and col_type != col_type.upper():
            errors.append(
                f"referenceAttributes[{i}].columnType = '{col_type}' must be UPPERCASE "
                f"(e.g., '{col_type.upper()}'). The type field uses mixed case, but "
                "columnType in referenceAttributes must be UPPERCASE."
            )

    # --- Check 3: modelConfig for AI/PromptTemplate ---
    col_type = config.get("type", "")
    if col_type in ("AI", "PromptTemplate"):
        model_config = inner_config.get("modelConfig")
        if not model_config:
            errors.append(
                f"{col_type} columns require modelConfig with modelId and modelName. "
                "Example: { \"modelId\": \"sfdc_ai__DefaultGPT4Omni\", "
                "\"modelName\": \"sfdc_ai__DefaultGPT4Omni\" }"
            )
        elif model_config:
            if not model_config.get("modelId") or not model_config.get("modelName"):
                errors.append(
                    "modelConfig must have both modelId and modelName fields set "
                    "to the model's name value."
                )

    # --- Check 4: AI column responseFormat ---
    if col_type == "AI":
        response_fmt = inner_config.get("responseFormat")
        if not response_fmt:
            errors.append(
                "AI columns require responseFormat with type and options array. "
                'Example: { "type": "PLAIN_TEXT", "options": [] }'
            )

    if errors:
        print("BLOCK: Column config validation failed:")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    validate()
```

---

### 3. PostToolUse: `post-api-call.sh`

**Trigger:** After any MCP tool call that mutates worksheet state.

**Purpose:** Automatically render the updated grid state after mutations so the user always sees current state. This is the highest-value hook -- it eliminates the "now call get_worksheet_data to see what happened" pattern.

**File:** `.claude/hooks/post-api-call.sh`

```bash
#!/usr/bin/env bash
# Hook: PostToolUse — auto-render grid state after mutation tools
# Reads tool call result from stdin (JSON with tool_name, tool_input, tool_output).
# Prints supplemental context to stdout (appended to tool result).
# Uses SF CLI for authentication.

set -euo pipefail

# Read the hook context from stdin
CONTEXT=$(cat)
TOOL_NAME=$(echo "$CONTEXT" | jq -r '.tool_name // ""')

# Mutation tools that warrant a state refresh
MUTATION_TOOLS="add_column edit_column delete_column paste_data update_cells trigger_row_execution reprocess_column save_column create_worksheet"

# Check if the tool is a mutation tool
MATCH=false
for tool in $MUTATION_TOOLS; do
  if [ "$TOOL_NAME" = "$tool" ]; then
    MATCH=true
    break
  fi
done

if [ "$MATCH" = false ]; then
  exit 0
fi

# Extract worksheet ID from tool input (different tools use different param names)
WORKSHEET_ID=$(echo "$CONTEXT" | jq -r '
  .tool_input.worksheetId //
  .tool_input.worksheet_id //
  .tool_output.worksheetId //
  .tool_output.id //
  ""
')

if [ -z "$WORKSHEET_ID" ] || [ "$WORKSHEET_ID" = "null" ]; then
  exit 0
fi

# Fetch current state via SF CLI
if [ -z "${SF_ORG_ALIAS:-}" ] || ! command -v sf &>/dev/null; then
  # Skip auto-refresh if SF CLI not configured
  exit 0
fi

RESPONSE=$(sf api request rest "/services/data/v66.0/public/grid/worksheets/${WORKSHEET_ID}/data" \
  --method GET \
  --target-org "$SF_ORG_ALIAS" 2>/dev/null || echo "")

if [ -z "$RESPONSE" ]; then
  exit 0
fi

# Build a compact status summary
echo ""
echo "--- Grid State (auto-refresh) ---"

# Use jq to produce a column status summary
echo "$RESPONSE" | jq -r '
  .columns // [] | to_entries[] |
  .value as $col |
  ($col.name // "unnamed") as $name |
  ($col.type // "?") as $type |
  "  \($name) (\($type))"
' 2>/dev/null || true

# Count cell statuses
echo "$RESPONSE" | jq -r '
  [.rows // [] | .[].cells // {} | to_entries[].value.status // "Unknown"] |
  group_by(.) | map({status: .[0], count: length}) |
  "  Status: " + (map("\(.status)=\(.count)") | join(", "))
' 2>/dev/null || true

echo "--- End Grid State ---"
exit 0
```

---

### 4. PostToolUse: `detect-grid-curl.sh`

**Trigger:** After any `Bash` tool call.

**Purpose:** Detect when Claude uses raw `curl` commands against Grid API endpoints and suggest the equivalent MCP tool instead. This prevents bypassing the MCP layer (which has validation, auth handling, and error recovery).

**File:** `.claude/hooks/detect-grid-curl.sh`

```bash
#!/usr/bin/env bash
# Hook: PostToolUse — detect raw curl to Grid API, suggest MCP tools instead
# Reads tool call context from stdin. Prints suggestion to stdout.

set -euo pipefail

CONTEXT=$(cat)
TOOL_NAME=$(echo "$CONTEXT" | jq -r '.tool_name // ""')

# Only inspect Bash tool calls
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$CONTEXT" | jq -r '.tool_input.command // ""')

# Check if the command contains a curl to the Grid API
if ! echo "$COMMAND" | grep -q "public/grid"; then
  exit 0
fi

echo ""
echo "--- Grid API Usage Warning ---"
echo "Detected raw curl to the Grid API. Prefer MCP tools instead."
echo ""

# Map endpoint patterns to MCP tool suggestions
if echo "$COMMAND" | grep -qE "POST.*/workbooks"; then
  echo "  Instead of: curl -X POST .../workbooks"
  echo "  Use tool:   create_workbook"
elif echo "$COMMAND" | grep -qE "GET.*/workbooks"; then
  echo "  Instead of: curl -X GET .../workbooks"
  echo "  Use tool:   list_workbooks or get_workbook"
elif echo "$COMMAND" | grep -qE "POST.*/worksheets/[^/]+/columns"; then
  echo "  Instead of: curl -X POST .../worksheets/{id}/columns"
  echo "  Use tool:   add_column"
elif echo "$COMMAND" | grep -qE "POST.*/worksheets/[^/]+/paste"; then
  echo "  Instead of: curl -X POST .../worksheets/{id}/paste"
  echo "  Use tool:   paste_data"
elif echo "$COMMAND" | grep -qE "POST.*/trigger-row-execution"; then
  echo "  Instead of: curl -X POST .../trigger-row-execution"
  echo "  Use tool:   trigger_row_execution"
elif echo "$COMMAND" | grep -qE "GET.*/worksheets/[^/]+/data"; then
  echo "  Instead of: curl -X GET .../worksheets/{id}/data"
  echo "  Use tool:   get_worksheet_data"
elif echo "$COMMAND" | grep -qE "GET.*/llm-models"; then
  echo "  Instead of: curl -X GET .../llm-models"
  echo "  Use tool:   list_llm_models"
elif echo "$COMMAND" | grep -qE "columns/[^/]+/reprocess"; then
  echo "  Instead of: curl -X POST .../columns/{id}/reprocess"
  echo "  Use tool:   reprocess_column"
else
  echo "  Check available MCP tools: the plugin has 43 tools covering all Grid API endpoints."
  echo "  MCP tools provide input validation, auth handling, and consistent error messages."
fi

echo ""
echo "MCP tools handle authentication, path construction, and error handling automatically."
echo "--- End Warning ---"
exit 0
```

---

## hooks.json Registration

**File:** `.claude/hooks.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash .claude/hooks/session-init.sh",
        "description": "Validate Salesforce environment variables and test Grid API connection"
      }
    ],
    "PreToolUse": [
      {
        "type": "command",
        "command": "python3 .claude/hooks/validate-config.py",
        "matcher": {
          "tool_name": "add_column|edit_column"
        },
        "description": "Validate column config structure before API call (nested config, columnType casing, modelConfig)"
      }
    ],
    "PostToolUse": [
      {
        "type": "command",
        "command": "bash .claude/hooks/post-api-call.sh",
        "matcher": {
          "tool_name": "add_column|edit_column|delete_column|paste_data|update_cells|trigger_row_execution|reprocess_column|save_column|create_worksheet"
        },
        "description": "Auto-render grid state after mutation tools so the user always sees current state"
      },
      {
        "type": "command",
        "command": "bash .claude/hooks/detect-grid-curl.sh",
        "matcher": {
          "tool_name": "Bash"
        },
        "description": "Detect raw curl commands to Grid API and suggest MCP tools instead"
      }
    ]
  }
}
```

---

## File Summary

| File | Type | Purpose |
|------|------|---------|
| `skills/grid-new/SKILL.md` | Slash command | Create grid from NL description |
| `skills/grid-status/SKILL.md` | Slash command | Show grid state and column health |
| `skills/grid-run/SKILL.md` | Slash command | Execute/reprocess cells |
| `skills/grid-results/SKILL.md` | Slash command | Evaluation results and metrics |
| `skills/grid-add/SKILL.md` | Slash command | Add column to active grid |
| `skills/grid-debug/SKILL.md` | Slash command | Investigate failures |
| `skills/grid-compare/SKILL.md` | Slash command | Compare two worksheets |
| `skills/grid-export/SKILL.md` | Slash command | Export data to CSV/JSON |
| `skills/grid-list/SKILL.md` | Slash command | List workbooks tree |
| `skills/grid-models/SKILL.md` | Slash command | List available LLM models |
| `.claude/hooks.json` | Hook config | Register all 4 hooks |
| `.claude/hooks/session-init.sh` | SessionStart hook | Validate SF env vars, test connection |
| `.claude/hooks/validate-config.py` | PreToolUse hook | Catch config errors before API call |
| `.claude/hooks/post-api-call.sh` | PostToolUse hook | Auto-render grid state after mutations |
| `.claude/hooks/detect-grid-curl.sh` | PostToolUse hook | Intercept curl, suggest MCP tools |
