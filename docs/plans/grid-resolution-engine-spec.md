> **Status:** ACTIVE | Phase 1.8 | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) Phase 1.8 (resolution engine)
> **What changed:** The type definitions in Section 2 (GridSpec, ColumnConfig, etc.) are now superseded by the Zod schemas in `src/schemas.ts`. The config expander output MUST pass `ColumnConfigUnionSchema.parse()`. Do not duplicate types from schemas.ts. The `GridSpec` and `ResolutionContext` interfaces remain valid as new types not covered by schemas.ts. The `ColumnConfig` output types in Section 5 (Expand & Create) should import from `schemas.ts` rather than defining new ones.

# Grid Resolution Engine Architecture

**Version:** 1.0.0
**Date:** 2026-03-06
**Status:** ~~Draft~~ Active (Phase 1.8)

---

## 1. Overview

The resolution engine translates a parsed YAML DSL specification into a sequence of Grid API calls. It bridges the gap between human-readable declarative definitions (agent names, column name references, flat config) and the Grid API's requirements (Salesforce IDs, triple-nested config.config structures, sequential column creation with ID wiring).

### Core Pipeline

```
YAML Source
    |
    v
[1. Parse & Validate] --- syntax errors, missing fields
    |
    v
[2. Resolve Names] ------ agent names -> IDs, model aliases -> IDs, SObject validation
    |
    v
[3. Build Dependency Graph] - scan column references, construct DAG
    |
    v
[4. Topological Sort] --- Kahn's algorithm, detect cycles
    |
    v
[5. Expand & Create] ---- for each column in order:
    |                        - expand compact YAML -> full GCC JSON
    |                        - substitute resolved column IDs
    |                        - POST to API
    |                        - capture returned ID
    v
[6. Post-Create] --------- paste sample data, add rows, trigger execution
```

---

## 2. Data Structures

> **Note on types:** The types below (`GridSpec`, `ResolutionContext`, `DependencyGraph`, `ColumnSpec`) are NEW types defined by the resolution engine -- they do not duplicate anything in `src/schemas.ts`. However, the **output** of config expansion (Section 7) must produce objects conforming to `ColumnConfigUnionSchema` from `src/schemas.ts`. Do not define parallel `ColumnConfig`, `AIConfig`, etc. output types here.

### 2.1 Parsed Grid Spec

The output of YAML parsing, before any resolution. This is the engine's input.

```typescript
interface GridSpec {
  name: string;                          // Workbook name
  worksheets: WorksheetSpec[];
}

interface WorksheetSpec {
  name: string;
  defaults?: WorksheetDefaults;
  columns: ColumnSpec[];
  data?: DataSpec;                       // Inline data or CSV reference
}

interface WorksheetDefaults {
  model?: string;                        // Default LLM model alias
  numberOfRows?: number;
  autoUpdate?: boolean;
}

interface ColumnSpec {
  name: string;                          // Human-readable column name (used as ref key)
  type: string;                          // Column type or shorthand (e.g., "eval/coherence")
  // Flattened config fields — type-specific, varies by column type.
  // These are the compact YAML keys that get expanded into full GCC JSON.
  [key: string]: unknown;
}

interface DataSpec {
  inline?: Record<string, string[]>;     // columnName -> array of values
  csv?: { path: string; mapping: Record<string, number> };
}
```

### 2.2 Resolution Context

Accumulated state as the engine works through the pipeline. Passed between phases.

```typescript
interface ResolutionContext {
  // Resolved external names (populated in phase 2)
  agents: Map<string, ResolvedAgent>;        // agentName -> {definitionId, versionId, variables}
  models: Map<string, ResolvedModel>;        // alias -> {modelId, modelName}
  sobjects: Map<string, ResolvedSObject>;    // objectApiName -> {validated: true, fields: [...]}
  promptTemplates: Map<string, ResolvedPromptTemplate>;
  dataspaces: Map<string, string[]>;         // dataspace -> DMO names

  // Column resolution state (populated in phase 5, incrementally)
  columnIds: Map<string, string>;            // columnName -> columnId (filled as columns are created)
  columnTypes: Map<string, string>;          // columnName -> GCC type string (e.g., "AGENT_TEST")

  // Target worksheet state (for incremental apply)
  existingColumns: Map<string, ExistingColumn>;  // columnName -> {id, type, config}

  // API client
  worksheetId: string;
  workbookId: string;
}

interface ResolvedAgent {
  definitionId: string;                  // 0Xx...
  versionId: string;                     // 0Xy...
  contextVariables: AgentVariable[];     // From GET /agents/{versionId}/variables
  isDraft: boolean;
}

interface ResolvedModel {
  modelId: string;                       // e.g., "sfdc_ai__DefaultGPT4Omni"
  modelName: string;                     // Same as modelId for Grid API
}

interface ExistingColumn {
  id: string;
  name: string;
  type: string;
  config: unknown;
}
```

### 2.3 Dependency Graph

```typescript
interface DependencyGraph {
  // Adjacency list: column name -> set of column names it depends on
  edges: Map<string, Set<string>>;
  // All column names in the graph
  nodes: Set<string>;
}
```

### 2.4 Column Type Map

Maps DSL column types (including shorthands) to GCC type values and the uppercase columnType used in referenceAttributes.

