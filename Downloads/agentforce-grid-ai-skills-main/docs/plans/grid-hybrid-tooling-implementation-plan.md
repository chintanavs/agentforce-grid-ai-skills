# Agentforce Grid Hybrid Tooling -- Implementation Plan

**Date:** 2026-03-06 (updated)
**Status:** Active -- Phase 0 complete, Phases 1-4 ready to build
**Goal:** Make Claude Code build Agentforce Grids 10x faster and with near-zero config errors

---

## Current State (Phase 0 -- Complete)

Four PRs have been merged into `grid-connect-mcp`, producing a fully functional CRUD MCP server:

### What Exists Today

| Component | File | Details |
|-----------|------|---------|
| Hardened HTTP client | `src/client.ts` | Retry on ECONNRESET/ETIMEDOUT, 401 token refresh, 429 rate-limit respect, 5xx exponential backoff, configurable timeout |
| Zod schemas for all 12 column types | `src/schemas.ts` | `ColumnInputSchema`, `ColumnConfigUnionSchema` (discriminated union), per-type inner config schemas |
| MCP server entry point | `src/index.ts` | Registers 8 tool modules |
| 40+ MCP tools across 8 modules | `src/tools/*.ts` | Workbooks (4), Worksheets (10), Columns (8), Cells (5), Agents (5), Metadata (14), Data (7), Workflows (4) |
| Composite workflow: `setup_agent_test` | `src/tools/workflows.ts` | Creates workbook + worksheet + Text col + AgentTest col + Evaluation cols + pastes data in one call |
| Composite workflow: `poll_worksheet_status` | `src/tools/workflows.ts` | Polls until all cells reach terminal state with per-column status counts |
| Composite workflow: `get_worksheet_summary` | `src/tools/workflows.ts` | Structured summary with column names, types, and cell status counts |
| Zod-validated column tools | `src/tools/columns.ts` | `add_column`, `edit_column`, `save_column`, `reprocess_column` all validate against `ColumnConfigUnionSchema` |

### File Structure (Current)

```
grid-connect-mcp/
  src/
    index.ts                   # MCP server entry, registers all tool modules
    client.ts                  # HTTP client with retry/auth/rate-limit handling
    schemas.ts                 # Zod schemas for all 12 column types (THE CONTRACT)
    types.ts                   # Minimal types (RegisterToolsFn)
    tools/
      workbooks.ts             # get_workbooks, create_workbook, get_workbook, delete_workbook
      worksheets.ts            # create_worksheet, get_worksheet, get_worksheet_data, etc (10 tools)
      columns.ts               # add_column, edit_column, delete_column, save_column, reprocess_column, etc (8 tools)
      cells.ts                 # update_cells, paste_data, trigger_row_execution, etc (5 tools)
      agents.ts                # get_agents, get_agent_variables, get_draft_topics, etc (5 tools)
      metadata.ts              # get_llm_models, get_evaluation_types, get_prompt_templates, etc (14 tools)
      data.ts                  # get_sobjects, get_dataspaces, get_data_model_objects, etc (7 tools)
      workflows.ts             # setup_agent_test, poll_worksheet_status, get_worksheet_summary, create_workbook_with_worksheet (4 tools)
  package.json
  tsconfig.json
  FOLLOWUPS.md                 # Remaining items from initial build
```

### Key Architectural Decision: Zod Schemas ARE the Contract

`src/schemas.ts` defines the authoritative schema for all 12 column types as Zod discriminated unions. This has critical implications for the plan:

- **The config expander (Phase 1.7) must produce objects that pass `ColumnConfigUnionSchema`** -- it does not define its own types.
- **Typed mutation tools (Phase 2) read/write objects validated by these schemas** -- they share the same contract.
- **The YAML DSL resolution engine outputs must conform to `ColumnInputSchema`** -- the Zod schemas are the bridge between flat YAML and the API.
- **`setup_agent_test` in `workflows.ts` is the pattern for `apply_grid`** -- it demonstrates how to compose workbook creation + column creation + data paste in a single tool, constructing config objects that match the schema.

