> **Status:** ACTIVE | Reference document | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) -- Cross-cutting analysis
> **What changed:** Updated executive summary to reflect Phase 0 completion. FOLLOWUPS items now mapped to hybrid plan tasks (see hybrid plan "FOLLOWUPS.md Items Integration" table). The "Recommended Priorities" section aligns with the hybrid plan's "What to Build Next" section.

# Grid Hybrid Tooling — Gap Analysis: Built vs Planned

**Date:** 2026-03-06
**Scope:** Compare `grid-connect-mcp` codebase against `grid-hybrid-tooling-implementation-plan.md` and related specs

---

## Executive Summary

The current `grid-connect-mcp` server is a solid **Phase 0** foundation: a fully functional CRUD MCP server with 40+ tools, Zod validation on column configs, a hardened HTTP client, and composite workflow tools (`setup_agent_test`, `poll_worksheet_status`). However, **none of the four planned phases have been started**. The plan describes a significant evolution from CRUD wrappers to a declarative YAML-driven grid engine with typed mutations and MCP resources.

---

## What's Built (Current State)

### Core Infrastructure
| Component | File | Status |
|-----------|------|--------|
| HTTP Client with retry/401/429/5xx handling | `src/client.ts` | Complete |
| Zod schemas for all 12 column types | `src/schemas.ts` | Complete |
| MCP server entry point | `src/index.ts` | Complete |
| TypeScript types | `src/types.ts` | Minimal (just `RegisterToolsFn`) |

### Tool Categories (40+ tools registered)
| Category | File | Tools | Status |
|----------|------|-------|--------|
| Workbooks | `src/tools/workbooks.ts` | get_workbooks, create_workbook, get_workbook, delete_workbook | Complete |
| Worksheets | `src/tools/worksheets.ts` | create_worksheet, get_worksheet, get_worksheet_data, get_worksheet_data_generic, update_worksheet, delete_worksheet, get_supported_columns, add_rows, delete_rows, import_csv | Complete |
| Columns | `src/tools/columns.ts` | add_column (Zod-validated), edit_column (Zod-validated), delete_column, save_column (Zod-validated), reprocess_column (Zod-validated), get_column_data, create_column_from_utterance, generate_json_path | Complete |
| Cells | `src/tools/cells.ts` | update_cells, paste_data, trigger_row_execution, validate_formula, generate_ia_input | Complete |
| Agents | `src/tools/agents.ts` | get_agents (with includeDrafts), get_agent_variables, get_draft_topics, get_draft_topics_compiled, get_draft_context_variables | Complete |
| Metadata | `src/tools/metadata.ts` | get_column_types, get_llm_models, get_supported_types, get_evaluation_types, get_formula_functions, get_formula_operators, get_invocable_actions, describe_invocable_action, get_prompt_templates, get_prompt_template, get_list_views, get_list_view_soql, generate_soql, generate_test_columns | Complete |
| Data | `src/tools/data.ts` | get_sobjects, get_sobject_fields_display, get_sobject_fields_filter, get_sobject_fields_record_update, get_dataspaces, get_data_model_objects, get_data_model_object_fields | Complete |
| Workflows | `src/tools/workflows.ts` | create_workbook_with_worksheet, poll_worksheet_status, get_worksheet_summary, setup_agent_test | Complete |

### Key Strengths Already Built
1. **Zod validation on column tools** -- `add_column`, `edit_column`, `save_column`, `reprocess_column` all validate against `ColumnConfigUnionSchema` (discriminated union of all 12 types)
2. **Composite workflow tools** -- `setup_agent_test` replaces 10-15 manual steps; `poll_worksheet_status` handles async processing
3. **Hardened client** -- retry on network errors, 401 token refresh, 429 rate-limit respect, 5xx exponential backoff, configurable timeout

---

## What's Planned but Not Built

### Phase 1: Foundation (Core Libraries) -- NOT STARTED

