# Agentforce Grid Plugin Architecture

## Architectural Recommendations for a Claude Code Plugin

**Author:** Architecture research based on analysis of Claude Code v2.1.70 plugin system, existing AFDX agent/hook patterns, and Agentforce Grid API v66.0.

---

## 1. Plugin Directory Structure

Based on the real plugin conventions observed in `superpowers` (4.3.1), `feature-dev`, `salesforce-trust-foundations`, and the Salesforce marketplace, the canonical Claude Code plugin layout is:

```
agentforce-grid/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (required)
├── .mcp.json                    # MCP server configuration (optional)
├── skills/
│   ├── grid-api/                # Core API knowledge
│   │   ├── SKILL.md             # Evolved from current SKILL.md
│   │   └── references/
│   │       ├── column-configs.md
│   │       ├── evaluation-types.md
│   │       ├── api-endpoints.md
│   │       └── use-case-patterns.md
│   ├── grid-patterns/           # Higher-level orchestration patterns
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── polling-strategies.md
│   │       ├── error-recovery.md
│   │       └── multi-worksheet-workflows.md
│   └── grid-templates/          # Template knowledge
│       ├── SKILL.md
│       └── references/
│           ├── agent-test-suite.md
│           ├── data-enrichment-pipeline.md
│           ├── prompt-evaluation.md
│           └── ab-testing.md
├── agents/
│   ├── grid-builder.md          # Creates worksheets from descriptions
│   ├── grid-inspector.md        # Reads and summarizes grid state
│   ├── grid-evaluator.md        # Analyzes evaluation results
│   ├── grid-debugger.md         # Diagnoses failures
│   └── grid-orchestrator.md     # Multi-step workflow coordinator
├── commands/
│   ├── grid-create.md           # /grid-create slash command
│   ├── grid-status.md           # /grid-status slash command
│   └── grid-run.md              # /grid-run slash command
├── hooks/
│   ├── hooks.json               # Hook registration manifest
│   ├── post-api-call.sh         # Render grid state after mutations
│   ├── poll-status.py           # Poll processing status
│   └── validate-config.py       # Validate column configs pre-commit
├── mcp-server/
│   ├── package.json
│   ├── src/
│   │   ├── index.ts             # MCP server entry point
│   │   ├── tools/               # Tool implementations
│   │   │   ├── workbooks.ts
│   │   │   ├── worksheets.ts
│   │   │   ├── columns.ts
│   │   │   ├── cells.ts
│   │   │   ├── agents.ts
│   │   │   └── metadata.ts
│   │   ├── resources/           # MCP resource providers
│   │   │   ├── workbook-resource.ts
│   │   │   └── worksheet-resource.ts
│   │   └── types.ts             # Shared type definitions
│   └── tsconfig.json
├── templates/                   # Exportable grid config templates
│   ├── agent-test-suite.json
│   ├── data-enrichment.json
│   ├── prompt-evaluation.json
│   ├── ab-testing.json
│   └── flow-testing.json
├── LICENSE
└── README.md
```

### plugin.json Manifest

```json
{
  "name": "agentforce-grid",
  "displayName": "Agentforce Grid",
  "version": "1.0.0",
  "description": "Complete toolkit for Agentforce Grid (AI Workbench): API skills, specialized agents, MCP tools, and workflow templates for agent testing, data enrichment, and prompt evaluation.",
  "author": {
    "name": "Salesforce",
    "email": "agentforce-grid@salesforce.com"
  },
  "license": "MIT",
  "keywords": [
    "agentforce", "grid", "ai-workbench", "agent-testing",
    "salesforce", "evaluation", "data-enrichment"
  ],
  "skills": "./skills/",
  "agents": "./agents/",
  "commands": "./commands/",
  "hooks": "./hooks/hooks.json"
}
```

### .mcp.json (co-located at plugin root)