```typescript
const TYPE_MAP: Record<string, { gccType: string; refType: string }> = {
  "ai":               { gccType: "AI",               refType: "AI" },
  "agent":            { gccType: "Agent",             refType: "AGENT" },
  "agent-test":       { gccType: "AgentTest",         refType: "AGENT_TEST" },
  "object":           { gccType: "Object",            refType: "OBJECT" },
  "text":             { gccType: "Text",              refType: "TEXT" },
  "reference":        { gccType: "Reference",         refType: "REFERENCE" },
  "formula":          { gccType: "Formula",           refType: "FORMULA" },
  "prompt-template":  { gccType: "PromptTemplate",    refType: "PROMPT_TEMPLATE" },
  "invocable-action": { gccType: "InvocableAction",   refType: "INVOCABLE_ACTION" },
  "action":           { gccType: "Action",            refType: "ACTION" },
  "evaluation":       { gccType: "Evaluation",        refType: "EVALUATION" },
  "data-model-object":{ gccType: "DataModelObject",   refType: "DATA_MODEL_OBJECT" },
  // Evaluation shorthands
  "eval/response-match":      { gccType: "Evaluation", refType: "EVALUATION" },
  "eval/topic-assertion":     { gccType: "Evaluation", refType: "EVALUATION" },
  "eval/coherence":           { gccType: "Evaluation", refType: "EVALUATION" },
  "eval/latency":             { gccType: "Evaluation", refType: "EVALUATION" },
  "eval/custom-llm":          { gccType: "Evaluation", refType: "EVALUATION" },
  "eval/expression":          { gccType: "Evaluation", refType: "EVALUATION" },
  // ... additional eval shorthands
};
```

---

## 3. Phase 1: Parse and Validate

### 3.1 Validation Rules

Before any API calls, validate the spec structurally:

```
function validate(spec: GridSpec): ValidationError[]
  errors = []

  for each worksheet in spec.worksheets:
    columnNames = new Set()

    for each column in worksheet.columns:
      // 1. Column name uniqueness
      if columnNames.has(column.name):
        errors.push("Duplicate column name: '{column.name}'")
      columnNames.add(column.name)

      // 2. Valid column type
      if not TYPE_MAP.has(normalizeType(column.type)):
        errors.push("Unknown column type: '{column.type}'")

      // 3. Required fields per type
      errors.push(...validateRequiredFields(column))

      // 4. Column references exist
      for each ref in extractColumnReferences(column):
        if not columnNames.has(ref) and ref not in worksheet.columns[*].name:
          errors.push("Column '{column.name}' references unknown column '{ref}'")

  return errors
```

### 3.2 Required Fields by Type

| Type | Required Fields |
|------|----------------|
| AI | `prompt`, at least one column reference in prompt (`{ColumnName}` or `refs`) |
| Agent | `agent` (name or ID) |
| AgentTest | `agent`, `utterances` (column ref) |
| Object | `object` (SObject API name), `fields` |
| Text | (none beyond name) |
| Reference | `source` (column ref), `field` (JSON path) |
| Formula | `formula`, `return_type` |
| Evaluation | `target` (column ref); `evaluationType` or inferred from shorthand |
| PromptTemplate | `template` (dev name) |
| InvocableAction | `action_type`, `action_name` |
| Action | `action_name` |
| DataModelObject | `dmo`, `dataspace`, `fields` |

---

## 4. Phase 2: Resolve External Names

This phase resolves human-readable names to Salesforce IDs by calling discovery APIs. All resolution happens before column creation begins.

### 4.1 Agent Resolution

```
function resolveAgents(spec, context):
  // Collect all unique agent references from the spec
  agentRefs = collectAgentReferences(spec)  // Set of agent name strings

  if agentRefs.isEmpty():
    return

  // Fetch all agents from the org
  agents = GET /agents                       // mcp: get_agents
  draftAgents = GET /agents?includeDrafts=true  // mcp: get_agents_including_drafts

  for each agentName in agentRefs:
    // Match by developer name (case-insensitive)
    match = agents.find(a => a.developerName.toLowerCase() === agentName.toLowerCase())

    if not match:
      // Try matching by label
      match = agents.find(a => a.label.toLowerCase() === agentName.toLowerCase())

    if not match:
      throw ResolutionError("Agent not found: '{agentName}'. Available: {agents.map(a => a.developerName)}")

    // Get the active version (or draft if specified)
    version = match.activeVersion ?? match.latestVersion

    // Fetch context variables for this version
    variables = GET /agents/{version.id}/variables

    context.agents.set(agentName, {
      definitionId: match.id,
      versionId: version.id,
      contextVariables: variables,
      isDraft: version === match.latestVersion && !match.activeVersion
    })
```

### 4.2 Model Resolution

Model names in the YAML can be:
- Full API names: `sfdc_ai__DefaultGPT4Omni` (pass through)
- Short aliases: `gpt-4o`, `claude-4.5-sonnet`, `gemini-2.5-flash`

```
// Built-in alias map (extensible via config)
const MODEL_ALIASES: Record<string, string> = {
  "gpt-4o":              "sfdc_ai__DefaultGPT4Omni",
  "gpt-4.1":             "sfdc_ai__DefaultGPT41",
  "gpt-5":               "sfdc_ai__DefaultGPT5",
  "gpt-5-mini":          "sfdc_ai__DefaultGPT5Mini",
  "o3":                  "sfdc_ai__DefaultO3",
  "o4-mini":             "sfdc_ai__DefaultO4Mini",
  "claude-4.5-sonnet":   "sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet",
  "claude-4-sonnet":     "sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet",
  "gemini-2.5-flash":    "sfdc_ai__DefaultVertexAIGemini25Flash001",
  "gemini-2.5-pro":      "sfdc_ai__DefaultVertexAIGeminiPro25",
};

function resolveModels(spec, context):
  modelRefs = collectModelReferences(spec)  // includes worksheet defaults

  if modelRefs.isEmpty():
    return

  // Fetch available models to validate
  availableModels = GET /llm-models

  for each modelRef in modelRefs:
    // Check alias map first
    resolved = MODEL_ALIASES[modelRef.toLowerCase()] ?? modelRef

    // Validate against available models
    match = availableModels.find(m => m.name === resolved)
    if not match:
      throw ResolutionError(
        "Model not found: '{modelRef}' (resolved to '{resolved}'). " +
        "Available: {availableModels.map(m => m.name)}"
      )

    context.models.set(modelRef, { modelId: resolved, modelName: resolved })
```