| Task | Planned File | Gap |
|------|-------------|-----|
| 1.1 Model shorthand map | `src/lib/model-map.ts` | Not built. No `src/lib/` directory exists. Model shorthands (e.g., `gpt-4-omni` -> `sfdc_ai__DefaultGPT4Omni`) not implemented. |
| 1.2 Config helpers (fetch, resolve, merge) | `src/lib/config-helpers.ts` | Not built. `getColumnConfig()`, `resolveColumnRef()`, `mergeConfig()` don't exist. |
| 1.3 Resource cache | `src/lib/resource-cache.ts` | Not built. No TTL caching layer. |
| 1.4 Column schemas (static data) | `src/lib/column-schemas.ts` | Partially exists in `src/schemas.ts` as Zod schemas, but the plan calls for static per-type schema data for the `grid://schema/{type}` resource, which is different. |
| 1.5 YAML parser + GridSpec types | `src/lib/yaml-parser.ts` | Not built. No YAML dependency in package.json. No `GridSpec` types. |
| 1.6 Validation engine (6 passes) | `src/lib/validator.ts` | Not built. The validation spec defines 6 passes (YAML parse, type-specific fields, reference integrity, cycle detection, type compatibility, value validation). |
| 1.7 Config expander (YAML -> GCC JSON) | `src/lib/config-expander.ts` | Not built. This is the core of translating flat YAML keys to triple-nested `config.config` structures. |
| 1.8 Resolution engine (full pipeline) | `src/lib/resolution-engine.ts` | Not built. Name-to-ID resolution, dependency graph, topological sort, config expansion pipeline. |

### Phase 2: MCP Tools -- NOT STARTED

| Task | Planned Tool | Gap |
|------|-------------|-----|
| 2.1 `apply_grid` | Composite YAML-to-grid tool | Not built. This is the flagship feature -- one tool call creates an entire grid from YAML. |
| 2.2 `edit_ai_prompt` | Typed mutation | Not built. Currently requires raw JSON via `edit_column`. |
| 2.3 `edit_agent_config` | Typed mutation | Not built. |
| 2.4 `add_evaluation` | Typed mutation | Not built. Only available via generic `add_column` with full JSON config. |
| 2.5 `change_model` | Typed mutation | Not built. |
| 2.6 `update_filters` | Typed mutation | Not built. |
| 2.7 `reprocess` | Typed mutation | Partially exists as `reprocess_column`, but the plan's version would use config helpers (fetch-merge-save pattern). |
| 2.8 `edit_prompt_template` | Typed mutation | Not built. |

### Phase 3: MCP Resources -- NOT STARTED

| Resource URI | Gap |
|-------------|-----|
| `grid://worksheets/{id}/schema` | Not built. No `src/resources/` directory. |
| `grid://worksheets/{id}/status` | Not built. `get_worksheet_summary` tool provides similar data, but as a tool not a resource. |
| `grid://agents` | Not built. `get_agents` tool exists but not as a cacheable resource. |
| `grid://models` | Not built. `get_llm_models` tool exists but not as a resource. |
| `grid://schema/{columnType}` | Not built. |
| `grid://schema/dsl` | Not built. |

### Phase 4: Claude Code Integration -- NOT STARTED

| Task | Gap |
|------|-----|
| 4.1 PreToolUse validation hook | Not built. No `hooks/` directory. |
| 4.2 PostToolUse ASCII rendering hook | Not built. |
| 4.3 Compact DSL skill reference | Not built. |
| 4.4 Update SKILL.md to reference DSL | Not built. |
| 4.5 hooks.json registration | Not built. |
| 4.6 End-to-end testing | Not built. No test files exist. |

---

## Partial Overlaps / Existing Foundations

These built components partially address planned features or can be leveraged:

