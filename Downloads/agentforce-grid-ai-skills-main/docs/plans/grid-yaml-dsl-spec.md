> **Status:** ACTIVE | Phase 1 deliverable | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) Phase 1.5 (YAML parser)
> **What changed:** Added note on top-level format alignment. The hybrid plan recommends flat top-level (`workbook:`, `worksheet:`, `columns:`) matching the resolution engine spec, NOT the `grid:` wrapper used in examples throughout this doc. The `grid:` wrapper in examples below should be treated as the outer key that the parser strips, or removed entirely. See "Format Alignment Note" below.

# Grid YAML DSL Specification

**Version:** 1.0.0
**Date:** 2026-03-06
**Status:** ~~Draft~~ Active (Phase 1 deliverable)

---

## 1. Overview

The Grid YAML DSL provides a flat, human-readable format for defining Agentforce Grid worksheets. It replaces the deeply-nested JSON column configs (GCC) with a format optimized for Claude Code authoring speed and correctness. A resolution engine (`apply_grid`) reads the YAML, resolves names to IDs, infers defaults, and issues the correct API calls.

### Design Principles

1. **Column names as references** -- never column IDs. The engine resolves names at apply time.
2. **Agent names, not IDs** -- `agent: "Sales Coach"` resolved via `GET /agents`.
3. **Model shorthands** -- `model: gpt-4-omni` instead of `sfdc_ai__DefaultGPT4Omni`.
4. **Flat config** -- no `config.config` nesting. Keys sit directly on the column.
5. **Auto-inferred queryResponseFormat** -- Object/DataModelObject/CSV-import columns default to `WHOLE_COLUMN`; everything else defaults to `EACH_ROW`.
6. **Sensible defaults** -- `autoUpdate: true`, `numberOfRows: 50`, `model: gpt-4-omni`, `responseFormat: plain_text`.
7. **Evaluation shorthand** -- `type: eval/coherence` instead of full Evaluation config.
8. **Compact and explicit forms** -- simple columns in one line, complex columns with full detail.

---

## 2. Top-Level Structure

### Format Alignment Note

> **IMPORTANT:** The hybrid plan and resolution engine spec use a **flat top-level format** (no `grid:` wrapper). The examples in this spec use `grid:` as a top-level key for historical reasons. When implementing the parser (Phase 1.5), use the flat format as the canonical form:

```yaml
# CANONICAL FORMAT (flat top-level, per hybrid plan):
workbook: "My Workbook"
worksheet: "My Worksheet"
columns:
  - ...

# ALSO ACCEPTED (grid: wrapper, for backwards compatibility):
grid:
  workbook: "My Workbook"
  ...
```

The hybrid plan's `GridSpec` interface defines the flat structure:
```typescript
interface GridSpec {
  workbook: string;
  worksheet: string;
  defaults: { numberOfRows: number; model: string };
  columns: ColumnSpec[];
  data?: Record<string, string[]>;
}
```

### Original Format (with grid: wrapper)