### 4.3 SObject Resolution

```
function resolveSObjects(spec, context):
  sobjectRefs = collectSObjectReferences(spec)

  if sobjectRefs.isEmpty():
    return

  // Validate each SObject exists
  for each objectApiName in sobjectRefs:
    fields = GET /sobjects/{objectApiName}/fields
    if error:
      throw ResolutionError("SObject not found: '{objectApiName}'")

    context.sobjects.set(objectApiName, { validated: true, fields })
```

### 4.4 Prompt Template Resolution

```
function resolvePromptTemplates(spec, context):
  templateRefs = collectPromptTemplateReferences(spec)

  if templateRefs.isEmpty():
    return

  templates = GET /prompt-templates

  for each templateDevName in templateRefs:
    match = templates.find(t => t.developerName === templateDevName)
    if not match:
      throw ResolutionError("Prompt template not found: '{templateDevName}'")

    // Optionally fetch template details for input validation
    detail = GET /prompt-templates/{templateDevName}
    context.promptTemplates.set(templateDevName, {
      devName: templateDevName,
      versionId: detail.latestVersionId,
      type: detail.type,
      inputs: detail.inputs
    })
```

### 4.5 Resolution Order

External name resolution is independent (no cross-dependencies), so all four resolution types can run in parallel:

```
await Promise.all([
  resolveAgents(spec, context),
  resolveModels(spec, context),
  resolveSObjects(spec, context),
  resolvePromptTemplates(spec, context),
])
```

---

## 5. Phase 3: Build Dependency Graph

### 5.1 Dependency Extraction Rules

For each column, identify which other columns it depends on. Dependencies are expressed as column names (the `name` field in the YAML).

| Column Type | Dependency Sources |
|------------|-------------------|
| **AI** | Columns referenced in `prompt` via `{ColumnName}` or `{ColumnName.FieldName}` placeholders; explicit `refs` list |
| **Agent** | Columns referenced in `utterance` via `{ColumnName}` placeholders; columns in `context_variables[*].column` |
| **AgentTest** | `utterances` column ref; columns in `context_variables[*].column`; `initial_state` and `conversation_history` column refs |
| **Evaluation** | `target` column ref; `reference` column ref (if present) |
| **Reference** | `source` column ref |
| **Formula** | Columns referenced in `formula` via `{ColumnName}` placeholders; explicit `refs` list |
| **Object** | Columns in `advanced.refs` (for parameterized SOQL) |
| **PromptTemplate** | Columns in `inputs[*].column` |
| **InvocableAction** | Columns referenced in `payload` via `{$N}` with corresponding `refs` list |
| **Action** | Columns in `inputs[*].column` |
| **Text** | None (leaf node) |
| **DataModelObject** | Columns in `advanced.refs` (for parameterized DCSQL) |

### 5.2 Graph Construction Algorithm

```
function buildDependencyGraph(columns: ColumnSpec[]): DependencyGraph
  graph = { edges: new Map(), nodes: new Set() }

  // Index columns by name for lookup
  columnIndex = new Map(columns.map(c => [c.name, c]))

  for each column in columns:
    graph.nodes.add(column.name)
    deps = new Set<string>()

    switch normalizeType(column.type):
      case "ai":
        // Extract {ColumnName} and {ColumnName.FieldName} from prompt string
        for match in column.prompt.matchAll(/\{([^}$]+?)(?:\.\w+)?\}/g):
          candidateName = match[1]
          if columnIndex.has(candidateName):
            deps.add(candidateName)
        // Also check explicit refs array if present
        if column.refs:
          for ref in column.refs:
            deps.add(typeof ref === 'string' ? ref : ref.column)

      case "evaluation", starts with "eval/":
        deps.add(column.target)
        if column.reference:
          deps.add(column.reference)

      case "reference":
        deps.add(column.source)

      case "agent-test":
        deps.add(column.utterances)
        if column.context_variables:
          for cv in column.context_variables:
            if cv.column: deps.add(cv.column)
        if column.initial_state: deps.add(column.initial_state)
        if column.conversation_history: deps.add(column.conversation_history)

      case "agent":
        // Extract {ColumnName} from utterance string
        for match in column.utterance.matchAll(/\{([^}$]+?)(?:\.\w+)?\}/g):
          if columnIndex.has(match[1]):
            deps.add(match[1])
        if column.context_variables:
          for cv in column.context_variables:
            if cv.column: deps.add(cv.column)

      case "formula":
        for match in column.formula.matchAll(/\{([^}$]+?)(?:\.\w+)?\}/g):
          if columnIndex.has(match[1]):
            deps.add(match[1])

      case "prompt-template":
        if column.inputs:
          for input in column.inputs:
            if input.column: deps.add(input.column)

      case "invocable-action":
        if column.refs:
          for ref in column.refs: deps.add(ref)

      case "action":
        if column.inputs:
          for input in column.inputs:
            if input.column: deps.add(input.column)

      case "object":
        if column.advanced?.refs:
          for ref in column.advanced.refs: deps.add(ref)

      case "data-model-object":
        if column.advanced?.refs:
          for ref in column.advanced.refs: deps.add(ref)

    // Validate all deps reference actual columns
    for dep in deps:
      if not columnIndex.has(dep):
        throw ResolutionError("Column '{column.name}' depends on unknown column '{dep}'")

    graph.edges.set(column.name, deps)

  return graph
```