| Built | Planned | Overlap |
|-------|---------|---------|
| `src/schemas.ts` (Zod schemas for 12 column types) | `src/lib/column-schemas.ts` (static per-type schema data) | Zod schemas validate configs but don't provide the static metadata needed for `grid://schema/{type}` resources. The Zod schemas are a strong base to derive from. |
| `setup_agent_test` in `workflows.ts` | `apply_grid` composite tool | `setup_agent_test` demonstrates the composite pattern (workbook + worksheet + columns + data in one call) but is hardcoded to agent testing. `apply_grid` generalizes this to any grid shape. |
| `poll_worksheet_status` / `get_worksheet_summary` | `grid://worksheets/{id}/status` resource | The tool implementations contain the status-counting logic that would back the resource. |
| `get_agents`, `get_llm_models` tools | `grid://agents`, `grid://models` resources | The tools make the same API calls; resources just add caching and URI-based access. |
| `ColumnConfigUnionSchema` (discriminated union) | Validation engine Pass 2 (type-specific required fields) | The Zod schemas already enforce required fields per type. The validation engine adds reference integrity, cycle detection, and cross-column validation on top. |

---

## Missing Dependencies

| Item | Notes |
|------|-------|
| `yaml` npm package | Not in `package.json`. Required for Phase 1 YAML parser. |
| `zod` npm package | Listed as dependency of `@modelcontextprotocol/sdk` but not direct. Used in `schemas.ts` and tool registrations. Should be a direct dependency. |
| Test framework | No test framework configured. Plan mentions "extensive unit tests per column type" for the resolution engine. |
| `src/lib/` directory | Does not exist. All Phase 1 files go here. |
| `src/resources/` directory | Does not exist. All Phase 3 files go here. |
| `hooks/` directory | Does not exist. Phase 4 hooks go here. |

---

## FOLLOWUPS.md Items vs Plan

The `FOLLOWUPS.md` file documents improvements identified during the initial build. All items are now mapped to the hybrid plan:

| FOLLOWUPS Item | Hybrid Plan Task | Status |
|----------------|-----------------|--------|
| P2-1: Rewrite workflow examples to MCP tool calls | **4.6** | Incorporated (highest-impact skill change) |
| P2-2: MCP tool quick-reference table in SKILL.md | **4.7** | Incorporated |
| P2-3: Document 5 undocumented tools | **4.8** | Incorporated |
| P2-4: Document trigger_row_execution types | **4.9** | Incorporated |
| P2-5: Tool orchestration guidance | **4.3** (DSL reference covers this) | Incorporated |
| P2-6: Data Cloud / DMO use-case pattern | **4.10** | Incorporated |
| P2-7: List View import pattern | **4.11** | Incorporated |
| P2-8: Clarify edit vs save vs reprocess | Phase 2 typed mutations supersede this | Superseded |
| P3-1: MCP Prompts | Not in scope (future) | Deferred |
| P3-2: MCP Resources | **Phase 3** | Incorporated |
| P3-3: Remove redundant get_agents_including_drafts | Already consolidated (`get_agents` has `includeDrafts`) | **Done** |
| P3-4: Replace JSON-string params with Zod object schemas | Phase 2 typed mutations avoid JSON strings entirely | Superseded |
| PreToolUse Validation Hook | **4.1** | Incorporated |
| PostToolUse Auto-Render Hook | **4.2** | Incorporated |
| Agent Definitions | Not in scope (cockpit architecture) | Deferred |
| Slash Commands | Not in scope (cockpit architecture) | Deferred |
| Template System | `apply_grid` with YAML DSL subsumes this | Superseded |

---

## New Capabilities Not Anticipated by the Plan

The current codebase includes several features the implementation plan didn't account for:

