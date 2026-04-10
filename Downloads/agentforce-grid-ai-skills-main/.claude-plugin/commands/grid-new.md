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
2. For standard agent testing scenarios, prefer the `setup_agent_test` composite tool which handles the full pipeline in one call.
3. For custom grids, execute manually:
   a. Call `create_workbook_with_worksheet` MCP tool to create both resources at once.
   b. For each column, call `add_column` with the correct nested config structure:
      - Text columns: `config.type: "Text"` with nested `config.config.autoUpdate: true`
      - AI columns: include `modelConfig`, `instruction`, `referenceAttributes`, `responseFormat`
      - Agent/AgentTest columns: include `agentId`, `inputUtterance` references
      - Evaluation columns: include evaluation `type` and `referenceColumnReference` where required
   c. If the description includes test data, call `paste_data` to populate Text columns.
   d. Call `get_worksheet_data` to confirm creation and display the resulting grid structure.

## Critical Config Rules

- ALL columns require the nested config structure: `{ type, config: { type, config: { ... } } }`
- Use mixed case for `type` field ("AI", "Text"), UPPERCASE for `columnType` in referenceAttributes ("OBJECT", "TEXT")
- AI/PromptTemplate columns MUST include `modelConfig` with both `modelId` and `modelName`
- When adding columns to a worksheet with existing data, use `queryResponseFormat: { type: "EACH_ROW" }`
- After each column creation, capture the returned `id` for use in dependent columns

## Examples

- `/grid-new agent test pipeline for ServiceBot with 10 utterances and response match evaluation`
- `/grid-new data enrichment grid: query Accounts, generate AI summaries using GPT 4 Omni`
- `/grid-new simple text grid with 3 columns: input, expected output, notes`