---

## 6. Phase 4: Topological Sort

Uses Kahn's algorithm (BFS-based), consistent with the approach in `platform-metabolism`'s `TopologicalSortHelper`.

```
function topologicalSort(graph: DependencyGraph): string[]
  // Compute in-degree for each node
  inDegree = new Map<string, number>()
  for node in graph.nodes:
    inDegree.set(node, 0)

  for [node, deps] of graph.edges:
    // Each dep is a node that `node` depends on.
    // In Kahn's, we need reverse edges: for each dep, node is a "dependent".
    // In-degree of `node` = number of its dependencies.
    inDegree.set(node, deps.size)

  // Seed queue with zero-dependency columns
  queue = []
  for [node, degree] of inDegree:
    if degree === 0:
      queue.push(node)

  sorted = []
  // Reverse adjacency: dep -> list of nodes that depend on it
  reverseDeps = new Map<string, string[]>()
  for [node, deps] of graph.edges:
    for dep in deps:
      if not reverseDeps.has(dep):
        reverseDeps.set(dep, [])
      reverseDeps.get(dep).push(node)

  while queue.length > 0:
    current = queue.shift()
    sorted.push(current)

    // Decrement in-degree of all nodes that depend on `current`
    for dependent in (reverseDeps.get(current) ?? []):
      newDegree = inDegree.get(dependent) - 1
      inDegree.set(dependent, newDegree)
      if newDegree === 0:
        queue.push(dependent)

  if sorted.length !== graph.nodes.size:
    // Find the cycle for error reporting
    remaining = graph.nodes.filter(n => !sorted.includes(n))
    throw CyclicDependencyError(
      "Circular dependency detected among columns: " + remaining.join(", ") +
      ". Check for mutual references between these columns."
    )

  return sorted
```

### Topological Sort Properties

- **Leaf nodes first**: Text, Object, DataModelObject columns (no dependencies) appear first.
- **Processing columns next**: AI, Agent, AgentTest columns that reference leaf nodes.
- **Evaluation columns last**: They depend on processing columns.
- **Deterministic**: When multiple columns have the same in-degree, process in YAML declaration order (stable sort by preserving insertion order in the queue).

### Example

Given this YAML:

```yaml
columns:
  - name: Utterances       # type: text, no deps
  - name: Expected         # type: text, no deps
  - name: Agent Output     # type: agent-test, deps: [Utterances]
  - name: Response Match   # type: eval/response-match, deps: [Agent Output, Expected]
  - name: Coherence        # type: eval/coherence, deps: [Agent Output]
```

Dependency graph:
```
Utterances -> (none)
Expected -> (none)
Agent Output -> {Utterances}
Response Match -> {Agent Output, Expected}
Coherence -> {Agent Output}
```

Topological order: `[Utterances, Expected, Agent Output, Response Match, Coherence]`

or equivalently: `[Expected, Utterances, Agent Output, Coherence, Response Match]`

(Both are valid; we prefer YAML declaration order among equal-priority nodes.)

---

## 7. Phase 5: Config Expansion and Sequential Creation

> **IMPORTANT: schemas.ts is the contract.** The config expander output MUST pass `ColumnConfigUnionSchema.parse()` from `src/schemas.ts`. Do NOT define new output types here -- import `ColumnInput` / `ColumnConfigUnionSchema` from `schemas.ts`. The per-type inner config schemas (e.g., `AIColumnInnerConfigSchema`, `AgentTestColumnInnerConfigSchema`) define exactly which fields the inner `config.config` object needs. Use `safeParse()` as an assertion after expansion to catch bugs.

This is the core of the engine. For each column in topological order, expand the compact YAML into full GCC JSON, substitute resolved IDs, and POST to the API.

### 7.1 Config Expansion: YAML to GCC JSON

The YAML DSL uses flat, intuitive keys. The Grid API requires a triple-nested `config.config` structure. Each column type has a specific expansion.

#### General Expansion Pattern

Every column expands to:

```json
{
  "name": "<column.name>",
  "type": "<gccType>",
  "config": {
    "type": "<gccType>",
    "numberOfRows": <resolved>,
    "queryResponseFormat": <auto-determined>,
    "autoUpdate": true,
    "config": {
      "autoUpdate": true,
      ... type-specific fields ...
    }
  }
}
```

#### queryResponseFormat Auto-Detection

```
function determineQueryResponseFormat(column, worksheetHasData):
  // Data-importing column types always use WHOLE_COLUMN
  if column.type in ["object", "data-model-object"]:
    return { type: "WHOLE_COLUMN", splitByType: "OBJECT_PER_ROW" }

  if column.type === "text" and column has csv or inline data with WHOLE_COLUMN intent:
    return { type: "WHOLE_COLUMN", splitByType: "OBJECT_PER_ROW" }

  // Everything else processes existing rows
  return { type: "EACH_ROW" }
```

#### Type-Specific Expansion Pseudocode

**AI Column:**

