# Planning Documents Index

> **Last updated:** 2026-03-06
> **Master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md)

---

## Document Status Overview

| Document | Status | Phase | Summary |
|----------|--------|-------|---------|
| [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) | **SOURCE OF TRUTH** | All | Master implementation plan: Phase 0 (complete), Phases 1-4 (planned) |
| [grid-yaml-dsl-spec.md](grid-yaml-dsl-spec.md) | **ACTIVE** | Phase 1 | YAML DSL syntax for all 12 column types, resolution behavior, examples |
| [grid-resolution-engine-spec.md](grid-resolution-engine-spec.md) | **ACTIVE** | Phase 1 | Resolution engine architecture: parse, resolve, sort, expand, create pipeline |
| [grid-mcp-tools-spec.md](grid-mcp-tools-spec.md) | **ACTIVE** | Phase 2-3 | apply_grid tool, 7 typed mutation tools, 6 MCP resources |
| [grid-validation-integration-spec.md](grid-validation-integration-spec.md) | **ACTIVE** | Phase 4.1 | 6-pass validation pipeline, PreToolUse hook, error catalog, Claude integration |
| [grid-plan-gap-analysis.md](grid-plan-gap-analysis.md) | **ACTIVE** | N/A | Gap analysis: built vs planned, schema implications, priorities |
| [2026-03-06-mcp-server-improvements-spec.md](2026-03-06-mcp-server-improvements-spec.md) | **PARTIALLY DONE** | Phase 0 | Original MCP server spec; most items complete, remaining mapped to Phases 1-4 |
| [2026-03-06-plugin-evolution-roadmap.md](2026-03-06-plugin-evolution-roadmap.md) | **ACTIVE** | Phase 5 | Plugin skeleton, agent packaging, desktop artifacts (reinstated) |
| [2026-03-06-template-system-spec.md](2026-03-06-template-system-spec.md) | **SUPERSEDED** | N/A | JSON template system; superseded by YAML DSL + apply_grid |
| [2026-03-06-p2-skill-updates-spec.md](2026-03-06-p2-skill-updates-spec.md) | **ACTIVE** | Phase 4 | Skill documentation updates: MCP syntax rewrite, tool reference, new patterns |
| [2026-03-06-commands-and-hooks-spec.md](2026-03-06-commands-and-hooks-spec.md) | **ACTIVE** | Phase 4-5 | Hooks in Phase 4.1-4.2; slash commands in Phase 5 |
| [2026-03-06-agent-definitions-spec.md](2026-03-06-agent-definitions-spec.md) | **ACTIVE** | Phase 5 | 5 agent definitions (grid-builder, inspector, evaluator, debugger, orchestrator) |
| [2026-03-06-plugin-evolution-roadmap.md](2026-03-06-plugin-evolution-roadmap.md) | **ACTIVE** | Phase 5 | Plugin skeleton, desktop artifacts, marketplace packaging |

---

## Critical Path

Build order follows the hybrid plan's dependency chain:

```
Phase 1: Foundation Libraries (unblocks everything)
  1.1 model-map.ts ---------> no deps
  1.2 config-helpers.ts ----> no deps
  1.5 yaml-parser.ts -------> no deps (add yaml to package.json)
  1.7 config-expander.ts ---> depends on 1.1
  1.6 validator.ts ----------> depends on 1.5
  1.8 resolution-engine.ts -> depends on 1.5, 1.6, 1.7
      |
      v
Phase 2: MCP Tools (highest-value deliverables)
  2.1 apply-grid.ts --------> depends on Phase 1 (follow setup_agent_test pattern)
  2.2-2.8 typed-mutations.ts -> depends on 1.1, 1.2
      |
      v
Phase 3: MCP Resources (lower urgency, existing tools provide same data)
  3.1-3.6 resources/ -------> depends on 1.3 (cache), 1.4 (column-schemas)
      |
      v
Phase 4: Claude Code Integration (hooks can start in parallel)
  4.1 PreToolUse hook ------> independent (can start during Phase 1)
  4.2 PostToolUse hook -----> independent (can start during Phase 1)
  4.3-4.4 Skill updates ----> depends on Phase 2 (apply_grid must be stable)
  4.6-4.11 Doc updates -----> depends on Phase 2
      |
      v
Phase 5: Plugin & Cockpit Experience (depends on Phases 2-4)
  5.1 Plugin skeleton -------> plugin.json, restructure into plugin layout
  5.2 Agent definitions -----> 5 agents (builder, inspector, evaluator, debugger, orchestrator)
  5.3 Slash commands --------> 10 /grid-* commands
  5.4 Desktop artifacts -----> HTML visualizations (grid table, eval dashboard, heatmap, DAG)
  5.5 Marketplace packaging -> README, LICENSE, versioning
```

---

## Phase-to-Document Mapping

### Phase 0: MCP Server Foundation -- COMPLETE

Everything in this phase is built and merged into `grid-connect-mcp`.

| Deliverable | Spec Document | Status |
|-------------|---------------|--------|
| 57 MCP tools across 8 modules | [mcp-server-improvements-spec](2026-03-06-mcp-server-improvements-spec.md) | DONE |
| Zod schemas for all 12 column types | [mcp-server-improvements-spec](2026-03-06-mcp-server-improvements-spec.md) | DONE |
| Hardened HTTP client (retry, 401, 429, 5xx) | [mcp-server-improvements-spec](2026-03-06-mcp-server-improvements-spec.md) | DONE |
| setup_agent_test composite workflow | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) | DONE |
| poll_worksheet_status, get_worksheet_summary | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) | DONE |
| Zod-validated column tools | [mcp-server-improvements-spec](2026-03-06-mcp-server-improvements-spec.md) | DONE |