### What `setup_agent_test` Teaches Us About `apply_grid`

The existing `setup_agent_test` tool (`src/tools/workflows.ts:93-269`) is a domain-specific precursor to the general-purpose `apply_grid`. Key patterns to reuse:

1. **Sequential creation with ID threading** -- creates workbook, then worksheet, then columns, passing IDs from each step to the next
2. **Config objects built in-line** -- constructs the triple-nested `config.config` structure directly (lines 186-209)
3. **Dynamic reference wiring** -- uses `utteranceColId` from a prior step to build `inputUtterance.columnId` in the AgentTest config
4. **Row management** -- adds rows, fetches row IDs, then pastes data
5. **Error handling** -- try/catch with descriptive error messages

`apply_grid` generalizes this: instead of hardcoded column types, it reads them from YAML and uses the config expander to build the nested JSON.

---

## Architecture Overview

```
                        Claude Code CLI
                             |
                    +--------v--------+
                    |   MCP Server    |  grid-connect-mcp (enhanced)
                    +--------+--------+
                             |
         +-------------------+-------------------+
         |                   |                   |
    +----v----+       +------v------+     +------v------+
    |apply_grid|      |Typed Mutate |     |  Resources  |
    |  (YAML)  |      |   Tools     |     |  (read-only)|
    +----+----+       +------+------+     +------+------+
         |                   |                   |
    +----v----------+        |            +------v------+
    |  Resolution   |        |            |  Resource   |
    |    Engine     |        |            |   Cache     |
    | +~~~~~~~~~~~+ |        |            +-------------+
    | | Validate  | |        |
    | | Resolve   | |        |
    | | Topo Sort | |        |
    | | Expand    | |        |
    | | Create    | |        |
    | +~~~~~~~~~~~+ |        |
    +-------+-------+        |
            |                |
            +--------+-------+
                     |
             +-------v-------+
             |  Grid REST API |
             +---------------+
```

**Three interaction modes:**
1. **Create** -- `apply_grid` with YAML DSL -> resolution engine -> sequential API calls (one tool call creates entire grid)
2. **Modify** -- Typed mutation tools (`edit_ai_prompt`, `add_evaluation`, `change_model`, etc.) -> fetch-merge-save pattern
3. **Read** -- MCP Resources (`grid://worksheets/{id}/schema`, `grid://models`, etc.) -> just-in-time context

---

## Implementation Phases

### Phase 1: Foundation (Core Libraries)

**Goal:** Build the core libraries that the resolution engine and typed mutations depend on.

**Key constraint:** The config expander MUST produce objects that pass the existing Zod schemas in `src/schemas.ts`. Do not duplicate type definitions.