```
YAML:
  name: Summary
  type: ai
  model: gpt-4o
  prompt: "Summarize this account: {Accounts.Name}, {Accounts.Industry}"
  response_format: plain_text

Expansion:
  1. Parse prompt for {ColumnName} and {ColumnName.FieldName} references
  2. Assign $1, $2, ... placeholders in order of appearance
  3. Build referenceAttributes array with resolved column IDs

GCC JSON:
  {
    "name": "Summary",
    "type": "AI",
    "config": {
      "type": "AI",
      "numberOfRows": 50,
      "queryResponseFormat": { "type": "EACH_ROW" },
      "autoUpdate": true,
      "config": {
        "autoUpdate": true,
        "mode": "llm",
        "modelConfig": {
          "modelId": "sfdc_ai__DefaultGPT4Omni",
          "modelName": "sfdc_ai__DefaultGPT4Omni"
        },
        "instruction": "Summarize this account: {$1}, {$2}",
        "referenceAttributes": [
          {
            "columnId": "<resolved-id-of-Accounts>",
            "columnName": "Accounts",
            "columnType": "OBJECT",
            "fieldName": "Name"
          },
          {
            "columnId": "<resolved-id-of-Accounts>",
            "columnName": "Accounts",
            "columnType": "OBJECT",
            "fieldName": "Industry"
          }
        ],
        "responseFormat": { "type": "PLAIN_TEXT", "options": [] }
      }
    }
  }
```

**Prompt Reference Rewriting:**

The YAML uses `{ColumnName}` or `{ColumnName.FieldName}` in prompt strings. The GCC API uses `{$1}`, `{$2}`, ... positional placeholders. The engine must:

1. Find all `{...}` references in the prompt string (excluding `{$N}` which are already positional).
2. Assign positional indices in order of first appearance.
3. Replace each `{ColumnName}` or `{ColumnName.FieldName}` with `{$N}`.
4. Build the corresponding `referenceAttributes` array.

```
function rewritePromptReferences(prompt, context):
  refs = []
  index = 1
  seenRefs = new Map()  // "ColumnName.FieldName" -> "$N"

  rewritten = prompt.replace(/\{([^}$]+)\}/g, (match, refExpr) => {
    if seenRefs.has(refExpr):
      return seenRefs.get(refExpr)

    parts = refExpr.split(".")
    columnName = parts[0]
    fieldName = parts[1] ?? undefined

    columnId = context.columnIds.get(columnName)
    columnType = context.columnTypes.get(columnName)

    placeholder = "{$" + index + "}"
    seenRefs.set(refExpr, placeholder)

    refs.push({
      columnId,
      columnName,
      columnType,             // Already UPPERCASE from columnTypes map
      ...(fieldName ? { fieldName } : {})
    })

    index++
    return placeholder
  })

  return { instruction: rewritten, referenceAttributes: refs }
```

**Agent Column:**

```
YAML:
  name: Sales Response
  type: agent
  agent: Sales_Assistant
  utterance: "Help with {CustomerQuery}"
  context_variables:
    - name: CustomerName
      column: Customers.Name
    - name: Priority
      value: High

Expands to config.config:
  {
    "agentId": "<resolved-agent-def-id>",
    "agentVersion": "<resolved-agent-version-id>",
    "utterance": "Help with {$1}",
    "utteranceReferences": [
      { "columnId": "<id>", "columnName": "CustomerQuery", "columnType": "TEXT" }
    ],
    "contextVariables": [
      {
        "variableName": "CustomerName",
        "type": "Text",
        "reference": { "columnId": "<id>", "columnName": "Customers", "columnType": "OBJECT", "fieldName": "Name" }
      },
      {
        "variableName": "Priority",
        "type": "Text",
        "value": "High"
      }
    ]
  }
```

**AgentTest Column:**

```
YAML:
  name: Agent Output
  type: agent-test
  agent: Sales_Assistant
  utterances: Test Utterances      # column ref
  draft: false

Expands to config.config:
  {
    "agentId": "<resolved>",
    "agentVersion": "<resolved>",
    "inputUtterance": {
      "columnId": "<resolved-id-of-Test Utterances>",
      "columnName": "Test Utterances",
      "columnType": "TEXT"
    },
    "contextVariables": [],
    "isDraft": false,
    "enableSimulationMode": false
  }
```

**Evaluation Column:**

```
YAML:
  name: Response Match
  type: eval/response-match
  target: Agent Output
  reference: Expected Responses

Expands to config.config:
  {
    "evaluationType": "RESPONSE_MATCH",   // derived from type shorthand
    "inputColumnReference": {
      "columnId": "<resolved-id-of-Agent Output>",
      "columnName": "Agent Output",
      "columnType": "AGENT_TEST"
    },
    "referenceColumnReference": {
      "columnId": "<resolved-id-of-Expected Responses>",
      "columnName": "Expected Responses",
      "columnType": "TEXT"
    },
    "autoEvaluate": true
  }
```

Evaluation type shorthand mapping:

| Shorthand | evaluationType |
|-----------|---------------|
| `eval/response-match` | `RESPONSE_MATCH` |
| `eval/topic-assertion` | `TOPIC_ASSERTION` |
| `eval/coherence` | `COHERENCE` |
| `eval/latency` | `LATENCY_ASSERTION` |
| `eval/groundedness` | `GROUNDEDNESS` |
| `eval/relevance` | `RELEVANCE` |
| `eval/toxicity` | `TOXICITY` |
| `eval/tool-selection` | `TOOL_SELECTION` |
| `eval/action-sequence` | `ACTION_SEQUENCE_MATCH` |
| `eval/custom-llm` | `CUSTOM_LLM_EVALUATION` |
| `eval/expression` | `EXPRESSION_EVAL` |