### Phase 1: Foundation Libraries -- NOT STARTED

| Deliverable | Spec Document | File |
|-------------|---------------|------|
| Model shorthand map | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) B.1 | `src/lib/model-map.ts` |
| Config helpers | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) B (internal helper) | `src/lib/config-helpers.ts` |
| YAML parser + GridSpec | [grid-yaml-dsl-spec](grid-yaml-dsl-spec.md) | `src/lib/yaml-parser.ts` |
| Config expander | [grid-resolution-engine-spec](grid-resolution-engine-spec.md) Section 5 | `src/lib/config-expander.ts` |
| Validation engine | [grid-validation-integration-spec](grid-validation-integration-spec.md) Section 1.1 | `src/lib/validator.ts` |
| Resolution engine | [grid-resolution-engine-spec](grid-resolution-engine-spec.md) | `src/lib/resolution-engine.ts` |
| Resource cache | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) C (caching) | `src/lib/resource-cache.ts` |
| Column schemas (static) | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) C.5 | `src/lib/column-schemas.ts` |

### Phase 2: MCP Tools -- NOT STARTED

| Deliverable | Spec Document | File |
|-------------|---------------|------|
| apply_grid | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) A | `src/tools/apply-grid.ts` |
| 7 typed mutation tools | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) B.1-B.7 | `src/tools/typed-mutations.ts` |

### Phase 3: MCP Resources -- NOT STARTED

| Deliverable | Spec Document | File |
|-------------|---------------|------|
| 6 MCP resources | [grid-mcp-tools-spec](grid-mcp-tools-spec.md) C.1-C.6 | `src/resources/*.ts` |

### Phase 4: Claude Code Integration -- NOT STARTED

| Deliverable | Spec Document | File |
|-------------|---------------|------|
| PreToolUse validation hook | [grid-validation-integration-spec](grid-validation-integration-spec.md) 1.3, [commands-and-hooks-spec](2026-03-06-commands-and-hooks-spec.md) | `hooks/validate-config.py` |
| PostToolUse ASCII hook | [grid-validation-integration-spec](grid-validation-integration-spec.md) 3.3, [commands-and-hooks-spec](2026-03-06-commands-and-hooks-spec.md) | `hooks/post-api-call.sh` |
| DSL skill reference | [grid-validation-integration-spec](grid-validation-integration-spec.md) 3.1 | `skills/references/dsl-reference.md` |
| Skill example rewrite | [p2-skill-updates-spec](2026-03-06-p2-skill-updates-spec.md) | Various skill files |
| MCP tool quick-reference | [p2-skill-updates-spec](2026-03-06-p2-skill-updates-spec.md) | `skills/SKILL.md` |
| Undocumented tool docs | [p2-skill-updates-spec](2026-03-06-p2-skill-updates-spec.md) | Skill reference files |
| hooks.json registration | [commands-and-hooks-spec](2026-03-06-commands-and-hooks-spec.md) | `hooks/hooks.json` |

### Phase 5: Plugin & Cockpit Experience -- NOT STARTED

Depends on stable MCP tools (Phase 2) and hooks (Phase 4). This phase transforms the skill + MCP server into a distributable plugin with specialized agents and rich visualization.

| Deliverable | Spec Document | Details |
|-------------|---------------|---------|
| Plugin skeleton (`plugin.json`, directory restructure) | [plugin-evolution-roadmap](2026-03-06-plugin-evolution-roadmap.md) | `.claude-plugin/plugin.json`, move skill to `skills/grid-api/`, wire `.mcp.json` |
| 5 Agent definitions | [agent-definitions-spec](2026-03-06-agent-definitions-spec.md) | grid-builder (Opus, 30 turns), grid-inspector (10), grid-evaluator (20), grid-debugger (15), grid-orchestrator (50) |
| 10 Slash commands | [commands-and-hooks-spec](2026-03-06-commands-and-hooks-spec.md) | `/grid-new`, `/grid-status`, `/grid-run`, `/grid-results`, `/grid-add`, `/grid-debug`, `/grid-compare`, `/grid-export`, `/grid-list`, `/grid-models` |
| Desktop HTML artifacts | [plugin-evolution-roadmap](2026-03-06-plugin-evolution-roadmap.md) | Interactive grid table, evaluation dashboard, dependency DAG, heatmap, processing timeline |
| Marketplace packaging | [plugin-evolution-roadmap](2026-03-06-plugin-evolution-roadmap.md) | README, LICENSE, versioning, publish to salesforce-native-ai-stack |

### SUPERSEDED / DEFERRED

| Item | Spec Document | Reason |
|------|---------------|--------|
| JSON template system | [template-system-spec](2026-03-06-template-system-spec.md) | Superseded by YAML DSL + apply_grid |
| MCP Prompts | [p2-skill-updates-spec](2026-03-06-p2-skill-updates-spec.md) #20 | Future scope (post-Phase 5) |

---

## Key Architectural Decisions

These decisions are documented in the master plan and apply across all specs:

1. **Zod schemas in `src/schemas.ts` ARE the contract** -- no parallel type definitions. The config expander, typed mutations, and resolution engine all target `ColumnConfigUnionSchema`.

2. **`setup_agent_test` is the pattern for `apply_grid`** -- sequential creation with ID threading, config objects built inline, dynamic reference wiring.

3. **YAML DSL uses flat top-level format** -- `workbook:`, `worksheet:`, `columns:` at top level (not wrapped in `grid:`). Aligns with resolution engine spec.

4. **Additive migration** -- all existing tools continue to work. New tools are added alongside, not replacing.

5. **Model shorthands fall back to passthrough** -- unrecognized model names are passed through as full IDs.