```yaml
grid:
  workbook: "My Workbook"            # Create or match existing workbook by name
  worksheet: "My Worksheet"          # Create or match existing worksheet by name
  numberOfRows: 50                   # Default for all columns (optional, default: 50)
  model: gpt-4-omni                  # Default model for all AI/PromptTemplate columns
  columns:
    - ... column definitions ...
  data:                              # Optional: seed data for text columns
    "Column Name":
      - "row 1 value"
      - "row 2 value"
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `workbook` | string | Yes | -- | Workbook name. Created if it doesn't exist. |
| `worksheet` | string | Yes | -- | Worksheet name. Created if it doesn't exist. |
| `numberOfRows` | integer | No | `50` | Default row count for all columns. |
| `model` | string | No | `gpt-4-omni` | Default model shorthand for AI/PromptTemplate columns. |
| `columns` | list | Yes | -- | Ordered list of column definitions. |
| `data` | map | No | -- | Map of column name to list of string values (for Text columns). |

---

## 3. Model Shorthands

| Shorthand | Resolves To |
|-----------|-------------|
| `gpt-4-omni` | `sfdc_ai__DefaultGPT4Omni` |
| `gpt-4.1` | `sfdc_ai__DefaultGPT41` |
| `gpt-5` | `sfdc_ai__DefaultGPT5` |
| `gpt-5-mini` | `sfdc_ai__DefaultGPT5Mini` |
| `o3` | `sfdc_ai__DefaultO3` |
| `o4-mini` | `sfdc_ai__DefaultO4Mini` |
| `claude-4.5-sonnet` | `sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet` |
| `claude-4-sonnet` | `sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet` |
| `gemini-2.5-flash` | `sfdc_ai__DefaultVertexAIGemini25Flash001` |
| `gemini-2.5-pro` | `sfdc_ai__DefaultVertexAIGeminiPro25` |

Full `sfdc_ai__*` names are also accepted and passed through unchanged.

---

## 4. Column Reference Syntax

Columns reference other columns **by name**. The resolution engine maps names to IDs.

### In instructions/utterances (positional placeholders)

Use `{ColumnName}` or `{ColumnName.FieldName}` directly in prompt text. The engine converts these to `{$1}`, `{$2}`, etc. and builds `referenceAttributes` automatically.

```yaml
instruction: |
  Summarize this company:
  Name: {Accounts.Name}
  Industry: {Accounts.Industry}
```

The engine parses `{Accounts.Name}` and `{Accounts.Industry}`, creates two referenceAttributes pointing to the "Accounts" column with fieldNames "Name" and "Industry", and rewrites the instruction to use `{$1}` and `{$2}`.

### In evaluation/reference configs (direct name reference)

```yaml
input: "Agent Output"          # References column named "Agent Output"
reference: "Expected Response"  # References column named "Expected Response"
source: "Flow Result"           # For Reference columns
```

---

## 5. Column Type Definitions

### 5.1 Text Column

Static or editable text input.

**Compact form:**
```yaml
- name: Test Utterances
  type: text
```

**CSV import form:**
```yaml
- name: Imported Data
  type: text
  documentId: "069xxxxxxxxxxxxxxx"
  documentColumnIndex: 0
  includeHeaders: true
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `text` | Yes | -- | -- |
| `documentId` | string | No | -- | Salesforce document ID for CSV import |
| `documentColumnIndex` | integer | No | -- | CSV column index |
| `includeHeaders` | boolean | No | -- | Include CSV headers |

**queryResponseFormat:** Auto-inferred as `WHOLE_COLUMN` when `documentId` is present, otherwise none (manual entry).

---

### 5.2 AI Column

Generate text using an LLM with custom prompts.

**Compact form:**
```yaml
- name: Summary
  type: ai
  instruction: "Summarize: {Source}"
```

**Full form:**
```yaml
- name: Draft Email
  type: ai
  model: claude-4.5-sonnet
  instruction: |
    Write a personalized email for:
    Name: {Leads.FirstName}
    Title: {Leads.Title}
    Company: {Leads.Company}
  responseFormat: plain_text
```

**Single-select classification:**
```yaml
- name: Sentiment
  type: ai
  instruction: "Classify the sentiment: {CustomerFeedback}"
  responseFormat:
    type: single_select
    options:
      - Positive
      - Negative
      - Neutral
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `ai` | Yes | -- | -- |
| `model` | string | No | worksheet default | Model shorthand |
| `instruction` | string | Yes | -- | Prompt with `{ColumnName}` or `{ColumnName.FieldName}` refs |
| `responseFormat` | string or object | No | `plain_text` | `plain_text` or `{type: single_select, options: [...]}` |
| `numberOfRows` | integer | No | worksheet default | Override row count |

**responseFormat options shorthand:** When `options` is a list of strings, the engine expands each to `{label: "Value", value: "value"}` (label = original, value = lowercased). For full control, use `{label: "Display", value: "api_value"}` objects.

---

### 5.3 Object Column

Query Salesforce SObjects.

```yaml
- name: Accounts
  type: object
  object: Account
  fields:
    - Id
    - Name
    - Industry: picklist
    - Description: textarea
    - AnnualRevenue: currency
  filters:
    - field: Industry
      operator: in
      values: [Technology, Finance]
