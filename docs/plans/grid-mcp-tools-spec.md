> **Status:** ACTIVE | Phase 2-3 | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) Phase 2 (tools) and Phase 3 (resources)
> **What changed:** Updated tool count (57, not ~40). Noted that `setup_agent_test` is DONE and serves as the pattern for `apply_grid`. Noted that `edit_column` now validates via Zod. Model shorthand map aligns with hybrid plan 1.1. Migration path aligns with additive strategy.

# Grid MCP Tools & Resources Specification

**Date:** 2026-03-06
**Status:** ~~Design spec for Task #3~~ Active: Phase 2 (tools) and Phase 3 (resources)
**Scope:** `apply_grid` composite tool, typed mutation tools, MCP resources

---

## Overview

The current grid-connect MCP server exposes 57 tools (40+ core + 14 metadata + 5 agents + 4 workflow composites) for CRUD operations on the Grid API. The primary pain point: modifying existing columns requires the generic `edit_column` tool, which takes a raw JSON string (now Zod-validated against `ColumnConfigUnionSchema`). Claude must reconstruct the entire nested config structure every time it wants to change a single field (e.g., a prompt or model). This is error-prone and wastes context window space.

This spec introduces three enhancements:

1. **`apply_grid`** -- a composite tool that accepts a YAML DSL spec and creates/updates entire grids in one call
2. **Typed mutation tools** -- focused tools for common modifications that handle config expansion internally
3. **MCP Resources** -- read-only URI-based endpoints that give Claude just-in-time context about grid state

### Design Principles

- **Simple inputs, complex outputs**: Tools accept the minimum parameters needed; they build the nested JSON internally
- **Read via Resources, write via Tools**: Resources are for contextual reading; tools are for mutations
- **Backwards compatible**: New tools coexist with existing tools; no breaking changes
- **Fail fast**: Zod schemas validate inputs before any API call

---

## A. The `apply_grid` Composite Tool -- Phase 2.1

> **Phase 2.1.** Depends on Phase 1 (foundation libraries). Follow the `setup_agent_test` pattern from `src/tools/workflows.ts` -- it demonstrates sequential creation with ID threading, inline config construction, and dynamic reference wiring.

### Purpose

Create or update an entire grid from a single YAML DSL string. This replaces the multi-step workflow of creating a workbook, worksheet, columns, rows, and pasting data -- turning 10-15 tool calls into one.

### Tool Registration

```typescript
server.tool(
  "apply_grid",
  `Create or update an Agentforce Grid from a YAML specification. Accepts a declarative YAML
string describing the grid structure (workbook, worksheet, columns, data). Creates all resources
in dependency order, resolving column references automatically.

Use this tool when:
- Creating a new grid from scratch (omit worksheetId)
- Adding columns to an existing grid (provide worksheetId)
- Rebuilding a grid from a modified spec

The YAML format uses column names as references -- you never need to know column IDs.
Returns the created resource IDs (workbook, worksheet, columns) and any errors.`,
  {
    spec: z.string().describe(
      "YAML string defining the grid. Must include 'name' and 'columns' at minimum. " +
      "See grid://schema/dsl for the full DSL reference."
    ),
    worksheetId: z.string().optional().describe(
      "If provided, adds columns to this existing worksheet instead of creating a new one. " +
      "Existing columns are matched by name and updated; new columns are appended."
    ),
    dryRun: z.boolean().optional().describe(
      "If true, validates the spec and returns the execution plan without making API calls."
    ),
  },
  async ({ spec, worksheetId, dryRun }) => { /* implementation */ }
);
```

### Input Schema

