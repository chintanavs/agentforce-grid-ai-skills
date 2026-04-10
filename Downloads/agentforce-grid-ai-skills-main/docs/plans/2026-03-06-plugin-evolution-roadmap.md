> **Status:** ACTIVE | Phase 5 | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) Phase 5 (Plugin & Cockpit)
> **What changed:** Reinstated as Phase 5 of the implementation plan. Plugin skeleton, agent definitions, slash commands, and desktop artifacts are now planned deliverables (after Phases 1-4 stabilize the MCP tools and hooks). The JSON template system remains superseded by YAML DSL + apply_grid. Phase 0 MCP server foundation is complete.

# Agentforce Grid: Skill-to-Plugin Evolution Roadmap

**Date:** 2026-03-06
**Status:** ~~Implementation Plan~~ SUPERSEDED by [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md)
**References:**
- `AGENTFORCE-GRID-COCKPIT-SPEC.md` (master spec)
- `COCKPIT-VISUALIZATION-SPEC.md` (rendering spec)
- `PLUGIN-ARCHITECTURE.md` (plugin structure spec)

---

## Supersession Notes

**What the hybrid plan replaces from this roadmap:**

| This Roadmap | Hybrid Plan Equivalent | Status |
|-------------|----------------------|--------|
| Phase 1: Foundation (plugin skeleton, agents, commands, hooks, MCP wiring) | Phase 0 (MCP server) is DONE. Plugin skeleton, agents, commands are DEFERRED. | Partially done, partially deferred |
| Phase 2: MCP Integration (composite tools, resources, cockpit skill) | Hybrid Phase 2 (apply_grid, typed mutations) + Phase 3 (resources) | Active |
| Phase 3: Intelligence (template system, PreToolUse/PostToolUse hooks) | Template system SUPERSEDED by YAML DSL. Hooks moved to hybrid Phase 4. | Superseded / remapped |
| Phase 4: Polish (desktop artifacts, CI/CD, testing, packaging) | Deferred beyond hybrid Phase 4. | Deferred |

**Key changes in direction:**
- The JSON template system (`templates/*.json`) is superseded by the YAML DSL + `apply_grid` tool
- Plugin structure (plugin.json, .mcp.json, agent definitions, slash commands) is deferred until MCP server evolution is complete
- The hybrid plan focuses on MCP server capabilities first, then Claude Code integration

---

## 1. Current State Assessment

> **NOTE:** Section 1.2 (MCP Server) is largely outdated. The MCP server now has 57 tools (not 43), Zod schema validation, retry logic, and 4 composite workflows. See the hybrid plan for current state.

### 1.1 Skill Repo (`agentforce-grid-ai-skills`)

**What exists and works:**

| Asset | Path | Status |
|-------|------|--------|
| SKILL.md | `.claude/skills/agentforce-grid/SKILL.md` | Working. Updated to v66.0. Covers all 12 column types, evaluation types, API endpoints, config rules, and 3 use-case patterns. |
| api-endpoints.md | `.claude/skills/agentforce-grid/references/api-endpoints.md` | Complete endpoint reference. |
| column-configs.md | `.claude/skills/agentforce-grid/references/column-configs.md` | Full JSON configs for all 12 column types. |
| evaluation-types.md | `.claude/skills/agentforce-grid/references/evaluation-types.md` | All 12 evaluation types documented. |
| use-case-patterns.md | `.claude/skills/agentforce-grid/references/use-case-patterns.md` | 6 workflow patterns (agent testing, enrichment, flow testing, etc.). |
| workflow-patterns.md | `.claude/skills/agentforce-grid/references/workflow-patterns.md` | Detailed conversation flows, slash command specs, CI/CD patterns. |
| Three spec documents | Root directory | Architecture research complete. No code produced from them yet. |
| TESTING.md | `docs/TESTING.md` | Testing guidance document. |

**What is missing from the skill repo:**

- No `plugin.json` manifest -- still a bare skill, not a plugin
- No `.mcp.json` -- no MCP server integration configured
- No agents (grid-builder, grid-inspector, grid-evaluator, grid-debugger, grid-orchestrator)
- No slash commands (`/grid-new`, `/grid-status`, `/grid-run`, etc.)
- No hooks (session-init, validate-config, post-api-call, poll-status)
- No templates (agent-test-suite.json, data-enrichment.json, etc.)
- No visualization skill (grid-cockpit)
- No error-recovery / advanced-patterns skill (grid-patterns)

### 1.2 MCP Server Repo (`agentforce-grid-mcp`)

**What exists and works:**

The MCP server is functional with 43 tools across 7 modules:

| Module | File | Tools | Tool Names |
|--------|------|-------|------------|
| Workbooks | `src/tools/workbooks.ts` | 4 | `get_workbooks`, `create_workbook`, `get_workbook`, `delete_workbook` |
| Worksheets | `src/tools/worksheets.ts` | 10 | `create_worksheet`, `get_worksheet`, `get_worksheet_data`, `get_worksheet_data_generic`, `update_worksheet`, `delete_worksheet`, `get_supported_columns`, `add_rows`, `delete_rows`, `import_csv` |
| Columns | `src/tools/columns.ts` | 8 | `add_column`, `edit_column`, `delete_column`, `save_column`, `reprocess_column`, `get_column_data`, `create_column_from_utterance`, `generate_json_path` |
| Cells | `src/tools/cells.ts` | 5 | `update_cells`, `paste_data`, `trigger_row_execution`, `validate_formula`, `generate_ia_input` |
| Agents | `src/tools/agents.ts` | 6 | `get_agents`, `get_agents_including_drafts`, `get_agent_variables`, `get_draft_topics`, `get_draft_topics_compiled`, `get_draft_context_variables` |
| Metadata | `src/tools/metadata.ts` | 14 | `get_column_types`, `get_llm_models`, `get_supported_types`, `get_evaluation_types`, `get_formula_functions`, `get_formula_operators`, `get_invocable_actions`, `describe_invocable_action`, `get_prompt_templates`, `get_prompt_template`, `get_list_views`, `get_list_view_soql`, `generate_soql`, `generate_test_columns` |
| Data/SObject | `src/tools/data.ts` | 7 (including 1 uncounted previously) | `get_sobjects`, `get_sobject_fields_display`, `get_sobject_fields_filter`, `get_sobject_fields_record_update`, `get_dataspaces`, `get_data_model_objects`, `get_data_model_object_fields` |

**Architecture:**

- TypeScript with `@modelcontextprotocol/sdk` v1.12.1, stdio transport
- `GridClient` class in `src/client.ts` uses SF CLI for authentication, HTTP via `node:https`
- Auth requires SF CLI with `SF_ORG_ALIAS` env var
- API version defaults to v66.0, configurable via `API_VERSION` env var
- Zod schema validation on all tool inputs
- Consistent error handling pattern across all tools

**What is missing from the MCP server:**

- No README or usage documentation
- No tests (unit or integration)
- No MCP resources (`grid://` URIs for reading state as context)
- ~~No composite/high-level tools~~ **DONE:** `setup_agent_test`, `poll_worksheet_status`, `get_worksheet_summary`, `create_workbook_with_worksheet` now exist
- ~~No retry logic or exponential backoff in `GridClient`~~ **DONE:** Retry on ECONNRESET/ETIMEDOUT, 401 token refresh, 429 rate-limit respect, 5xx exponential backoff
- `rejectUnauthorized: false` in HTTP client (acceptable for dev, not production)
- Auth model uses SF CLI exclusively

### 1.3 Gap Summary

| Gap Category | Severity | Blocks |
|-------------|----------|--------|
| No plugin structure | High | Everything downstream -- agents, commands, hooks need plugin.json |
| No .mcp.json in skill repo | High | Claude Code cannot discover or auto-start the MCP server |
| No agents defined | High | No natural-language grid building, no specialized analysis |
| No hooks | Medium | No config validation, no auto-rendering, no async feedback |
| No slash commands | Medium | No quick-action entry points for users |
| No MCP resources | Low | Inspector agent works fine with tools; resources are a convenience |
| No composite MCP tools | Medium | Multi-step workflows require many round trips without them |
| No templates | Medium | Every grid built from scratch; no reusable patterns |
| No tests in MCP server | Medium | Risk of regressions as composite tools are added |
| No visualization skill | Medium | Claude falls back to raw JSON dumps |
| Auth model | N/A | Using SF CLI exclusively |

---

## 2. Target Architecture

The target layout integrates both repos into a single plugin structure, as defined in PLUGIN-ARCHITECTURE.md Section 1. The MCP server remains a separate repo but is referenced via `.mcp.json`.

```
agentforce-grid-ai-skills/          (this repo, becomes the plugin)
├── .claude-plugin/
│   └── plugin.json                 # Plugin manifest (required)
├── .mcp.json                       # Points to agentforce-grid-mcp
├── skills/
│   ├── grid-api/                   # Core API knowledge (migrated from .claude/skills/)
│   │   ├── SKILL.md                # Evolved current SKILL.md
│   │   └── references/
│   │       ├── api-endpoints.md
│   │       ├── column-configs.md
│   │       ├── evaluation-types.md
│   │       ├── use-case-patterns.md
│   │       └── workflow-patterns.md
│   ├── grid-cockpit/               # Visualization and state awareness
│   │   ├── SKILL.md                # How to render grid state (from COCKPIT-VISUALIZATION-SPEC.md)
│   │   └── references/
│   │       ├── cli-views.md        # ASCII table formats, summary banners, status indicators
│   │       └── desktop-artifacts.md # HTML artifact templates for Claude Desktop
│   └── grid-patterns/              # Error recovery, advanced orchestration
│       ├── SKILL.md
│       └── references/
│           ├── error-recovery.md
│           ├── polling-strategies.md
│           └── multi-worksheet-workflows.md
├── agents/
│   ├── grid-builder.md             # Creates worksheets from NL descriptions
│   ├── grid-inspector.md           # Reads and summarizes grid state
│   ├── grid-evaluator.md           # Analyzes evaluation results
│   ├── grid-debugger.md            # Diagnoses failures
│   └── grid-orchestrator.md        # Multi-step workflow coordinator
├── commands/
│   ├── grid-new.md                 # /grid-new <description>
│   ├── grid-status.md              # /grid-status [worksheet-id]
│   ├── grid-run.md                 # /grid-run [options]
│   ├── grid-results.md             # /grid-results [options]
│   ├── grid-add.md                 # /grid-add <column-description>
│   ├── grid-debug.md               # /grid-debug [row] [--column <name>]
│   ├── grid-compare.md             # /grid-compare <ws-1> <ws-2>
│   ├── grid-export.md              # /grid-export [options]
│   ├── grid-list.md                # /grid-list
│   └── grid-models.md              # /grid-models
├── hooks/
│   ├── hooks.json                  # Hook registration manifest
│   ├── session-init.sh             # Validate SF connection on session start
│   ├── post-api-call.sh            # Auto-render grid state after MCP mutations
│   ├── validate-config.py          # PreToolUse: catch config errors before API call
│   └── poll-status.py              # Background poll + notify on completion
├── templates/
│   ├── agent-test-suite.json
│   ├── data-enrichment.json
│   ├── prompt-evaluation.json
│   ├── ab-testing.json
│   ├── flow-testing.json
│   ├── data-classification.json
│   └── multi-turn-conversation.json
├── AGENTFORCE-GRID-COCKPIT-SPEC.md  # (existing)
├── COCKPIT-VISUALIZATION-SPEC.md    # (existing)
├── PLUGIN-ARCHITECTURE.md           # (existing)
└── README.md                        # (existing)

agentforce-grid-mcp/                 (separate repo, referenced by .mcp.json)
├── src/
│   ├── index.ts                     # (existing)
│   ├── client.ts                    # (existing, enhanced with retry logic)
│   ├── tools/                       # (existing 7 modules + composite tools)
│   │   ├── workbooks.ts
│   │   ├── worksheets.ts
│   │   ├── columns.ts
│   │   ├── cells.ts
│   │   ├── agents.ts
│   │   ├── metadata.ts
│   │   ├── data.ts
│   │   └── composite.ts            # NEW: high-level workflow tools
│   ├── resources/                   # NEW: MCP resource providers
│   │   ├── workbook-resource.ts
│   │   └── worksheet-resource.ts
│   └── types.ts
├── tests/                           # NEW
│   ├── client.test.ts
│   ├── tools/
│   └── resources/
├── package.json
├── tsconfig.json
└── README.md                        # NEW
```