```json
{
  "mcpServers": {
    "agentforce-grid": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/mcp-server/dist/index.js"],
      "transport": "stdio",
      "env": {
        "SF_INSTANCE_URL": "${SF_INSTANCE_URL}",
                "GRID_API_VERSION": "v66.0"
      }
    }
  }
}
```

**Key conventions discovered from existing plugins:**
- `plugin.json` lives in `.claude-plugin/` subdirectory
- `.mcp.json` lives at plugin root (not inside `.claude-plugin/`)
- `hooks.json` is referenced from `plugin.json` via relative path
- `${CLAUDE_PLUGIN_ROOT}` is available in hook/MCP commands
- Skills use `SKILL.md` + `references/` subdirectory pattern
- Agents are standalone `.md` files with YAML frontmatter

---

## 2. Hook Design

### hooks.json

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-init.sh",
            "async": true
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__agentforce-grid__*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-api-call.sh",
            "timeout": 15000
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/detect-grid-curl.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "mcp__agentforce-grid__*",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/validate-config.py",
            "timeout": 5000
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "grid_processing_complete",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-processing-complete.sh",
            "async": true
          }
        ]
      }
    ]
  }
}
```

### Hook Descriptions

#### 2.1 SessionStart: `session-init.sh`
**Purpose:** Validate Salesforce connection on session start.
- Check SF CLI is installed and org is authenticated
- Optionally ping `/services/data/v66.0/public/grid/workbooks` to validate auth
- Output a brief connection status message (instance, user, grid API availability)
- Cache available agents, models, and column types for the session

#### 2.2 PostToolUse: `post-api-call.sh`
**Purpose:** Auto-render grid state after any Grid MCP tool call that mutates state.
- After column creation/update: show updated worksheet schema (column names, types, order)
- After paste/cell update: show row count and processing status
- After trigger-row-execution: start a background polling loop
- Reads the tool output JSON from stdin, extracts worksheet ID, fetches fresh state
- Renders a compact ASCII table of the worksheet

**This is the highest-value hook.** It turns the CLI into a cockpit by showing grid state without the user asking.

#### 2.3 PreToolUse: `validate-config.py`
**Purpose:** Catch common configuration errors before they hit the API.
- Validates the nested `config.config` structure is present (the single most common error)
- Checks `type` field consistency (outer type matches inner config.type)
- Validates `queryResponseFormat` is appropriate (EACH_ROW vs WHOLE_COLUMN)
- Checks `referenceAttributes` use UPPERCASE `columnType`
- Validates `modelConfig` has both `modelId` and `modelName`
- Checks `ContextVariable` has either `value` or `reference`, not both
- On validation failure: returns `BLOCKER` with specific fix suggestion

#### 2.4 PostToolUse: `detect-grid-curl.sh`
**Purpose:** When users run raw `curl` commands against the Grid API via Bash, intercept the output and render it.
- Pattern-match Bash commands for `/public/grid/` URLs
- Parse the JSON response and render worksheet/column state
- Suggest using MCP tools instead for better integration

#### 2.5 Background Polling: `poll-status.py`
**Purpose:** Poll worksheet processing status and notify on completion.
- Triggered after `trigger-row-execution` or column creation with `autoUpdate: true`
- Polls `GET /worksheets/{id}/data` at configurable intervals (default 5s)
- Tracks cell status distribution: New/InProgress/Complete/Failed
- Emits a notification when all cells reach terminal state (Complete or Failed)
- Provides a summary: X/Y complete, Z failed, with failure reasons

#### 2.6 Status Line Integration
Extend the existing `statusline-command.sh` to show active grid operations:

```bash
# When grid polling is active, append to status line:
# [opus] | project | ctx:23% | grid: 45/50 cells complete (3 running)
```

Implementation: The poll-status hook writes to a temp file (`/tmp/grid-status-{session}`). The status line script reads it.

---

## 3. Subagent Definitions

Each agent uses YAML frontmatter following the pattern established by `afdx-architect.md` and `code-reviewer.md`.

### 3.1 `grid-builder.md`

```yaml
---
name: grid-builder
description: >
  Creates Agentforce Grid worksheets from natural language descriptions.
  Translates requirements into API calls: creates workbooks, worksheets,
  columns (all 12 types), populates data, and triggers processing.
