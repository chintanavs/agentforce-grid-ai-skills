# Agentforce Grid Cockpit Experience: Complete Specification

> **Purpose:** Define how Claude Code and Claude Desktop should interact with Agentforce Grid to provide a world-class "cockpit" experience — making grid data visible, grid operations intuitive, and grid results actionable.
>
> **Design Philosophy:** Boris Cherny's type-safe composability meets Ivan Zhao's block-based information architecture. Every view is a composable block. Every block has a clear type contract. The user never wonders "what is happening in my grid."
>
> **Status:** Research specification (no code yet). Produced by a 4-agent Opus research team.

---

## Table of Contents

1. [What is Agentforce Grid?](#1-what-is-agentforce-grid)
2. [Current State and Gaps](#2-current-state-and-gaps)
3. [Design Principles](#3-design-principles)
4. [Architecture: From Skill to Plugin](#4-architecture-from-skill-to-plugin)
5. [MCP Server](#5-mcp-server)
6. [Specialized Agents](#6-specialized-agents)
7. [Hook System](#7-hook-system)
8. [Visualization: CLI Cockpit](#8-visualization-cli-cockpit)
9. [Visualization: Desktop Artifacts](#9-visualization-desktop-artifacts)
10. [Workflow Patterns](#10-workflow-patterns)
11. [Slash Commands](#11-slash-commands)
12. [Template System](#12-template-system)
13. [Configuration](#13-configuration)
14. [CI/CD Integration](#14-cicd-integration)
15. [Implementation Roadmap](#15-implementation-roadmap)

---

## 1. What is Agentforce Grid?

Agentforce Grid (AF Grid) is a **programmable spreadsheet for AI operations** in Salesforce. Think Clay.io, but more general and deeply integrated with the Salesforce platform.

**Core concept:** `Workbook -> Worksheet -> Columns -> Rows -> Cells`

Each column has a **type** that defines its behavior:

| Category | Column Types | What They Do |
|----------|-------------|--------------|
| **Data Sources** | Object, DataModelObject, Text | Query SObjects, Data Cloud DMOs, or hold static text |
| **AI Processing** | AI, Agent, AgentTest, PromptTemplate | Run LLM prompts, test agents, execute prompt templates |
| **Automation** | InvocableAction, Action | Execute Flows, Apex, platform actions |
| **Derivation** | Reference, Formula | Extract fields via JSON path, compute formulas |
| **Evaluation** | Evaluation (12 types) | Score quality, assert correctness, measure latency |

**The key insight:** Columns form a **directed acyclic graph (DAG)**. An Evaluation column depends on an AgentTest column, which depends on a Text column. Data flows left to right through the pipeline. This is the mental model everything builds on.

**API:** Public Connect API at `/services/data/v66.0/public/grid/` with 40+ endpoints (OpenAPI 3.0.1). Fully async — you trigger processing and poll for results.

**What makes it unique vs Clay.io:**
- Deep Salesforce data integration (SObjects, Data Cloud DMOs, SOQL, DCSQL)
- 12 evaluation types for AI quality assessment (COHERENCE, FACTUALITY, TOPIC_ASSERTION, etc.)
- Multi-turn conversation testing with conversation history
- Flow/Apex invocation as columns
- Formula system referencing cross-column data

---

## 2. Current State and Gaps

### What Exists
A single skill at `.claude/skills/agentforce-grid/` with:
- `SKILL.md` — API reference, column type configs, use case patterns
- `references/column-configs.md` — Complete JSON for all 12 column types
- `references/evaluation-types.md` — All 12 evaluation types
- `references/api-endpoints.md` — Endpoint documentation
- `references/use-case-patterns.md` — 6 workflow patterns

### What's Missing

| Gap | Impact |
|-----|--------|
| **No visualization** | Users get raw JSON dumps. No tables, no status indicators, no dashboards. |
| **No state awareness** | Claude doesn't understand grid health. Can't tell you "8 cells failed" without being asked. |
| **No async handling** | No polling strategy. Processing is fire-and-forget with no feedback loop. |
| **No natural language building** | Users must understand JSON configs. No "build me a grid that tests my agent." |
| **No hooks** | No auto-rendering after API calls. No config validation. No status line. |
| **No specialized agents** | No builder, inspector, evaluator, or debugger agents. |
| **No MCP server** | All API calls go through raw HTTP. No type-safe tool interface. |
| **No templates** | Every grid is built from scratch. No reusable patterns. |
| **No CI/CD story** | No deployment gates, version comparison, or regression detection. |
| **API version outdated** | Skill references v64.0; current API is v66.0. |
| **Missing endpoints** | `generate-test-columns`, `agents/including-drafts`, `agents/draft-topics-compiled` not documented. |

---

## 3. Design Principles

### From Boris Cherny: Composability and Type Safety

1. **Composability over monoliths.** Each agent does one thing well. Tools are small. Composite tools layer on top. Templates compose from atomic column definitions.

2. **Fail fast, fail informatively.** PreToolUse validation hooks catch config errors *before* the API call. Error messages include the specific field that's wrong and the correct value.

3. **One contract, many views.** A single `GridState` data model powers every visualization — CLI tables, Desktop dashboards, progress reporters. Change the data once, every view updates.

### From Ivan Zhao: Blocks and Progressive Disclosure

4. **Blocks, not JSON.** Users manipulate "columns" and "evaluations," not `referenceAttributes` arrays. Natural language in, structured API calls out.

5. **Progressive disclosure.** Summary first, then table, then cell detail. Never dump raw JSON. The right information at the right altitude.

6. **Direct manipulation feel.** Even in a text CLI, users should feel like they're dragging columns into place. `/grid-add evaluation for conciseness` feels like clicking "add column."

### From Clay.io: Pipeline as Spreadsheet

7. **Visible data flow.** The column dependency DAG is always available. Users trace how data moves left-to-right.

8. **Cell-level status.** Per-cell feedback (loading, complete, failed) makes async operations comprehensible at a glance.

9. **Immediate feedback loops.** Adding a column starts populating data. No separate "run" step unless manually triggered.

### Operational

10. **All Opus, all the time.** Every agent uses Opus for maximum reasoning quality. Grid operations involve complex config generation and nuanced evaluation analysis — don't compromise on model capability.

11. **Templates are data, not code.** JSON files with `$ref` pointers, not scripts. Versionable, shareable, diffable.

12. **Auth is separate from logic.** The MCP server gets credentials from the environment. The plugin never stores secrets.

---

## 4. Architecture: From Skill to Plugin

### Current: Single Skill
```
.claude/skills/agentforce-grid/
├── SKILL.md
└── references/
    ├── api-endpoints.md
    ├── column-configs.md
    ├── evaluation-types.md
    └── use-case-patterns.md
```

### Target: Full Plugin
```
agentforce-grid/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── .mcp.json                    # MCP server config
├── skills/
│   ├── grid-api/                # Core API knowledge (evolved SKILL.md)
│   │   ├── SKILL.md
│   │   └── references/
│   ├── grid-cockpit/            # Visualization and state awareness
│   │   ├── SKILL.md
│   │   └── references/
│   └── grid-patterns/           # Higher-level orchestration
│       ├── SKILL.md
│       └── references/
├── agents/
│   ├── grid-builder.md          # Creates worksheets from NL
│   ├── grid-inspector.md        # Reads and summarizes state
│   ├── grid-evaluator.md        # Analyzes evaluation results
│   ├── grid-debugger.md         # Diagnoses failures
│   └── grid-orchestrator.md     # Multi-step workflow coordinator
├── commands/
│   ├── grid-new.md              # /grid-new slash command
│   ├── grid-status.md           # /grid-status
│   ├── grid-run.md              # /grid-run
│   ├── grid-results.md          # /grid-results
│   ├── grid-add.md              # /grid-add
│   ├── grid-debug.md            # /grid-debug
│   ├── grid-compare.md          # /grid-compare
│   ├── grid-export.md           # /grid-export
│   ├── grid-list.md             # /grid-list
│   └── grid-models.md           # /grid-models
├── hooks/
│   ├── hooks.json               # Hook registration
│   ├── session-init.sh          # Validate SF connection
│   ├── post-api-call.sh         # Auto-render grid after mutations
│   ├── validate-config.py       # Pre-flight config validation
│   └── poll-status.py           # Background polling
├── mcp-server/
│   ├── package.json
│   ├── src/
│   │   ├── index.ts             # MCP server entry
│   │   ├── tools/               # 30+ tool implementations
│   │   ├── resources/           # grid:// resource providers
│   │   └── types.ts             # Shared types
│   └── tsconfig.json
├── templates/
│   ├── agent-test-suite.json
│   ├── data-enrichment.json
│   ├── prompt-evaluation.json
│   ├── ab-testing.json
│   ├── flow-testing.json
│   ├── data-classification.json
│   └── multi-turn-conversation.json
└── README.md
```

### plugin.json

```json
{
  "name": "agentforce-grid",
  "displayName": "Agentforce Grid",
  "version": "1.0.0",
  "description": "Complete toolkit for Agentforce Grid: API skills, specialized agents, MCP tools, and workflow templates.",
  "skills": "./skills/",
  "agents": "./agents/",
  "commands": "./commands/",
  "hooks": "./hooks/hooks.json"
}
```

---

## 5. MCP Server

### Why MCP Over Raw HTTP

| Concern | Direct HTTP (curl) | MCP Server |
|---------|-------------------|------------|
| Auth management | User manages tokens | Server manages lifecycle |
| Type safety | Raw JSON | JSON Schema validation |
| Discoverability | Must know endpoints | Tools appear in Claude's list |
| Validation | None pre-flight | Schema catches errors before call |
| Claude Desktop | Not available | Full integration |
| Hooks | Grep for curl patterns | Clean matcher: `mcp__agentforce-grid__*` |

### Tool Inventory (30+ tools)

**Core CRUD:**
```
grid_list_workbooks, grid_create_workbook, grid_get_workbook, grid_delete_workbook
grid_create_worksheet, grid_get_worksheet, grid_get_worksheet_data, grid_delete_worksheet
grid_add_column, grid_update_column, grid_delete_column, grid_reprocess_column, grid_get_column_data
grid_update_cells, grid_paste_data, grid_trigger_execution
grid_add_rows, grid_delete_rows
```

**Discovery:**
```
grid_list_agents, grid_get_agent_variables, grid_list_models
grid_list_sobjects, grid_get_sobject_fields
grid_list_prompt_templates, grid_list_evaluation_types
grid_list_dataspaces, grid_list_dmos, grid_get_dmo_fields
```

**AI-Assisted:**
```
grid_create_column_from_utterance, grid_generate_soql
```

**Composite (high-value abstractions):**
```
grid_create_agent_test_suite    # 15 API calls -> 1 tool
grid_poll_until_complete         # Async coordination
grid_get_evaluation_summary      # Aggregate analysis
```

### MCP Resources

```
grid://workbooks                    # List all workbooks
grid://workbooks/{id}               # Single workbook with worksheets
grid://worksheets/{id}              # Worksheet metadata + schema
grid://worksheets/{id}/data         # Full worksheet data
grid://worksheets/{id}/status       # Processing status summary
grid://columns/{id}/data            # Column cell data
```

---

## 6. Specialized Agents

### grid-builder (Opus, maxTurns: 30)
**Creates worksheets from natural language.** Accepts "create an agent test suite for my Sales Agent" and decomposes into ordered API calls. Manages the column dependency state machine (column IDs from creation responses feed into subsequent columns).

### grid-inspector (Opus, maxTurns: 10)
**Reads and summarizes grid state.** Lists workbooks, renders status tables, shows processing progress, extracts evaluation scores. Used for `/grid-status` and frequent monitoring.

### grid-evaluator (Opus, maxTurns: 20)
**Analyzes evaluation results.** Computes aggregates, identifies failure patterns, cross-correlates evaluation types, suggests improvements. "Your password reset responses score 30% lower on coherence than other topics." Used for `/grid-results` deep analysis.

### grid-debugger (Opus, maxTurns: 15)
**Diagnoses failed cells.** Reads error messages, analyzes configs, identifies root causes. Handles common failures: nested `config.config` missing, wrong `columnType` casing, invalid references, agent timeouts, model unavailability.

### grid-orchestrator (Opus, maxTurns: 50)
**Coordinates multi-step workflows.** Build -> populate -> execute -> wait -> evaluate -> report. Delegates to specialized agents for each phase. Manages async coordination, retry logic, and final reporting.

---

## 7. Hook System

### hooks.json

```json
{
  "hooks": {
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-init.sh",
        "async": true
      }]
    }],
    "PreToolUse": [{
      "matcher": "mcp__agentforce-grid__*",
      "hooks": [{
        "type": "command",
        "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/validate-config.py",
        "timeout": 5000
      }]
    }],
    "PostToolUse": [{
      "matcher": "mcp__agentforce-grid__*",
      "hooks": [{
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-api-call.sh",
        "timeout": 15000
      }]
    }]
  }
}
```

### Hook Descriptions

| Hook | Trigger | Purpose | Value |
|------|---------|---------|-------|
| **session-init.sh** | SessionStart | Validate SF connection, cache agents/models | Fail fast if not authenticated |
| **validate-config.py** | PreToolUse (MCP tools) | Catch config errors before API call | **Prevents the #1 error:** missing nested `config.config` |
| **post-api-call.sh** | PostToolUse (MCP tools) | Auto-render grid state after mutations | **Highest-value hook:** turns CLI into cockpit |
| **poll-status.py** | After trigger-execution | Background poll + notify on completion | Closes the async feedback loop |

### PreToolUse Validation Catches

1. Nested `config.config` structure missing (most common error)
2. `type` field mismatch (outer vs inner)
3. Wrong `queryResponseFormat` (EACH_ROW vs WHOLE_COLUMN)
4. `referenceAttributes` using lowercase `columnType` (must be UPPERCASE)
5. Missing `modelConfig` on AI/PromptTemplate columns
6. `ContextVariable` with both `value` AND `reference` (must be one)

### Status Line Integration

```
[opus] | project | ctx:23% | grid: 45/50 cells complete (3 running)
```

---

## 8. Visualization: CLI Cockpit

### Core Data Model

All views are powered by a single normalized `GridState`:

```
GridState {
  worksheet: { id, name, workbookId }
  columns: Column[]           // ordered by precedingColumnId chain
  rows: string[]              // ordered row IDs
  cells: Map<columnId, Map<rowId, Cell>>
  summary: GridSummary        // computed
}

GridSummary {
  totalRows, totalColumns
  statusCounts: Map<Status, number>
  evalPassRate?: number
  evalScoreDistribution?: { p25, p50, p75, p90, p99 }
  latencyDistribution?: { p50, p90, p99 }
  errorsByColumn: Map<columnId, number>
}
```

### Three-Layer Progressive Disclosure

#### Layer 1: Summary Banner (always shown first)

```
┌─────────────────────────────────────────────────────────────────┐
│  WORKSHEET: Sales Agent Tests                                   │
│  Workbook:  Agent Test Suite           ID: 1W1xx0000004Abc      │
├─────────────────────────────────────────────────────────────────┤
│  Columns: 7    Rows: 50    Cells: 350                           │
│  Status:  Complete 298  InProgress 12  Failed 8  Stale 32       │
│           [########################################----xxxx~~~] │
│  Evals:   42/50 passed (84.0%)    Avg Score: 3.7/5             │
│  Latency: P50=1.2s  P90=3.4s  P99=8.1s                        │
│  Errors:  8 failures in "Agent Output" (col 4)                  │
└─────────────────────────────────────────────────────────────────┘
```

Status bar characters: `#` Complete, `-` InProgress, `x` Failed, `~` Stale, `.` New

#### Layer 2: Column Pipeline Strip

```
 #  Column Name          Type         Status        Health
 1  Test Utterances      [TXT]        --            50/50
 2  Expected Responses   [TXT]        --            50/50
 3  Expected Topics      [TXT]        --            50/50
 4  Agent Output         [AGT-TEST]   InProgress    38/50 (8 err)
 5  Response Match       [EVAL]       Stale         32/50
 6  Topic Check          [EVAL]       Stale         32/50
 7  Quality Score        [EVAL]       Complete      42/50
```

Type badges: `[TXT]` `[AI]` `[AGT]` `[AGT-TEST]` `[OBJ]` `[EVAL]` `[REF]` `[FORMULA]` `[PROMPT]` `[ACTION]` `[IA]` `[DMO]`

#### Layer 3: Data Grid Table

```
┌────┬──────────────────┬──────────────────┬──────────────────┬───────┬───────┐
│ ## │ Test Utterances   │ Agent Output     │ Response Match   │ Topic │ Qual. │
│    │ [TXT]             │ [AGT-TEST]       │ [EVAL]           │[EVAL] │[EVAL] │
├────┼──────────────────┼──────────────────┼──────────────────┼───────┼───────┤
│  1 │ Help me reset    │ Sure, I'll...    │ PASS             │ PASS  │ 4/5   │
│    │ my password      │            [OK]  │            [OK]  │  [OK] │  [OK] │
├────┼──────────────────┼──────────────────┼──────────────────┼───────┼───────┤
│  4 │ Cancel my sub    │ ERROR: Time...   │                  │       │       │
│    │                  │            [XX]  │            [~~]  │  [~~] │  [~~] │
└────┴──────────────────┴──────────────────┴──────────────────┴───────┴───────┘

Legend: [OK] Complete  [..] InProgress  [XX] Failed  [~~] Stale
```

### Evaluation Summary Table

```
EVALUATION SUMMARY (50 test cases)
┌────────────────────┬────────┬────────┬─────────┬──────────────────────┐
│ Evaluation         │ Passed │ Failed │ Rate    │ Distribution         │
├────────────────────┼────────┼────────┼─────────┼──────────────────────┤
│ Response Match     │   42   │    8   │  84.0%  │ ############--       │
│ Topic Check        │   48   │    2   │  96.0%  │ ###############-     │
│ Quality Score      │   --   │   --   │  avg 3.7│ ..###########....    │
│ Latency            │   45   │    5   │  90.0%  │ ##############--     │
├────────────────────┼────────┼────────┼─────────┼──────────────────────┤
│ OVERALL            │        │        │  84.0%  │                      │
└────────────────────┴────────┴────────┴─────────┴──────────────────────┘
```

### Additional CLI Views

- **Vertical Card View** — For narrow terminals or row detail (`show row 4`)
- **Diff View** — After reprocessing, shows what changed per cell
- **Dependency DAG** — ASCII graph of column references
- **Progress Reporter** — Compact lines during polling: `[14:23:12] Processing: 31/50 (62%), 19 in progress...`

### Adaptive Polling

```
Poll 1:   2s (fast check)
Poll 2:   3s
Poll 3:   5s
Poll 4+:  8s (steady state)
Bail out: 5 minutes total

Progress format:
[14:23:12] Processing: 12/50 complete (24%), 38 in progress...
[14:23:20] Processing: 31/50 complete (62%), 19 in progress...
[14:23:36] Done. 46 passed, 4 failed.
```

---

## 9. Visualization: Desktop Artifacts

Claude Desktop supports HTML artifacts — self-contained, interactive, no external dependencies.

### Artifact 1: Interactive Grid Table
- Sortable columns (click header)
- Filterable by status (dropdown)
- Cell expansion on click (shows `fullContent`)
- Color-coded cells by status
- Evaluation pass/fail backgrounds

### Artifact 2: Evaluation Dashboard
- **Panel 1:** Horizontal bar chart — pass rate per evaluation type
- **Panel 2:** Histogram — score distribution for numeric evals
- **Panel 3:** Failure analysis — errors grouped by type with affected rows
- **Panel 4:** Latency percentile chart (P50/P75/P90/P95/P99)
- **Panel 5:** Trend chart — pass rates across multiple runs

### Artifact 3: Column Dependency Graph
- SVG-based DAG with clickable nodes
- Each node shows: column name, type badge, status dot, completion count
- Highlighting upstream/downstream on click

### Artifact 4: Evaluation Heatmap
- Rows x evaluation columns matrix
- Color scale: Red (0-2) -> Yellow (2-3.5) -> Green (3.5-5)
- Instant pattern recognition: "rows 3, 12, 18 consistently fail"

### Artifact 5: Processing Timeline
- Gantt-chart showing when each column processed
- Identifies bottleneck columns and parallelism opportunities

### Artifact Guidelines
- Self-contained (no CDN links, inline all CSS/JS)
- Responsive (CSS Grid/Flexbox)
- Accessible (aria-labels, semantic HTML)
- Under 100KB (paginate client-side for large grids)

---

## 10. Workflow Patterns

### Natural Language Grid Building

Every grid-building interaction follows three phases:

1. **Understand & Plan** — Parse intent, identify column pipeline, surface ambiguities
2. **Confirm & Resolve** — Present plan as table, ask for missing info (agent IDs, models)
3. **Execute & Report** — Create resources sequentially, report progress, show structure

**Translation rules:**

| User Says | Column Pattern |
|-----------|---------------|
| "test my agent" | Text + AgentTest + Evaluation columns |
| "query accounts" | Object with WHOLE_COLUMN |
| "generate/write" | AI with PLAIN_TEXT |
| "classify/categorize" | AI with SINGLE_SELECT |
| "evaluate/score" | Evaluation with appropriate type |
| "compare X vs Y" | Same prompt, different modelConfig |
| "enrich" | Object (WHOLE_COLUMN) then AI (EACH_ROW) |
| "run this flow" | InvocableAction + Reference extraction |

### Example Conversation

```
USER: Create a grid that tests my Sales Agent with 50 utterances
      and evaluates coherence + topic routing

CLAUDE: I'll build a Sales Agent testing grid:

  | #  | Column           | Type       | Purpose                    |
  |----|------------------|------------|----------------------------|
  | 1  | Test Utterances  | Text       | Your 50 test inputs        |
  | 2  | Expected Topics  | Text       | Ground truth topic names   |
  | 3  | Agent Output     | AgentTest  | Run your Sales Agent       |
  | 4  | Coherence        | Evaluation | Assess logical flow        |
  | 5  | Topic Routing    | Evaluation | Verify correct topic       |

  Before I create this, I need:
  1. Your agent ID — which agent should I look for?
  2. Do you have utterances ready (CSV/list)?

USER: Agent is "Sales Assistant". Utterances in /tmp/tests.csv

CLAUDE: [executes 9 API calls sequentially, reports progress]
  Grid created. 50 rows loaded. Agent processing started.
  Use /grid-status to check progress.
```

### Iterative Refinement

Users modify grids conversationally:
- **Add columns:** "Add a conciseness evaluation" -> GET worksheet, POST evaluation column
- **Change filters:** "Include Healthcare accounts too" -> PUT column with updated filters
- **Swap models:** "Switch GPT to Claude" -> PUT column with new modelConfig, reprocess
- **Debug failures:** "Why did row 12 fail?" -> GET data, inspect statusMessage, suggest fix

### Data Import/Export

- **CSV Import:** Two paths — API `import-csv` endpoint (needs ContentDocument) or local parse + paste matrix (recommended for Claude Code)
- **Export:** No native endpoint. Reconstruct CSV from `GET /worksheets/{id}/data`
- **Reports:** Aggregate evaluation data into markdown tables with recommendations

### Monitoring

- **Status checks:** Aggregate cell statuses per column, show completion %
- **Failure debugging:** Extract `statusMessage` from failed cells, categorize errors, suggest fixes
- **Worst performers:** Sort by evaluation score, cross-reference with input utterances
- **Polling:** 10s initial wait, 15s intervals, max 20 attempts. No webhooks — all poll-based.
- **Stale detection:** Find stale cells from upstream failures, offer targeted reprocessing

---

## 11. Slash Commands

| Command | Purpose | Key Behavior |
|---------|---------|-------------|
| `/grid-new <desc>` | Create grid from NL | Parse -> plan table -> confirm -> execute |
| `/grid-status [id]` | Show grid state | Summary banner + column health strip |
| `/grid-run [opts]` | Execute/reprocess | `--failed`, `--stale`, `--column <name>` |
| `/grid-results [id]` | Evaluation results | `--summary`, `--bottom 10`, `--format json` |
| `/grid-add <desc>` | Add column to grid | "evaluation for conciseness" -> POST column |
| `/grid-debug [row]` | Investigate failures | Error categorization + suggested fixes |
| `/grid-compare <a> <b>` | Compare worksheets | Side-by-side evals + regression flags |
| `/grid-export [opts]` | Export data | `--format csv\|json`, `--path <file>` |
| `/grid-list` | List workbooks | Tree view with worksheet counts |
| `/grid-models` | List LLM models | Table with model IDs and labels |

---

## 12. Template System

Templates are declarative JSON specifications for reusable grid configurations. They use `$ref` pointers for column cross-references and `{{parameter}}` interpolation for user inputs.

### Template Resolution

1. **Topological sort** — Order columns by dependency DAG
2. **Sequential creation with ID substitution** — Create each column, capture ID, substitute into subsequent configs

### Template Catalog

| Template | Use Case | Column Types |
|----------|----------|-------------|
| `agent-test-suite.json` | Comprehensive agent testing | Text x3, AgentTest, Evaluation x4 |
| `data-enrichment.json` | AI-enrich SObject records | Object, AI x2, Reference x2 |
| `prompt-evaluation.json` | Batch-test prompt templates | Text x2, PromptTemplate, Evaluation x3 |
| `ab-testing.json` | Compare two models | Text, AI x2 (different models), Evaluation x4 |
| `flow-testing.json` | Test Flows with varied inputs | Text x3, InvocableAction, Reference x2 |
| `data-classification.json` | AI classification | Object, AI (SINGLE_SELECT) x3, Formula |
| `multi-turn-conversation.json` | Multi-turn agent testing | Text x2, Agent (turn 1), Text, Agent (turn 2 + history) |

### Example Template (abbreviated)

```json
{
  "name": "Agent Test Suite",
  "version": "1.0.0",
  "parameters": {
    "agentId": { "type": "string", "required": true },
    "agentVersion": { "type": "string", "required": true },
    "modelId": { "type": "string", "default": "sfdc_ai__DefaultGPT4Omni" }
  },
  "columns": [
    { "ref": "utterances", "name": "Test Utterances", "type": "Text" },
    { "ref": "expected_topics", "name": "Expected Topics", "type": "Text" },
    {
      "ref": "agent_output", "name": "Agent Output", "type": "AgentTest",
      "config": {
        "agentId": "{{agentId}}",
        "agentVersion": "{{agentVersion}}",
        "inputUtterance": { "$ref": "#/columns/utterances" }
      }
    },
    {
      "ref": "topic_check", "name": "Topic Assertion", "type": "Evaluation",
      "config": {
        "evaluationType": "TOPIC_ASSERTION",
        "inputColumnReference": { "$ref": "#/columns/agent_output" },
        "referenceColumnReference": { "$ref": "#/columns/expected_topics" }
      }
    }
  ]
}
```

---

## 13. Configuration

### User-Level (`~/.claude/settings.json`)

```json
{
  "agentforce-grid": {
    "connection": {
      "instanceUrl": "https://myorg.my.salesforce.com",
      "authMethod": "env"
    },
    "defaults": {
      "modelId": "sfdc_ai__DefaultGPT4Omni",
      "numberOfRows": 50
    },
    "polling": {
      "intervalMs": 5000,
      "maxWaitMs": 300000
    },
    "display": {
      "maxCellContentLength": 200,
      "compactMode": false
    }
  }
}
```

### Project-Level (`.claude/settings.json`)

```json
{
  "agentforce-grid": {
    "defaults": {
      "agentId": "0XxRM0000001234",
      "agentVersion": "0XyRM0000005678",
      "workbookId": "1W4RM0000009ABC"
    }
  }
}
```

### Auth Strategy

**Recommended:** Environment variables via SF CLI integration.
```bash
sf org login web --alias <alias> --instance-url <url>
export SF_ORG_ALIAS=<alias>
export SF_INSTANCE_URL=$(sf org display --json | jq -r '.result.instanceUrl')
```

The SessionStart hook validates auth and provides clear error messages if misconfigured.

---

## 14. CI/CD Integration

### Evaluation as Deployment Gate

```
CI Pipeline
  → sf deploy (agent metadata)
  → /grid-run {worksheet-id}
  → Poll for completion
  → /grid-results --format json
  → Assert: coherence_avg >= 4.0, topic_accuracy >= 90%
  → Pass → continue / Fail → block + report
```

### Version Comparison

Create parallel worksheets with same utterances but different agent versions. Compare evaluation scores side-by-side with delta highlighting.

### Regression Detection Rules

| Rule | Severity |
|------|----------|
| Any eval average drops > 0.2 points | WARNING |
| Any eval average drops > 0.5 points | FAILURE |
| Previously-passing row now fails | FLAG |
| New failures in stable test cases | CRITICAL |
| Latency increase > 20% | WARNING |

### Grid-Refinery Feedback Loop

```
1. GRID (Evaluate)   → Run test suite, identify failures
2. REFINERY (Improve) → Refine agent topics/instructions
3. GRID (Re-Evaluate) → Same test suite, compare results
4. Repeat until quality gates pass
```

---

## 15. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] Restructure skill into plugin layout with `plugin.json`
- [ ] Build MCP server with core CRUD tools (workbooks, worksheets, columns, cells)
- [ ] Write `grid-builder` agent
- [ ] Write `grid-inspector` agent
- [ ] Update API references to v66.0

### Phase 2: Intelligence (Weeks 3-4)
- [ ] Add composite MCP tools (`grid_create_agent_test_suite`, `grid_poll_until_complete`, `grid_get_evaluation_summary`)
- [ ] Build `grid-evaluator` agent
- [ ] Build `grid-debugger` agent
- [ ] Implement PreToolUse validation hook
- [ ] Write `grid-cockpit` skill with visualization instructions

### Phase 3: Orchestration (Weeks 5-6)
- [ ] Build `grid-orchestrator` agent
- [ ] Implement PostToolUse state-rendering hook
- [ ] Implement polling hook with status line
- [ ] Create template system + first 3 templates
- [ ] Implement slash commands

### Phase 4: Polish (Weeks 7-8)
- [ ] Add MCP resource providers (`grid://` URIs)
- [ ] Complete template catalog (all 7)
- [ ] Desktop HTML artifact generation (dashboards, heatmaps, dependency graphs)
- [ ] CI/CD integration documentation
- [ ] Write `grid-patterns` skill (error recovery, advanced workflows)

---

## Appendix A: API Spec Changes (v64 -> v66)

| Change | Detail |
|--------|--------|
| Version bump | v64.0 -> v66.0 |
| New endpoint | `POST /generate-test-columns` — AI-generated test columns |
| New endpoint | `GET /agents/including-drafts` — Separate draft agent listing |
| New endpoint | `POST /agents/draft-topics-compiled` — Compile + return draft topics |
| Column delete | Now requires `worksheetId` as query parameter |
| `TriggerRowExecution` | `trigger` field with types: `RUN_SELECTION`, `RUN_ROW`, `EDIT`, `PASTE` |
| Column ordering | `precedingColumnId` field on column output |

## Appendix B: Related Documents

- [COCKPIT-VISUALIZATION-SPEC.md](./COCKPIT-VISUALIZATION-SPEC.md) — Detailed visualization specification with rendering examples
- [PLUGIN-ARCHITECTURE.md](./PLUGIN-ARCHITECTURE.md) — Detailed plugin architecture with code examples
- [references/workflow-patterns.md](./.claude/skills/agentforce-grid/references/workflow-patterns.md) — Detailed workflow specifications with conversation examples

## Appendix C: Competitive Positioning

**vs Clay.io:** AF Grid's evaluation system is the key differentiator. Clay is an enrichment tool; AF Grid is a testing and quality framework. Clay has 150+ enrichment providers; AF Grid has deep Salesforce integration + 12 evaluation types + agent testing.

**vs Airtable:** Airtable separates data view from automation. AF Grid merges them — the grid IS the pipeline.

**vs Notion Databases:** Notion's relation + rollup model is analogous to Reference columns. AF Grid extends this with AI processing as first-class column types.

**AF Grid's unique moat:** No other tool combines SObject queries, agent testing, multi-turn conversation history, Flow/Apex invocation, and multi-dimensional AI evaluation in a single spreadsheet interface.
