---
name: agentforce-grid
description: Use this skill whenever users mention Grid, AI Workbench, workbooks, worksheets, or Grid columns. Also use when users want to: test an Agentforce agent with different utterances or evaluate agent responses; enrich Salesforce records using AI-generated content; add AI, Formula, Evaluation, Object, Reference, or Text columns to a worksheet; import CSV data into a Grid; compare agent versions with evaluation columns; query SObjects or Data Cloud DMOs in a grid context; or debug a failing AI/Agent column config. This skill manages the Grid Connect API for column creation, cell operations, row execution, and paste/import workflows. Do NOT trigger for generic Salesforce tasks (Apex, Flows, dashboards, reports, validation rules, Einstein Bots).
---

# Agentforce Grid API Helper

Agentforce Grid (AF Grid), also known as AI Workbench, is a spreadsheet-like interface for AI operations in Salesforce. It allows you to create worksheets with different column types to test agents, run prompts, query data, and evaluate AI outputs.

## Hierarchy

```
Workbook → Worksheet → Columns → Rows → Cells
```

## API Base URL

```
/services/data/v66.0/public/grid/...
```

## SF CLI Setup & Authentication

Before using the Grid API, you need to authenticate to a Salesforce org using the Salesforce CLI.

### Check if SF CLI is Installed

```bash
sf --version
```**IMPORTANT**: When the user provides an "org domain", this refers to the `--instance-url` parameter. Common formats

If the command fails, SF CLI is not installed.

### Install SF CLI (if needed)

**macOS (Homebrew):**
```bash
brew install salesforce-cli
```

**macOS/Linux (npm):**
```bash
npm install -g @salesforce/cli
```

**Manual installation:**
Visit https://developer.salesforce.com/tools/salesforcecli and download the installer for your platform.

### Authenticate to an Org

**IMPORTANT**: When the user provides an "org domain", this refers to the `--instance-url` parameter. Common formats:
- Lightning domain: `orgfarm-a06b541775.test1.lightning.pc-rnd.force.com`
- Instance URL: `https://sdb3.test1.pc-rnd.pc-aws.salesforce.com/`
- My Domain: `https://mycompany.my.salesforce.com`
- Sandbox: `https://mycompany--sandbox.sandbox.my.salesforce.com`

**Note**: SF CLI does NOT accept lightning domains. If a lightning domain is provided, ask the user for the actual instance URL (usually in the format `https://sdbX.testX.pc-rnd.pc-aws.salesforce.com/` for internal orgs).

**Production/Developer Edition:**
```bash
sf org login web --alias my-org
```

**Sandbox:**
```bash
sf org login web --alias my-sandbox --instance-url https://test.salesforce.com
```

**With specific instance URL (org domain):**
```bash
sf org login web --alias my-org --instance-url https://sdb3.test1.pc-rnd.pc-aws.salesforce.com
```

**Using JWT (for CI/CD):**
```bash
sf org login jwt --client-id YOUR_CONSUMER_KEY --jwt-key-file server.key --username your@email.com --alias my-org
```

### List Authenticated Orgs

```bash
sf org list
```

### Get Access Token for API Calls

```bash
sf org display --target-org my-org --json
```

The response includes `accessToken` and `instanceUrl` needed for API calls.

### Set Default Org

```bash
sf config set target-org my-org
```

### Quick Auth Check

To verify authentication is working:
```bash
sf org display
```

This should show details of the currently authenticated org including username, instance URL, and org ID.

## Column Types Quick Reference