model: opus
permissionMode: acceptEdits
maxTurns: 30
---
```

**Responsibilities:**
- Accept natural language like "Create an agent test suite for my Sales Agent with 20 test utterances, response matching, topic assertion, and coherence evaluation"
- Decompose into ordered API calls (workbook -> worksheet -> text columns -> agent column -> evaluation columns)
- Handle the column dependency graph (evaluation columns reference agent columns, which reference text columns)
- Use `create-column-from-utterance` endpoint when the user's description is vague
- Populate test data via paste matrix endpoint
- Trigger row execution and report initial status

**Why this agent is critical:** The API has a strict ordering requirement (you need column IDs from creation responses to build subsequent columns). A builder agent that manages this state machine is essential.

### 3.2 `grid-inspector.md`

```yaml
---
name: grid-inspector
description: >
  Reads and summarizes Agentforce Grid worksheet state. Fetches workbooks,
  worksheets, column schemas, cell data, and processing status. Renders
  compact summaries for the user.
model: opus
permissionMode: default
maxTurns: 10
---
```

**Responsibilities:**
- List workbooks and worksheets with summary stats
- Render worksheet state as formatted tables (column names, types, row counts, status distribution)
- Fetch and display cell data for specific columns or rows
- Show processing progress (X/Y complete, Z failed, W in-progress)
- Extract and display evaluation scores with pass/fail rates
- Compare two worksheets or two runs of the same worksheet

**Why opus:** Even read-only inspection benefits from Opus-level reasoning — it can spot anomalies, infer staleness cascades, and produce better-structured summaries.

### 3.3 `grid-evaluator.md`

```yaml
---
name: grid-evaluator
description: >
  Analyzes Agentforce Grid evaluation results. Computes aggregate scores,
  identifies failure patterns, suggests improvements to agent instructions
  or prompt templates, and recommends additional evaluation types.
model: opus
permissionMode: default
maxTurns: 20
---
```

**Responsibilities:**
- Fetch all evaluation columns from a worksheet
- Compute aggregate statistics: mean scores, pass rates, score distributions
- Identify patterns in failures (specific utterance types that consistently fail, topics that route incorrectly)
- Cross-correlate evaluation types (e.g., "rows that fail RESPONSE_MATCH also tend to score low on COHERENCE")
- Suggest concrete improvements: "Your agent's password reset responses are too verbose — coherence scores drop 30% vs other topics"
- Recommend additional evaluation types based on what's missing (e.g., "You have RESPONSE_MATCH but no TOPIC_ASSERTION — add it to catch routing regressions")
- Generate A/B comparison reports between two worksheet runs

**Why opus:** Evaluation analysis requires genuine reasoning about patterns across data. This is where model quality pays off.

### 3.4 `grid-debugger.md`

```yaml
---
name: grid-debugger
description: >
  Diagnoses failed cells in Agentforce Grid worksheets. Reads error messages,
  analyzes column configurations, identifies root causes, and suggests fixes.
model: opus
permissionMode: acceptEdits
maxTurns: 15
---
```

**Responsibilities:**
- Fetch cells with `status: Failed` and their `statusMessage`
- Categorize failures: config errors, API errors, timeout errors, data errors
- For config errors: diff the column config against the schema and pinpoint the issue
- For agent/prompt failures: analyze the input that caused the failure
- Suggest and optionally apply fixes (update column config, reprocess)
- Handle the common failure modes:
  - Missing nested `config.config` structure
  - Wrong `columnType` casing in `referenceAttributes`
  - Invalid `referenceColumnId` (deleted or reordered column)
  - Agent timeout (suggest reducing `numberOfRows`)
  - Model not available (suggest alternative from `GET /llm-models`)

### 3.5 `grid-orchestrator.md`

```yaml
---
name: grid-orchestrator
description: >
  Coordinates multi-step Agentforce Grid workflows. Manages the full lifecycle:
  build -> populate -> execute -> wait -> evaluate -> report. Delegates to
  specialized agents for each phase.