| Capability | File | Impact on Plan |
|-----------|------|----------------|
| `setup_agent_test` composite tool | `src/tools/workflows.ts:93-269` | Creates workbook + worksheet + Text column + AgentTest column + Evaluation columns + pastes utterances in one call. The plan's `apply_grid` should generalize this pattern rather than reimplementing it. Consider extracting shared orchestration logic into `src/lib/config-helpers.ts`. |
| `poll_worksheet_status` with structured summary | `src/tools/workflows.ts:27-43` | Polls until all cells reach terminal status, returns per-column status counts and completion percentage. Not mentioned in the plan. Should be preserved as-is and potentially called by `apply_grid` as a post-create step. |
| `get_worksheet_summary` | `src/tools/workflows.ts:45-91` | Returns structured column metadata with cell status counts. Direct foundation for the `grid://worksheets/{id}/status` resource (Phase 3.2). |
| `create_workbook_with_worksheet` | `src/tools/workflows.ts:7-24` | Atomic workbook+worksheet creation. `apply_grid` should delegate to this or use the same pattern. |
| `create_column_from_utterance` | `src/tools/columns.ts:171-187` | AI-driven column creation from natural language. Not in the plan. Orthogonal to `apply_grid` (declarative vs natural language). |
| `generate_json_path` | `src/tools/columns.ts:189-211` | AI-assisted JSON path generation. Not in the plan. |
| `generate_ia_input` | `src/tools/cells.ts:108-131` | Generates invocable action input payloads. Not in the plan. |
| `validate_formula` | `src/tools/cells.ts:84-106` | Pre-flight formula validation. Could be integrated into the validation engine (Phase 1.6) for Formula columns. |
| `generate_soql` | `src/tools/metadata.ts:253-272` | Natural language to SOQL. Could be integrated into `apply_grid` for Object columns that specify queries in natural language. |
| `generate_test_columns` | `src/tools/metadata.ts:274-306` | Testing Center column generation. Not in the plan. |
| Zod validation on `edit_column`, `save_column`, `reprocess_column` | `src/tools/columns.ts:49-152` | The plan assumes these tools take raw unvalidated JSON. They now validate against `ColumnConfigUnionSchema`. This partially addresses the PreToolUse hook (Phase 4.1) for these specific tools. |

---

## How Zod Schemas Change the Config Expander Design

The existence of `src/schemas.ts` with comprehensive Zod schemas for all 12 column types has significant implications for Phase 1.7 (config expander):

### schemas.ts IS the config contract

The plan's Task 1.4 (`column-schemas.ts`) envisioned creating static per-type schema data from scratch. Instead, `schemas.ts` already defines the authoritative TypeScript types via Zod:

- `ColumnConfigUnionSchema` -- discriminated union of all 12 outer configs
- Per-type inner config schemas (e.g., `AIColumnInnerConfigSchema`, `AgentTestColumnInnerConfigSchema`)
- Shared schemas (`ModelConfigSchema`, `ReferenceAttributeSchema`, `ContextVariableSchema`, etc.)
- The `ColumnInputSchema` wrapping name + type + config

**Design implication:** The config expander (`src/lib/config-expander.ts`) should produce objects that conform to the existing Zod types, then validate the output with `ColumnInputSchema.parse()` before sending to the API. This gives free validation of the expansion output.

### What the config expander must do differently

The expander's job is: flat YAML keys -> triple-nested GCC JSON. With `schemas.ts` in place:

1. **Output type is already defined.** The expander's return type should be `z.infer<typeof ColumnConfigUnionSchema>`. No need to define new output types.

2. **Validation is free.** After expansion, call `ColumnConfigUnionSchema.safeParse(expanded)` to catch expansion bugs. This replaces the need for separate expansion-output validation.

3. **Inner config shapes are documented.** Each `*InnerConfigSchema` (e.g., `AIColumnInnerConfigSchema` at `schemas.ts:154-163`) defines exactly which fields the inner `config.config` object needs. The expander maps flat YAML keys to these fields.

4. **Shared schemas reduce expander complexity.** `ReferenceAttributeSchema`, `FilterConditionSchema`, `FieldConfigSchema`, etc. are already defined. The expander just needs to construct objects matching these shapes.

### Specific mapping: YAML flat keys -> Zod schema fields