### Key Structural Decision: Two Repos

The MCP server stays in its own repo (`agentforce-grid-mcp`). The plugin repo references it via `.mcp.json` with a local path or npx command. Rationale:

1. The MCP server has its own build toolchain (TypeScript, npm)
2. It can be used independently (e.g., from Claude Desktop without the plugin)
3. Versioning and releases can be independent
4. `.mcp.json` supports both local dev paths and published npm packages

```json
// .mcp.json (in plugin repo root)
{
  "mcpServers": {
    "agentforce-grid": {
      "command": "node",
      "args": ["/path/to/agentforce-grid-mcp/dist/index.js"],
      "env": {
        "SF_ORG_ALIAS": "${SF_ORG_ALIAS}"
      }
    }
  }
}
```

---

## 3. Phased Implementation Plan

### Phase 1: Foundation (Weeks 1-2) -- DEFERRED

> **DEFERRED:** Plugin structure (plugin.json, agent definitions, slash commands) is deferred. The hybrid plan focuses on MCP server evolution first. See hybrid plan Phase 4 for hooks; agents and commands come later.

**Goal:** Transform the skill repo into a valid plugin structure. Move existing content into place. Define agents and slash commands. Get the MCP server wired up.

#### Deliverable 1.1: Plugin Skeleton

Create the plugin manifest and restructure directories.

**Files to create:**

```
.claude-plugin/plugin.json
```