model: opus
permissionMode: acceptEdits
maxTurns: 50
---
```

**Responsibilities:**
- Accept high-level workflow descriptions ("Run my agent test suite, wait for completion, analyze results, and create a report")
- Decompose into phases and delegate to specialized agents:
  1. `grid-builder` for worksheet creation
  2. `grid-inspector` for status monitoring
  3. `grid-evaluator` for results analysis
  4. `grid-debugger` for failure recovery
- Manage async coordination: trigger execution, poll for completion, handle partial failures
- Implement retry logic for transient failures
- Generate final reports combining all evaluation data

**Why this matters:** The Grid API is inherently async — you create columns, trigger execution, wait, then read results. An orchestrator that manages this state machine is the key differentiator over raw API calls.

### 3.6 Additional Agent Candidates (v2)

- **`grid-migrator`**: Exports worksheet configs as JSON templates, imports templates into new orgs, handles ID remapping
- **`grid-comparator`**: A/B comparison between two worksheet runs (different agent versions, different models, different prompts)
- **`grid-reporter`**: Generates formatted reports (markdown, CSV) from evaluation data for stakeholders

---

## 4. MCP Server

### 4.1 Recommendation: Yes, Build It

**The MCP server is the architectural centerpiece.** Here is why:

| Concern | Direct HTTP (curl/fetch) | MCP Server |
|---------|------------------------|------------|
| Auth management | User manages tokens manually | Server manages token lifecycle |
| Type safety | Raw JSON, easy to malform | Typed tool inputs with JSON Schema validation |
| Error handling | Raw HTTP status codes | Structured error messages with recovery suggestions |
| Discoverability | User must know endpoints | Tools appear in Claude's tool list with descriptions |
| Composability | Each call is standalone | Tools can share state (cached IDs, session context) |
| Validation | None pre-flight | Schema validation catches errors before API call |
| Claude Desktop | Not available | Full integration via MCP protocol |
| Hooks integration | Awkward (grep for curl patterns) | Clean matcher: `mcp__agentforce-grid__*` |

### 4.2 Tool Definitions

Group tools by resource type, matching the API structure:

```typescript
// Workbook tools
grid_list_workbooks()
grid_create_workbook(name: string)
grid_get_workbook(workbookId: string)
grid_delete_workbook(workbookId: string)

// Worksheet tools
grid_create_worksheet(name: string, workbookId: string)
grid_get_worksheet(worksheetId: string)
grid_get_worksheet_data(worksheetId: string)
grid_delete_worksheet(worksheetId: string)

// Column tools (the workhorse)
grid_add_column(worksheetId: string, config: ColumnConfig)
grid_update_column(columnId: string, config: ColumnConfig)
grid_delete_column(columnId: string, worksheetId: string)
grid_reprocess_column(columnId: string)
grid_get_column_data(columnId: string)

// Cell tools
grid_update_cells(worksheetId: string, cells: CellUpdate[])
grid_paste_data(worksheetId: string, startColumnId: string, startRowId: string, matrix: string[][])
grid_trigger_execution(worksheetId: string, rowIds?: string[])

// Row tools
grid_add_rows(worksheetId: string, count: number)
grid_delete_rows(worksheetId: string, rowIds: string[])

// Discovery tools
grid_list_agents(includeDrafts?: boolean)
grid_get_agent_variables(versionId: string)
grid_list_models()
grid_list_sobjects()
grid_get_sobject_fields(objectApiName: string)
grid_list_prompt_templates()
grid_list_evaluation_types()

// AI-assisted tools
grid_create_column_from_utterance(worksheetId: string, utterance: string)
grid_generate_soql(utterance: string, objectApiName: string)

