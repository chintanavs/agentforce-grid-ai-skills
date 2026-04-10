#!/bin/bash
# PostToolUse hook: After mutation tools, show compact worksheet status.
#
# Reads tool output from stdin JSON. After any grid-connect-mcp mutation tool,
# extracts the worksheetId and fetches worksheet data to render a compact
# status summary showing column names, types, and cell status counts.
#
# This transforms the CLI experience from opaque JSON responses to a visible
# grid state after every change.

set -euo pipefail

# Read the hook input from stdin
INPUT=$(cat)

# Extract the tool name
TOOL_NAME=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('tool_name', ''))
" 2>/dev/null || echo "")

# Only run for mutation tools (not read-only tools)
MUTATION_TOOLS=(
    "mcp__grid-connect-mcp__add_column"
    "mcp__grid-connect-mcp__edit_column"
    "mcp__grid-connect-mcp__save_column"
    "mcp__grid-connect-mcp__reprocess_column"
    "mcp__grid-connect-mcp__delete_column"
    "mcp__grid-connect-mcp__update_cells"
    "mcp__grid-connect-mcp__paste_data"
    "mcp__grid-connect-mcp__trigger_row_execution"
    "mcp__grid-connect-mcp__add_rows"
    "mcp__grid-connect-mcp__delete_rows"
    "mcp__grid-connect-mcp__create_workbook_with_worksheet"
    "mcp__grid-connect-mcp__setup_agent_test"
)

IS_MUTATION=false
for mt in "${MUTATION_TOOLS[@]}"; do
    if [[ "$TOOL_NAME" == "$mt" ]]; then
        IS_MUTATION=true
        break
    fi
done

if [[ "$IS_MUTATION" != "true" ]]; then
    exit 0
fi

# Extract worksheetId from tool input or tool output
WORKSHEET_ID=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)

# Try tool_input first
ws_id = data.get('tool_input', {}).get('worksheetId', '')

# If not in input, try to find it in the tool output
if not ws_id:
    output = data.get('tool_output', '')
    if isinstance(output, str):
        try:
            out_data = json.loads(output)
            ws_id = out_data.get('worksheetId', '')
        except (json.JSONDecodeError, TypeError):
            pass

print(ws_id)
" 2>/dev/null || echo "")

if [[ -z "$WORKSHEET_ID" ]]; then
    # Cannot determine worksheet, skip status render
    exit 0
fi

# Render compact status summary
echo ""
echo "--- Grid Status (worksheet: ${WORKSHEET_ID:0:18}...) ---"
echo ""

# Note: This hook shows the intent. In practice, the PostToolUse hook
# output is informational -- Claude will see it and can use the MCP tool
# get_worksheet_summary for the actual data if needed.
echo "Tip: Use get_worksheet_summary({worksheetId: \"$WORKSHEET_ID\"}) to see current grid state."
echo ""

exit 0