**Reference Column:**

```
YAML:
  name: Agent Topic
  type: reference
  source: Agent Output
  field: response.topicName

Expands to config.config:
  {
    "referenceColumnId": "<resolved-id-of-Agent Output>",
    "referenceField": "response.topicName"
  }
```

**Formula Column:**

```
YAML:
  name: Is High Value
  type: formula
  formula: "{Accounts.AnnualRevenue} > 100000"
  return_type: boolean

Expands to config.config (same prompt-rewriting as AI):
  {
    "formula": "{$1} > 100000",
    "returnType": "boolean",
    "referenceAttributes": [
      { "columnId": "<id>", "columnName": "Accounts", "columnType": "OBJECT", "fieldName": "AnnualRevenue" }
    ]
  }
```

**Object Column:**

```
YAML:
  name: Accounts
  type: object
  object: Account
  fields: [Id, Name, Industry, Description]
  filters:
    - field: Industry
      operator: In
      values: [Technology, Finance]

Expands to config.config:
  {
    "objectApiName": "Account",
    "fields": [
      { "name": "Id", "type": "id" },
      { "name": "Name", "type": "string" },
      { "name": "Industry", "type": "picklist" },
      { "name": "Description", "type": "textarea" }
    ],
    "filters": [
      {
        "field": "Industry",
        "operator": "In",
        "values": [
          { "value": "Technology", "type": "string" },
          { "value": "Finance", "type": "string" }
        ]
      }
    ]
  }
```

Note: Field types (`id`, `string`, `picklist`, `textarea`) are looked up from the SObject metadata resolved in Phase 2. If the spec uses shorthand field names only, the engine infers types from `context.sobjects.get(objectApiName).fields`.

**Text Column:**

```
YAML:
  name: Test Utterances
  type: text

Expands to:
  {
    "name": "Test Utterances",
    "type": "Text",
    "config": {
      "type": "Text",
      "autoUpdate": true,
      "config": { "autoUpdate": true }
    }
  }
```

### 7.2 Sequential Creation Loop

```
function createColumns(sortedNames, columns, context):
  columnMap = new Map(columns.map(c => [c.name, c]))
  createdColumns = []

  for each name in sortedNames:
    column = columnMap.get(name)

    // Check if column already exists (incremental apply)
    if context.existingColumns.has(name):
      existing = context.existingColumns.get(name)
      context.columnIds.set(name, existing.id)
      context.columnTypes.set(name, typeToRefType(existing.type))
      // Optionally update config if changed (see Section 10)
      continue

    // Expand compact YAML into full GCC JSON
    gccPayload = expandToGCC(column, context)

    // POST to Grid API
    try:
      result = POST /worksheets/{context.worksheetId}/columns
        body: gccPayload

      // Capture the returned column ID
      createdId = result.id ?? result.columnId
      context.columnIds.set(name, createdId)
      context.columnTypes.set(name, typeToRefType(column.type))
      createdColumns.push({ name, id: createdId })

    catch apiError:
      // Verification: sometimes the API returns an error but the column was created
      worksheetData = GET /worksheets/{context.worksheetId}/data
      matchingColumn = worksheetData.columns.find(c => c.name === name)

      if matchingColumn:
        context.columnIds.set(name, matchingColumn.id)
        context.columnTypes.set(name, typeToRefType(column.type))
        createdColumns.push({ name, id: matchingColumn.id, warning: "Created despite API error" })
      else:
        throw ColumnCreationError(
          "Failed to create column '{name}': {apiError.message}. " +
          "Previously created columns: {createdColumns.map(c => c.name).join(', ')}",
          { createdColumns, failedColumn: name, originalError: apiError }
        )

  return createdColumns
```

### 7.3 ReferenceAttribute Construction

When building `referenceAttributes`, `inputColumnReference`, `referenceColumnReference`, or any field that needs a column reference:

```
function buildReferenceAttribute(columnName, fieldName, context):
  columnId = context.columnIds.get(columnName)
  if not columnId:
    throw ResolutionError("Column '{columnName}' has not been created yet")

  columnType = context.columnTypes.get(columnName)   // Already UPPERCASE

  ref = {
    columnId,
    columnName,
    columnType
  }

  if fieldName:
    ref.fieldName = fieldName

  return ref
```

---

## 8. Phase 6: Post-Create Operations

### 8.1 Sample Data / Inline Data

After all columns are created:

```
function pasteInlineData(spec, context):
  if not spec.data?.inline:
    return

  // Get worksheet data to find first row ID
  wsData = GET /worksheets/{context.worksheetId}/data
  rows = wsData.rows

  // Determine max data length
  maxRows = max(spec.data.inline.values().map(v => v.length))

  // Add rows if needed
  existingRowCount = rows.length
  if maxRows > existingRowCount:
    POST /worksheets/{context.worksheetId}/rows
      body: { count: maxRows - existingRowCount }
    // Re-fetch to get new row IDs
    wsData = GET /worksheets/{context.worksheetId}/data
    rows = wsData.rows

  // Build paste matrix
  // Order columns by their position in the worksheet
  textColumns = spec.columns.filter(c => spec.data.inline.has(c.name))
  startColumnId = context.columnIds.get(textColumns[0].name)
  startRowId = rows[0].id

  matrix = []
  for i in 0..maxRows:
    row = []
    for col in textColumns:
      values = spec.data.inline.get(col.name) ?? []
      row.push({ displayContent: values[i] ?? "" })
    matrix.push(row)

  POST /worksheets/{context.worksheetId}/paste
    body: { startColumnId, startRowId, matrix }
```