// Data Cloud tools
grid_list_dataspaces()
grid_list_dmos(dataspace: string)
grid_get_dmo_fields(dataspace: string, dmoName: string)

// Composite tools (high-value abstractions)
grid_create_agent_test_suite(agentId: string, agentVersion: string, utterances: string[], options?: TestSuiteOptions)
grid_poll_until_complete(worksheetId: string, timeoutMs?: number)
grid_get_evaluation_summary(worksheetId: string)
```

### 4.3 Resource Definitions

MCP resources allow Claude to "read" grid state as structured data:

```typescript
// Resource URIs
grid://workbooks                           // List all workbooks
grid://workbooks/{id}                      // Single workbook with worksheets
grid://worksheets/{id}                     // Worksheet metadata + schema
grid://worksheets/{id}/data                // Full worksheet data
grid://worksheets/{id}/status              // Processing status summary
grid://columns/{id}/data                   // Column cell data
```

Resources are especially valuable for the inspector agent — it can read grid state as context without making explicit tool calls.

### 4.4 Server Architecture

```typescript
// src/index.ts - Simplified structure
import { McpServer } from "@anthropic-ai/mcp";

const server = new McpServer({
  name: "agentforce-grid",
  version: "1.0.0",
});

// Connection state
let instanceUrl: string;
let accessToken: string;
let cachedModels: Model[] | null = null;
let cachedAgents: Agent[] | null = null;

// Shared HTTP client with retry logic
async function gridFetch(path: string, options?: RequestInit) {
  const url = `${instanceUrl}/services/data/v66.0/public/grid${path}`;
  const response = await fetch(url, {
    ...options,
    headers: {
      // Authorization handled by SF CLI
      "Content-Type": "application/json",
      ...options?.headers,
    },
  });
  if (!response.ok) {
    const error = await response.json();
    throw new GridApiError(response.status, error);
  }
  return response.json();
}

// Register tools, resources, and start
server.tool("grid_list_workbooks", "List all Agentforce Grid workbooks", {}, async () => {
  const data = await gridFetch("/workbooks");
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
});