| # | Task | File | Depends On | Notes |
|---|------|------|------------|-------|
| 1.1 | Model shorthand map | `src/lib/model-map.ts` | -- | Map `gpt-4-omni` -> `sfdc_ai__DefaultGPT4Omni`, etc. Fallback: unrecognized names pass through as full IDs. ~10 mappings. |
| 1.2 | Config helpers (fetch, resolve, merge) | `src/lib/config-helpers.ts` | -- | `getColumnConfig(client, columnId)` -> fetches worksheet data, extracts column config. `resolveColumnRef(name, columns)` -> name to ID/type. `mergeConfig(existing, changes)` -> deep merge. Shared by typed mutations and resolution engine. |
| 1.3 | Resource cache | `src/lib/resource-cache.ts` | -- | Simple TTL map. Keys: resource URIs. Values: cached data + expiry. |
| 1.4 | Column schemas (static metadata) | `src/lib/column-schemas.ts` | -- | Static per-type metadata for `grid://schema/{type}` resource. Derived from but NOT duplicating `src/schemas.ts` -- these provide human-readable descriptions, examples, and pitfalls. |
| 1.5 | YAML parser + GridSpec types | `src/lib/yaml-parser.ts` | -- | Parse YAML string -> typed `GridSpec` AST. Add `yaml` npm dependency. Types defined here but config expansion output validated against `schemas.ts`. |
| 1.6 | Validation engine (6 passes) | `src/lib/validator.ts` | 1.5 | YAML parse, type-specific required fields, reference integrity, cycle detection (Kahn's algorithm), type compatibility, value validation. Zod schemas handle structural validation; this adds cross-column semantic validation. |
| 1.7 | Config expander (YAML -> GCC JSON) | `src/lib/config-expander.ts` | 1.1 | Expand flat YAML column specs to triple-nested GCC JSON. **Output must pass `ColumnConfigUnionSchema.parse()`**. Import and use the Zod types from `schemas.ts` for type safety. |
| 1.8 | Resolution engine (full pipeline) | `src/lib/resolution-engine.ts` | 1.5, 1.6, 1.7 | Orchestrates: parse -> validate -> resolve names to IDs -> topo sort -> expand -> create. Returns `ApplyGridResult`. |

**Key data structures:**

```typescript
// Parsed YAML (from yaml-parser.ts)
interface GridSpec {
  workbook: string;
  worksheet: string;
  defaults: { numberOfRows: number; model: string };
  columns: ColumnSpec[];
  data?: Record<string, string[]>;
}

// Resolution context (accumulated during execution)
interface ResolutionContext {
  workbookId: string | null;
  worksheetId: string | null;
  columnMap: Map<string, string>;          // name -> ID
  agentMap: Map<string, AgentInfo>;        // name -> {id, version}
  existingColumns: Map<string, ColumnMeta>; // for incremental apply
}

// Config expander output: must satisfy ColumnInputSchema from schemas.ts
// import { ColumnInput } from "../schemas.js";
```

**Spec assumption update:** The resolution engine spec defines its own `ColumnConfig` types. These are now superseded by the Zod schemas in `src/schemas.ts`. The config expander should import and target `ColumnInput` / `ColumnConfigUnionSchema` directly rather than defining parallel types.

---

### Phase 2: MCP Tools

**Goal:** Ship `apply_grid` and typed mutation tools.

| # | Task | File | Depends On | Notes |
|---|------|------|------------|-------|
| 2.1 | `apply_grid` tool | `src/tools/apply-grid.ts` | Phase 1 | Follow `setup_agent_test` pattern: sequential creation with ID threading. Delegates to resolution engine. Supports `dryRun` mode. |
| 2.2 | `edit_ai_prompt` | `src/tools/typed-mutations.ts` | 1.1, 1.2 | Change instruction, model, responseFormat. Fetch-merge-save. |
| 2.3 | `edit_agent_config` | `src/tools/typed-mutations.ts` | 1.2 | Change agent, utterance, contextVariables. Works for both Agent and AgentTest. |
| 2.4 | `add_evaluation` | `src/tools/typed-mutations.ts` | 1.2 | Add eval column by type + target column name. Resolves names to IDs. |
| 2.5 | `change_model` | `src/tools/typed-mutations.ts` | 1.1, 1.2 | Switch model on AI or PromptTemplate column. |
| 2.6 | `update_filters` | `src/tools/typed-mutations.ts` | 1.2 | Replace filters on Object or DataModelObject column. |
| 2.7 | `reprocess` | `src/tools/typed-mutations.ts` | 1.2 | Enhanced reprocess: scope by column or worksheet, filter by all/failed/stale. |
| 2.8 | `edit_prompt_template` | `src/tools/typed-mutations.ts` | 1.1, 1.2 | Change template, input mappings, model. |
| 2.9 | Register new tools in index.ts | `src/index.ts` | 2.1-2.8 | Add imports and registration calls. |

**Typed mutation pattern (all tools share this via config-helpers):**
1. `getColumnConfig(client, columnId)` -- fetch current config from worksheet data
2. Validate column type matches tool's target type
3. Resolve column name references against worksheet schema
4. Merge user's changes into existing `config.config`
5. Validate merged config against `ColumnConfigUnionSchema`
6. `PUT /columns/{id}` (reprocess) or `POST /columns/{id}/save` (save only)

---

### Phase 3: MCP Resources

**Goal:** Give Claude just-in-time contextual information without loading full reference docs.

| # | Task | File | Depends On | Notes |
|---|------|------|------------|-------|
| 3.1 | `grid://worksheets/{id}/schema` | `src/resources/worksheet-resources.ts` | 1.3 | Column names, types, IDs, dependency graph. Reuse logic from `get_worksheet_summary`. |
| 3.2 | `grid://worksheets/{id}/status` | `src/resources/worksheet-resources.ts` | 1.3 | Per-column processing status. Reuse `countStatuses()` from `workflows.ts`. |
| 3.3 | `grid://agents` | `src/resources/metadata-resources.ts` | 1.3 | Agent list with IDs, versions, topics. Backed by `get_agents` API call + cache. |
| 3.4 | `grid://models` | `src/resources/metadata-resources.ts` | 1.1, 1.3 | Available LLM models with shorthand aliases from model-map. |
| 3.5 | `grid://schema/{columnType}` | `src/resources/metadata-resources.ts` | 1.4 | On-demand schema reference for a column type. Replaces loading full column-configs.md. |
| 3.6 | `grid://schema/dsl` | `src/resources/dsl-resource.ts` | -- | YAML DSL reference for `apply_grid`. |
| 3.7 | Register resources in index.ts | `src/index.ts` | 3.1-3.6 | Add imports and registration calls. |

**Cache TTLs:**

| Resource | TTL | Rationale |
|----------|-----|-----------|
| `grid://agents` | 5 min | Agent list changes rarely |
| `grid://models` | 30 min | Model list is very stable |
| `grid://schema/{type}` | Infinite (static) | Compiled at build time |
| `grid://schema/dsl` | Infinite (static) | Changes only on deploy |
| `grid://worksheets/{id}/schema` | 30 sec | Changes when columns added/removed |
| `grid://worksheets/{id}/status` | 10 sec | Changes frequently during processing |

---

### Phase 4: Claude Code Integration

**Goal:** Hooks, skill reference update, and end-to-end polish.

| # | Task | File | Depends On | Notes |
|---|------|------|------------|-------|
| 4.1 | PreToolUse validation hook | `hooks/validate-config.py` | -- | Catches top 6 config errors (missing `config.config`, type mismatch, lowercase `columnType`, etc.). Can start in parallel with Phases 1-2. |
| 4.2 | PostToolUse ASCII rendering hook | `hooks/post-api-call.sh` + `hooks/render-grid.py` | -- | Renders worksheet state after mutations. Can start in parallel. |
| 4.3 | Compact DSL skill reference | `skills/references/dsl-reference.md` | Phase 2 | ~100-line YAML DSL quick reference replacing ~900-line column-configs.md. |
| 4.4 | Update SKILL.md to reference DSL | `skills/SKILL.md` | 4.3 | Point Claude to DSL reference and `apply_grid` tool. |
| 4.5 | hooks.json registration | `hooks/hooks.json` | 4.1, 4.2 | Register hooks for `add_column`, `edit_column`, `apply_grid`, etc. |
| 4.6 | Rewrite skill examples to MCP syntax | Skill `use-case-patterns.md`, `workflow-patterns.md` | Phase 2 | **From FOLLOWUPS P2-1.** Replace curl/REST examples with `mcp__grid-connect__<tool>()` syntax. Highest-impact skill change. |
| 4.7 | Add MCP tool quick-reference table | Skill `SKILL.md` | Phase 2 | **From FOLLOWUPS P2-2.** Maps common actions to tool names. |
| 4.8 | Document undocumented tools | Skill docs | -- | **From FOLLOWUPS P2-3.** `get_agents_including_drafts`, `get_draft_topics`, `get_draft_topics_compiled`, `get_draft_context_variables`, `generate_test_columns`. |
| 4.9 | Document trigger_row_execution types | Skill docs | -- | **From FOLLOWUPS P2-4.** `RUN_SELECTION`, `EDIT`, `PASTE` trigger types. |
| 4.10 | Add Data Cloud / DMO use-case pattern | Skill docs | -- | **From FOLLOWUPS P2-6.** End-to-end DMO workflow. |
| 4.11 | Add List View import pattern | Skill docs | -- | **From FOLLOWUPS P2-7.** `get_list_views` -> `get_list_view_soql` -> Object column. |
| 4.12 | End-to-end testing | -- | All phases | Test full YAML -> grid creation pipeline. |

---

## File Structure (Final State)

```
grid-connect-mcp/
  src/
    index.ts                          # Updated: register new tools + resources
    client.ts                         # Unchanged
    schemas.ts                        # Unchanged (THE CONTRACT -- all new code targets these schemas)
    types.ts                          # Unchanged
    tools/
      workbooks.ts                    # Unchanged
      worksheets.ts                   # Unchanged
      columns.ts                      # Unchanged (descriptions updated in Phase 4 soft-deprecation)
      cells.ts                        # Unchanged
      agents.ts                       # Unchanged
      metadata.ts                     # Unchanged
      data.ts                         # Unchanged
      workflows.ts                    # Unchanged (setup_agent_test remains as-is)
      apply-grid.ts                   # NEW: apply_grid composite tool
      typed-mutations.ts              # NEW: 7 typed mutation tools
    resources/
      worksheet-resources.ts          # NEW: schema, status
      metadata-resources.ts           # NEW: agents, models, column-type-schema
      dsl-resource.ts                 # NEW: DSL reference
    lib/
      yaml-parser.ts                  # NEW: YAML -> GridSpec
      validator.ts                    # NEW: 6-pass validation
      resolution-engine.ts            # NEW: full resolution pipeline
      config-expander.ts              # NEW: YAML -> GCC JSON (output validated by schemas.ts)
      model-map.ts                    # NEW: shorthand <-> full model IDs
      column-schemas.ts               # NEW: static per-type metadata for grid://schema/{type}
      config-helpers.ts               # NEW: shared helpers (getColumnConfig, resolveColumnRef, mergeConfig)
      resource-cache.ts               # NEW: TTL cache
  hooks/
    validate-config.py                # NEW: PreToolUse hook
    post-api-call.sh                  # NEW: PostToolUse hook
    render-grid.py                    # NEW: ASCII table renderer
    hooks.json                        # NEW: hook registration
  package.json                        # Updated: add yaml dependency
  tsconfig.json                       # Unchanged
```

---

## What to Build Next (Priority Order)

### Tier 1: Foundation (unblocks everything)

These are the critical path. Build in dependency order.

1. **`src/lib/model-map.ts`** (1.1) -- No dependencies, simple, needed by config expander and typed mutations.
2. **`src/lib/config-helpers.ts`** (1.2) -- No dependencies, needed by all typed mutations and resolution engine.
3. **`src/lib/yaml-parser.ts`** (1.5) -- Add `yaml` to package.json. Defines `GridSpec` types.
4. **`src/lib/config-expander.ts`** (1.7) -- Depends on 1.1. The hardest piece: must produce objects passing `ColumnConfigUnionSchema`. Test extensively per column type.
5. **`src/lib/validator.ts`** (1.6) -- Depends on 1.5. Six validation passes.
6. **`src/lib/resolution-engine.ts`** (1.8) -- Depends on 1.5, 1.6, 1.7. Orchestrates the full pipeline.

### Tier 2: High-value tools

7. **`src/tools/apply-grid.ts`** (2.1) -- Highest-value single deliverable. Follow `setup_agent_test` pattern.
8. **`src/tools/typed-mutations.ts`** (2.2-2.8) -- High value for iterative workflows. All share config-helpers.

### Tier 3: Integration (can start in parallel)

9. **`hooks/validate-config.py`** (4.1) -- Independent of MCP server code. Catches config errors before API calls.
10. **`hooks/post-api-call.sh` + `render-grid.py`** (4.2) -- Independent. ASCII grid rendering after mutations.
11. **Skill example rewrite** (4.6, from FOLLOWUPS P2-1) -- Independent. Highest-impact skill change.

### Tier 4: Polish

12. **MCP Resources** (Phase 3) -- Lower urgency. Existing tools provide the same data; resources add caching and URI convention.
13. **DSL skill reference** (4.3) -- Wait until `apply_grid` is stable.
14. **Remaining skill doc updates** (4.7-4.11) -- Can be done incrementally.

---

## Spec Assumptions Now Invalidated

| Spec | Assumption | Reality |
|------|-----------|---------|
| Resolution engine spec | Defines its own `ColumnConfig`, `AIConfig`, etc. types | `src/schemas.ts` already defines these as Zod schemas. The config expander should import and target `ColumnInput` / `ColumnConfigUnionSchema` from `schemas.ts`, not redefine them. |
| MCP tools spec | Says ~40 tools exist | Actually 57 tools (40+ core + 14 metadata + 5 agents + workflow composites). Tool count was underestimated. |
| MCP tools spec | `edit_column` takes raw JSON string | `edit_column` now takes a JSON string but validates it against `ColumnConfigUnionSchema` before sending. The Zod validation layer already catches structural errors. |
| Validation spec | PreToolUse hook catches missing `config.config` structure | `add_column` already validates via `ColumnInputSchema.safeParse()`. The hook is still useful for `edit_column` / `save_column` / `reprocess_column` where users pass the outer config directly, but has less urgency than originally planned. |
| Implementation plan | `column-schemas.ts` is a new static data file | The Zod schemas in `schemas.ts` already encode required fields, types, and constraints per column type. `column-schemas.ts` should derive from / annotate these, not duplicate them. |
| Implementation plan | `src/lib/` directory for new code | Directory does not exist yet. All Phase 1 files create it. |
| Implementation plan | `src/resources/` directory | Does not exist yet. Phase 3 creates it. |
| YAML DSL spec | Uses `grid:` top-level key | Resolution engine spec uses flat top-level. Need to align on one format before building the parser. Recommend: flat top-level (`workbook:`, `worksheet:`, `columns:`) to match the resolution engine spec. |

---

## Migration Strategy

**Additive, not replacing.** All existing tools continue to work.

| Phase | Existing Tools | New Tools |
|-------|---------------|-----------|
| Phases 1-3 | Full functionality, unchanged | Shipped alongside |
| Phase 4 | Descriptions updated: "Low-level. Prefer apply_grid / typed tools for common operations" | Primary recommendation |
| Future | Keep indefinitely for edge cases | Default path |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Config expander complexity | Bugs in YAML -> nested JSON conversion | **Output must pass `ColumnConfigUnionSchema.parse()`** -- Zod catches structural errors. Add unit tests for all 12 column types. Use `setup_agent_test` configs as reference implementations. |
| YAML library choice | Spec compliance | Use `yaml` package (YAML 1.2 spec compliant), not `js-yaml` (YAML 1.1). |
| Model shorthand list goes stale | Invalid model references | Fallback: unrecognized names pass through as full IDs. `grid://models` resource shows real-time list. |
| Incremental apply edge cases | Unexpected column updates | Conservative: only update columns that differ. Never delete implicitly. |
| YAML DSL format divergence | DSL spec uses `grid:` wrapper, resolution engine spec uses flat format | Align before building parser. Recommend flat format. |
| No test framework | Can't verify config expander correctness | Add test framework (vitest recommended) as part of Phase 1.7. |

---

## FOLLOWUPS.md Items Integration

Items from `FOLLOWUPS.md` mapped to this plan:

| FOLLOWUPS Item | Plan Task | Status |
|----------------|-----------|--------|
| P2-1: Rewrite skill examples to MCP syntax | 4.6 | Incorporated |
| P2-2: MCP tool quick-reference table | 4.7 | Incorporated |
| P2-3: Document undocumented tools | 4.8 | Incorporated |
| P2-4: Document trigger_row_execution types | 4.9 | Incorporated |
| P2-5: Tool orchestration guidance | 4.3 (DSL reference covers this) | Incorporated |
| P2-6: Data Cloud / DMO use-case pattern | 4.10 | Incorporated |
| P2-7: List View import pattern | 4.11 | Incorporated |
| P2-8: Clarify edit vs save vs reprocess | Phase 2 typed mutations supersede this | Superseded |
| P3-1: MCP Prompts | Not in scope (future) | Deferred |
| P3-2: MCP Resources | Phase 3 | Incorporated |
| P3-3: Remove redundant `get_agents_including_drafts` | Already consolidated (`get_agents` has `includeDrafts`) | Done |
| P3-4: Replace JSON-string params with Zod schemas | Phase 2 typed mutations avoid JSON strings entirely | Superseded |
| PreToolUse Validation Hook | 4.1 | Incorporated |
| PostToolUse Auto-Render Hook | 4.2 | Incorporated |
| Agent Definitions (cockpit scope) | Phase 5.2 | Planned |
| Slash Commands (cockpit scope) | Phase 5.3 | Planned |
| Plugin Skeleton (plugin.json) | Phase 5.1 | Planned |
| Desktop HTML Artifacts | Phase 5.4 | Planned |
| Template System | `apply_grid` with YAML DSL subsumes this | Superseded |

---

## Phase 5: Plugin & Cockpit Experience

**Goal:** Transform the skill + MCP server into a distributable Claude Code plugin with specialized agents, slash commands, and rich visualization.

**Depends on:** Stable MCP tools (Phase 2) and hooks (Phase 4).

| # | Task | Spec Document | Details |
|---|------|---------------|---------|
| 5.1 | Plugin skeleton | [plugin-evolution-roadmap](2026-03-06-plugin-evolution-roadmap.md) | `.claude-plugin/plugin.json`, restructure into `skills/grid-api/`, wire `.mcp.json` |
| 5.2 | Agent definitions | [agent-definitions-spec](2026-03-06-agent-definitions-spec.md) | 5 agents: grid-builder (Opus/30), grid-inspector (10), grid-evaluator (20), grid-debugger (15), grid-orchestrator (50) |
| 5.3 | Slash commands | [commands-and-hooks-spec](2026-03-06-commands-and-hooks-spec.md) | 10 commands: `/grid-new`, `/grid-status`, `/grid-run`, `/grid-results`, `/grid-add`, `/grid-debug`, `/grid-compare`, `/grid-export`, `/grid-list`, `/grid-models` |
| 5.4 | Desktop HTML artifacts | [plugin-evolution-roadmap](2026-03-06-plugin-evolution-roadmap.md) | Interactive grid table, evaluation dashboard, dependency DAG, heatmap, processing timeline |
| 5.5 | Marketplace packaging | [plugin-evolution-roadmap](2026-03-06-plugin-evolution-roadmap.md) | README, LICENSE, versioning, publish |

---

## Detailed Spec References

| Area | Spec Document |
|------|--------------|
| YAML DSL syntax & examples | [`grid-yaml-dsl-spec.md`](grid-yaml-dsl-spec.md) |
| Resolution engine architecture | [`grid-resolution-engine-spec.md`](grid-resolution-engine-spec.md) |
| MCP tools & resources | [`grid-mcp-tools-spec.md`](grid-mcp-tools-spec.md) |
| Validation & Claude integration | [`grid-validation-integration-spec.md`](grid-validation-integration-spec.md) |
| Gap analysis | [`grid-plan-gap-analysis.md`](grid-plan-gap-analysis.md) |
| Agent definitions | [`2026-03-06-agent-definitions-spec.md`](2026-03-06-agent-definitions-spec.md) |
| Commands & hooks | [`2026-03-06-commands-and-hooks-spec.md`](2026-03-06-commands-and-hooks-spec.md) |
| Plugin evolution | [`2026-03-06-plugin-evolution-roadmap.md`](2026-03-06-plugin-evolution-roadmap.md) |