### 8.2 Row Execution Trigger

After data is pasted, processing columns automatically execute if `autoUpdate: true`. No explicit trigger is usually needed. However, the engine can optionally trigger:

```
POST /worksheets/{context.worksheetId}/trigger-row-execution
  body: { rowIds: rows.map(r => r.id) }
```

---

## 9. Error Handling

### 9.1 Error Categories

| Category | Examples | Strategy |
|----------|----------|----------|
| **Validation Errors** | Missing required field, unknown column type, duplicate names | Fail fast before any API calls. Return all errors at once. |
| **Resolution Errors** | Agent not found, model not available, SObject doesn't exist | Fail fast with suggestions (list available agents/models). |
| **Dependency Errors** | Circular dependency, reference to non-existent column | Fail fast with cycle path or missing ref name. |
| **API Errors (Transient)** | 429 rate limit, 500 server error, network timeout | Retry with exponential backoff (handled by GridClient). |
| **API Errors (Permanent)** | 400 bad config, 403 permission denied | Stop creation, report error with created-so-far context. |
| **Partial Creation** | Column N fails after columns 1..N-1 were created | Do NOT auto-rollback. Report what was created and what failed. |

### 9.2 Error Types

```typescript
class GridResolutionError extends Error {
  phase: "validate" | "resolve" | "dependency" | "create" | "post-create";
  details: unknown;
}

class ValidationError extends GridResolutionError {
  phase = "validate";
  errors: { column?: string; field?: string; message: string }[];
}

class NameResolutionError extends GridResolutionError {
  phase = "resolve";
  entityType: "agent" | "model" | "sobject" | "prompt-template";
  name: string;
  available: string[];   // Suggestions
}

class CyclicDependencyError extends GridResolutionError {
  phase = "dependency";
  cycle: string[];       // Column names in the cycle
}

class ColumnCreationError extends GridResolutionError {
  phase = "create";
  failedColumn: string;
  createdColumns: { name: string; id: string }[];   // What succeeded
  originalError: Error;
}
```

### 9.3 Partial Failure Strategy

When column creation fails mid-sequence:

1. **Do NOT auto-delete** previously created columns. The user may want to inspect the partial state or fix the failing column and retry.
2. **Report clearly**: "Created 4/7 columns successfully. Column 'Response Match' failed: [error details]. Columns created: Utterances (1W5...), Expected (1W5...), Topics (1W5...), Agent Output (1W5...)."
3. **Support incremental retry**: On next run, the engine detects existing columns and skips them (see Section 10).

### 9.4 Pre-Flight Validation Checklist

Before any API calls:

```
function preflight(spec, context):
  errors = []

  // Structure validation
  errors.push(...validate(spec))

  // Dependency graph validation (cycles)
  graph = buildDependencyGraph(spec.columns)
  try:
    topologicalSort(graph)
  catch CyclicDependencyError as e:
    errors.push(e)

  // Type-specific validation
  for column in spec.columns:
    if column.type starts with "eval/" and not column.target:
      errors.push("Evaluation column '{column.name}' missing 'target'")
    if column.type in ["ai", "prompt-template"] and not column.model and not spec.defaults?.model:
      errors.push("Column '{column.name}' needs a model (set column.model or worksheet defaults.model)")

  if errors.length > 0:
    throw ValidationError(errors)
```

---

## 10. Incremental Apply

When applying a YAML spec to an existing worksheet, the engine should detect what already exists and only create/update what's needed.

### 10.1 Diff Algorithm

```
function computeDiff(spec, existingWorksheet):
  existing = new Map(existingWorksheet.columns.map(c => [c.name, c]))
  actions = []

  for column in spec.columns:
    if existing.has(column.name):
      existingCol = existing.get(column.name)

      // Check if type matches
      if normalizeType(existingCol.type) !== normalizeType(column.type):
        actions.push({
          action: "recreate",
          column: column.name,
          reason: "Type changed from {existingCol.type} to {column.type}"
        })
      else:
        // Column exists with same type — check if config differs
        newConfig = expandToGCC(column, context)
        if configDiffers(existingCol.config, newConfig.config):
          actions.push({
            action: "update",
            column: column.name,
            columnId: existingCol.id
          })
        else:
          actions.push({ action: "skip", column: column.name })
    else:
      actions.push({ action: "create", column: column.name })

  // Columns in worksheet but not in spec — leave alone (don't delete)
  return actions
```

### 10.2 Applying the Diff

```
function applyIncremental(actions, spec, context):
  // First pass: register existing column IDs in context
  for action in actions where action.action in ["skip", "update"]:
    existing = context.existingColumns.get(action.column)
    context.columnIds.set(action.column, existing.id)
    context.columnTypes.set(action.column, typeToRefType(existing.type))

  // Topological sort only the columns that need creation
  toCreate = actions.filter(a => a.action === "create").map(a => a.column)
  // But sort with awareness of ALL columns (some deps may already exist)
  sortedCreates = topologicalSortSubset(graph, toCreate, context.columnIds)

  // Create new columns in order
  for name in sortedCreates:
    expandAndCreate(name, spec, context)

  // Update changed columns (order doesn't matter for updates)
  for action in actions where action.action === "update":
    column = spec.columns.find(c => c.name === action.column)
    gccPayload = expandToGCC(column, context)
    PUT /columns/{action.columnId}
      body: gccPayload
```