```

**Advanced SOQL form:**
```yaml
- name: Custom Query
  type: object
  object: Account
  soql: |
    SELECT Id, Name, Industry FROM Account
    WHERE Industry = '{TargetIndustry}'
    AND CreatedDate > LAST_N_DAYS:30
    LIMIT 50
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `object` | Yes | -- | -- |
| `object` | string | Yes | -- | SObject API name |
| `fields` | list | Yes (basic) | -- | Field names or `name: type` maps |
| `filters` | list | No | -- | Filter conditions |
| `soql` | string | No | -- | Raw SOQL (activates advancedMode) |
| `numberOfRows` | integer | No | worksheet default | Override row count |

**Field type inference:** Plain strings default to type `string`. Use `FieldName: type` for other types. Common types: `id`, `string`, `picklist`, `textarea`, `currency`, `date`, `datetime`, `boolean`, `double`, `integer`, `reference`.

**Filter operator shorthands:** `in`, `not_in`, `eq`, `neq`, `contains`, `starts_with`, `ends_with`, `is_null`, `is_not_null`, `lt`, `lte`, `gt`, `gte`. These map to the API's PascalCase operators (`In`, `NotIn`, `EqualTo`, etc.).

**queryResponseFormat:** Always `WHOLE_COLUMN` (auto-inferred).

---

### 5.4 DataModelObject Column

Query Data Cloud DMOs.

```yaml
- name: Unified Individuals
  type: data_model_object
  dmo: UnifiedIndividual__dlm
  dataspace: default
  fields:
    - Id__c
    - FirstName__c
    - LastName__c
    - Email__c
```

**Advanced DCSQL form:**
```yaml
- name: Custom DMO Query
  type: data_model_object
  dmo: UnifiedIndividual__dlm
  dataspace: default
  dcsql: |
    SELECT Id__c, FirstName__c, Email__c
    FROM UnifiedIndividual__dlm
    WHERE Email__c LIKE '%{EmailDomain}%'
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `data_model_object` | Yes | -- | -- |
| `dmo` | string | Yes | -- | DMO API name |
| `dataspace` | string | Yes | -- | Data Cloud dataspace name |
| `fields` | list | Yes (basic) | -- | Field names |
| `filters` | list | No | -- | Same format as Object filters |
| `dcsql` | string | No | -- | Raw DCSQL (activates advancedMode) |

**queryResponseFormat:** Always `WHOLE_COLUMN` (auto-inferred).

---

### 5.5 Agent Column

Run agent conversations with dynamic inputs.

```yaml
- name: Sales Agent Response
  type: agent
  agent: "Sales Coach"
  utterance: "Hello, I need help with {CustomerQuery}"
  contextVariables:
    CustomerName: {Customers.Name}
    Priority: "High"
```

**Multi-turn form:**
```yaml
- name: Turn 2 Response
  type: agent
  agent: "Sales Coach"
  utterance: "{Turn 2 Utterance}"
  conversationHistory: "Turn 1 Response"
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `agent` | Yes | -- | -- |
| `agent` | string | Yes | -- | Agent name (resolved to agentId/agentVersion via API) |
| `utterance` | string | Yes | -- | Message with `{ColumnName}` refs |
| `contextVariables` | map | No | -- | Map of variable name to value or `{ColumnName}` / `{ColumnName.FieldName}` ref |
| `conversationHistory` | string | No | -- | Column name of prior Agent turn |
| `initialState` | string | No | -- | Column name for initial state |
| `numberOfRows` | integer | No | worksheet default | Override row count |

