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

## Column Type Detection

| User Says | Inferred Type |
|-----------|---------------|
| "AI column", "generate", "summarize" | AI |
| "evaluation", "score", "assess" | Evaluation |
| "agent test", "test agent" | AgentTest |
| "text column", "input column" | Text |
| "extract field", "reference" | Reference |
| "query objects", "salesforce data" | Object |
| "run flow", "invoke" | InvocableAction |

## Examples

- `/grid-add evaluation column for coherence on the Agent Output column`
- `/grid-add AI column "Summary" using GPT 4 Omni: summarize {Account Name} in {Industry}`
- `/grid-add reference column extracting "topic" field from Agent Output`
