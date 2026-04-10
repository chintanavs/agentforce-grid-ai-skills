> **Status:** ACTIVE | Phase 1.6 (validation engine) + Phase 4.1 (PreToolUse hook) | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) Phase 1.6 and Phase 4.1-4.2
> **What changed:** Reduced urgency for the PreToolUse hook (Section 1.3) because `add_column` already validates via Zod `ColumnInputSchema.safeParse()`. The hook is still useful for `edit_column`/`save_column`/`reprocess_column` where users pass the outer config directly, but has less urgency than originally planned. Section 3.1 (DSL skill reference) maps to Phase 4.3. Section 3.3 (PostToolUse hook) maps to Phase 4.2.

# Grid Validation, Error Handling, and Claude Integration Specification

**Date:** 2026-03-06
**Status:** ~~Draft~~ Active (Phase 1.6 + Phase 4.1-4.2)
**Depends on:** Grid YAML DSL Schema, MCP Server Improvements, Resolution Engine Architecture

---

## Table of Contents

1. [Pre-flight Validation Rules](#1-pre-flight-validation-rules)
2. [Error Message Catalog](#2-error-message-catalog)
3. [Claude Code Integration](#3-claude-code-integration)
4. [Example End-to-End Conversations](#4-example-end-to-end-conversations)

---

## 1. Pre-flight Validation Rules

Validation happens at two layers: (A) YAML DSL validation inside the `apply_grid` MCP tool before any API calls, and (B) raw JSON config validation in the PreToolUse hook for backwards-compatible direct MCP tool usage.

### 1.1 YAML DSL Validation Pipeline

When `apply_grid` receives a YAML spec, it runs these validation passes **in order**. Each pass assumes the previous pass succeeded.

#### Pass 1: YAML Parse and Schema Validation

Validates that the YAML is well-formed and matches the DSL schema.

**Rules:**

| Rule ID | Check | Error Code |
|---------|-------|------------|
| Y-001 | YAML parses without syntax errors | `YAML_PARSE_ERROR` |
| Y-002 | Top-level `name` field is present and non-empty | `MISSING_REQUIRED_FIELD` |
| Y-003 | `columns` is present and is a non-empty list | `MISSING_REQUIRED_FIELD` |
| Y-004 | Each column has a `name` field | `MISSING_REQUIRED_FIELD` |
| Y-005 | Each column has a `type` field | `MISSING_REQUIRED_FIELD` |
| Y-006 | `type` is one of the 12 valid column types | `INVALID_COLUMN_TYPE` |
| Y-007 | `workbook` field, if present, is a string | `INVALID_FIELD_TYPE` |
| Y-008 | `rows` field, if present, is a positive integer | `INVALID_FIELD_TYPE` |
| Y-009 | `data` field, if present, is a map of column-name to list | `INVALID_FIELD_TYPE` |

#### Pass 2: Type-Specific Required Fields

Each column type has required fields. Missing fields are caught here.

| Column Type | Required Fields in Column Spec | Rule ID |
|-------------|-------------------------------|---------|
| AI | `model`, `prompt` | T-001 |
| AI (with refs) | `prompt` must contain `{column_name}` placeholders that match defined columns | T-002 |
| AI (SINGLE_SELECT) | `response_format: single_select` requires `options` list with >= 1 item | T-003 |
| Agent | `agent`, `utterance` | T-010 |
| AgentTest | `agent`, `input_column` | T-020 |
| Object | `object` (SObject API name) | T-030 |
| Object (basic) | `fields` is a non-empty list | T-031 |
| Object (advanced) | `soql` is present (alternative to `fields`) | T-032 |
| Formula | `formula`, `return_type` | T-040 |
| Reference | `source` (column name), `field` (JSON path) | T-050 |
| Evaluation | `eval_type`, `input` (column name) | T-060 |
| Evaluation (comparison) | `reference` column when eval_type requires it | T-061 |
| PromptTemplate | `template`, `model` | T-070 |
| PromptTemplate | `inputs` mapping is present | T-071 |
| InvocableAction | `action_type`, `action_name` | T-080 |
| InvocableAction | `input_payload` is present | T-081 |
| DataModelObject | `dmo`, `dataspace` | T-090 |
| Text | No required fields beyond `name` and `type` | -- |

#### Pass 3: Reference Integrity

All column-name references must resolve to columns defined in the same spec (or existing columns in the target worksheet if `worksheet` is specified).

**Rules:**

| Rule ID | Check | Error Code |
|---------|-------|------------|
| R-001 | `{column_name}` placeholders in AI `prompt` resolve to defined columns | `UNDEFINED_COLUMN_REF` |
| R-002 | AgentTest `input_column` resolves to a defined column | `UNDEFINED_COLUMN_REF` |
| R-003 | Evaluation `input` resolves to a defined column | `UNDEFINED_COLUMN_REF` |
| R-004 | Evaluation `reference` resolves to a defined column (when required) | `UNDEFINED_COLUMN_REF` |
| R-005 | Reference `source` resolves to a defined column | `UNDEFINED_COLUMN_REF` |
| R-006 | Agent `utterance` placeholders `{column_name}` resolve | `UNDEFINED_COLUMN_REF` |
| R-007 | Formula `{column_name}` placeholders resolve | `UNDEFINED_COLUMN_REF` |
| R-008 | PromptTemplate `inputs` reference attributes resolve | `UNDEFINED_COLUMN_REF` |
| R-009 | InvocableAction `{column_name}` placeholders in `input_payload` resolve | `UNDEFINED_COLUMN_REF` |
| R-010 | Object/DMO `soql` placeholders `{column_name}` resolve (advanced mode) | `UNDEFINED_COLUMN_REF` |

#### Pass 4: Circular Dependency Detection

Build a directed acyclic graph (DAG) from column references and detect cycles.

**Algorithm:**
1. For each column, compute its dependency set (columns it references).
2. Run topological sort using Kahn's algorithm.
3. If any columns remain after sort completes, they form a cycle.

**Rules:**

| Rule ID | Check | Error Code |
|---------|-------|------------|
| D-001 | No column references itself | `SELF_REFERENCE` |
| D-002 | No circular dependency chains exist | `CIRCULAR_DEPENDENCY` |
| D-003 | Evaluation columns only reference processing/input columns, not other evaluations | `INVALID_EVAL_TARGET` |

**Error detail for D-002 includes the cycle path:** e.g., `"cycle": ["Summary", "Analysis", "Summary"]`

#### Pass 5: Type Compatibility

Certain column types can only reference certain other column types.

| Rule ID | Source Type | Can Reference | Error Code |
|---------|------------|---------------|------------|
| C-001 | Evaluation (`input`) | Agent, AgentTest, PromptTemplate (quality evals); Agent, AgentTest (comparison evals) | `INVALID_EVAL_INPUT_TYPE` |
| C-002 | Evaluation (`reference`) | Text only | `INVALID_EVAL_REFERENCE_TYPE` |
| C-003 | Reference (`source`) | Any column type (extracts JSON fields) | -- |
| C-004 | AgentTest (`input_column`) | Text only | `INVALID_AGENT_INPUT_TYPE` |

#### Pass 6: Value Validation

Validates that enumerated values are correct.

| Rule ID | Check | Error Code |
|---------|-------|------------|
| V-001 | `eval_type` is one of the 12 valid evaluation types | `INVALID_EVAL_TYPE` |
| V-002 | `model` resolves to a known shorthand or full model ID | `INVALID_MODEL` |
| V-003 | `response_format` is `plain_text` or `single_select` | `INVALID_RESPONSE_FORMAT` |
| V-004 | `return_type` for Formula is a valid type (string, boolean, double, integer, etc.) | `INVALID_RETURN_TYPE` |
| V-005 | `query_format` is `each_row` or `whole_column` | `INVALID_QUERY_FORMAT` |
| V-006 | `action_type` for InvocableAction is FLOW, APEX, etc. | `INVALID_ACTION_TYPE` |
| V-007 | Context variable has EITHER `value` OR `reference`, not both | `CONTEXT_VAR_CONFLICT` |

### 1.2 Model Shorthand Resolution

The YAML DSL supports short model names. Validation confirms they map to real model IDs.

| Shorthand | Full Model ID |
|-----------|---------------|
| `gpt-4-omni` | `sfdc_ai__DefaultGPT4Omni` |
| `gpt-4.1` | `sfdc_ai__DefaultGPT41` |
| `gpt-4.1-mini` | `sfdc_ai__DefaultGPT41Mini` |
| `gpt-5` | `sfdc_ai__DefaultGPT5` |
| `gpt-5-mini` | `sfdc_ai__DefaultGPT5Mini` |
| `o3` | `sfdc_ai__DefaultO3` |
| `o4-mini` | `sfdc_ai__DefaultO4Mini` |
| `claude-sonnet-4.5` | `sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet` |
| `claude-sonnet-4` | `sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet` |
| `claude-haiku-4.5` | `sfdc_ai__DefaultBedrockAnthropicClaude45Haiku` |
| `gemini-2.5-flash` | `sfdc_ai__DefaultVertexAIGemini25Flash001` |
| `gemini-2.5-pro` | `sfdc_ai__DefaultVertexAIGeminiPro25` |

If a model string does not match any shorthand AND does not match the `sfdc_ai__*` pattern, emit `INVALID_MODEL` with a "did you mean?" suggestion using Levenshtein distance against the shorthand list.

### 1.3 PreToolUse Hook: Raw JSON Config Validation -- Phase 4.1 (Reduced Urgency)

> **Reduced urgency:** `add_column` now validates via `ColumnInputSchema.safeParse()` in the MCP server itself (Phase 0). The hook is still useful for `edit_column`, `save_column`, and `reprocess_column` where the Zod validation catches structural issues but not semantic ones (e.g., wrong columnType casing in referenceAttributes). See hybrid plan "Spec Assumptions Now Invalidated" table.

For backwards compatibility, when users or Claude call the raw MCP tools (`add_column`, `edit_column`) with JSON configs, the PreToolUse hook catches common structural errors before the API call.

**Hook trigger:** `mcp__agentforce-grid__add_column`, `mcp__agentforce-grid__edit_column`

**Implementation:** `hooks/validate-config.py`

The hook reads the tool input from stdin, parses the `config` parameter, and validates:

| Rule ID | Check | Severity | Error Code |
|---------|-------|----------|------------|
| H-001 | `config.config` nested structure is present | BLOCKER | `MISSING_NESTED_CONFIG` |
| H-002 | Outer `type` matches inner `config.type` | BLOCKER | `TYPE_MISMATCH` |
| H-003 | `referenceAttributes[].columnType` is UPPERCASE | BLOCKER | `LOWERCASE_COLUMN_TYPE` |
| H-004 | `modelConfig` has both `modelId` and `modelName` (for AI/PromptTemplate) | BLOCKER | `INCOMPLETE_MODEL_CONFIG` |
| H-005 | `modelConfig.modelId` equals `modelConfig.modelName` | WARNING | `MODEL_ID_NAME_MISMATCH` |
| H-006 | `queryResponseFormat` is present for processing columns | WARNING | `MISSING_QUERY_FORMAT` |
| H-007 | `autoUpdate: true` is set at both levels | WARNING | `MISSING_AUTO_UPDATE` |
| H-008 | AI column has `mode: "llm"` | BLOCKER | `MISSING_AI_MODE` |
| H-009 | AI column has `responseFormat` with `type` and `options` | BLOCKER | `MISSING_RESPONSE_FORMAT` |
| H-010 | ContextVariable has either `value` or `reference`, not both | BLOCKER | `CONTEXT_VAR_CONFLICT` |
| H-011 | Text column config is not empty `{}` -- must have `type` field | BLOCKER | `EMPTY_TEXT_CONFIG` |

**Hook output format:**

```json
{
  "decision": "block",
  "reason": "MISSING_NESTED_CONFIG: Column config is missing the nested config.config structure. The API requires: {\"config\": {\"type\": \"AI\", \"config\": { ...fields... }}}. You provided config without the inner config object."
}
```

Or for warnings that don't block:

```json
{
  "decision": "approve",
  "reason": "MISSING_AUTO_UPDATE: Column config is missing autoUpdate: true. The column will work but won't auto-process new rows."
}
```

---

## 2. Error Message Catalog

Every error follows this structure:

```typescript
interface GridError {
  code: string;           // Machine-readable error code (e.g., "UNDEFINED_COLUMN_REF")
  message: string;        // Human-readable message
  suggestion: string;     // Specific fix suggestion
  details: {              // Machine-readable context
    field?: string;       // Field that caused the error
    value?: string;       // Value that caused the error
    expected?: string;    // What was expected
    column?: string;      // Column name involved
    line?: number;        // YAML line number if applicable
    [key: string]: any;
  };
}
```

### 2.1 YAML Parse Errors

| Code | Message Template | Suggestion |
|------|-----------------|------------|
| `YAML_PARSE_ERROR` | "Failed to parse YAML at line {line}: {parser_message}" | "Check indentation and YAML syntax. Common issues: missing colon after key, incorrect list formatting (use `- item`), unquoted strings containing special characters." |
| `YAML_INVALID_ENCODING` | "YAML contains invalid characters at position {pos}" | "Ensure the YAML is UTF-8 encoded. Remove any non-printable characters." |

### 2.2 Schema Validation Errors

| Code | Message Template | Suggestion |
|------|-----------------|------------|
| `MISSING_REQUIRED_FIELD` | "Column '{column}' is missing required field '{field}' for type '{type}'" | "Add `{field}: <value>` to the column definition. See DSL reference for {type} columns." |
| `INVALID_COLUMN_TYPE` | "Column '{column}' has invalid type '{value}'. Valid types: AI, Agent, AgentTest, Object, Formula, Reference, Evaluation, PromptTemplate, InvocableAction, Action, Text, DataModelObject" | "Change `type: {value}` to one of the valid column types." |
| `INVALID_FIELD_TYPE` | "Field '{field}' in column '{column}' expects {expected} but got {actual}" | "Change `{field}` to a {expected} value." |

### 2.3 Reference Errors

| Code | Message Template | Suggestion |
|------|-----------------|------------|
| `UNDEFINED_COLUMN_REF` | "Column '{column}' references '{ref}' but no column named '{ref}' is defined in this spec" | "Either add a column named '{ref}' to the spec, or fix the reference to match an existing column name. Defined columns: {available_columns}" |
| `UNDEFINED_AGENT` | "Agent '{agent_name}' not found in your org" | "Available agents: {agent_list}. Use the agent name or ID. Run `GET /agents` to refresh the list." |
| `UNDEFINED_TEMPLATE` | "Prompt template '{template_name}' not found" | "Available templates: {template_list}. Use `GET /prompt-templates` to see all templates." |

### 2.4 Dependency Errors

| Code | Message Template | Suggestion |
|------|-----------------|------------|
| `SELF_REFERENCE` | "Column '{column}' references itself" | "A column cannot use its own output as input. Reference a different column." |
| `CIRCULAR_DEPENDENCY` | "Circular dependency detected: {cycle_path}" | "Break the cycle by removing one of the references. Column execution requires a directed acyclic graph." |
| `INVALID_EVAL_TARGET` | "Evaluation column '{column}' targets '{target}' which is type '{target_type}', but {eval_type} only supports: {supported_types}" | "Change `input` to reference a column of type {supported_types}." |

### 2.5 Value Validation Errors

| Code | Message Template | Suggestion |
|------|-----------------|------------|
| `INVALID_EVAL_TYPE` | "Unknown evaluation type '{value}'" | "Valid evaluation types: COHERENCE, CONCISENESS, FACTUALITY, INSTRUCTION_FOLLOWING, COMPLETENESS, RESPONSE_MATCH, TOPIC_ASSERTION, ACTION_ASSERTION, LATENCY_ASSERTION, BOT_RESPONSE_RATING, EXPRESSION_EVAL, CUSTOM_LLM_EVALUATION" |
| `INVALID_MODEL` | "Model '{value}' is not a recognized model shorthand or full ID" | "Did you mean '{closest_match}'? Valid shorthands: gpt-4-omni, gpt-5, claude-sonnet-4.5, gemini-2.5-flash, etc. Use `GET /llm-models` for the full list." |
| `INVALID_RESPONSE_FORMAT` | "Response format '{value}' is not valid" | "Use `plain_text` or `single_select`." |
| `INVALID_RETURN_TYPE` | "Formula return type '{value}' is not valid" | "Valid return types: string, boolean, double, integer, long, date, datetime, time, id, reference." |
| `CONTEXT_VAR_CONFLICT` | "Context variable '{var}' has both `value` and `reference` set" | "Remove either `value` or `reference`. A context variable must use one or the other, not both." |

### 2.6 PreToolUse Hook Errors (Raw JSON)

| Code | Message Template | Suggestion |
|------|-----------------|------------|
| `MISSING_NESTED_CONFIG` | "Column config is missing the required nested structure. Found `config: {...}` but expected `config: { type: '...', config: { ...fields... } }`" | "Wrap your column-specific fields inside `config.config`. The API requires double nesting: outer config has `type`, `queryResponseFormat`, `autoUpdate`; inner config has column-specific fields." |
| `TYPE_MISMATCH` | "Outer type '{outer}' does not match config.type '{inner}'" | "Set both to the same value: `\"type\": \"{outer}\"` at both levels." |
| `LOWERCASE_COLUMN_TYPE` | "referenceAttributes[{index}].columnType is '{value}' but must be UPPERCASE" | "Change `columnType: \"{value}\"` to `columnType: \"{uppercase_value}\"`." |
| `INCOMPLETE_MODEL_CONFIG` | "modelConfig is missing '{missing_field}'" | "modelConfig requires both `modelId` and `modelName` set to the same model identifier, e.g., `\"modelId\": \"sfdc_ai__DefaultGPT4Omni\", \"modelName\": \"sfdc_ai__DefaultGPT4Omni\"`." |
| `MISSING_AI_MODE` | "AI column config is missing `mode` field" | "Add `\"mode\": \"llm\"` to the inner config.config object." |
| `MISSING_RESPONSE_FORMAT` | "AI column config is missing `responseFormat`" | "Add `\"responseFormat\": {\"type\": \"PLAIN_TEXT\", \"options\": []}` to the inner config.config object." |
| `EMPTY_TEXT_CONFIG` | "Text column has empty config object" | "Even Text columns require the nested structure: `{\"config\": {\"type\": \"Text\", \"autoUpdate\": true, \"config\": {\"autoUpdate\": true}}}`." |

### 2.7 API Error Mapping

When the Grid API returns HTTP errors, map them to user-friendly messages.

| HTTP Status | API Error Pattern | Error Code | Message | Suggestion |
|-------------|-------------------|------------|---------|------------|
| 400 | "config.config.{field} is required" | `API_MISSING_FIELD` | "The API rejected the config: field '{field}' is required" | "Add '{field}' to the column config. This is a required field for {column_type} columns." |
| 400 | "Invalid {field} value" | `API_INVALID_VALUE` | "The API rejected the value for '{field}'" | "Check the value for '{field}' against the API documentation." |
| 403 | Any | `API_FORBIDDEN` | "Access denied. Your Salesforce user may lack Grid permissions" | "Verify that your user has the 'Agentforce Grid User' permission set. Check that your SF CLI org is authenticated (sf org display)." |
| 404 | "Agent with ID {id} not found" | `API_AGENT_NOT_FOUND` | "Agent '{id}' not found" | "The agent ID may be wrong or the agent was deleted. Use `GET /agents` to list available agents." |
| 404 | "Worksheet {id} not found" | `API_WORKSHEET_NOT_FOUND` | "Worksheet '{id}' not found" | "The worksheet may have been deleted. Use `GET /workbooks` to list available worksheets." |
| 404 | Generic | `API_NOT_FOUND` | "Resource not found: {url}" | "Check the resource ID. It may have been deleted or the ID is incorrect." |
| 409 | "Column name already exists" | `API_CONFLICT` | "A column named '{name}' already exists in this worksheet" | "Use a different column name, or update the existing column instead of creating a new one." |
| 429 | Any | `API_RATE_LIMITED` | "Rate limit exceeded" | "Wait {retry_after} seconds before retrying. Reduce the number of concurrent API calls." |
| 500 | Any | `API_SERVER_ERROR` | "Salesforce internal error" | "This is a server-side issue. Wait a moment and retry. If persistent, check Salesforce status at status.salesforce.com." |

### 2.8 Partial Failure Handling

When `apply_grid` processes multiple columns sequentially and one fails mid-way:

```typescript
interface ApplyGridResult {
  status: "success" | "partial_failure" | "failure";
  workbook_id: string;
  worksheet_id: string;
  columns_created: {
    name: string;
    id: string;
    type: string;
    status: "created" | "failed";
    error?: GridError;
  }[];
  summary: string;  // Human-readable summary
  recovery: string; // What to do next
}
```

**Example partial failure output:**

```
Status: partial_failure
Created 3 of 5 columns successfully.

  [OK] Test Utterances (Text) -> 1W5xx001
  [OK] Expected Topics (Text) -> 1W5xx002
  [OK] Agent Output (AgentTest) -> 1W5xx003
  [FAIL] Response Match (Evaluation) -> API_AGENT_NOT_FOUND: Agent '0Xx000' not found
  [SKIP] Topic Check (Evaluation) -> Skipped (depends on prior resolution)

Recovery: Fix the agent ID in the AgentTest column config and re-run apply_grid
with only the failed columns. The successfully created columns are preserved.
Worksheet ID: 1W1xx001
```

The `apply_grid` tool should:
1. **Never roll back** successfully created columns on partial failure.
2. Return the worksheet ID and column map so Claude can fix and retry.
3. Include a `recovery` field with the specific next step.

---

## 3. Claude Code Integration

### 3.1 Skill Reference Doc (Compact DSL Reference)

Replace the current ~900-line `column-configs.md` with a compact DSL reference that Claude loads into context. The DSL reference should be **under 200 lines** and focus on the YAML syntax, not raw JSON.

**File:** `skills/grid-api/references/dsl-reference.md`

**Structure:**

```markdown
# Grid YAML DSL Quick Reference

## Minimal Example
```yaml
name: My Test Suite
columns:
  - name: Utterances
    type: Text
  - name: Agent Output
    type: AgentTest
    agent: Sales_Assistant
    input_column: Utterances
  - name: Quality
    type: Evaluation
    eval_type: COHERENCE
    input: Agent Output
```

## Column Types (one-liner each)
- **Text**: `{name, type: Text}` -- static input
- **AI**: `{name, type: AI, model, prompt, response_format?}` -- LLM generation
- **Agent**: `{name, type: Agent, agent, utterance, context_variables?}`
- **AgentTest**: `{name, type: AgentTest, agent, input_column}`
- **Object**: `{name, type: Object, object, fields, filters?}`
- **Evaluation**: `{name, type: Evaluation, eval_type, input, reference?}`
- **Reference**: `{name, type: Reference, source, field}`
- **Formula**: `{name, type: Formula, formula, return_type}`
- **PromptTemplate**: `{name, type: PromptTemplate, template, model, inputs}`
- **InvocableAction**: `{name, type: InvocableAction, action_type, action_name, input_payload}`
- **DataModelObject**: `{name, type: DataModelObject, dmo, dataspace, fields}`
- **Action**: `{name, type: Action, action_name, input_params?}`

## Model Shorthands
gpt-4-omni, gpt-5, claude-sonnet-4.5, gemini-2.5-flash, gemini-2.5-pro

## Evaluation Types
No-reference: COHERENCE, CONCISENESS, FACTUALITY, INSTRUCTION_FOLLOWING, COMPLETENESS, LATENCY_ASSERTION, EXPRESSION_EVAL
Needs reference: RESPONSE_MATCH, TOPIC_ASSERTION, ACTION_ASSERTION, BOT_RESPONSE_RATING, CUSTOM_LLM_EVALUATION
```

This replaces the 900-line reference with ~100 lines. The `apply_grid` tool handles all the JSON complexity internally.

### 3.2 Tool Description: How Claude Learns the YAML Format

The `apply_grid` MCP tool description itself teaches Claude the format. This is the primary discovery mechanism.

**Proposed tool description:**

```
apply_grid - Create or update an Agentforce Grid worksheet from a YAML specification.

The YAML spec declares columns declaratively. The tool handles:
- Creating workbook/worksheet if needed
- Resolving column name references to IDs
- Building the nested JSON configs
- Creating columns in dependency order
- Triggering row execution

YAML format:
  name: <worksheet name>          # Required
  workbook: <name or ID>          # Optional (creates new if omitted)
  worksheet: <ID>                 # Optional (for updating existing)
  rows: <number>                  # Optional (default: 50)
  columns:                        # Required, list of column specs
    - name: <column name>         # Required
      type: <column type>         # Required: Text, AI, Agent, AgentTest,
                                  #   Object, Evaluation, Reference, Formula,
                                  #   PromptTemplate, InvocableAction, Action,
                                  #   DataModelObject
      # ... type-specific fields (see skill reference)
  data:                           # Optional, initial data
    <column_name>:
      - "value 1"
      - "value 2"

Example - Agent test suite:
  name: Sales Agent Tests
  columns:
    - name: Utterances
      type: Text
    - name: Agent Output
      type: AgentTest
      agent: Sales_Assistant       # Agent name (resolved to ID automatically)
      input_column: Utterances     # References column by name
    - name: Quality
      type: Evaluation
      eval_type: COHERENCE
      input: Agent Output          # References column by name
  data:
    Utterances:
      - "How do I reset my password?"
      - "What is your return policy?"

Input: yaml_spec (string) - The YAML specification
Output: Created worksheet ID, column IDs, and status summary
```

### 3.3 PostToolUse Hook: ASCII Table Rendering

After any Grid MCP tool that mutates state, render the current worksheet as a compact ASCII table.

**Hook trigger:** `mcp__agentforce-grid__apply_grid`, `mcp__agentforce-grid__add_column`, `mcp__agentforce-grid__edit_column`, `mcp__agentforce-grid__paste_data`, `mcp__agentforce-grid__update_cells`, `mcp__agentforce-grid__trigger_row_execution`, `mcp__agentforce-grid__add_rows`, `mcp__agentforce-grid__reprocess_column`

**Implementation:** `hooks/post-api-call.sh`

**Behavior:**
1. Read tool output JSON from stdin.
2. Extract `worksheet_id` from the tool result (or from session state).
3. Call `GET /worksheets/{id}/data` to fetch fresh state.
4. Render as compact ASCII table.

**Output format:**

```
Grid: Sales Agent Tests (1W1xx001)
Workbook: Agent Test Suite (1W4xx001)

| #  | Utterances              | Agent Output     | Quality    |
|----|-------------------------|------------------|------------|
| 1  | How do I reset my pa... | [InProgress]     | [New]      |
| 2  | What is your return ... | [InProgress]     | [New]      |
| 3  | Can I speak to a ma... | [Complete] I c...| [New]      |

Status: 1/3 complete, 2 in progress | Columns: 3 | Rows: 3
```

**Rendering rules:**
- Truncate cell content to 20 characters with `...`
- Show `[Status]` prefix for non-Complete processing cells
- Show first 10 rows; if more, show `... and 40 more rows`
- Include status summary line at bottom
- Total output should be under 30 lines to avoid flooding the conversation

**When NOT to render:**
- After `list_workbooks` or `get_workbooks` (read-only, no worksheet context)
- After `delete_workbook` or `delete_worksheet` (nothing to render)
- When tool call failed (show error instead)

### 3.4 Session State Management

Claude needs to track the "active" workbook and worksheet across conversation turns to avoid asking "which worksheet?" repeatedly.

**Mechanism:** The MCP server maintains session state internally.

```typescript
interface SessionState {
  active_workbook_id: string | null;
  active_workbook_name: string | null;
  active_worksheet_id: string | null;
  active_worksheet_name: string | null;
  column_map: Record<string, string>;  // name -> id
  last_agent_id: string | null;
  last_model: string | null;
}
```

**State transitions:**

| Event | State Update |
|-------|-------------|
| `apply_grid` creates new worksheet | Set active workbook + worksheet to created IDs. Populate column_map. |
| `apply_grid` updates existing worksheet | Set active worksheet. Merge column_map. |
| `get_worksheet` or `get_worksheet_data` called | Set active worksheet to the queried ID. |
| `add_column` called | Add column to column_map. |
| `delete_worksheet` called | Clear active worksheet if it matches. |
| User says "switch to worksheet X" | Claude calls `get_worksheet(X)`, which updates state. |

**How Claude uses state:**
- When a tool requires `worksheet_id` and the user doesn't specify one, Claude uses `active_worksheet_id`.
- When building column references, Claude uses `column_map` to resolve names to IDs.
- The MCP server exposes a `grid_session_state` resource at `grid://session` that Claude can read.

**State is NOT persisted across sessions.** Each new Claude Code session starts fresh. The user can re-establish context by calling `get_workbooks` or providing a worksheet ID.

### 3.5 Discovery Flow: How Claude Finds and Uses Grid Tools

The discovery path for Claude, in priority order:

1. **Skill SKILL.md** -- Loaded when the user's task matches the skill description keywords (agentforce, grid, workbench, agent testing, evaluation). Points Claude to the DSL reference and the `apply_grid` tool.

2. **Tool descriptions** -- The `apply_grid` tool description (Section 3.2) contains a complete YAML example. Claude reads this when it discovers the tool.

3. **DSL reference doc** -- The compact reference (Section 3.1) is loaded as a skill reference. Provides the column type quick reference and model shorthands.

4. **PostToolUse hook output** -- After every mutation, Claude sees the grid state rendered as ASCII. This teaches Claude the grid's current shape without reading docs.

**What to remove from Claude's context:**
- The 900-line `column-configs.md` -- replaced by DSL reference (~100 lines)
- The raw JSON examples in `use-case-patterns.md` -- replaced by YAML examples
- The API endpoint reference -- Claude uses MCP tools, not raw HTTP

**Net context reduction:** ~2,500 lines of reference docs reduced to ~200 lines of DSL reference + tool description.

---

## 4. Example End-to-End Conversations

### 4.1 Creating a New Agent Test Suite from Scratch

```
USER: Create a test suite for my Sales Assistant agent with 10 utterances.
      Evaluate coherence and topic routing.

CLAUDE (thinking):
  - User wants: AgentTest pipeline with evaluations
  - Need: agent name resolution, utterance column, evaluation columns
  - I'll use apply_grid with YAML spec

CLAUDE: I'll create an agent test suite. Let me first find your Sales Assistant
agent.

  [Calls: grid_list_agents]

  Found: Sales_Assistant (0XxRM001, version 0XyRM001, active)

  Now I'll create the grid.

  [Calls: apply_grid with YAML:]
  ```yaml
  name: Sales Assistant Test Suite
  rows: 10
  columns:
    - name: Test Utterances
      type: Text
    - name: Expected Topics
      type: Text
    - name: Agent Output
      type: AgentTest
      agent: 0XxRM001/0XyRM001
      input_column: Test Utterances
    - name: Coherence
      type: Evaluation
      eval_type: COHERENCE
      input: Agent Output
    - name: Topic Routing
      type: Evaluation
      eval_type: TOPIC_ASSERTION
      input: Agent Output
      reference: Expected Topics
  ```

  [PostToolUse hook renders:]

  Grid: Sales Assistant Test Suite (1W1xx001)

  | #  | Test Utterances | Expected Topics | Agent Output | Coherence | Topic Routing |
  |----|-----------------|-----------------|--------------|-----------|---------------|
  | 1  | [empty]         | [empty]         | [New]        | [New]     | [New]         |
  | 2  | [empty]         | [empty]         | [New]        | [New]     | [New]         |
  ...

  Status: 0/10 complete | Columns: 5 | Rows: 10

CLAUDE: Created the test suite with 5 columns and 10 empty rows.

  **Worksheet:** Sales Assistant Test Suite (1W1xx001)
  **Columns:** Test Utterances, Expected Topics, Agent Output, Coherence, Topic Routing

  Next steps:
  1. Paste your test utterances into the "Test Utterances" column
  2. Fill "Expected Topics" with ground truth topic names
  3. The agent and evaluations will auto-process once data is populated

  Want me to add some sample utterances, or do you have a CSV?

USER: Here are my test cases:
  1. How do I reset my password?
  2. What is your return policy?
  3. I want to cancel my subscription
  ...

CLAUDE:
  [Calls: paste_data with the utterances into Test Utterances column]
  [Calls: trigger_row_execution]

  [PostToolUse hook renders updated state with processing status]

CLAUDE: Loaded 10 utterances and triggered processing. The agent is now running
  against each utterance. Evaluations will auto-run as agent responses complete.
  Use `/grid-status` to check progress.
```

### 4.2 Modifying an Existing Grid

```
USER: Add a conciseness evaluation to the grid we just made. Also change
      the agent test to use the draft version.

CLAUDE (thinking):
  - Session state has active_worksheet_id = 1W1xx001
  - Need to: (1) add Evaluation column, (2) update AgentTest column
  - I can use add_column for the evaluation, edit_column for the agent update

CLAUDE: I'll add the conciseness evaluation and update the agent to use the
  draft version.

  [Calls: add_column on worksheet 1W1xx001]
  {
    "name": "Conciseness",
    "type": "Evaluation",
    "config": {
      "type": "Evaluation",
      "queryResponseFormat": {"type": "EACH_ROW"},
      "autoUpdate": true,
      "config": {
        "autoUpdate": true,
        "evaluationType": "CONCISENESS",
        "inputColumnReference": {
          "columnId": "1W5xx003",
          "columnName": "Agent Output",
          "columnType": "AGENT_TEST"
        },
        "autoEvaluate": true
      }
    }
  }

  [Calls: edit_column on Agent Output column]
  Update: isDraft: true

  [Calls: reprocess_column on Agent Output]

  [PostToolUse hook renders:]

  Grid: Sales Assistant Test Suite (1W1xx001)

  | #  | Test Utterances     | Agent Output  | Coherence  | Topic Routing | Conciseness |
  |----|---------------------|---------------|------------|---------------|-------------|
  | 1  | How do I reset m... | [InProgress]  | [Stale]    | [Stale]       | [New]       |
  | 2  | What is your ret... | [InProgress]  | [Stale]    | [Stale]       | [New]       |
  ...

  Status: 0/10 complete, 10 reprocessing | Columns: 6 | Rows: 10

CLAUDE: Done. Added "Conciseness" evaluation column and switched Agent Output
  to use the draft agent version. All rows are reprocessing -- the existing
  coherence and topic routing evaluations are now stale and will re-evaluate
  once the agent responses complete.
```

### 4.3 Debugging a Failed Grid

```
USER: My grid has a bunch of failures. Can you figure out what's wrong?

CLAUDE (thinking):
  - Need to check the active worksheet for failed cells
  - Read the worksheet data and look for Failed status

  [Calls: get_worksheet_data on active worksheet 1W1xx001]

CLAUDE: I see 4 of 10 rows have failures in the Agent Output column. Let me
  check the details.

  **Failed Rows:**

  | Row | Utterance                          | Agent Output Status | Error |
  |-----|------------------------------------|---------------------|-------|
  | 3   | "I need to cancel and also..."     | Failed | Agent response timeout (120s) |
  | 5   | ""                                 | Failed | Empty input utterance |
  | 7   | "Transfer me to a human agent"     | Failed | Agent 0XxRM001 version not found |
  | 9   | "What is the meaning of life?"     | Failed | Agent response timeout (120s) |

  **Analysis:**

  1. **Rows 3, 9 (timeout):** These utterances are complex or off-topic. The
     agent may be entering a long reasoning loop. Consider simplifying the
     utterances or checking if the agent has a fallback topic.

  2. **Row 5 (empty input):** The utterance cell is empty. Either add a test
     case or delete this row.

  3. **Row 7 (version not found):** You switched to draft mode, but the draft
     version may have been published or deleted. Let me check.

  [Calls: grid_list_agents(includeDrafts: true)]

  The draft version ID changed -- the agent was re-published. The new draft
  version is 0XyRM002.

  **Suggested fixes:**
  1. Update the agent column to use version 0XyRM002
  2. Add an utterance to row 5
  3. Simplify the complex utterances in rows 3 and 9, or accept timeouts

  Want me to apply fixes 1 and 2 automatically?

USER: Yes, fix those. For row 5, use "What are your business hours?"

CLAUDE:
  [Calls: edit_column -- update agent version to 0XyRM002]
  [Calls: update_cells -- set row 5 utterance to "What are your business hours?"]
  [Calls: trigger_row_execution -- reprocess rows 3, 5, 7, 9]

  [PostToolUse hook renders updated state]

CLAUDE: Applied fixes. Updated the agent version and added the missing utterance.
  Reprocessing the 4 failed rows now. The other 6 rows are unchanged.
```

---

## Appendix A: Validation Pass Summary

```
YAML Input
  |
  v
Pass 1: YAML Parse + Schema (Y-xxx errors)
  |
  v
Pass 2: Type-Specific Required Fields (T-xxx errors)
  |
  v
Pass 3: Reference Integrity (R-xxx errors)
  |
  v
Pass 4: Circular Dependency Detection (D-xxx errors)
  |
  v
Pass 5: Type Compatibility (C-xxx errors)
  |
  v
Pass 6: Value Validation (V-xxx errors)
  |
  v
Resolution Engine (resolve names to IDs, build JSON configs)
  |
  v
Sequential Column Creation (API calls)
  |
  v
Partial Failure Handling (report successes + failures)
```

## Appendix B: PreToolUse Hook Implementation Sketch

```python
#!/usr/bin/env python3
"""PreToolUse hook for validating raw JSON column configs."""

import json
import sys

COLUMN_TYPES = {"AI", "Agent", "AgentTest", "Object", "Formula", "Reference",
                "Evaluation", "PromptTemplate", "InvocableAction", "Action",
                "Text", "DataModelObject"}

UPPERCASE_TYPES = {"AI": "AI", "Agent": "AGENT", "AgentTest": "AGENT_TEST",
                   "Object": "OBJECT", "Formula": "FORMULA", "Reference": "REFERENCE",
                   "Evaluation": "EVALUATION", "PromptTemplate": "PROMPT_TEMPLATE",
                   "InvocableAction": "INVOCABLE_ACTION", "Action": "ACTION",
                   "Text": "TEXT", "DataModelObject": "DATA_MODEL_OBJECT"}


def validate(tool_input: dict) -> dict:
    """Validate column config and return hook decision."""
    config_str = tool_input.get("config", "")
    try:
        config = json.loads(config_str) if isinstance(config_str, str) else config_str
    except json.JSONDecodeError:
        return block("Config is not valid JSON.")

    # H-001: Nested config.config structure
    outer_config = config.get("config")
    if not outer_config or not isinstance(outer_config, dict):
        return block("MISSING_NESTED_CONFIG: Column config is missing the nested "
                     "config.config structure. Wrap column-specific fields inside "
                     "config.config: {\"config\": {\"type\": \"...\", \"config\": {...}}}")

    inner_config = outer_config.get("config")
    if not inner_config or not isinstance(inner_config, dict):
        return block("MISSING_NESTED_CONFIG: config.config (inner config) is missing.")

    # H-002: Type consistency
    outer_type = config.get("type", "")
    config_type = outer_config.get("type", "")
    if outer_type and config_type and outer_type != config_type:
        return block(f"TYPE_MISMATCH: Outer type '{outer_type}' != config.type "
                     f"'{config_type}'. Set both to '{outer_type}'.")

    col_type = outer_type or config_type

    # H-003: UPPERCASE columnType in referenceAttributes
    for key in ("referenceAttributes", "utteranceReferences"):
        refs = inner_config.get(key, [])
        for i, ref in enumerate(refs):
            ct = ref.get("columnType", "")
            if ct and ct != ct.upper():
                return block(f"LOWERCASE_COLUMN_TYPE: {key}[{i}].columnType is "
                             f"'{ct}' but must be UPPERCASE '{ct.upper()}'.")

    # H-004: modelConfig completeness
    if col_type in ("AI", "PromptTemplate"):
        mc = inner_config.get("modelConfig", {})
        if not mc.get("modelId"):
            return block("INCOMPLETE_MODEL_CONFIG: modelConfig is missing 'modelId'.")
        if not mc.get("modelName"):
            return block("INCOMPLETE_MODEL_CONFIG: modelConfig is missing 'modelName'.")

    # H-008: AI mode
    if col_type == "AI" and not inner_config.get("mode"):
        return block("MISSING_AI_MODE: AI column config is missing 'mode: \"llm\"'.")

    # H-009: AI responseFormat
    if col_type == "AI" and not inner_config.get("responseFormat"):
        return block("MISSING_RESPONSE_FORMAT: AI column config is missing "
                     "'responseFormat'. Add {\"type\": \"PLAIN_TEXT\", \"options\": []}.")

    # H-010: ContextVariable conflict
    for cv in inner_config.get("contextVariables", []):
        if cv.get("value") and cv.get("reference"):
            return block(f"CONTEXT_VAR_CONFLICT: Context variable "
                         f"'{cv.get('variableName', '?')}' has both value and reference.")

    # H-011: Empty Text config
    if col_type == "Text" and not inner_config:
        return block("EMPTY_TEXT_CONFIG: Text column has empty inner config. "
                     "Add at least {\"autoUpdate\": true}.")

    return approve()


def block(reason: str) -> dict:
    return {"decision": "block", "reason": reason}


def approve() -> dict:
    return {"decision": "approve"}


if __name__ == "__main__":
    hook_input = json.load(sys.stdin)
    tool_input = hook_input.get("tool_input", {})
    result = validate(tool_input)
    json.dump(result, sys.stdout)
```

## Appendix C: PostToolUse Hook Implementation Sketch

```bash
#!/usr/bin/env bash
# PostToolUse hook: render grid state after mutations
# Reads tool output from stdin, fetches fresh worksheet data, renders ASCII table

set -euo pipefail

HOOK_INPUT=$(cat)
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""')
TOOL_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_output // ""')

# Extract worksheet ID from tool output or session
WORKSHEET_ID=$(echo "$TOOL_OUTPUT" | jq -r '.worksheet_id // .worksheetId // ""')

if [ -z "$WORKSHEET_ID" ]; then
  # Try session state file
  WORKSHEET_ID=$(cat /tmp/grid-session-worksheet 2>/dev/null || echo "")
fi

if [ -z "$WORKSHEET_ID" ]; then
  exit 0  # No worksheet context, skip rendering
fi

# Save for future hooks
echo "$WORKSHEET_ID" > /tmp/grid-session-worksheet

# Fetch fresh worksheet data
DATA=$(sf api request rest \
  "$SF_INSTANCE_URL/services/data/v66.0/public/grid/worksheets/$WORKSHEET_ID/data")

if [ $? -ne 0 ] || [ -z "$DATA" ]; then
  exit 0  # Silently skip if fetch fails
fi

# Render using Python for better formatting
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/render-grid.py" <<< "$DATA"
```