| Type | `type` value | `columnType` in referenceAttributes | Use Case |
|------|--------------|-------------------------------------|----------|
| AI | `"Ai"` (canonical) or `"AI"` | `"AI"` | LLM text generation with custom prompts |
| Agent | `"Agent"` | `"Agent"` | Run agent conversations with context variables |
| AgentTest | `"AgentTest"` | `"AgentTest"` | Test agent with input utterances from a column |
| Formula | `"Formula"` | `"Formula"` | Computed values using formula expressions |
| Object | `"Object"` | `"Object"` | Query Salesforce SObjects |
| PromptTemplate | `"PromptTemplate"` | `"PromptTemplate"` | Execute GenAI prompt templates |
| Action | `"Action"` | `"Action"` | Execute platform actions |
| InvocableAction | `"InvocableAction"` | `"InvocableAction"` | Execute Flows or Apex invocable actions |
| Reference | `"Reference"` | `"Reference"` | Extract fields from other columns using JSON path |
| Text | `"Text"` | `"Text"` | Static/editable text input or CSV import |
| Evaluation | `"Evaluation"` | `"Evaluation"` | Evaluate agent/prompt outputs with 13 evaluation types |
| DataModelObject | `"DataModelObject"` | `"DataModelObject"` | Query Data Cloud DMOs |

**Casing note**: The server is case-insensitive — PascalCase (`"Object"`), UPPER_CASE (`"OBJECT"`), and variants all work for `type` and `columnType`. However, the API **returns** different casing depending on context: column `type` comes back PascalCase (`"Object"`, `"AI"`), but `referenceAttributes.columnType` comes back UPPER_CASE (`"OBJECT"`, `"AGENT_TEST"`). Object column field `type` values must be UPPER_CASE (`"STRING"`, not `"String"`). When in doubt, both PascalCase and UPPER_CASE are safe.

For complete JSON configurations: [Column Configs Reference](references/column-configs.md)

## Evaluation Types Quick Reference

| Type | Requires Reference Column | Supported Inputs |
|------|---------------------------|------------------|
| `COHERENCE` | No | Agent, AgentTest, PromptTemplate |
| `CONCISENESS` | No | Agent, AgentTest, PromptTemplate |
| `FACTUALITY` | No | Agent, AgentTest, PromptTemplate |
| `INSTRUCTION_FOLLOWING` | No | Agent, AgentTest, PromptTemplate |
| `COMPLETENESS` | No | Agent, AgentTest, PromptTemplate |
| `RESPONSE_MATCH` | **Yes** | Agent, AgentTest |
| `TOPIC_ASSERTION` (UI: "Subagent") | **Yes** | Agent, AgentTest |
| `ACTION_ASSERTION` | **Yes** | Agent, AgentTest |
| `LATENCY_ASSERTION` | No | Agent, AgentTest |
| `BOT_RESPONSE_RATING` | **Yes** | Agent, AgentTest |
| `EXPRESSION_EVAL` | No | Agent, AgentTest |
| `CUSTOM_LLM_EVALUATION` | **Yes** | Agent, AgentTest |
| `TASK_RESOLUTION` | No | Agent, AgentTest (conversation-level only) |

For complete evaluation guidance: [Evaluation Types Reference](references/evaluation-types.md)

## Status Values

| Status | API Value | Description |
|--------|-----------|-------------|
| NEW | `New` | Cell not yet processed |
| IN_PROGRESS | `InProgress` | Processing in progress |
| COMPLETE | `Complete` | Processing succeeded |
| FAILED | `Failed` | Processing failed |
| SKIPPED | `Skipped` | Skipped (e.g., null reference value) |
| STALE | `Stale` | Needs reprocessing |
| EMPTY | `Empty` | Placeholder cell |
| MISSING_INPUT | `MissingInput` | A required reference column had no data for this row |

## Common Use Case Patterns

### Pattern 1: Agent Testing Pipeline

Test an agent with different utterances and evaluate responses.

```
1. Text column: "Test Utterances" - your test cases
2. Text column: "Expected Responses" - ground truth (optional)
3. AgentTest column: "Agent Output" - runs the agent
4. Evaluation column: "Response Match" (RESPONSE_MATCH) - compare to expected
5. Evaluation column: "Quality Score" (COHERENCE) - assess quality
```