**contextVariables resolution:** String values are treated as static. Values wrapped in `{...}` are parsed as column references. The engine determines the type automatically.

---

### 5.6 AgentTest Column

Test agents with utterances from a column.

```yaml
- name: Agent Output
  type: agent_test
  agent: "Sales Coach"
  inputUtterance: "Test Utterances"
  contextVariables:
    AccountId: {Accounts.Id}
```

**Draft agent testing:**
```yaml
- name: Draft Agent Output
  type: agent_test
  agent: "Sales Coach"
  inputUtterance: "Utterances"
  isDraft: true
  enableSimulationMode: true
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `agent_test` | Yes | -- | -- |
| `agent` | string | Yes | -- | Agent name |
| `inputUtterance` | string | Yes | -- | Column name containing test utterances |
| `contextVariables` | map | No | -- | Same as Agent column |
| `isDraft` | boolean | No | `false` | Test draft agent version |
| `enableSimulationMode` | boolean | No | `false` | Enable simulation mode |
| `conversationHistory` | string | No | -- | Column name for conversation history |
| `initialState` | string | No | -- | Column name for initial state |

---

### 5.7 Evaluation Column

Evaluate agent/prompt outputs. Supports a compact shorthand syntax.

**Shorthand form (most common):**
```yaml
- name: Coherence Score
  type: eval/coherence
  input: "Agent Output"

- name: Response Match
  type: eval/response_match
  input: "Agent Output"
  reference: "Expected Response"
```

**Full form:**
```yaml
- name: Custom Quality Check
  type: evaluation
  evaluationType: CUSTOM_LLM_EVALUATION
  input: "Agent Output"
  reference: "Evaluation Criteria"
  customEvaluation:
    type: llm
    apiName: Custom_Evaluation_Template
```

**Expression form:**
```yaml
- name: Topic Check
  type: eval/expression
  input: "Agent Output"
  formula: "{response.topicName} == 'Service'"
  returnType: boolean
```

#### Evaluation Type Shorthands

| Shorthand `type` | evaluationType | Requires `reference` |
|-------------------|----------------|---------------------|
| `eval/coherence` | `COHERENCE` | No |
| `eval/conciseness` | `CONCISENESS` | No |
| `eval/factuality` | `FACTUALITY` | No |
| `eval/instruction_following` | `INSTRUCTION_FOLLOWING` | No |
| `eval/completeness` | `COMPLETENESS` | No |
| `eval/response_match` | `RESPONSE_MATCH` | **Yes** |
| `eval/topic_assertion` | `TOPIC_ASSERTION` | **Yes** |
| `eval/action_assertion` | `ACTION_ASSERTION` | **Yes** |
| `eval/latency` | `LATENCY_ASSERTION` | No |
| `eval/response_rating` | `BOT_RESPONSE_RATING` | **Yes** |
| `eval/expression` | `EXPRESSION_EVAL` | No |
| `eval/custom_llm` | `CUSTOM_LLM_EVALUATION` | **Yes** |

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | string | Yes | -- | Shorthand or `evaluation` |
| `input` | string | Yes | -- | Column name to evaluate |
| `reference` | string | Conditional | -- | Column name for comparison (required for types marked **Yes**) |
| `evaluationType` | string | Conditional | -- | Required when `type: evaluation` (full form) |
| `formula` | string | Conditional | -- | For `eval/expression` only |
| `returnType` | string | No | `boolean` | For `eval/expression` only |
| `customEvaluation` | object | Conditional | -- | For `eval/custom_llm` only |
| `autoEvaluate` | boolean | No | `true` | Auto-run evaluation |

---

### 5.8 Reference Column

Extract specific fields from other columns.

```yaml
- name: Agent Topic
  type: reference
  source: "Agent Output"
  field: response.topicName