### 10.3 Config Comparison

For determining whether a column needs updating, compare the semantically meaningful parts of the config, ignoring:
- Column IDs (they may differ but reference the same logical column)
- `numberOfRows` (not worth an update)
- Ordering of keys in objects

```
function configDiffers(existing, proposed):
  // Normalize both configs: strip IDs, sort keys
  a = normalizeForComparison(existing)
  b = normalizeForComparison(proposed)
  return JSON.stringify(a) !== JSON.stringify(b)
```

---

## 11. Full Pipeline Orchestration

```typescript
async function resolveAndApply(
  yamlSource: string,
  worksheetId: string,
  options?: { dryRun?: boolean; incremental?: boolean }
): Promise<ResolutionResult> {

  // Phase 1: Parse and validate
  const spec = parseYAML(yamlSource);
  const errors = validate(spec);
  if (errors.length > 0) throw new ValidationError(errors);

  // Initialize context
  const context: ResolutionContext = {
    agents: new Map(),
    models: new Map(),
    sobjects: new Map(),
    promptTemplates: new Map(),
    dataspaces: new Map(),
    columnIds: new Map(),
    columnTypes: new Map(),
    existingColumns: new Map(),
    worksheetId,
    workbookId: "",
  };

  // Phase 2: Resolve external names (parallel)
  await Promise.all([
    resolveAgents(spec, context),
    resolveModels(spec, context),
    resolveSObjects(spec, context),
    resolvePromptTemplates(spec, context),
  ]);

  // Phase 3: Build dependency graph
  const graph = buildDependencyGraph(spec.worksheets[0].columns);

  // Phase 4: Topological sort
  const sortedNames = topologicalSort(graph);

  // Load existing state for incremental apply
  if (options?.incremental) {
    const wsData = await client.get(`/worksheets/${worksheetId}/data`);
    for (const col of wsData.columns) {
      context.existingColumns.set(col.name, col);
    }
  }

  // Dry run: return the plan without executing
  if (options?.dryRun) {
    const plan = sortedNames.map(name => ({
      name,
      action: context.existingColumns.has(name) ? "skip" : "create",
      expandedConfig: expandToGCC(spec.worksheets[0].columns.find(c => c.name === name), context),
    }));
    return { dryRun: true, plan };
  }

  // Phase 5: Create columns sequentially
  let createdColumns;
  if (options?.incremental) {
    const diff = computeDiff(spec, context);
    createdColumns = await applyIncremental(diff, spec, context);
  } else {
    createdColumns = await createColumns(sortedNames, spec.worksheets[0].columns, context);
  }

  // Phase 6: Post-create operations
  await pasteInlineData(spec.worksheets[0], context);

  return {
    worksheetId,
    columns: createdColumns,
    columnIds: Object.fromEntries(context.columnIds),
  };
}
```

---

## 12. Integration Points

### 12.1 MCP Tool Interface

The resolution engine is exposed as an MCP tool:

```typescript
server.tool(
  "apply_grid_spec",
  "Apply a YAML grid specification to create/update a worksheet with all columns in dependency order.",
  {
    worksheetId: z.string(),
    yamlSpec: z.string().describe("YAML grid specification"),
    dryRun: z.boolean().optional().describe("Preview the plan without creating columns"),
    incremental: z.boolean().optional().describe("Only create/update columns that differ from existing"),
  },
  async ({ worksheetId, yamlSpec, dryRun, incremental }) => {
    const result = await resolveAndApply(yamlSpec, worksheetId, { dryRun, incremental });
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  }
);
```

### 12.2 CLI / Skill Interface

The engine can also be invoked from a Claude Code skill or slash command:

```
/grid-apply my-test-suite.yaml --worksheet 1W6xx... --dry-run
/grid-apply my-test-suite.yaml --worksheet 1W6xx... --incremental
```

### 12.3 Relationship to Template System

The resolution engine supersedes the template resolution algorithm described in `2026-03-06-template-system-spec.md`. Templates become YAML files processed by this engine rather than JSON files with `$ref` pointers. The engine's phases map to the template spec's phases:

| Template Spec Phase | Resolution Engine Phase |
|---------------------|------------------------|
| Parse Template & Validate Parameters | Phase 1: Parse & Validate |
| Topological Sort by $ref | Phase 3-4: Build Graph & Sort |
| Sequential Creation with ID Substitution | Phase 5: Expand & Create |
| Populate Sample Data | Phase 6: Post-Create |

The key improvement: the YAML DSL uses column **names** as references instead of `$ref` pointers, making the spec more readable and eliminating the need for a separate `ref` key.

---

## 13. Testing Strategy

### 13.1 Unit Tests

- **Dependency graph construction**: Given column specs, verify correct edges.
- **Topological sort**: Verify order for known DAGs. Test cycle detection.
- **Config expansion**: For each of the 12 column types, verify YAML-to-GCC-JSON expansion produces correct triple-nested structure.
- **Prompt reference rewriting**: Verify `{ColumnName.Field}` -> `{$N}` with correct referenceAttributes.
- **Model alias resolution**: Verify alias map produces correct API names.
- **Incremental diff**: Verify skip/create/update classification.

### 13.2 Integration Tests (against live org)

- Create a full agent-test-suite from YAML and verify all columns exist with correct configs.
- Apply same spec twice (incremental) and verify no duplicate columns.
- Apply spec with one changed column and verify only that column is updated.
- Verify error handling: missing agent name, circular dependency, invalid SObject.