```json
{
  "name": "agentforce-grid",
  "displayName": "Agentforce Grid",
  "version": "0.1.0",
  "description": "Complete toolkit for Agentforce Grid (AI Workbench): API skills, specialized agents, MCP tools, and workflow templates for agent testing, data enrichment, and prompt evaluation.",
  "author": {
    "name": "Salesforce"
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

**Files to move:**

| From | To |
|------|-----|
| `.claude/skills/agentforce-grid/SKILL.md` | `skills/grid-api/SKILL.md` |
| `.claude/skills/agentforce-grid/references/*` | `skills/grid-api/references/*` |

Keep the old `.claude/skills/agentforce-grid/` path as a symlink or redirect for backward compatibility during transition.

#### Deliverable 1.2: Agent Definitions

Create 5 agent markdown files with YAML frontmatter. Each agent delegates to MCP tools.

**`agents/grid-builder.md`** -- highest priority agent:

```yaml
---
name: grid-builder
description: >
  Creates Agentforce Grid worksheets from natural language descriptions.
  Translates requirements into API calls: creates workbooks, worksheets,
  columns (all 12 types), populates data, and triggers processing.
  Manages the column dependency graph (column IDs from creation responses
  feed into subsequent columns).
model: opus
permissionMode: acceptEdits
maxTurns: 30
---
```

The body should include the three-phase conversation pattern (Understand & Plan, Confirm & Resolve, Execute & Report) from `workflow-patterns.md` Section 1, the translation rules table (natural language to column types), and instructions to use `mcp__agentforce-grid__*` tools.

**`agents/grid-inspector.md`**:

```yaml
---
name: grid-inspector
description: >
  Reads and summarizes Agentforce Grid worksheet state. Fetches workbooks,
  worksheets, column schemas, cell data, and processing status. Renders
  compact summaries following the cockpit visualization patterns.
model: opus
permissionMode: default
maxTurns: 10
---
```

The body should reference the three-layer progressive disclosure from COCKPIT-VISUALIZATION-SPEC.md: summary banner first, then column strip, then data grid.

**`agents/grid-evaluator.md`**, **`agents/grid-debugger.md`**, **`agents/grid-orchestrator.md`** -- follow the same pattern from PLUGIN-ARCHITECTURE.md Section 3.

#### Deliverable 1.3: Slash Commands

Create 10 command files. Each is a markdown file defining the command name, description, arguments, and behavior instructions.

Priority order:
1. `commands/grid-new.md` -- delegates to grid-builder agent
2. `commands/grid-status.md` -- delegates to grid-inspector agent
3. `commands/grid-list.md` -- calls `mcp__agentforce-grid__get_workbooks`
4. `commands/grid-run.md` -- calls trigger/reprocess tools
5. `commands/grid-results.md` -- delegates to grid-evaluator agent
6. `commands/grid-debug.md` -- delegates to grid-debugger agent
7. `commands/grid-add.md` -- adds column via grid-builder logic
8. `commands/grid-models.md` -- calls `mcp__agentforce-grid__get_llm_models`
9. `commands/grid-export.md` -- fetches data, writes CSV/JSON locally
10. `commands/grid-compare.md` -- delegates to grid-evaluator with two worksheet IDs

Spec for each command is already defined in `workflow-patterns.md` Section 7.

#### Deliverable 1.4: Basic Hooks

Create `hooks/hooks.json` with SessionStart hook only (minimal viable hooks):

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
    ]
  }
}
```

**`hooks/session-init.sh`**: Check that SF CLI is installed and `SF_ORG_ALIAS` env var is set. Optionally ping `/workbooks` to validate auth. Output a brief status line.

#### Deliverable 1.5: Wire MCP Server

Create `.mcp.json` at plugin root pointing to the existing MCP server repo:

```json
{
  "mcpServers": {
    "agentforce-grid": {
      "command": "node",
      "args": ["../agentforce-grid-mcp/dist/index.js"],
      "env": {
        "SF_ORG_ALIAS": "${SF_ORG_ALIAS}"
      }
    }
  }
}
```

**Validation:** After this phase, `claude --plugin .` from the repo root should:
- Load all 3 skills
- Register all 5 agents
- Register all 10 slash commands
- Start the MCP server with 43 tools
- Run session-init hook on startup

---

### Phase 2: MCP Integration (Weeks 3-4) -- PARTIALLY SUPERSEDED

> **PARTIALLY SUPERSEDED:** Composite tools are now in hybrid plan Phase 2 (apply_grid + typed mutations). MCP resources are hybrid Phase 3. The cockpit visualization skill is DEFERRED.

**Goal:** Enhance the MCP server with composite tools, MCP resources, and wiring needed for the cockpit experience. Create the grid-cockpit visualization skill.

#### Deliverable 2.1: Composite MCP Tools

Add `src/tools/composite.ts` to the MCP server repo with three high-value tools:

**`create_agent_test_suite`** -- Single tool that:
1. Creates workbook + worksheet
2. Creates Text columns (utterances, expected responses, expected topics)
3. Looks up agent by name or ID via `get_agents`
4. Creates AgentTest column referencing utterance column
5. Creates Evaluation columns (configurable: RESPONSE_MATCH, TOPIC_ASSERTION, COHERENCE, LATENCY_ASSERTION)
6. Adds rows and pastes test data if provided
7. Triggers row execution
8. Returns worksheet ID, column map, row count

Parameters:
```typescript
{
  agentId: z.string(),
  agentVersion: z.string(),
  workbookName: z.string().optional(),
  worksheetName: z.string().optional(),
  utterances: z.array(z.string()).optional(),
  expectedResponses: z.array(z.string()).optional(),
  expectedTopics: z.array(z.string()).optional(),
  evaluationTypes: z.array(z.string()).default(["COHERENCE", "TOPIC_ASSERTION"]),
  rowCount: z.number().default(50)
}
```

**`poll_until_complete`** -- Polls worksheet status with adaptive backoff:
```typescript
{
  worksheetId: z.string(),
  timeoutMs: z.number().default(300000),
  columnId: z.string().optional()  // poll specific column only
}
```

Uses the adaptive poll interval from COCKPIT-VISUALIZATION-SPEC.md Section 5.2: 2s, 3s, 5s, then 8s steady state. Returns final status summary with cell counts by status.

**`get_evaluation_summary`** -- Fetches all evaluation column data, computes aggregates:
```typescript
{
  worksheetId: z.string()
}
```

Returns structured summary: per-evaluation pass rates, score distributions (p25/p50/p75/p90), failure breakdown by error type, worst-performing rows.

#### Deliverable 2.2: MCP Resources

Add `src/resources/` directory to the MCP server repo. Register resources in `src/index.ts`.

```typescript
// Resource URIs
"grid://workbooks"                    // List all workbooks
"grid://workbooks/{id}"               // Single workbook with worksheets
"grid://worksheets/{id}"              // Worksheet metadata + column schema
"grid://worksheets/{id}/data"         // Full worksheet data (cells)
"grid://worksheets/{id}/status"       // Processing status summary (computed)
"grid://columns/{id}/data"            // Column cell data
```

The `grid://worksheets/{id}/status` resource is the most valuable -- it computes the `GridSummary` from COCKPIT-VISUALIZATION-SPEC.md Section 1.1: total rows/columns, status counts, eval pass rate, score distributions, errors by column.

#### Deliverable 2.3: Grid-Cockpit Skill

Create `skills/grid-cockpit/SKILL.md` -- teaches Claude how to render grid state visually.

Content sourced from COCKPIT-VISUALIZATION-SPEC.md:
- Three-layer progressive disclosure (summary banner, column strip, data grid table)
- Status indicator system (`[OK]`, `[..]`, `[XX]`, `[~~]`)
- Type badge system (`[TXT]`, `[AI]`, `[AGT-TEST]`, `[EVAL]`, etc.)
- Truncation strategy for terminal width
- Evaluation summary table format
- Vertical card view for narrow terminals
- Column dependency DAG rendering (ASCII)
- Diff view for reprocessing results
- Worksheet briefing template (the structured summary Claude should lead with)
- Data freshness indicators and staleness warnings

References:
- `skills/grid-cockpit/references/cli-views.md` -- all ASCII formats with examples
- `skills/grid-cockpit/references/desktop-artifacts.md` -- HTML artifact templates

#### Deliverable 2.4: MCP Server Improvements

In the MCP server repo:

1. Add retry logic to `GridClient.httpRequest()` -- exponential backoff for 429 (rate limit) and 503 responses, max 3 retries
2. Add `README.md` with setup instructions, env var documentation, tool inventory
3. Add basic integration test scaffolding using `vitest` -- mock the HTTP layer, test tool registration and input validation

**Validation:** After this phase:
- Three composite tools available as `mcp__agentforce-grid__create_agent_test_suite`, etc.
- MCP resources readable via `grid://` URIs
- Grid-cockpit skill teaches Claude to render formatted tables instead of raw JSON
- `/grid-new "test my Sales Agent"` triggers agent-test-suite creation in one step

---

### Phase 3: Intelligence (Weeks 5-6) -- LARGELY SUPERSEDED

> **SUPERSEDED:** The template system (Deliverable 3.1) is superseded by YAML DSL + apply_grid (hybrid plan Phases 1-2). Hooks (3.2, 3.3) are moved to hybrid plan Phase 4.1-4.2. Grid-patterns skill (3.4) is DEFERRED.

**Goal:** Build the template system, implement PreToolUse and PostToolUse hooks, create the grid-patterns skill for error recovery.

#### Deliverable 3.1: Template System -- SUPERSEDED by YAML DSL + apply_grid

Create 7 JSON template files in `templates/`. Each follows the template schema from PLUGIN-ARCHITECTURE.md Section 5.1:

```json
{
  "$schema": "https://agentforce-grid.salesforce.com/template-schema/v1.json",
  "name": "...",
  "version": "1.0.0",
  "parameters": { ... },
  "columns": [ ... ],
  "sampleData": { ... }
}
```

Templates use `$ref` pointers for column cross-references and `{{parameter}}` interpolation.

| Template | File | Columns | Source Spec |
|----------|------|---------|------------|
| Agent Test Suite | `agent-test-suite.json` | Text x3, AgentTest, Evaluation x4 | PLUGIN-ARCHITECTURE.md Section 5.1 (full example provided) |
| Data Enrichment | `data-enrichment.json` | Object, AI x2, Reference x2 | COCKPIT-SPEC Section 12 |
| Prompt Evaluation | `prompt-evaluation.json` | Text x2, PromptTemplate, Evaluation x3 | COCKPIT-SPEC Section 12 |
| A/B Testing | `ab-testing.json` | Text, AI x2 (different models), Evaluation x4 | workflow-patterns.md Example C |
| Flow Testing | `flow-testing.json` | Text x3, InvocableAction, Reference x2, Evaluation | COCKPIT-SPEC Section 12 |
| Data Classification | `data-classification.json` | Object, AI (SINGLE_SELECT) x3, Formula | COCKPIT-SPEC Section 12 |
| Multi-Turn Conversation | `multi-turn-conversation.json` | Text x2, Agent (turn 1), Text, Agent (turn 2 + history) | COCKPIT-SPEC Section 12 |

Add a `create_from_template` composite tool to the MCP server that:
1. Reads a template JSON
2. Prompts for required parameters
3. Topologically sorts columns by dependency
4. Creates columns sequentially, substituting `$ref` with real column IDs
5. Optionally populates sample data

#### Deliverable 3.2: PreToolUse Validation Hook

Create `hooks/validate-config.py` and register in `hooks/hooks.json`:

```json
"PreToolUse": [
  {
    "matcher": "mcp__agentforce-grid__add_column",
    "hooks": [
      {
        "type": "command",
        "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/validate-config.py",
        "timeout": 5000
      }
    ]
  }
]
```

The script reads the tool input from stdin (JSON with `tool_input` containing the column config) and validates:

1. Nested `config.config` structure is present (the single most common error)
2. Outer `type` field matches inner `config.type`
3. `queryResponseFormat` is appropriate (`EACH_ROW` when worksheet has data, `WHOLE_COLUMN` for Object imports)
4. `referenceAttributes` use UPPERCASE `columnType` values
5. `modelConfig` has both `modelId` and `modelName` for AI/PromptTemplate columns
6. `ContextVariable` has either `value` or `reference`, not both
7. Evaluation columns with reference-requiring types (RESPONSE_MATCH, TOPIC_ASSERTION, etc.) have `referenceColumnReference`

On failure, returns `BLOCKER` status with a specific fix suggestion in the `message` field. On success, returns empty/passthrough.

#### Deliverable 3.3: PostToolUse Rendering Hook

Create `hooks/post-api-call.sh` and register:

```json
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
  }
]
```

Behavior by tool:
- After `add_column` / `edit_column`: Inject a message showing the updated column pipeline strip
- After `paste_data` / `update_cells`: Show row count and cell status summary
- After `trigger_row_execution` / `reprocess_column`: Start background polling, inject progress updates
- After `create_agent_test_suite`: Show the full summary banner

The hook reads tool output from stdin, extracts the worksheet ID, calls `get_worksheet_data` via the MCP server, and renders a compact summary using the cockpit formats from the grid-cockpit skill.

#### Deliverable 3.4: Grid-Patterns Skill

Create `skills/grid-patterns/SKILL.md` with references:

- `references/error-recovery.md` -- Common API errors, diagnosis steps, auto-fix patterns. Sourced from PLUGIN-ARCHITECTURE.md Section 3.4 (grid-debugger responsibilities) and workflow-patterns.md Section 4B/8.
- `references/polling-strategies.md` -- Adaptive polling intervals, selective data fetching, concurrent column tracking. From COCKPIT-VISUALIZATION-SPEC.md Section 5.
- `references/multi-worksheet-workflows.md` -- Cross-worksheet data passing, aggregate reporting, version comparison. From workflow-patterns.md Section 6.

**Validation:** After this phase:
- PreToolUse hook catches config errors before API call (eliminates the most common failure mode)
- PostToolUse hook auto-renders grid state after every mutation
- `/grid-new` can accept a template name and create a full grid from it
- Error recovery patterns are available to all agents

---

### Phase 4: Polish (Weeks 7-8) -- DEFERRED

> **DEFERRED:** Desktop artifacts, CI/CD, marketplace packaging are all deferred beyond the hybrid plan's scope.

**Goal:** Desktop visualization, CI/CD integration, comprehensive testing, packaging.

#### Deliverable 4.1: Desktop HTML Artifacts

Add artifact generation instructions to `skills/grid-cockpit/references/desktop-artifacts.md`. Define 5 HTML artifact types from COCKPIT-VISUALIZATION-SPEC.md Section 3:

1. **Interactive Grid Table** -- Sortable, filterable data table with color-coded cells, status indicators, cell expansion
2. **Evaluation Dashboard** -- Pass rate bars, score distribution histograms, failure analysis, latency percentiles
3. **Column Dependency Graph** -- SVG-based DAG with clickable nodes showing column name, type badge, status, completion count
4. **Evaluation Heatmap** -- Rows x evaluations matrix with red-yellow-green color scale
5. **Processing Timeline** -- Gantt-chart of column processing with bottleneck identification

All artifacts self-contained (inline CSS/JS, no CDN), responsive, accessible, under 100KB. Templates provided as reference examples in the skill so Claude can generate them from live data.

#### Deliverable 4.2: CI/CD Integration

Add CI/CD patterns to the grid-patterns skill or as a standalone reference:

- Shell script template for deployment gates (trigger grid run, poll, assert thresholds)
- GitHub Actions workflow example using Claude Code CLI
- Regression detection rules from AGENTFORCE-GRID-COCKPIT-SPEC.md Section 14
- Version comparison workflow (create parallel worksheet, same utterances, different agent version)
- Machine-readable JSON output format for CI assertion

#### Deliverable 4.3: Comprehensive Testing

**MCP server tests** (in `agentforce-grid-mcp/tests/`):
- Unit tests for `GridClient` (token caching, retry logic, error handling)
- Unit tests for each tool module (input validation, response formatting)
- Unit tests for composite tools (mock API responses, verify multi-step orchestration)
- Integration test harness that records and replays HTTP interactions

**Plugin structure validation:**
- Script that validates `plugin.json` references resolve correctly
- Script that checks all agent/command markdown files have valid YAML frontmatter
- Script that validates template JSON files match the schema
- Hook execution smoke tests

#### Deliverable 4.4: Marketplace Packaging

- Update `plugin.json` to version `1.0.0`
- Write comprehensive README with: overview, installation, configuration (env vars), quick start, full command reference, template catalog
- Add LICENSE file
- Create `.npmignore` / equivalent for clean packaging of the MCP server
- Tag releases for both repos

**Validation:** After this phase, the plugin is installable, documented, tested, and ready for the Claude Code marketplace.

---

## 4. Decision Log

| # | Decision | Rationale | Alternatives Considered |
|---|----------|-----------|------------------------|
| D1 | **Two separate repos** -- plugin in `agentforce-grid-ai-skills`, MCP server in `agentforce-grid-mcp` | MCP server has its own build toolchain, can be used independently from Claude Desktop, versioned separately. `.mcp.json` bridges them. | Monorepo with MCP server as subdirectory. Rejected because it complicates npm publishing and forces plugin consumers to install TypeScript toolchain. |
| D2 | **Single skill becomes three skills** (grid-api, grid-cockpit, grid-patterns) | Separation of concerns: API reference knowledge, visualization instructions, and advanced patterns are distinct skill domains. Claude loads only what is relevant to the current task. | Keep as single large SKILL.md. Rejected because the combined content would be ~2000+ lines, diluting relevance. |
| D3 | **Opus for all agents** | Grid operations involve complex JSON config generation, nuanced evaluation analysis, multi-step dependency management. Cheaper models consistently fail at nested config structures and cross-column reasoning. Per PLUGIN-ARCHITECTURE.md Section 8 Principle 7. | Use Sonnet for simple agents (inspector, list). Rejected because even "simple" tasks like rendering evaluation summaries benefit from Opus-level reasoning. |
| D4 | **MCP tools over direct HTTP** | Type-safe inputs with Zod validation, clean hook matching via `mcp__agentforce-grid__*`, discoverable tool list, auth management in one place, works in Claude Desktop. Per AGENTFORCE-GRID-COCKPIT-SPEC.md Section 5 comparison table. | Keep using curl/fetch via Bash. Rejected because it loses validation, discoverability, and Desktop support. |
| D5 | **Use SF CLI auth exclusively** | SF CLI provides seamless authentication without manual token management. | Implemented - all specs updated to use SF CLI. |
| D6 | **Templates are JSON data, not executable code** | Templates are versionable, diffable, shareable JSON with `$ref` pointers. Resolution logic lives in the `create_from_template` composite tool. Per PLUGIN-ARCHITECTURE.md Section 8 Principle 5. | Templates as shell scripts or Python scripts. Rejected because scripts are harder to validate, version, and share. |
| D7 | **PreToolUse validation targets `add_column` specifically** | Column creation is the highest-error-rate operation due to the nested `config.config` structure. Validating all MCP tools would add latency to read-only operations. | Match all `mcp__agentforce-grid__*` tools. Rejected for performance -- read operations do not benefit from config validation. Expand matcher to include `edit_column` and `reprocess_column` as well. |
| D8 | **Composite tools in MCP server, not in agents** | `create_agent_test_suite` as an MCP tool is callable from any agent, any slash command, and from Claude Desktop. If it were agent logic, it would only work within that agent's context. | Implement multi-step workflows purely in agent instructions. Rejected because agent instructions are less reliable for exact API call sequences than deterministic tool code. |
| D9 | **10 slash commands** | Each command maps to a clear user intent and delegates to the right agent or MCP tool. The full set covers the workflow lifecycle: create, monitor, run, analyze, debug, compare, export. | Fewer commands with subcommands (e.g., `/grid create`, `/grid status`). Claude Code's slash command system uses separate files per command, making the 10-command approach more natural. |
| D10 | **Phased rollout, not big-bang** | Enables incremental validation. Phase 1 delivers immediate value (plugin structure + MCP wiring). Each phase builds on the previous. Risks are isolated. | Ship everything at once. Rejected because the full plugin has ~50 files; incremental delivery reduces integration risk. |

---

## 5. Risk Register

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|------------|
| R1 | **Plugin system API changes** -- Claude Code's plugin.json schema, hook system, or agent frontmatter format may change between now and release | Medium | High | Pin to Claude Code v2.1.70 conventions observed in PLUGIN-ARCHITECTURE.md. Monitor Claude Code changelogs. Keep plugin.json minimal. |
| R2 | **MCP resource support incomplete** -- `grid://` URI scheme requires Claude Code to support custom resource URIs, which may not be fully implemented | Medium | Low | Resources are a convenience, not a requirement. All functionality works through tools alone. Defer resources if blocked. |
| R3 | **PreToolUse hook latency** -- Python script adds 1-3s to every column creation call | Low | Medium | Keep validation fast (pure JSON parsing, no network calls). Set 5000ms timeout. If too slow, rewrite in bash or Node.js. |
| R4 | **PostToolUse hook complexity** -- The hook needs to call the MCP server to fetch fresh state, which creates a circular dependency (hook triggers tool, tool triggers hook) | Medium | High | The hook should call the Grid API directly (via curl) rather than through the MCP server. Use the same env vars. Add a flag/marker to prevent hook-on-hook recursion. |
| R5 | **Composite tool reliability** -- `create_agent_test_suite` makes 8-15 sequential API calls; any failure mid-sequence leaves partial state | Medium | Medium | Implement idempotent cleanup: if step N fails, delete the workbook created in step 1. Return partial results with clear error indicating which step failed. |
| R6 | **SF CLI session expiry during long operations** -- Composite tools and polling may run for 5+ minutes | Low | Low | SF CLI manages session automatically with longer validity periods. |
| R7 | **Template schema drift** -- Grid API evolves, template column configs become invalid | Medium | Medium | Templates reference column types and evaluation types by name, not by internal IDs. Pin templates to API version (v66.0). Add a template validation step that checks configs against the current API schema. |
| R8 | **Agent hallucination of column configs** -- Even Opus may generate incorrect nested config structures | Medium | High | The PreToolUse validation hook (Deliverable 3.2) catches this before the API call. Additionally, the grid-api skill's SKILL.md has explicit examples of correct configs. Belt and suspenders. |
| R9 | **Rate limiting during polling** -- Aggressive polling of `GET /worksheets/{id}/data` hits API rate limits | Low | Medium | Adaptive polling interval (2s, 3s, 5s, 8s steady state) keeps request rate low. Add 429 retry logic with exponential backoff in GridClient. |
| R10 | **Two-repo coordination** -- Changes in MCP server (new tools, renamed tools) require matching updates in plugin (agent instructions, hook matchers) | Medium | Medium | Document tool naming conventions. Use a shared version contract. CI in the plugin repo should validate that expected MCP tools exist by checking the MCP server's tool registry. |

---

## 6. Dependencies and Critical Path

### Dependency Graph

```
Phase 1                     Phase 2                    Phase 3                   Phase 4
────────                    ────────                   ────────                  ────────

[1.1 Plugin skeleton] ──┬── [2.3 Grid-cockpit skill]  [3.1 Templates] ───────── [4.4 Packaging]
                        │                                    │
[1.2 Agent defs] ───────┤                              [3.4 Grid-patterns] ──── [4.2 CI/CD]
                        │
[1.3 Slash commands] ───┤
                        │
[1.4 Basic hooks] ──────┼── [3.2 PreToolUse hook]
                        │   [3.3 PostToolUse hook]
                        │
[1.5 Wire MCP] ────────┼── [2.1 Composite tools] ──── [3.1 create_from_template]
                        │   [2.2 MCP resources]
                        │   [2.4 MCP improvements]
                        │
                        └────────────────────────────── [4.3 Testing]
                                                        [4.1 Desktop artifacts]
```

### Critical Path

The longest dependency chain is:

```
1.5 Wire MCP (Week 1)
  -> 2.1 Composite tools (Week 3)
    -> 3.1 Templates + create_from_template (Week 5)
      -> 4.3 Testing (Week 7)
        -> 4.4 Packaging (Week 8)
```

This 8-week chain cannot be compressed without parallelization.

### Parallelizable Work

| Week | Track A (Plugin) | Track B (MCP Server) |
|------|-----------------|---------------------|
| 1 | 1.1 Plugin skeleton, 1.2 Agent defs | -- (existing server is sufficient) |
| 2 | 1.3 Slash commands, 1.4 Hooks, 1.5 Wire MCP | -- |
| 3 | 2.3 Grid-cockpit skill | 2.1 Composite tools, 2.4 MCP improvements |
| 4 | -- (test/validate Phase 2) | 2.2 MCP resources |
| 5 | 3.2 PreToolUse hook, 3.4 Grid-patterns skill | 3.1 Templates + create_from_template tool |
| 6 | 3.3 PostToolUse hook | 3.1 continued (7 templates) |
| 7 | 4.1 Desktop artifacts, 4.2 CI/CD | 4.3 Testing (MCP server) |
| 8 | 4.3 Testing (plugin), 4.4 Packaging | 4.4 Packaging (MCP server npm) |

### Blocking Dependencies

| Blocked Item | Blocked By | Reason |
|-------------|-----------|--------|
| All agents | 1.5 Wire MCP | Agents need `mcp__agentforce-grid__*` tools to function |
| Composite tools | Existing 43 tools | Composite tools call lower-level tools internally |
| PreToolUse hook | 1.4 hooks.json | Hook must be registered to fire |
| PostToolUse hook | 2.3 Grid-cockpit skill | Hook output should follow cockpit rendering conventions |
| Templates | 2.1 Composite tools | `create_from_template` is a composite tool |
| CI/CD patterns | 2.1 `poll_until_complete` | CI needs programmatic polling |
| Desktop artifacts | 2.3 Grid-cockpit skill | Artifact HTML follows cockpit data model |
| Marketplace packaging | All above | Cannot package until all features are in place |

### External Dependencies

| Dependency | Owner | Risk |
|-----------|-------|------|
| Claude Code plugin system stability | Anthropic | Medium -- plugin.json schema may evolve |
| MCP SDK stability | Anthropic | Low -- `@modelcontextprotocol/sdk` v1.12.1 is mature |
| Grid API v66.0 stability | Salesforce | Low -- public API with versioned endpoints |
| Grid API rate limits | Salesforce | Medium -- polling and composite tools hit limits |
| Claude Code hook system | Anthropic | Medium -- PreToolUse/PostToolUse may have undocumented constraints |

---

## Appendix A: MCP Server Tool Inventory (Current 43 Tools)

For reference, the complete list of tools currently implemented in `agentforce-grid-mcp`:

**Workbooks (4):** `get_workbooks`, `create_workbook`, `get_workbook`, `delete_workbook`

**Worksheets (10):** `create_worksheet`, `get_worksheet`, `get_worksheet_data`, `get_worksheet_data_generic`, `update_worksheet`, `delete_worksheet`, `get_supported_columns`, `add_rows`, `delete_rows`, `import_csv`

**Columns (8):** `add_column`, `edit_column`, `delete_column`, `save_column`, `reprocess_column`, `get_column_data`, `create_column_from_utterance`, `generate_json_path`

**Cells (5):** `update_cells`, `paste_data`, `trigger_row_execution`, `validate_formula`, `generate_ia_input`

**Agents (6):** `get_agents`, `get_agents_including_drafts`, `get_agent_variables`, `get_draft_topics`, `get_draft_topics_compiled`, `get_draft_context_variables`

**Metadata (14):** `get_column_types`, `get_llm_models`, `get_supported_types`, `get_evaluation_types`, `get_formula_functions`, `get_formula_operators`, `get_invocable_actions`, `describe_invocable_action`, `get_prompt_templates`, `get_prompt_template`, `get_list_views`, `get_list_view_soql`, `generate_soql`, `generate_test_columns`

**Data/SObject (7):** `get_sobjects`, `get_sobject_fields_display`, `get_sobject_fields_filter`, `get_sobject_fields_record_update`, `get_dataspaces`, `get_data_model_objects`, `get_data_model_object_fields`

**Planned additions (4):** `create_agent_test_suite`, `poll_until_complete`, `get_evaluation_summary`, `create_from_template`

## Appendix B: Auth Reconciliation

The MCP server currently uses a different auth model than what PLUGIN-ARCHITECTURE.md specifies:

| Aspect | Current (MCP Server) | Spec (PLUGIN-ARCHITECTURE.md) |
|--------|---------------------|-------------------------------|