- name: Account Name
  type: reference
  source: "Accounts"
  field: Name

- name: First Bot Message
  type: reference
  source: "Agent Response"
  field: response.botMessages[0].text
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `reference` | Yes | -- | -- |
| `source` | string | Yes | -- | Column name to extract from |
| `field` | string | Yes | -- | JSON path to extract |

---

### 5.9 Formula Column

Compute values using formula expressions.

```yaml
- name: Full Name
  type: formula
  formula: "CONCATENATE({FirstName}, ' ', {LastName})"
  returnType: string

- name: Is High Value
  type: formula
  formula: "{Accounts.AnnualRevenue} > 100000"
  returnType: boolean
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `formula` | Yes | -- | -- |
| `formula` | string | Yes | -- | Formula with `{ColumnName}` or `{ColumnName.FieldName}` refs |
| `returnType` | string | Yes | -- | `string`, `boolean`, `double`, `integer`, `long`, `date`, `datetime`, `time`, `id`, `reference` |

---

### 5.10 PromptTemplate Column

Execute GenAI prompt templates.

```yaml
- name: Generated Emails
  type: prompt_template
  template: Customer_Support_Email
  model: gpt-4.1
  inputs:
    CustomerName: {Customers.Name}
    Issue: {CaseDescription}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `prompt_template` | Yes | -- | -- |
| `template` | string | Yes | -- | Prompt template developer name |
| `templateType` | string | No | `flex` | Template type |
| `model` | string | No | worksheet default | Model shorthand |
| `inputs` | map | Yes | -- | Map of input name to `{ColumnName}` or `{ColumnName.FieldName}` ref |

---

### 5.11 InvocableAction Column

Execute Flows, Apex, or other invocable actions.

```yaml
- name: Create Case
  type: invocable_action
  action:
    type: FLOW
    name: Create_Support_Case
  payload:
    Subject: "{Subject}"
    Description: "{Description}"
    Priority: "{Priority}"
```

**Apex action:**
```yaml
- name: Process Record
  type: invocable_action
  action:
    type: APEX
    name: ProcessRecordAction
  payload:
    recordId: "{Records.Id}"
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `invocable_action` | Yes | -- | -- |
| `action` | object | Yes | -- | `{type: FLOW/APEX, name: apiName}` |
| `payload` | map | Yes | -- | Input payload. Values in `"{ColumnName}"` are resolved as column refs. Plain strings are literal values. |

**payload resolution:** The engine serializes the map to JSON. Values matching the pattern `{ColumnName}` or `{ColumnName.FieldName}` are converted to `{$N}` placeholders with corresponding referenceAttributes. The engine also builds the `url` and `label` fields from the action type and name.

---

### 5.12 Action Column

Execute standard platform actions.

```yaml
- name: Chatter Post
  type: action
  actionName: chatterPost
  inputs:
    text: {Message}
```

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | Yes | -- | Column display name |
| `type` | `action` | Yes | -- | -- |
| `actionName` | string | Yes | -- | Platform action API name |
| `inputs` | map | No | -- | Map of param name to `{ColumnName}` ref |

---

## 6. Complete Examples

### 6.1 Agent Testing Pipeline

```yaml
grid:
  workbook: "Agent Test Suite"
  worksheet: "Sales Agent Tests"
  columns:
    - name: Test Utterances
      type: text

    - name: Expected Responses
      type: text

    - name: Expected Topics
      type: text

    - name: Agent Output
      type: agent_test
      agent: "Sales Coach"
      inputUtterance: "Test Utterances"

    - name: Response Match
      type: eval/response_match
      input: "Agent Output"
      reference: "Expected Responses"

    - name: Topic Check
      type: eval/topic_assertion
      input: "Agent Output"
      reference: "Expected Topics"

    - name: Coherence
      type: eval/coherence
      input: "Agent Output"

    - name: Latency
      type: eval/latency
      input: "Agent Output"

  data:
    "Test Utterances":
      - "I need help resetting my password"
      - "What is my account balance?"
      - "How do I upgrade my plan?"
    "Expected Responses":
      - "I can help you reset your password..."
      - "Let me look up your account balance..."
      - "Here are the available upgrade options..."
    "Expected Topics":
      - "Password_Reset"
      - "Account_Inquiry"
      - "Plan_Upgrade"