// ... register all tools and resources
```

### 4.5 Composite Tools: The Key Differentiator

Raw API tools are necessary but insufficient. The real value comes from **composite tools** that encode multi-step workflows:

**`grid_create_agent_test_suite`** — A single tool call that:
1. Creates a workbook and worksheet
2. Creates Text columns for utterances, expected responses, expected topics
3. Creates an AgentTest column referencing the utterance column
4. Creates Evaluation columns (RESPONSE_MATCH, TOPIC_ASSERTION, COHERENCE)
5. Adds rows and pastes test data
6. Returns the worksheet ID and column map

This turns a 15-API-call workflow into one tool invocation.

**`grid_poll_until_complete`** — Polls processing status with exponential backoff, returns a summary when done.

**`grid_get_evaluation_summary`** — Fetches all evaluation column data, computes aggregate pass rates and score distributions, returns a structured summary.

---

## 5. Template System

Templates are JSON files that encode reusable worksheet configurations. They are **not** API payloads — they are declarative specifications that the `grid-builder` agent or `grid_create_from_template` MCP tool interprets.

### 5.1 Template Schema

```json
{
  "$schema": "https://agentforce-grid.salesforce.com/template-schema/v1.json",
  "name": "Agent Test Suite",
  "description": "Comprehensive agent testing with response matching, topic assertion, and quality metrics",
  "version": "1.0.0",
  "parameters": {
    "agentId": {
      "type": "string",
      "description": "The Agent Definition ID (0Xx...)",
      "required": true
    },
    "agentVersion": {
      "type": "string",
      "description": "The Agent Version ID (0Xy...)",
      "required": true
    },
    "modelId": {
      "type": "string",
      "description": "LLM model for AI evaluations",
      "default": "sfdc_ai__DefaultGPT4Omni"
    },
    "rowCount": {
      "type": "integer",
      "description": "Number of test rows",
      "default": 50
    }
  },
  "columns": [
    {
      "ref": "utterances",
      "name": "Test Utterances",
      "type": "Text",
      "description": "Input test cases for the agent"
    },
    {
      "ref": "expected_responses",
      "name": "Expected Responses",
      "type": "Text",
      "description": "Ground truth responses for comparison"
    },
    {
      "ref": "expected_topics",
      "name": "Expected Topics",
      "type": "Text",
      "description": "Expected topic names for routing validation"
    },
    {
      "ref": "agent_output",
      "name": "Agent Output",
      "type": "AgentTest",
      "config": {
        "agentId": "{{agentId}}",
        "agentVersion": "{{agentVersion}}",
        "inputUtterance": { "$ref": "#/columns/utterances" }
      }
    },
    {
      "ref": "response_match",
      "name": "Response Match",
      "type": "Evaluation",
      "config": {
        "evaluationType": "RESPONSE_MATCH",
        "inputColumnReference": { "$ref": "#/columns/agent_output" },
        "referenceColumnReference": { "$ref": "#/columns/expected_responses" }
      }
    },
    {
      "ref": "topic_check",
      "name": "Topic Assertion",
      "type": "Evaluation",
      "config": {
        "evaluationType": "TOPIC_ASSERTION",
        "inputColumnReference": { "$ref": "#/columns/agent_output" },
        "referenceColumnReference": { "$ref": "#/columns/expected_topics" }
      }
    },
    {
      "ref": "coherence",
      "name": "Coherence",
      "type": "Evaluation",
      "config": {
        "evaluationType": "COHERENCE",
        "inputColumnReference": { "$ref": "#/columns/agent_output" }
      }
    },
    {
      "ref": "latency",
      "name": "Latency",
      "type": "Evaluation",
      "config": {
        "evaluationType": "LATENCY_ASSERTION",
        "inputColumnReference": { "$ref": "#/columns/agent_output" }
      }
    }
  ],
  "sampleData": {
    "utterances": [
      "I need help resetting my password",
      "What is your return policy?",
      "Can I speak to a manager?",
      "How do I update my billing information?",
      "I want to cancel my subscription"
    ],
    "expected_topics": [
      "Password_Reset",
      "Return_Policy",
      "Escalation",
      "Billing",
      "Cancellation"
    ]
  }
}
```

### 5.2 Template Catalog

| Template | Use Case | Columns |
|----------|----------|---------|
| `agent-test-suite.json` | Comprehensive agent testing | Text x3, AgentTest, Evaluation x4 |
| `data-enrichment.json` | AI-enrich SObject records | Object, AI x2, Reference x2 |
| `prompt-evaluation.json` | Batch-test prompt templates | Text x2, PromptTemplate, Evaluation x3 |
| `ab-testing.json` | Compare two models/agents | Text, AgentTest x2, Evaluation x4 (paired) |
| `flow-testing.json` | Test Flows with varied inputs | Text x3, InvocableAction, Reference x2, Evaluation |
| `data-classification.json` | AI classification with single-select | Object, AI (SINGLE_SELECT) x3, Formula |
| `multi-turn-conversation.json` | Multi-turn agent testing | Text x2, Agent (turn 1), Text, Agent (turn 2 with history) |

### 5.3 Template Resolution

The `$ref` syntax handles the key challenge: **column IDs are not known until creation time.** Template resolution works in two passes:

1. **Topological sort**: Order columns by dependency graph (Text first, then processing columns that reference them, then evaluations)
2. **Sequential creation with ID substitution**: Create each column, capture its ID, substitute into subsequent column configs

This is the same logic the `grid-builder` agent needs anyway — templates just formalize it.

---

## 6. Configuration

### 6.1 User-Level Configuration

Stored in `~/.claude/settings.json` under the plugin namespace, or in a dedicated `~/.agentforce-grid/config.json`:

```json
{
  "agentforce-grid": {
    "connection": {
      "instanceUrl": "https://myorg.my.salesforce.com",
      "authMethod": "env",
      "envVars": {
        "orgAlias": "SF_ORG_ALIAS",
        "instanceUrl": "SF_INSTANCE_URL"
      }
    },
    "defaults": {
      "modelId": "sfdc_ai__DefaultGPT4Omni",
      "numberOfRows": 50,
      "autoUpdate": true
    },
    "polling": {
      "intervalMs": 5000,
      "maxWaitMs": 300000,
      "backoffMultiplier": 1.5
    },
    "display": {
      "maxCellContentLength": 200,
      "showTimestamps": true,
      "compactMode": false,
      "statusLineEnabled": true
    },
    "templates": {
      "customDir": "~/.agentforce-grid/templates/"
    }
  }
}
```

### 6.2 Project-Level Configuration

Stored in `.claude/settings.json` within the project:

```json
{
  "agentforce-grid": {
    "connection": {
      "instanceUrl": "https://dev-sandbox.my.salesforce.com"
    },
    "defaults": {
      "agentId": "0XxRM0000001234",
      "agentVersion": "0XyRM0000005678",
      "workbookId": "1W4RM0000009ABC"
    }
  }
}
```

Project config overrides user config, following Claude Code's existing settings cascade.

### 6.3 Auth Strategy

**Recommended approach: environment variables.**

The MCP server uses SF CLI for authentication. Users authenticate via:

1. **SF CLI login**: `sf org login web --alias <alias> --instance-url <url>`
2. **Set org alias**: `export SF_ORG_ALIAS=<alias>`
2. **Connected App OAuth**: Stored in OS keychain, injected at session start
3. **Named Credential proxy**: For org-internal deployments

The SessionStart hook should validate auth and provide clear error messages if misconfigured.

---

## 7. Implementation Priority

### Phase 1: Foundation (Week 1-2)
1. Restructure existing skill into plugin layout with `plugin.json`
2. Build the MCP server with core CRUD tools (workbooks, worksheets, columns, cells)
3. Write the `grid-builder` agent
4. Write the `grid-inspector` agent

### Phase 2: Intelligence (Week 3-4)
5. Add composite MCP tools (`grid_create_agent_test_suite`, `grid_poll_until_complete`)
6. Build the `grid-evaluator` agent
7. Build the `grid-debugger` agent
8. Implement PreToolUse validation hook

### Phase 3: Orchestration (Week 5-6)
9. Build the `grid-orchestrator` agent
10. Implement PostToolUse state-rendering hook
11. Implement polling hook with status line integration
12. Create template system and first 3 templates

### Phase 4: Polish (Week 7-8)
13. Add MCP resource providers
14. Complete template catalog
15. Write the `grid-patterns` skill with error recovery and advanced workflows
16. Publish to salesforce-native-ai-stack marketplace

---

## 8. Design Principles

These principles are informed by Boris Cherny's approach — composable, type-safe, developer-ergonomic:

1. **Composability over monoliths.** Each agent does one thing well. The orchestrator composes them. Tools are small; composite tools layer on top.

2. **Fail fast, fail informatively.** The PreToolUse validation hook catches config errors *before* the API call. Error messages include the specific field that's wrong and the correct value.

3. **Progressive disclosure.** New users start with `/grid-create "test my Sales Agent"` (one command). Power users drop into the MCP tools directly. The skill documents provide the API knowledge when needed.

4. **State is visible.** The PostToolUse hook and status line ensure the user always sees current grid state. No black-box operations.

5. **Templates are data, not code.** Templates are JSON files with `$ref` pointers, not scripts. They can be versioned, shared, diffed, and composed.

6. **Auth is separate from logic.** The MCP server gets credentials from the environment. The plugin never stores secrets.

7. **All Opus, all the time.** Every agent uses Opus for maximum reasoning quality. Grid operations involve complex config generation and nuanced evaluation — don't compromise on model capability.