| YAML flat key | Zod schema target | Transformation |
|--------------|-------------------|----------------|
| `model: gpt-4-omni` | `AIColumnInnerConfigSchema.modelConfig` | Resolve shorthand via model-map, wrap in `{modelId, modelName}` |
| `instruction: "Summarize: {Source}"` | `AIColumnInnerConfigSchema.instruction` + `.referenceAttributes` | Parse `{Name}` references, rewrite to `{$N}`, build `referenceAttributes` array |
| `response_format: single_select` | `AIColumnInnerConfigSchema.responseFormat` | Map to `{type: "SINGLE_SELECT", options: [...]}` |
| `agent: "Sales Coach"` | `AgentColumnInnerConfigSchema.agentId` | Resolve agent name to ID via API |
| `utterance: "Help with {Input}"` | `AgentColumnInnerConfigSchema.utterance` + `.utteranceReferences` | Parse references, rewrite, build `utteranceReferences` |
| `object: Account` | `ObjectColumnInnerConfigSchema.objectApiName` | Direct mapping |
| `fields: [Id, Name]` | `ObjectColumnInnerConfigSchema.fields` | Wrap each in `{name: field}` per `FieldConfigSchema` |
| `filters: [...]` | `ObjectColumnInnerConfigSchema.filters` | Map to `FilterConditionSchema` objects |
| `eval_type: COHERENCE` | `EvaluationColumnInnerConfigSchema.evaluationType` | Direct mapping |
| `input: "Agent Output"` | `EvaluationColumnInnerConfigSchema.inputColumnReference` | Resolve name to `ReferenceAttributeSchema` |

### Updated Phase 1 task list given schemas.ts

| Task | Original Scope | Revised Scope |
|------|---------------|---------------|
| 1.1 Model map | Build from scratch | Build from scratch (unchanged -- `schemas.ts` doesn't cover model shorthands) |
| 1.2 Config helpers | Build `getColumnConfig()`, `resolveColumnRef()`, `mergeConfig()` | Build from scratch, but `mergeConfig()` output validates against existing Zod schemas |
| 1.3 Resource cache | Build TTL cache | Build from scratch (unchanged) |
| 1.4 Column schemas (static data) | Build static per-type metadata | **Reduced scope.** Derive from `schemas.ts` Zod schemas using `zodToJsonSchema()` or manual extraction. Don't duplicate the type definitions. |
| 1.5 YAML parser + GridSpec types | Build parser and types | Build from scratch (unchanged -- YAML layer is new) |
| 1.6 Validation engine | Build 6-pass pipeline | **Reduced scope for Pass 2.** Type-specific required field checks are already handled by Zod schemas. The validation engine should focus on Passes 3-6 (reference integrity, cycles, type compatibility, value ranges) which Zod cannot express. |
| 1.7 Config expander | Build YAML -> GCC JSON | Build from scratch, but **target types are defined** by `schemas.ts`. Output must satisfy `ColumnConfigUnionSchema`. Use `safeParse()` as an assertion at the end of expansion. |
| 1.8 Resolution engine | Build full pipeline | Build from scratch (unchanged -- orchestration layer is new) |

---

## Recommended Priorities

Based on impact and dependency ordering:

1. **Phase 1 (Foundation)** is the critical path -- everything depends on it. Start with 1.1 (model map), 1.5 (YAML parser), and 1.7 (config expander) as they're the most self-contained.

2. **Phase 2.1 (`apply_grid`)** is the highest-value single deliverable. Once the foundation is ready, this turns 10-15 tool calls into one.

3. **Phase 2.2-2.8 (Typed mutations)** are high value for iterative workflows (modifying existing grids). Depends on 1.2 (config helpers).

4. **Phase 3 (MCP Resources)** is lower urgency. The existing tools provide the same data; resources add caching and convention but are not blocking.

5. **Phase 4 (Integration)** can start in parallel for hooks (4.1, 4.2) since they're independent of the MCP server code. Skill updates (4.3, 4.4) should wait until Phases 1-2 stabilize.

6. **FOLLOWUPS P2-1** (rewrite skill examples to MCP syntax) remains the highest-impact skill improvement and is independent of all plan phases.