**AgentTest Column Config (with correct nested structure):**
```json
{
  "name": "Agent Output",
  "type": "AgentTest",
  "config": {
    "type": "AgentTest",
    "numberOfRows": 50,
    "queryResponseFormat": {"type": "EACH_ROW"},
    "autoUpdate": true,
    "config": {
      "autoUpdate": true,
      "agentId": "0XxRM000000xxxxx",
      "agentVersion": "0XyRM000000xxxxx",
      "inputUtterance": {
        "columnId": "utterance-col-id",
        "columnName": "Test Utterances",
        "columnType": "Text"
      },
      "contextVariables": []
    }
  }
}
```

### Pattern 2: Data Enrichment with AI

Enrich Salesforce records with AI-generated content.

```
1. Object column: "Accounts" - query records
2. AI column: "Summary" - generate summaries using account fields
```

**AI Column Config (with correct nested structure):**
```json
{
  "name": "Company Summary",
  "type": "AI",
  "config": {
    "type": "AI",
    "numberOfRows": 50,
    "queryResponseFormat": {"type": "EACH_ROW"},
    "autoUpdate": true,
    "config": {
      "autoUpdate": true,
      "mode": "llm",
      "modelConfig": {
        "modelId": "sfdc_ai__DefaultGPT4Omni",
        "modelName": "sfdc_ai__DefaultGPT4Omni"
      },
      "instruction": "Write a brief summary for this company:\nName: {$1}\nIndustry: {$2}",
      "referenceAttributes": [
        {"columnId": "col-1", "columnName": "Accounts", "columnType": "Object", "fieldName": "Name"},
        {"columnId": "col-1", "columnName": "Accounts", "columnType": "Object", "fieldName": "Industry"}
      ],
      "responseFormat": {
        "type": "PLAIN_TEXT",
        "options": []
      }
    }
  }
}
```

### Pattern 3: Flow/Apex Testing

Test a Flow with different inputs and extract outputs.

```
1. Text column: "Input 1"
2. Text column: "Input 2"
3. InvocableAction column: "Flow Result"
4. Reference column: "Output Field" - extract specific output
```

For complete workflow examples: [Use Case Patterns Reference](references/use-case-patterns.md)

## API Endpoints Quick Reference

### Workbooks
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/workbooks` | List all workbooks |
| POST | `/workbooks` | Create workbook |
| GET | `/workbooks/{id}` | Get workbook |
| DELETE | `/workbooks/{id}` | Delete workbook |

### Worksheets
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/worksheets` | Create worksheet |
| GET | `/worksheets/{id}` | Get worksheet |
| PUT | `/worksheets/{id}` | Update worksheet |
| DELETE | `/worksheets/{id}` | Delete worksheet |
| GET | `/worksheets/{id}/data` | Get all data |