The `spec` parameter accepts a YAML string. Full DSL grammar is defined in the DSL spec (Task #1). Minimal example:

```yaml
name: Lead Enrichment
columns:
  - name: Leads
    type: object
    object: Lead
    fields: [Id, Name, Email, Company]
    filters:
      - field: CreatedDate
        operator: GreaterThan
        value: LAST_N_DAYS:30

  - name: Summary
    type: ai
    prompt: "Summarize this lead: {Leads.Name} at {Leads.Company}"
    model: gpt-4o

  - name: Sentiment
    type: ai
    prompt: "Classify sentiment: {Summary}"
    model: gpt-4o
    response_format: single_select
    options: [Positive, Negative, Neutral]
```

### Output Schema

```typescript
interface ApplyGridResult {
  workbookId: string;
  worksheetId: string;
  columns: Record<string, string>;  // name -> columnId
  rowIds: string[];
  errors: ApplyGridError[];
  plan: PlanStep[];                  // what was executed (or would be in dryRun)
}

interface ApplyGridError {
  column: string;       // column name that failed
  step: string;         // "create" | "update" | "paste"
  message: string;
  recoverable: boolean;
}

interface PlanStep {
  action: "create_workbook" | "create_worksheet" | "create_column"
        | "update_column" | "add_rows" | "paste_data";
  target: string;       // name of the resource
  status: "success" | "failed" | "skipped" | "pending";
  details?: string;
}
```

### Example Output

```json
{
  "workbookId": "1W4RM000000ABCD",
  "worksheetId": "1W5RM000000EFGH",
  "columns": {
    "Leads": "1W5SB000005zk6H",
    "Summary": "1W5SB000005zk6I",
    "Sentiment": "1W5SB000005zk6J"
  },
  "rowIds": ["row-1", "row-2", "..."],
  "errors": [],
  "plan": [
    {"action": "create_workbook", "target": "Lead Enrichment", "status": "success"},
    {"action": "create_worksheet", "target": "Lead Enrichment", "status": "success"},
    {"action": "create_column", "target": "Leads", "status": "success"},
    {"action": "create_column", "target": "Summary", "status": "success"},
    {"action": "create_column", "target": "Sentiment", "status": "success"}
  ]
}
```

### Resolution Engine Integration

`apply_grid` delegates to the resolution engine (designed in Task #2). The flow:

1. Parse YAML string into typed DSL AST
2. Validate the AST (type-check column references, detect cycles)
3. Topologically sort columns by dependency
4. If `worksheetId` provided: fetch existing worksheet schema, match columns by name
5. Execute plan sequentially: create workbook/worksheet, then columns in dependency order
6. For each column: resolve `{ColumnName}` references to actual column IDs from prior steps
7. Return structured result with all created IDs

If `dryRun` is true, steps 4-6 are skipped and only the plan is returned.

### Incremental Apply (worksheetId provided)

When applying to an existing worksheet:
- Columns matched by name are **updated** (using `PUT /columns/{id}`)
- Columns not found in the worksheet are **created** (using `POST /worksheets/{id}/columns`)
- Existing columns not in the spec are **left unchanged** (never deleted implicitly)
- Column ordering follows the spec order

---

## B. Typed Mutation Tools

These tools replace the generic `edit_column` for common operations. Each tool:
1. Accepts simple, typed parameters (no raw JSON)
2. Fetches the current column config internally
3. Merges the user's changes into the existing config
4. Calls the appropriate API endpoint (PUT for edit+reprocess, POST /save for save-only)

### B.1 `edit_ai_prompt`

Change an AI column's prompt, references, model, or response format.

```typescript
server.tool(
  "edit_ai_prompt",
  `Modify an AI column's prompt or settings. Fetches the current config, applies your changes,
and reprocesses all cells. Use this instead of edit_column when you want to change what an
AI column does.

Only provide the parameters you want to change -- omitted parameters keep their current values.`,
  {
    columnId: z.string().describe("The AI column to modify"),
    instruction: z.string().optional().describe(
      "New prompt text. Use {ColumnName} to reference other columns. " +
      "Column references are resolved automatically from the worksheet schema."
    ),
    model: z.string().optional().describe(
      "Model shorthand (e.g., 'gpt-4o', 'claude-sonnet', 'gemini-flash') or full model ID. " +
      "See grid://models for available models."
    ),
    responseFormat: z.enum(["plain_text", "single_select"]).optional().describe(
      "Response format type"
    ),
    options: z.array(z.string()).optional().describe(
      "Options for single_select response format (e.g., ['Positive', 'Negative', 'Neutral'])"
    ),
    reprocess: z.boolean().optional().default(true).describe(
      "Whether to reprocess cells after updating. Set false to save config without reprocessing."
    ),
  },
  async ({ columnId, instruction, model, responseFormat, options, reprocess }) => {
    // 1. GET current column config from worksheet data
    // 2. Resolve {ColumnName} references in instruction to referenceAttributes
    // 3. Map model shorthand to full modelConfig
    // 4. Merge changes into existing config.config
    // 5. PUT (reprocess=true) or POST /save (reprocess=false)
  }
);
```

**Model shorthand mapping** (resolved internally):

| Shorthand | Full Model ID |
|-----------|--------------|
| `gpt-4o` | `sfdc_ai__DefaultGPT4Omni` |
| `gpt-4.1` | `sfdc_ai__DefaultGPT41` |
| `gpt-5` | `sfdc_ai__DefaultGPT5` |
| `gpt-5-mini` | `sfdc_ai__DefaultGPT5Mini` |
| `o3` | `sfdc_ai__DefaultO3` |
| `o4-mini` | `sfdc_ai__DefaultO4Mini` |
| `claude-sonnet-4.5` | `sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet` |
| `claude-sonnet-4` | `sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet` |
| `gemini-flash` | `sfdc_ai__DefaultVertexAIGemini25Flash001` |
| `gemini-pro` | `sfdc_ai__DefaultVertexAIGeminiPro25` |

### B.2 `edit_agent_config`

Update an Agent or AgentTest column's configuration.

```typescript
server.tool(
  "edit_agent_config",
  `Modify an Agent or AgentTest column's configuration. Fetches the current config, applies
your changes, and reprocesses. Use this to change which agent is being tested, the utterance
template, or context variables.

Only provide the parameters you want to change.`,
  {
    columnId: z.string().describe("The Agent or AgentTest column to modify"),
    agentId: z.string().optional().describe("New agent definition ID"),
    agentVersion: z.string().optional().describe("New agent version ID"),
    utterance: z.string().optional().describe(
      "New utterance template (Agent columns only). Use {ColumnName} for references."
    ),
    contextVariables: z.array(z.object({
      name: z.string().describe("Variable name"),
      value: z.string().optional().describe("Static value"),
      column: z.string().optional().describe("Column name to reference (resolved to columnId)"),
      field: z.string().optional().describe("Field name within the referenced column"),
    })).optional().describe("Context variables. Each must have either 'value' or 'column', not both."),
    isDraft: z.boolean().optional().describe("Test a draft (unpublished) agent version"),
    reprocess: z.boolean().optional().default(true).describe(
      "Whether to reprocess cells after updating"
    ),
  },
  async ({ columnId, agentId, agentVersion, utterance, contextVariables, isDraft, reprocess }) => {
    // 1. GET current column config
    // 2. Determine if Agent or AgentTest type
    // 3. Resolve {ColumnName} in utterance to utteranceReferences
    // 4. Resolve contextVariable column names to columnId/columnType
    // 5. Merge into existing config.config
    // 6. PUT or POST /save
  }
);
```

### B.3 `add_evaluation`

Add an evaluation column to an existing worksheet.

```typescript
server.tool(
  "add_evaluation",
  `Add an evaluation column to an existing worksheet. Automatically wires up the input and
reference column references. No need to build the nested config JSON manually.

Supported types: COHERENCE, CONCISENESS, FACTUALITY, INSTRUCTION_FOLLOWING, COMPLETENESS,
RESPONSE_MATCH, TOPIC_ASSERTION, ACTION_ASSERTION, LATENCY_ASSERTION, BOT_RESPONSE_RATING,
EXPRESSION_EVAL, CUSTOM_LLM_EVALUATION.

Types requiring expectedColumn: RESPONSE_MATCH, TOPIC_ASSERTION, ACTION_ASSERTION,
BOT_RESPONSE_RATING, CUSTOM_LLM_EVALUATION.`,
  {
    worksheetId: z.string().describe("The worksheet to add the evaluation to"),
    evaluationType: z.enum([
      "COHERENCE", "CONCISENESS", "FACTUALITY", "INSTRUCTION_FOLLOWING",
      "COMPLETENESS", "RESPONSE_MATCH", "TOPIC_ASSERTION", "ACTION_ASSERTION",
      "LATENCY_ASSERTION", "BOT_RESPONSE_RATING", "EXPRESSION_EVAL",
      "CUSTOM_LLM_EVALUATION"
    ]).describe("The evaluation type"),
    targetColumn: z.string().describe(
      "Name or ID of the column to evaluate (typically an Agent, AgentTest, or PromptTemplate column)"
    ),
    expectedColumn: z.string().optional().describe(
      "Name or ID of the column with expected values (required for comparison evaluations)"
    ),
    name: z.string().optional().describe(
      "Display name for the evaluation column. Defaults to the evaluation type in title case."
    ),
    expressionFormula: z.string().optional().describe(
      "Formula for EXPRESSION_EVAL type (e.g., \"{response.topicName} == 'Service'\")"
    ),
    customEvalTemplate: z.string().optional().describe(
      "Prompt template API name for CUSTOM_LLM_EVALUATION type"
    ),
  },
  async ({ worksheetId, evaluationType, targetColumn, expectedColumn, name, expressionFormula, customEvalTemplate }) => {
    // 1. GET worksheet data to resolve column names to IDs and types
    // 2. Validate: if comparison eval, expectedColumn must be provided
    // 3. Build the full nested Evaluation config
    // 4. POST /worksheets/{id}/columns
    // 5. Return column ID and config summary
  }
);
```

### B.4 `change_model`

Switch the LLM model on any column that uses one (AI, PromptTemplate).

```typescript
server.tool(
  "change_model",
  `Change the LLM model used by an AI or PromptTemplate column. Accepts model shorthands
(e.g., 'gpt-4o', 'claude-sonnet-4') or full model IDs. Reprocesses all cells with the new model.

Use grid://models to see available models and their shorthands.`,
  {
    columnId: z.string().describe("The column to change the model for"),
    model: z.string().describe(
      "Model shorthand or full model ID (e.g., 'gpt-4o', 'sfdc_ai__DefaultGPT4Omni')"
    ),
    reprocess: z.boolean().optional().default(true).describe(
      "Whether to reprocess cells after changing. Set false to just save."
    ),
  },
  async ({ columnId, model, reprocess }) => {
    // 1. GET current column config
    // 2. Validate column type is AI or PromptTemplate
    // 3. Resolve model shorthand to full modelConfig
    // 4. Update config.config.modelConfig
    // 5. PUT or POST /save
  }
);
```

### B.5 `update_filters`

Change the filters on an Object or DataModelObject column.

```typescript
server.tool(
  "update_filters",
  `Update the query filters on an Object or DataModelObject column. Replaces the existing
filters with the new set. Reprocesses to re-query with new filters.

For SOQL/DCSQL advanced mode, use edit_column directly.`,
  {
    columnId: z.string().describe("The Object or DataModelObject column to update"),
    filters: z.array(z.object({
      field: z.string().describe("Field API name to filter on"),
      operator: z.enum([
        "In", "NotIn", "EqualTo", "NotEqualTo", "Contains", "StartsWith",
        "EndsWith", "IsNull", "IsNotNull", "LessThan", "LessThanOrEqualTo",
        "GreaterThan", "GreaterThanOrEqualTo"
      ]).describe("Filter operator"),
      values: z.array(z.string()).optional().describe(
        "Filter values (not needed for IsNull/IsNotNull)"
      ),
    })).describe("New filter conditions"),
    reprocess: z.boolean().optional().default(true).describe(
      "Whether to reprocess after updating filters"
    ),
  },
  async ({ columnId, filters, reprocess }) => {
    // 1. GET current column config
    // 2. Validate column type is Object or DataModelObject
    // 3. Build typed filter objects with value/type pairs
    // 4. Replace config.config.filters
    // 5. PUT or POST /save
  }
);
```

### B.6 `reprocess`

Reprocess cells in a column or entire worksheet with options.

```typescript
server.tool(
  "reprocess",
  `Reprocess cells in a column or worksheet. Use this after source data changes, or to retry
failed cells without changing any configuration.

Scope options:
- Provide columnId to reprocess a single column
- Provide worksheetId to reprocess all processing columns in the worksheet
- Use 'filter' to limit which cells are reprocessed`,
  {
    columnId: z.string().optional().describe("Reprocess a single column"),
    worksheetId: z.string().optional().describe(
      "Reprocess all processing columns in this worksheet"
    ),
    filter: z.enum(["all", "failed", "stale"]).optional().default("all").describe(
      "Which cells to reprocess: 'all' (default), 'failed' (only Error cells), " +
      "'stale' (cells whose source data changed)"
    ),
  },
  async ({ columnId, worksheetId, filter }) => {
    // Must provide exactly one of columnId or worksheetId
    // 1. If columnId: GET column config, POST /columns/{id}/reprocess
    // 2. If worksheetId: GET worksheet data, identify processing columns,
    //    reprocess each in dependency order
    // 3. If filter=failed: use trigger_row_execution with only failed row IDs
    // 4. Return summary of what was reprocessed
  }
);
```

### B.7 `edit_prompt_template`

Update a PromptTemplate column's template or input mappings.

```typescript
server.tool(
  "edit_prompt_template",
  `Modify a PromptTemplate column's template selection or input mappings. Use this to switch
which prompt template is used or to rewire the input variables.`,
  {
    columnId: z.string().describe("The PromptTemplate column to modify"),
    templateName: z.string().optional().describe("New prompt template developer name"),
    inputMappings: z.array(z.object({
      variable: z.string().describe("Template variable name (referenceName)"),
      column: z.string().describe("Column name to map to this variable"),
      field: z.string().optional().describe("Field name within the column"),
    })).optional().describe("Input variable to column mappings"),
    model: z.string().optional().describe("Model shorthand or full ID"),
    reprocess: z.boolean().optional().default(true).describe(
      "Whether to reprocess cells after updating"
    ),
  },
  async ({ columnId, templateName, inputMappings, model, reprocess }) => {
    // 1. GET current column config and worksheet schema
    // 2. Resolve column names in inputMappings to columnId/columnType
    // 3. Build promptTemplateInputConfigs array
    // 4. Merge into config.config
    // 5. PUT or POST /save
  }
);
```

### Internal Helper: Config Fetch and Merge

All typed mutation tools share this pattern:

```typescript
async function getColumnConfig(client: GridClient, columnId: string): Promise<{
  column: ColumnMetadata;
  worksheetId: string;
  worksheetColumns: ColumnMetadata[];
}> {
  // Fetch worksheet data that contains this column
  // Extract the column's full config
  // Return column + sibling columns for reference resolution
}

function resolveModelShorthand(shorthand: string): { modelId: string; modelName: string } {
  const MODEL_MAP: Record<string, string> = {
    "gpt-4o": "sfdc_ai__DefaultGPT4Omni",
    "gpt-4.1": "sfdc_ai__DefaultGPT41",
    "gpt-5": "sfdc_ai__DefaultGPT5",
    "gpt-5-mini": "sfdc_ai__DefaultGPT5Mini",
    "o3": "sfdc_ai__DefaultO3",
    "o4-mini": "sfdc_ai__DefaultO4Mini",
    "claude-sonnet-4.5": "sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet",
    "claude-sonnet-4": "sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet",
    "gemini-flash": "sfdc_ai__DefaultVertexAIGemini25Flash001",
    "gemini-pro": "sfdc_ai__DefaultVertexAIGeminiPro25",
  };
  const fullId = MODEL_MAP[shorthand] ?? shorthand;
  return { modelId: fullId, modelName: fullId };
}

function resolveColumnRef(
  name: string,
  columns: ColumnMetadata[]
): { columnId: string; columnName: string; columnType: string } {
  // Match by name (case-insensitive) or by ID
  // Return the referenceAttribute-compatible object with UPPERCASE columnType
}
```

---

## C. MCP Resources

MCP Resources provide read-only, URI-addressable data that Claude can request as context. Unlike tools, resources don't mutate state -- they give Claude just-in-time information to make better decisions.

### C.1 `grid://worksheets/{id}/schema`

Compact worksheet schema: column names, types, IDs, and dependency relationships. No cell data.

```typescript
server.resource(
  "worksheet-schema",
  new ResourceTemplate("grid://worksheets/{id}/schema", { list: undefined }),
  {
    description: "Column schema for a worksheet: names, types, IDs, and which columns reference which. " +
      "Use this to understand a grid's structure before modifying it.",
    mimeType: "application/json",
  },
  async (uri, { id }) => {
    const data = await client.get(`/worksheets/${id}/data`);
    const schema = {
      worksheetId: id,
      worksheetName: data.name,
      workbookId: data.workbookId,
      totalRows: (data.rows || []).length,
      columns: (data.columns || []).map((col: any) => ({
        id: col.id,
        name: col.name,
        type: col.type,
        // Extract dependencies from config
        references: extractReferences(col.config),
      })),
    };
    return {
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(schema, null, 2),
      }],
    };
  }
);
```

**Example response:**

```json
{
  "worksheetId": "1W5RM000000EFGH",
  "worksheetName": "Lead Enrichment",
  "workbookId": "1W4RM000000ABCD",
  "totalRows": 50,
  "columns": [
    { "id": "col-1", "name": "Leads", "type": "Object", "references": [] },
    { "id": "col-2", "name": "Summary", "type": "AI", "references": ["Leads"] },
    { "id": "col-3", "name": "Sentiment", "type": "AI", "references": ["Summary"] },
    { "id": "col-4", "name": "Coherence", "type": "Evaluation", "references": ["Summary"] }
  ]
}
```

### C.2 `grid://worksheets/{id}/status`

Per-column processing status. Compact alternative to `get_worksheet_data`.

```typescript
server.resource(
  "worksheet-status",
  new ResourceTemplate("grid://worksheets/{id}/status", { list: undefined }),
  {
    description: "Processing status for each column in a worksheet: complete/in-progress/failed/new counts. " +
      "Use this to check if processing is done or to find failed cells.",
    mimeType: "application/json",
  },
  async (uri, { id }) => {
    const data = await client.get(`/worksheets/${id}/data`);
    // Reuse the countStatuses logic from workflows.ts
    const status = buildStatusSummary(data);
    return {
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(status, null, 2),
      }],
    };
  }
);
```

**Example response:**

```json
{
  "worksheetId": "1W5RM000000EFGH",
  "allComplete": false,
  "completion": "80% (120/150 cells)",
  "columns": [
    { "name": "Leads", "type": "Object", "complete": 50, "inProgress": 0, "failed": 0, "new": 0 },
    { "name": "Summary", "type": "AI", "complete": 45, "inProgress": 3, "failed": 2, "new": 0 },
    { "name": "Sentiment", "type": "AI", "complete": 25, "inProgress": 10, "failed": 0, "new": 15 }
  ],
  "failedCells": [
    { "column": "Summary", "rowIndex": 12, "error": "Model timeout" },
    { "column": "Summary", "rowIndex": 37, "error": "Input too long" }
  ]
}
```

### C.3 `grid://agents`

Available agents with names, IDs, versions, and topics.

```typescript
server.resource(
  "agents",
  "grid://agents",
  {
    description: "List of available agents with their definition IDs, active version IDs, and topic names. " +
      "Use this to find agent IDs for Agent/AgentTest columns.",
    mimeType: "application/json",
  },
  async (uri) => {
    const agents = await client.get("/agents?includeDrafts=true");
    const summary = agents.map((a: any) => ({
      name: a.name,
      id: a.id,
      activeVersion: a.activeVersion,
      status: a.status,
      topics: (a.topics || []).map((t: any) => t.name),
    }));
    return {
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(summary, null, 2),
      }],
    };
  }
);
```

### C.4 `grid://models`

Available LLM models with shorthand aliases.

```typescript
server.resource(
  "models",
  "grid://models",
  {
    description: "Available LLM models with shorthand aliases. Use shorthands in tool calls " +
      "(e.g., 'gpt-4o' instead of 'sfdc_ai__DefaultGPT4Omni').",
    mimeType: "application/json",
  },
  async (uri) => {
    const models = await client.get("/llm-models");
    // Enrich with shorthand aliases
    const enriched = models.map((m: any) => ({
      id: m.name || m.id,
      label: m.label,
      shorthand: reverseModelMap(m.name || m.id),
      maxTokens: m.maxTokens,
      active: m.active,
    }));
    return {
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(enriched, null, 2),
      }],
    };
  }
);
```

**Example response:**

```json
[
  { "id": "sfdc_ai__DefaultGPT4Omni", "label": "GPT 4 Omni", "shorthand": "gpt-4o", "maxTokens": 16000, "active": true },
  { "id": "sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet", "label": "Claude 4 Sonnet", "shorthand": "claude-sonnet-4", "maxTokens": 8000, "active": true }
]
```

### C.5 `grid://schema/{columnType}`

On-demand schema reference for a specific column type. This replaces loading the full 900-line column-configs.md -- Claude queries only the type it needs.

```typescript
server.resource(
  "column-type-schema",
  new ResourceTemplate("grid://schema/{columnType}", { list: listColumnTypes }),
  {
    description: "Configuration schema for a specific column type. Returns required fields, " +
      "example configs, and common pitfalls. Query this before creating or editing columns.",
    mimeType: "application/json",
  },
  async (uri, { columnType }) => {
    const schema = COLUMN_SCHEMAS[columnType.toUpperCase()];
    if (!schema) {
      return { contents: [{ uri: uri.href, mimeType: "text/plain", text: `Unknown column type: ${columnType}` }] };
    }
    return {
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(schema, null, 2),
      }],
    };
  }
);
```

The `COLUMN_SCHEMAS` map is a static object compiled from the column-configs.md reference. Example entry for AI:

```json
{
  "type": "AI",
  "columnTypeForReferences": "AI",
  "requiredFields": {
    "mode": { "type": "string", "value": "llm", "description": "Always 'llm'" },
    "modelConfig": { "type": "ModelConfig", "description": "LLM model selection" },
    "instruction": { "type": "string", "description": "Prompt with {$N} placeholders" },
    "referenceAttributes": { "type": "ReferenceAttribute[]", "description": "Columns for placeholders" },
    "responseFormat": { "type": "object", "description": "PLAIN_TEXT or SINGLE_SELECT" }
  },
  "optionalFields": {
    "autoUpdate": { "type": "boolean", "default": true }
  },
  "example": {
    "name": "Summary",
    "type": "AI",
    "config": {
      "type": "AI",
      "queryResponseFormat": { "type": "EACH_ROW" },
      "autoUpdate": true,
      "config": {
        "autoUpdate": true,
        "mode": "llm",
        "modelConfig": { "modelId": "sfdc_ai__DefaultGPT4Omni", "modelName": "sfdc_ai__DefaultGPT4Omni" },
        "instruction": "Summarize: {$1}",
        "referenceAttributes": [
          { "columnId": "col-id", "columnName": "Source", "columnType": "TEXT" }
        ],
        "responseFormat": { "type": "PLAIN_TEXT", "options": [] }
      }
    }
  },
  "pitfalls": [
    "Must include nested config.config structure",
    "referenceAttributes uses UPPERCASE columnType (TEXT, OBJECT, etc.)",
    "Use modelId same as modelName (both are the model's name field)"
  ]
}
```

### C.6 `grid://schema/dsl` (bonus)

The YAML DSL reference itself, so Claude can query it on demand.

```typescript
server.resource(
  "dsl-schema",
  "grid://schema/dsl",
  {
    description: "YAML DSL reference for apply_grid. Shows all supported column types, " +
      "their simplified YAML syntax, and example specs.",
    mimeType: "text/markdown",
  },
  async (uri) => {
    // Return the DSL quick-reference (compiled from Task #1 output)
    return {
      contents: [{
        uri: uri.href,
        mimeType: "text/markdown",
        text: DSL_REFERENCE_MD,
      }],
    };
  }
);
```

### Caching Strategy

Resources should implement lightweight caching to avoid hammering the API:

```typescript
class ResourceCache {
  private cache = new Map<string, { data: any; expires: number }>();

  get(key: string, ttlMs: number): any | null {
    const entry = this.cache.get(key);
    if (entry && Date.now() < entry.expires) return entry.data;
    return null;
  }

  set(key: string, data: any, ttlMs: number): void {
    this.cache.set(key, { data, expires: Date.now() + ttlMs });
  }
}
```

| Resource | TTL | Rationale |
|----------|-----|-----------|
| `grid://agents` | 5 min | Agent list changes rarely |
| `grid://models` | 30 min | Model list is very stable |
| `grid://schema/{type}` | Infinite | Static data, compiled at build time |
| `grid://worksheets/{id}/schema` | 30 sec | Changes when columns are added/removed |
| `grid://worksheets/{id}/status` | 10 sec | Changes frequently during processing |

---

## D. Tool Descriptions (Context Window Optimization)

Each tool description is designed to be self-contained -- Claude should never need to read external documentation to use the tool correctly. But descriptions are kept concise to minimize context window usage.

### Description Guidelines

1. **First line**: What the tool does in one sentence
2. **When to use**: One-line guidance on when to choose this tool vs alternatives
3. **Key constraints**: Only the most critical rules (not full documentation)
4. **Parameter descriptions**: Each parameter has a `describe()` that includes valid values

### Full Tool Description Index

| Tool | Description (first line) | Context cost |
|------|------------------------|--------------|
| `apply_grid` | Create or update an Agentforce Grid from a YAML specification | ~150 tokens |
| `edit_ai_prompt` | Modify an AI column's prompt or settings | ~120 tokens |
| `edit_agent_config` | Modify an Agent or AgentTest column's configuration | ~140 tokens |
| `add_evaluation` | Add an evaluation column to an existing worksheet | ~130 tokens |
| `change_model` | Change the LLM model used by an AI or PromptTemplate column | ~80 tokens |
| `update_filters` | Update the query filters on an Object or DataModelObject column | ~100 tokens |
| `reprocess` | Reprocess cells in a column or worksheet | ~90 tokens |
| `edit_prompt_template` | Modify a PromptTemplate column's template or input mappings | ~100 tokens |

**Total new tool context**: ~810 tokens (vs ~900 lines of column-configs.md loaded into context).

The key insight: by encoding column config knowledge *inside* the tools, Claude's context window only needs the tool descriptions, not the full reference documentation.

---

## E. Migration Path

### Strategy: Additive, Not Replacing

New tools are **added alongside** existing tools. No existing tool is removed or renamed.

### Phase 1: Ship New Tools (Week 1-2)

- Add `apply_grid`, all typed mutation tools, and all MCP resources
- Existing tools (`add_column`, `edit_column`, `save_column`, `reprocess_column`) continue to work unchanged
- New tools are registered in a new file: `src/tools/typed-mutations.ts` and `src/resources/`

### Phase 2: Soft Deprecation (Week 3-4)

- Update `edit_column` description to say: "Low-level column editor. Prefer `edit_ai_prompt`, `edit_agent_config`, or `change_model` for common operations."
- Update `add_column` description to say: "Low-level column creator. Prefer `apply_grid` for creating multiple columns, or `add_evaluation` for adding evaluations."
- Monitor usage to confirm new tools are being used

### Phase 3: Hard Deprecation (Week 6+)

- If metrics confirm new tools handle >90% of use cases, add "[DEPRECATED]" prefix to old tool descriptions
- Never remove tools -- just make descriptions clearly point to the replacements

### File Structure

```
src/
  tools/
    columns.ts              # Existing (unchanged)
    metadata.ts             # Existing (unchanged)
    workbooks.ts            # Existing (unchanged)
    worksheets.ts           # Existing (unchanged)
    workflows.ts            # Existing (unchanged)
    agents.ts               # Existing (unchanged)
    cells.ts                # Existing (unchanged)
    data.ts                 # Existing (unchanged)
    typed-mutations.ts      # NEW: edit_ai_prompt, edit_agent_config, etc.
    apply-grid.ts           # NEW: apply_grid composite tool
  resources/
    worksheet-resources.ts  # NEW: schema, status
    metadata-resources.ts   # NEW: agents, models, column-type-schema
    dsl-resource.ts         # NEW: dsl schema reference
  lib/
    model-map.ts            # NEW: model shorthand resolution
    column-schemas.ts       # NEW: static column type schemas
    config-helpers.ts       # NEW: getColumnConfig, resolveColumnRef, etc.
    resource-cache.ts       # NEW: TTL cache for resources
  index.ts                  # Updated to register new tools + resources
```

### index.ts Changes

```typescript
// Add to existing imports
import { registerTypedMutationTools } from "./tools/typed-mutations.js";
import { registerApplyGridTool } from "./tools/apply-grid.js";
import { registerWorksheetResources } from "./resources/worksheet-resources.js";
import { registerMetadataResources } from "./resources/metadata-resources.js";
import { registerDslResource } from "./resources/dsl-resource.js";

// Add after existing registrations
registerTypedMutationTools(server, client);
registerApplyGridTool(server, client);
registerWorksheetResources(server, client);
registerMetadataResources(server, client);
registerDslResource(server);
```

---

## F. Example Conversations

### Example 1: Create a Grid from Scratch with `apply_grid`

**User:** Create an agent test suite for my Sales Agent with coherence and topic assertion evaluations.

**Claude reads `grid://agents` resource:**
```json
[
  { "name": "Sales Agent", "id": "0XxRM000001234", "activeVersion": "0XyRM000005678", "topics": ["Sales", "Support", "Billing"] }
]
```

**Claude calls `apply_grid`:**
```yaml
spec: |
  name: Sales Agent Test Suite
  columns:
    - name: Utterances
      type: text

    - name: Expected Topics
      type: text

    - name: Agent Output
      type: agent_test
      agent: Sales Agent
      input_utterance: Utterances

    - name: Coherence
      type: evaluation
      eval_type: COHERENCE
      target: Agent Output

    - name: Topic Assertion
      type: evaluation
      eval_type: TOPIC_ASSERTION
      target: Agent Output
      expected: Expected Topics
  data:
    Utterances:
      - "I want to buy your enterprise plan"
      - "Can you help me with a refund?"
      - "What payment methods do you accept?"
    Expected Topics:
      - "Sales"
      - "Support"
      - "Billing"
```

**Tool returns:**
```json
{
  "workbookId": "1W4RM...",
  "worksheetId": "1W5RM...",
  "columns": {
    "Utterances": "col-1",
    "Expected Topics": "col-2",
    "Agent Output": "col-3",
    "Coherence": "col-4",
    "Topic Assertion": "col-5"
  },
  "rowIds": ["row-1", "row-2", "row-3"],
  "errors": [],
  "plan": [...]
}
```

**Claude:** Created your Sales Agent test suite with 3 test utterances, coherence evaluation, and topic assertion. The agent is now processing. Use `poll_worksheet_status` with worksheet ID `1W5RM...` to monitor progress.

---

### Example 2: Iterate on an Existing Grid

**User:** The AI summary column in my Lead Enrichment grid is too verbose. Make it more concise and switch to Claude Sonnet.

**Claude reads `grid://worksheets/1W5RM000000EFGH/schema` resource:**
```json
{
  "columns": [
    { "id": "col-1", "name": "Leads", "type": "Object", "references": [] },
    { "id": "col-2", "name": "Summary", "type": "AI", "references": ["Leads"] },
    { "id": "col-3", "name": "Sentiment", "type": "AI", "references": ["Summary"] }
  ]
}
```

**Claude calls `edit_ai_prompt`:**
```json
{
  "columnId": "col-2",
  "instruction": "Write a 2-sentence summary of this lead. Be concise.\nName: {Leads.Name}\nCompany: {Leads.Company}\nIndustry: {Leads.Industry}",
  "model": "claude-sonnet-4"
}
```

**Tool returns:**
```json
{
  "columnId": "col-2",
  "updated": true,
  "reprocessing": true,
  "changes": {
    "instruction": "changed",
    "model": "sfdc_ai__DefaultGPT4Omni -> sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet"
  }
}
```

**Claude:** Updated the Summary column with a more concise prompt and switched to Claude Sonnet 4. All 50 cells are reprocessing now.

**User:** Also add a completeness evaluation to check the summaries.

**Claude calls `add_evaluation`:**
```json
{
  "worksheetId": "1W5RM000000EFGH",
  "evaluationType": "COMPLETENESS",
  "targetColumn": "Summary"
}
```

**Tool returns:**
```json
{
  "columnId": "col-4",
  "name": "Completeness",
  "evaluationType": "COMPLETENESS",
  "targetColumn": "Summary"
}
```

**Claude:** Added a Completeness evaluation column targeting the Summary column. It will evaluate each summary as cells finish processing.

---

### Example 3: Debug and Recover Failed Cells

**User:** Check the status of my agent test worksheet 1W5RM000000XYZW.

**Claude reads `grid://worksheets/1W5RM000000XYZW/status` resource:**
```json
{
  "worksheetId": "1W5RM000000XYZW",
  "allComplete": false,
  "completion": "90% (45/50 cells)",
  "columns": [
    { "name": "Utterances", "type": "Text", "complete": 10, "inProgress": 0, "failed": 0, "new": 0 },
    { "name": "Agent Output", "type": "AgentTest", "complete": 8, "inProgress": 0, "failed": 2, "new": 0 },
    { "name": "Coherence", "type": "Evaluation", "complete": 8, "inProgress": 0, "failed": 0, "new": 2 },
    { "name": "Topic Check", "type": "Evaluation", "complete": 7, "inProgress": 0, "failed": 0, "new": 3 }
  ],
  "failedCells": [
    { "column": "Agent Output", "rowIndex": 4, "error": "Agent timeout after 120s" },
    { "column": "Agent Output", "rowIndex": 7, "error": "Agent timeout after 120s" }
  ]
}
```

**Claude:** Your worksheet is 90% complete. The Agent Output column has 2 failed cells (rows 4 and 7) due to agent timeouts. The evaluation columns have pending cells waiting for those agent outputs. Want me to retry the failed cells?

**User:** Yes, retry them.

**Claude calls `reprocess`:**
```json
{
  "columnId": "col-agent-output-id",
  "filter": "failed"
}
```

**Tool returns:**
```json
{
  "reprocessed": 2,
  "columnId": "col-agent-output-id",
  "filter": "failed",
  "message": "Reprocessing 2 failed cells in Agent Output"
}
```

**Claude:** Retrying the 2 failed cells. The evaluation columns will auto-process once the agent outputs complete. Use `poll_worksheet_status` to monitor.