```

### 6.2 Data Enrichment with AI

```yaml
grid:
  workbook: "Data Enrichment"
  worksheet: "Account Summaries"
  model: claude-4.5-sonnet
  columns:
    - name: Accounts
      type: object
      object: Account
      fields:
        - Id
        - Name
        - Industry: picklist
        - Description: textarea
        - AnnualRevenue: currency
      filters:
        - field: Industry
          operator: in
          values: [Technology, Finance]

    - name: Company Summary
      type: ai
      instruction: |
        Write a brief 2-3 sentence summary of this company:
        Name: {Accounts.Name}
        Industry: {Accounts.Industry}
        Description: {Accounts.Description}
        Revenue: {Accounts.AnnualRevenue}
```

### 6.3 Prompt Quality Evaluation

```yaml
grid:
  workbook: "Prompt Testing"
  worksheet: "Email Quality"
  columns:
    - name: Customer Names
      type: text

    - name: Issues
      type: text

    - name: Generated Emails
      type: prompt_template
      template: Customer_Support_Email
      inputs:
        CustomerName: {Customer Names}
        Issue: {Issues}

    - name: Coherence
      type: eval/coherence
      input: "Generated Emails"

    - name: Completeness
      type: eval/completeness
      input: "Generated Emails"

    - name: Instruction Following
      type: eval/instruction_following
      input: "Generated Emails"
```

### 6.4 Flow Testing

```yaml
grid:
  workbook: "Flow Tests"
  worksheet: "Create Case Flow"
  columns:
    - name: Subject
      type: text

    - name: Description
      type: text

    - name: Priority
      type: text

    - name: Flow Result
      type: invocable_action
      action:
        type: FLOW
        name: Create_Support_Case
      payload:
        Subject: "{Subject}"
        Description: "{Description}"
        Priority: "{Priority}"

    - name: Case Id
      type: reference
      source: "Flow Result"
      field: outputValues.caseId

    - name: Status
      type: reference
      source: "Flow Result"
      field: outputValues.status
```

### 6.5 AI Classification

```yaml
grid:
  workbook: "Text Analysis"
  worksheet: "Feedback Classification"
  columns:
    - name: Customer Feedback
      type: text

    - name: Sentiment
      type: ai
      instruction: "Classify the sentiment of this customer feedback: {Customer Feedback}"
      responseFormat:
        type: single_select
        options:
          - Positive
          - Negative
          - Neutral

    - name: Category
      type: ai
      instruction: "Categorize this customer feedback: {Customer Feedback}"
      responseFormat:
        type: single_select
        options:
          - label: Product Issue
            value: product
          - label: Service Issue
            value: service
          - label: Billing Issue
            value: billing
          - label: Feature Request
            value: feature
          - label: General Inquiry
            value: general
```

### 6.6 Multi-Turn Conversation Testing

```yaml
grid:
  workbook: "Conversation Tests"
  worksheet: "Multi-Turn"
  columns:
    - name: Turn 1 Utterance
      type: text

    - name: Turn 1 Response
      type: agent
      agent: "Sales Coach"
      utterance: "{Turn 1 Utterance}"

    - name: Turn 2 Utterance
      type: text

    - name: Turn 2 Response
      type: agent
      agent: "Sales Coach"
      utterance: "{Turn 2 Utterance}"
      conversationHistory: "Turn 1 Response"