### Columns
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/worksheets/{wsId}/columns` | Add column |
| PUT | `/worksheets/{wsId}/columns/{colId}` | Update column |
| DELETE | `/worksheets/{wsId}/columns/{colId}` | Delete column |
| POST | `/worksheets/{wsId}/columns/{colId}/save` | Save without processing |
| POST | `/worksheets/{wsId}/columns/{colId}/reprocess` | Reprocess cells |
| GET | `/worksheets/{wsId}/columns/{colId}/data` | Get column cell data |

**IMPORTANT:** Column operations use `/worksheets/{wsId}/columns/{colId}/...` path, NOT `/columns/{colId}/...`.

### Cells
| Method | Endpoint | Description |
|--------|----------|-------------|
| PUT | `/worksheets/{id}/cells` | Update cells |
| POST | `/worksheets/{id}/paste` | Paste data matrix |
| POST | `/worksheets/{id}/trigger-row-execution` | Run processing |

### Paste Data Format (IMPORTANT)

The paste endpoint uses a `matrix` field (not `data`):

```json
{
  "startColumnId": "column-id",
  "startRowId": "row-id",
  "matrix": [
    [{"displayContent": "row 1 col 1"}, {"displayContent": "row 1 col 2"}],
    [{"displayContent": "row 2 col 1"}, {"displayContent": "row 2 col 2"}]
  ]
}
```

For complete API documentation: [API Endpoints Reference](references/api-endpoints.md)

## Important API Behavior Notes

### Use `/data` Endpoint for Reading State
`GET /worksheets/{id}` may return empty columns/rows/cells. Always use `GET /worksheets/{id}/data` to reliably read the full worksheet state including all columns, rows, and cell values.

### Column Creation May Return Errors But Succeed
Column creation can return error messages (like "Unable to start processing workflow") yet still create the column successfully. Always verify with `GET /worksheets/{id}/data` after creation.

### Default Row Count
When creating a Text column, the API automatically generates 200 rows by default.

## Critical Configuration Rules

### Nested Config Structure (MOST IMPORTANT)

**ALL column configs require the nested structure with `type` field - even Text columns. An empty `config: {}` will fail:**

```json
{
  "name": "Column Name",
  "type": "AI",
  "config": {
    "type": "AI",
    "queryResponseFormat": {"type": "EACH_ROW"},
    "autoUpdate": true,
    "config": {
      "autoUpdate": true,
      // ... column-specific fields
    }
  }
}
```

**CRITICAL: Even simple Text columns need the nested config:**
```json
{
  "name": "My Text Column",
  "type": "Text",
  "config": {
    "type": "Text",
    "autoUpdate": true,
    "config": {
      "autoUpdate": true
    }
  }
}
```

### queryResponseFormat

**When worksheet already has data, new columns MUST use `EACH_ROW`:**

| Scenario | queryResponseFormat |
|----------|---------------------|
| Adding AI column to existing data | `{"type": "EACH_ROW"}` |
| Adding Agent column to existing utterances | `{"type": "EACH_ROW"}` |
| Importing new Object records | `{"type": "WHOLE_COLUMN", "splitByType": "OBJECT_PER_ROW"}` |

### modelConfig (Required for AI/PromptTemplate)

**Use the model `name` for both `modelId` and `modelName` fields:**

```json
"modelConfig": {
  "modelId": "sfdc_ai__DefaultGPT4Omni",
  "modelName": "sfdc_ai__DefaultGPT4Omni"
}
```

**Recommended models (active, high-capability):**

| Model Name | Label | Max Tokens |
|------------|-------|------------|
| `sfdc_ai__DefaultGPT4Omni` | GPT 4 Omni | 16384 |
| `sfdc_ai__DefaultGPT4OmniMini` | GPT 4 Omni Mini | 16384 |
| `sfdc_ai__DefaultGPT41` | GPT 4.1 | 32768 |
| `sfdc_ai__DefaultGPT41Mini` | GPT 4.1 Mini | 32768 |
| `sfdc_ai__DefaultGPT5` | GPT 5 | 128000 |
| `sfdc_ai__DefaultGPT5Mini` | GPT 5 Mini | 128000 |
| `sfdc_ai__DefaultO3` | O3 | 100000 |
| `sfdc_ai__DefaultO4Mini` | O4 Mini | 100000 |
| `sfdc_ai__DefaultOpenAIGPT4OmniMini` | OpenAI GPT 4 Omni Mini | 16384 |
| `sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet` | Claude Sonnet 4.5 on Amazon | 8192 |
| `sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet` | Claude Sonnet 4 on Amazon | 8192 |
| `sfdc_ai__DefaultBedrockAnthropicClaude45Haiku` | Claude Haiku 4.5 on Amazon | 8192 |
| `sfdc_ai__DefaultVertexAIGemini25Flash001` | Google Gemini 2.5 Flash | 65536 |
| `sfdc_ai__DefaultVertexAIGemini25FlashLite001` | Google Gemini 2.5 Flash Lite | 65536 |
| `sfdc_ai__DefaultVertexAIGeminiPro25` | Google Gemini 2.5 Pro | 65536 |
| `sfdc_ai__DefaultBedrockAmazonNovaLite` | Amazon Nova Lite | 5000 |
| `sfdc_ai__DefaultBedrockAmazonNovaPro` | Amazon Nova Pro | 5000 |

Use `GET /llm-models` to list all available models in the org.

### ReferenceAttribute (Use PascalCase columnType)

```json
{
  "columnId": "1W5SB000005zk6H0AQ",
  "columnName": "Salesforce",
  "columnType": "Object",
  "fieldName": "Name"
}
```

### Column Ordering

Columns have a `precedingColumnId` field that controls display order. When creating columns, they are appended after the last column by default. The response includes `precedingColumnId` to indicate position.

### Other Validation Rules

1. **AI columns**: Require `mode: "llm"` and `responseFormat` with `options` array
2. **ContextVariable**: Must have EITHER `value` OR `reference`, not both
3. **Evaluation columns**: Types requiring reference columns must include `referenceColumnReference`
4. **Text columns**: CANNOT use empty `config: {}` - must include `type` field in config

## Role-Aware Column Suggestions

Before suggesting columns, understand the user's role and intent. Ask "What are you trying to accomplish?" if unclear.

| Role | Common Use Cases | Suggested Column Pipeline |
|------|-----------------|--------------------------|
| Sales Rep | Opportunity risk, competitive intel, account priority | Object(Opps) → AI(risk/priority, SINGLE_SELECT) |
| CSM | Customer health, check-in emails, case trends | Object(Accounts/Cases) → AI(analysis) → AI(email, PLAIN_TEXT) |
| RevOps | Pipeline quality, forecast accuracy, data hygiene | Object(Opps) → AI(quality flag, SINGLE_SELECT: Clean/Minor Issues/Needs Fix) |
| Developer/QA | Agent testing, flow testing, prompt evaluation | Text(utterances) → AgentTest → Evaluation |
| Admin | Data enrichment, bulk updates, list view analysis | Object/ListView → AI → Action(RecordUpdate) |

Always tailor suggestions to the user's role. A RevOps user needs data quality flags (SINGLE_SELECT for filtering), not outreach emails. A CSM needs customer-facing outputs, not pipeline metrics.

## Before Adding a Column

Always check existing grid state via `get_worksheet_data` before adding columns.
Do NOT add a column if:
- A column with the same name already exists
- A column with the same purpose already exists (even with a different name)
- The data is already available in an existing column (use a Reference column to extract it instead)

If the user wants to modify an existing column, use the typed mutation tools (`edit_ai_prompt`, `change_model`, etc.) or `edit_column` — don't create a duplicate.

## Choosing the Right Column Type and Response Format

| Need | Column Type | Format | Why |
|------|------------|--------|-----|
| Filter/sort by category | AI | SINGLE_SELECT | Limited options enable filtering and scanning |
| Categorize with fixed labels | AI | SINGLE_SELECT | Mutually exclusive options, consistent output |
| Generate free-text (email, summary) | AI | PLAIN_TEXT | Open-ended content needs free-form output |
| Deterministic computation | Formula | N/A | No LLM needed — exact, reproducible results |
| Extract specific field from JSON | Reference | N/A | Zero LLM cost, exact extraction |
| Score/rate on a scale | AI | SINGLE_SELECT | e.g., High/Medium/Low for scannable output |

Key principle: If the output will be used for filtering, sorting, or downstream comparison, use SINGLE_SELECT. Free-text output defeats scanability.

## Dependency Rules

A column CANNOT reference a column that depends on it. The dependency graph must be acyclic.

Before adding a reference, trace the dependency chain: if Column A → B → C, then C cannot reference A.

Column creation order must follow the dependency DAG:
1. Source data (Text, Object, DataModelObject) — no dependencies
2. Processing (AI, Agent, AgentTest, PromptTemplate, InvocableAction) — depend on source
3. Extraction (Reference) — depend on processing columns
4. Assessment (Evaluation) — depend on AgentTest/Agent/PromptTemplate
5. Formula — can appear at any level but must only reference existing columns

## Leverage Existing Resources

Before creating an AI column, check if existing resources handle the task better:
1. **Prompt Templates** (`get_prompt_templates`): Use PromptTemplate column — pre-built, tested prompts
2. **Flows/Apex** (`get_invocable_actions`): Use InvocableAction column — deterministic logic
3. **List Views** (`get_list_views`): Use list view SOQL in Object column's advancedMode
4. **Existing Columns**: Use Reference column to extract data already in another column

AI columns should be reserved for tasks requiring LLM reasoning — not for tasks that platform capabilities handle more reliably.

## MCP Tool Quick Reference

All tools are accessed via MCP with the prefix `mcp__grid-connect-mcp__`. The table below maps operations to tool names.

### Workbook Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| List workbooks | `get_workbooks` | -- |
| Create workbook | `create_workbook` | `name` |
| Get workbook details | `get_workbook` | `workbookId` |
| Delete workbook | `delete_workbook` | `workbookId` |

### Worksheet Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| Create worksheet | `create_worksheet` | `name`, `workbookId` |
| Get worksheet metadata | `get_worksheet` | `worksheetId` |
| Get full worksheet data | `get_worksheet_data` | `worksheetId` |
| Get data (generic format) | `get_worksheet_data_generic` | `worksheetId` |
| Update worksheet name | `update_worksheet` | `worksheetId`, `name` |
| Delete worksheet | `delete_worksheet` | `worksheetId` |
| Add rows | `add_rows` | `worksheetId`, `numberOfRows`, `anchorRowId?`, `position?` |
| Delete rows | `delete_rows` | `worksheetId`, `rowIds` |
| Import CSV | `import_csv` | `worksheetId`, `documentId`, `includeHeaders` |
| Run worksheet | `run_worksheet` | `config` (JSON string with worksheetId, row inputs, column config; optional `runStrategy`: omit for parallel, `"ColumnByColumn"` for sequential) |
| Get run worksheet job | `get_run_worksheet_job` | `jobId` |

### Column Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| Add column | `add_column` | `worksheetId`, `name`, `type`, `config` (JSON string) |
| Edit column (+ reprocess) | `edit_column` | `columnId`, `config` (JSON string) |
| Save column (no reprocess) | `save_column` | `columnId`, `config` (JSON string) |
| Reprocess column | `reprocess_column` | `columnId`, `config` (JSON string) |
| Delete column | `delete_column` | `columnId`, `worksheetId` |
| Get column cell data | `get_column_data` | `columnId` |
| Create column from NL | `create_column_from_utterance` | `worksheetId`, `utterance` |
| Generate JSON path | `generate_json_path` | `worksheetId`, `userInput`, `variableName`, `dataType` |

### Cell Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| Update cells | `update_cells` | `worksheetId`, `cells` (JSON string -- use `fullContent` not `displayContent`) |
| Paste data matrix | `paste_data` | `worksheetId`, `startColumnId`, `startRowId`, `matrix` (JSON string) |
| Trigger row execution | `trigger_row_execution` | `worksheetId`, `config` (JSON string -- see trigger types below) |
| Validate formula | `validate_formula` | `worksheetId`, `config` (JSON string) |
| Generate IA input | `generate_ia_input` | `worksheetId`, `config` (JSON string) |

### Agent Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| List agents | `get_agents` | `includeDrafts?` |
| Get agent context variables | `get_agent_variables` | `versionId` |

### Data Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| List SObjects | `get_sobjects` | -- |
| Get SObject fields (display) | `get_sobject_fields_display` | `sobjectList` (JSON array string) |
| Get SObject fields (filter) | `get_sobject_fields_filter` | `sobjectList` (JSON array string) |
| Get SObject fields (update) | `get_sobject_fields_record_update` | `sobjectList` (JSON array string) |
| List dataspaces | `get_dataspaces` | -- |
| List DMOs in dataspace | `get_data_model_objects` | `dataspace` |
| Get DMO fields | `get_data_model_object_fields` | `dataspace`, `dmoName` |

### Metadata Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| List column types | `get_column_types` | -- |
| List LLM models | `get_llm_models` | -- |
| List supported types | `get_supported_types` | -- |
| List evaluation types | `get_evaluation_types` | -- |
| List formula functions | `get_formula_functions` | -- |
| List formula operators | `get_formula_operators` | -- |
| List invocable actions | `get_invocable_actions` | -- |
| Describe invocable action | `describe_invocable_action` | `actionName`, `actionType`, `url` |
| List prompt templates | `get_prompt_templates` | -- |
| Get prompt template detail | `get_prompt_template` | `promptTemplateDevName` |
| List list views | `get_list_views` | -- |
| Get list view SOQL | `get_list_view_soql` | `listViewId`, `sObjectType` |
| Natural language to SOQL | `generate_soql` | `text` |
| Generate test columns | `generate_test_columns` | `testData` (JSON string) |

### Workflow / Orchestration Tools

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| Create workbook + worksheet | `create_workbook_with_worksheet` | `workbookName`, `worksheetName` |
| Run worksheet (sequential) | `run_worksheet` | Include `"runStrategy": "ColumnByColumn"` in `config` to run columns one at a time instead of in parallel |
| Poll until processing done | `poll_worksheet_status` | `worksheetId`, `maxAttempts?`, `intervalMs?` |
| Get worksheet status summary | `get_worksheet_summary` | `worksheetId` |
| Set up full agent test suite | `setup_agent_test` | `agentId`, `agentVersion`, `utterances`, `evaluationTypes?`, `expectedResponses?`, `isDraft?` |

### Typed Mutations & Convenience Tools

Prefer these over raw `edit_column` — they auto-fetch the current config, merge your changes, and handle references correctly.

| Tool | Description |
|------|-------------|
| `apply_grid` | Create/update a full grid from a YAML DSL specification — the most powerful orchestration tool |
| `edit_ai_prompt` | Modify an AI column's prompt, model, or response format. Auto-resolves `{ColumnName}` references |
| `edit_agent_config` | Modify Agent or AgentTest column config (agentId, utterance, context variables) |
| `edit_prompt_template` | Modify PromptTemplate column (template name, input mappings, model) |
| `change_model` | Switch LLM model on an AI or PromptTemplate column |
| `add_evaluation` | Add evaluation column with auto-wired references to target and expected columns |
| `update_filters` | Update Object or DataModelObject query filters |
| `reprocess` | Reprocess a column or entire worksheet with filter (all/failed/stale) |
| `get_url` | Generate Lightning Experience URLs for grid, record, flow, or setup pages |

### Column Operation Distinctions

| Tool | What It Does | When to Use |
|------|-------------|-------------|
| `edit_column` | Updates config AND reprocesses all cells | Changing prompt, model, references, or any functional config |
| `save_column` | Updates config WITHOUT reprocessing | Renaming, adjusting display settings, non-functional changes |
| `reprocess_column` | Reprocesses cells with current config | Source data changed, retrying after failures |

## Trigger Row Execution Types

The `trigger_row_execution` tool accepts different trigger types via the `config` JSON parameter:

### RUN_ROW -- Process Specific Rows

Processes all columns for the specified rows. Most common trigger type.

```json
{
  "trigger": "RUN_ROW",
  "rowIds": ["row-id-1", "row-id-2", "row-id-3"]
}
```

### RUN_SELECTION -- Process Specific Cells

Processes only the specified cells (by cell ID). Use when you want to reprocess individual cells rather than whole rows.

```json
{
  "trigger": "RUN_SELECTION",
  "seedCellIds": ["cell-id-1", "cell-id-2"]
}
```

### EDIT -- Re-trigger After Cell Edit

Signals that specific cells were edited and dependent columns should reprocess. The system determines which downstream columns need re-evaluation.

```json
{
  "trigger": "EDIT",
  "editedCells": [
    {
      "worksheetColumnId": "col-id",
      "worksheetRowId": "row-id"
    }
  ]
}
```

### PASTE -- Re-trigger After Paste Operation

Signals that data was pasted into the grid. Processes downstream columns for the pasted region.

```json
{
  "trigger": "PASTE",
  "startColumnId": "col-id",
  "matrix": [[{"displayContent": "value1"}], [{"displayContent": "value2"}]]
}
```

## Tool Orchestration Guidance

### Dependency Ordering Rules

Column creation must follow dependency order because each column may reference previous columns by ID:

1. **Text/Object/DataModelObject columns first** -- these provide source data
2. **Processing columns second** -- AI, Agent, AgentTest, PromptTemplate, InvocableAction (reference source columns)
3. **Reference columns third** -- extract fields from processing columns
4. **Evaluation columns last** -- evaluate processing column output
5. **Formula columns** -- can be added at any point but must reference existing columns

**Each `add_column` call returns the new column ID.** You must capture this ID before creating any column that references it.

### Why Parallel Column Creation Is Unsafe

Do NOT create multiple columns in parallel. Each column's config often references the IDs of previously created columns (via `referenceAttributes`, `inputColumnReference`, `referenceColumnReference`, etc.). Creating columns concurrently means you will not have the IDs needed for cross-references.

Additionally, columns have an implicit ordering (`precedingColumnId`). The API determines position based on the current worksheet state at creation time. Parallel creation leads to unpredictable ordering.

**Always create columns sequentially, one at a time.**

### State Refresh Patterns

Call `get_worksheet_data` (or `get_worksheet_summary` for a compact view) after:

- Adding a column (to get the new column ID and row IDs)
- Pasting data (to confirm rows were populated)
- Triggering execution (to check processing status)
- Any operation that may have side effects (column creation can auto-create rows)

For long-running operations, use `poll_worksheet_status` instead of manual get/sleep loops.

### Error Retry Patterns

1. **Column creation returns error but column exists**: Column creation can return error messages like "Unable to start processing workflow" yet still create the column. Always call `get_worksheet_data` to verify.
2. **Cell processing failures**: Use `reprocess_column` to retry all cells, or `trigger_row_execution` with `RUN_ROW` and the specific failed row IDs.
3. **Config validation errors**: The MCP server validates column configs before sending to the API. Fix the config based on the error message and retry.
4. **Rate limiting**: If you get rate limit errors, wait and retry. The `poll_worksheet_status` tool has built-in intervals.
5. **Duplicate column name**: The server rejects duplicate column names with error `DuplicateColumnName`. Always check existing columns before creating.

## Known Limits

- 100 test suites per org
- 20 test runs per test suite
- 10 concurrent test runs per org
- AI column batches: 25 rows per batch, 4 parallel threads for evaluations

## Conditional Execution (runIfExpression)

All column types support conditional execution via `runIfExpression` in the base config. This is a SEL expression evaluated per row -- if false, the cell is skipped (status `Skipped`).

Example: Only process rows where Amount > 10000:
```json
"runIfExpression": "{$1} > 10000",
"runIfReferenceAttributes": [{"columnId": "col-A", "columnName": "Amount", "columnType": "Reference"}]
```

## Reference Handling: isRequired and MissingInput

By default, `referenceAttributes` are optional -- if the referenced cell is empty, an empty string is substituted. Set `isRequired: true` on a referenceAttribute to block execution when the reference is missing. When a required reference is missing, the cell gets status `MissingInput` instead of processing.


## Reference Documentation

- **[Column Configurations](references/column-configs.md)**: Complete JSON configs for all 12 column types
- **[Evaluation Types](references/evaluation-types.md)**: All 13 evaluation types with detailed guidance
- **[API Endpoints](references/api-endpoints.md)**: Complete endpoint documentation with examples
- **[Use Case Patterns](references/use-case-patterns.md)**: Common workflows with MCP tool call examples

For detailed user interaction models, conversation examples, CI/CD integration patterns, and slash command specifications, read `references/workflow-patterns.md`.