```

---

## 7. Resolution Engine Behavior

The `apply_grid` tool performs the following steps:

### 7.1 Parse and Validate

1. Parse YAML and validate against this schema.
2. Validate all column name references resolve to defined columns.
3. Validate evaluation types have required `reference` fields.
4. Validate model shorthands are recognized.

### 7.2 Build Dependency Graph

1. Parse `{ColumnName}` references from instructions, utterances, formulas, inputs, source, input, reference fields.
2. Build a directed acyclic graph of column dependencies.
3. Topologically sort columns for creation order.
4. Error if cycles are detected.

### 7.3 Resolve External References

1. **Agents:** `GET /agents` to resolve agent name to `agentId` + `agentVersion`.
2. **Models:** Map shorthand to `sfdc_ai__*` full name.
3. **Prompt Templates:** Validate template developer name exists via `GET /prompt-templates`.
4. **Invocable Actions:** Build `url` and `label` from action type and name.

### 7.4 Create Workbook and Worksheet

1. `GET /workbooks` to check if workbook exists by name. Create if not.
2. `GET /worksheets` to check if worksheet exists in workbook. Create if not.
3. If worksheet already exists, fetch existing columns for ID mapping.

### 7.5 Create Columns in Order

For each column in topological order:

1. Expand `{ColumnName}` / `{ColumnName.FieldName}` references to `{$N}` placeholders.
2. Build `referenceAttributes` array with resolved column IDs.
3. Infer `queryResponseFormat` based on column type and context.
4. Apply defaults (`autoUpdate`, `numberOfRows`, `model`, etc.).
5. Construct the full nested GCC JSON.
6. `POST /worksheets/{id}/columns` to create.
7. Record returned column ID for subsequent columns to reference.

### 7.6 Populate Data

1. Count required rows from `data` section (max across all columns).
2. `POST /worksheets/{id}/rows` to add rows.
3. `POST /worksheets/{id}/paste` with matrix of data values.

### 7.7 queryResponseFormat Inference Rules

| Column Type | Condition | Inferred Format |
|-------------|-----------|-----------------|
| Object | always | `WHOLE_COLUMN` + `OBJECT_PER_ROW` |
| DataModelObject | always | `WHOLE_COLUMN` + `OBJECT_PER_ROW` |
| Text | `documentId` present | `WHOLE_COLUMN` + `OBJECT_PER_ROW` |
| Text | no `documentId` | omitted (manual entry) |
| AI, Agent, AgentTest, Evaluation, Formula, Reference, PromptTemplate, InvocableAction, Action | always | `EACH_ROW` |

---

## 8. Type Name Mapping

DSL type names use `snake_case` for readability. The engine maps them to API type values.

| DSL `type` | API `type` value |
|------------|-----------------|
| `text` | `Text` |
| `ai` | `AI` |
| `object` | `Object` |
| `data_model_object` | `DataModelObject` |
| `agent` | `Agent` |
| `agent_test` | `AgentTest` |
| `evaluation` | `Evaluation` |
| `eval/*` (shorthands) | `Evaluation` |
| `reference` | `Reference` |
| `formula` | `Formula` |
| `prompt_template` | `PromptTemplate` |
| `invocable_action` | `InvocableAction` |
| `action` | `Action` |

---

## 9. Error Handling

| Error | Behavior |
|-------|----------|
| Unknown column name in reference | Fail with: `Column "{name}" referenced but not defined` |
| Cycle in dependency graph | Fail with: `Circular dependency detected: A -> B -> A` |
| Unknown model shorthand | Fail with: `Unknown model "{name}". Valid: gpt-4-omni, ...` |
| Missing required field | Fail with: `Column "{name}": missing required field "{field}"` |
| eval type missing `reference` | Fail with: `Column "{name}": eval/{type} requires "reference" field` |
| Agent not found | Fail with: `Agent "{name}" not found. Available: ...` |
| API column creation fails | Report error and stop (do not create dependent columns) |
