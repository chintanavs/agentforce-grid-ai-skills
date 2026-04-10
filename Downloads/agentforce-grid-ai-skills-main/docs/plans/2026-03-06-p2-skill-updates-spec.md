> **Status:** ACTIVE | Phase 4.6-4.11 | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) Phase 4
> **What changed:** All items mapped to hybrid plan Phase 4 tasks. The MCP server is now functional (Phase 0 complete) so these updates can proceed. Item 25 (setup_agent_test) is DONE. Item 13 (MCP syntax rewrite) is the highest-impact task (hybrid plan 4.6).

# P2 — Skill Updates: MCP-Native Documentation

> Priority: **P2** (after MCP server stabilization)
> Status: ~~Planning~~ Active (Phase 0 dependency met)
> Depends on: MCP server at `agentforce-grid-mcp` being functional -- **DONE**

---

## Overview

The skill documentation currently assumes `curl` for all API interactions. With the MCP server (`agentforce-grid-mcp`) providing 43 native tools, the skill must be rewritten to reference MCP tools as the primary interface.

---

## Changes Required

### 13. Rewrite use-case-patterns.md and workflow-patterns.md from curl to MCP tool calls

**Current state:** All 6 patterns in `use-case-patterns.md` use raw `curl` commands with `POST /services/data/v66.0/public/grid/...` URLs.

**Target state:** Each pattern uses MCP tool names as the primary interface, with curl as a fallback reference.

**Example transformation:**

Before:
```bash
POST /services/data/v66.0/public/grid/workbooks
Content-Type: application/json
{"name": "Agent Test Suite"}
```

After:
```
Use MCP tool: create_workbook
  Input: { "name": "Agent Test Suite" }
  Returns: { "id": "1W4xx...", "name": "Agent Test Suite", "aiWorksheetList": [] }
```

**Files to update:**
- `.claude/skills/agentforce-grid/references/use-case-patterns.md` (6 patterns)
- `.claude/skills/agentforce-grid/references/workflow-patterns.md` (all workflows)

---

### 14. Add MCP tool quick-reference table to SKILL.md

Add a section mapping Grid operations to MCP tool names for immediate lookup:

```markdown
## MCP Tool Quick Reference

| Operation | MCP Tool | Key Parameters |
|-----------|----------|----------------|
| List workbooks | `get_workbooks` | — |
| Create workbook | `create_workbook` | name |
| Create worksheet | `create_worksheet` | name, workbookId |
| Get worksheet data | `get_worksheet_data` | worksheetId |
| Add column | `add_column` | worksheetId, name, type, config |
| Paste data | `paste_data` | worksheetId, startColumnId, startRowId, matrix |
| Trigger execution | `trigger_row_execution` | worksheetId, rowIds |
| List agents | `get_agents` | includeDrafts? |
| Get agent variables | `get_agent_variables` | versionId |
| List models | `get_llm_models` | — |
| List evaluation types | `get_evaluation_types` | — |
| Generate SOQL | `generate_soql` | text |
| Create from utterance | `create_column_from_utterance` | worksheetId, utterance |
```

All 43 MCP tools should be listed with descriptions.

---

### 15. Document the 5 undocumented MCP tools

These tools exist in the MCP server but have no skill documentation:

| Tool | Endpoint | Purpose |
|------|----------|---------|
| `get_agents_including_drafts` | `GET /agents/including-drafts` | List agents including draft versions |
| `get_draft_topics` | `POST /agents/draft-topics` | Get topics for a draft agent |
| `get_draft_topics_compiled` | `POST /agents/draft-topics-compiled` | Compile and return draft topics |
| `get_draft_context_variables` | `POST /agents/draft-context-variables` | Get context variables for draft agents |
| `generate_test_columns` | `POST /generate-test-columns` | AI-generated test column configurations |

**Note:** `get_draft_topics` and `get_draft_context_variables` returned 404 in our live API testing. They may require specific org configuration or be version-gated. Document with appropriate caveats.

---

### 16. Document all 4 trigger_row_execution trigger types

The `trigger_row_execution` endpoint supports a `trigger` field with these types:

| Trigger Type | Purpose | When to Use |
|-------------|---------|-------------|
| `RUN_SELECTION` | Process selected rows | User-initiated batch processing |
| `RUN_ROW` | Process specific rows by ID | Targeted reprocessing after fixes |
| `EDIT` | Triggered after cell edits | Auto-processing after data changes |
| `PASTE` | Triggered after paste operations | Auto-processing after bulk data input |

Only `RUN_ROW` is documented today. Add complete documentation with request examples for all 4 types.

---

### 17. Add "Draft Agent Testing" use-case pattern

**Goal:** Test a draft (unpublished) agent version using the Grid.

**Column setup:**
| Order | Column | Type | Purpose |
|-------|--------|------|---------|
| 1 | Test Utterances | Text | Input test cases |
| 2 | Expected Topics | Text | Expected topic routing |
| 3 | Draft Agent Output | AgentTest | Test draft agent (isDraft: true) |
| 4 | Topic Assertion | Evaluation | Verify topic routing |
| 5 | Coherence | Evaluation | Quality assessment |

**Key differences from published agent testing:**
- Use `get_agents_including_drafts` to find draft agent IDs
- Use `get_draft_topics` to list available topics for the draft
- Use `get_draft_context_variables` to discover required context variables
- Set `isDraft: true` in the AgentTest column config
- Set `enableSimulationMode: true` if available

**MCP workflow:**
```
1. get_agents_including_drafts → find draft agent
2. get_draft_topics → list draft topics
3. get_draft_context_variables → discover variables
4. create_workbook + create_worksheet
5. add_column (Text) × 2
6. add_column (AgentTest with isDraft: true)
7. add_column (Evaluation) × 2
8. paste_data → populate test utterances
9. trigger_row_execution → run tests
10. get_worksheet_data → check results
```

---

### 18. Add "Data Cloud / DMO Pipeline" use-case pattern

**Goal:** Query Data Cloud DMOs, enrich with AI, and classify.

**Column setup:**
| Order | Column | Type | Purpose |
|-------|--------|------|---------|
| 1 | Unified Individuals | DataModelObject | Query DMO records |
| 2 | Customer Summary | AI | Generate summaries from DMO data |
| 3 | Segment Classification | AI (SINGLE_SELECT) | Classify into segments |
| 4 | Completeness Score | Evaluation | Assess summary quality |

**MCP workflow:**
```
1. get_dataspaces → list available dataspaces
2. get_data_model_objects → find target DMO
3. get_data_model_object_fields → discover fields
4. create_workbook + create_worksheet
5. add_column (DataModelObject with WHOLE_COLUMN)
6. add_column (AI with EACH_ROW, referencing DMO fields)
7. add_column (AI with SINGLE_SELECT, referencing DMO fields)
8. add_column (Evaluation: COMPLETENESS)
```

---

### 19. Add tool orchestration guidance

**Key rules for MCP tool orchestration:**

#### Dependency Ordering
Columns form a DAG. Creation order MUST respect dependencies:
1. Data source columns first (Text, Object, DataModelObject)
2. Processing columns next (AI, Agent, AgentTest, PromptTemplate, InvocableAction)
3. Derivation columns (Reference, Formula)
4. Evaluation columns last (depend on processing columns)

#### State Refresh
After creating a column, always call `get_worksheet_data` to get the updated column IDs before creating dependent columns. Column IDs are assigned by the server and cannot be predicted.

#### Why Parallel Column Creation is Unsafe
Creating multiple columns in parallel can cause:
- Race conditions on row generation (each column may try to create rows)
- Missing column IDs (needed for `referenceAttributes` in dependent columns)
- Incorrect `precedingColumnId` ordering
- Stale cell references

**Always create columns sequentially**, capturing the ID from each response before creating the next.

#### Recommended Pattern
```
for each column in topological_order(columns):
    response = add_column(worksheetId, column_config)
    column_id_map[column.ref] = response.id
    # Substitute real IDs into next column's referenceAttributes
```

---

## Mapping to Hybrid Plan Phase 4

| Item in this spec | Hybrid Plan Task | Priority |
|-------------------|-----------------|----------|
| #13 Rewrite use-case-patterns and workflow-patterns to MCP | 4.6 | Highest impact |
| #14 MCP tool quick-reference table | 4.7 | High |
| #15 Document 5 undocumented tools | 4.8 | Medium |
| #16 Document trigger_row_execution types | 4.9 | Medium |
| #17 Draft agent testing pattern | (not explicitly in hybrid plan, but aligns with 4.8) | Medium |
| #18 Data Cloud / DMO pattern | 4.10 | Medium |
| #19 Tool orchestration guidance | 4.3 (DSL reference covers this) | Covered by DSL |
| #25 Composite setup_agent_test tool | **DONE** (Phase 0) | Done |

---

## P3 — Future (Plugin Architecture) -- DEFERRED / REMAPPED

> Items below are either DEFERRED or already covered by the hybrid plan.

### 20. MCP Prompts -- DEFERRED
Encode primary workflows as reusable MCP prompts:
- "Create agent test workbook" → guided multi-step workflow
- "Analyze worksheet results" → evaluation summary + recommendations

### 21. MCP Resources -- Remapped to Hybrid Phase 3
- `grid://workbooks` — browsable workbook list
- `grid://worksheets/{id}/status` — processing status summary

### 22. PreToolUse validation hook -- Remapped to Hybrid Phase 4.1
Catch nested config errors before API call:
- Missing `config.config` structure
- Wrong `columnType` casing
- Missing `modelConfig`

### 23. PostToolUse auto-render hook -- Remapped to Hybrid Phase 4.2
Show grid state after every mutation — the "highest-value hook" per all 3 specs.

### 24. Slash commands -- DEFERRED
- `/grid-new` — create grid from natural language
- `/grid-status` — show grid health
- `/grid-run` — execute/reprocess
- `/grid-results` — evaluation summary

### 25. Composite `setup_agent_test` tool -- DONE (Phase 0)
Collapse 15 API calls into 1 tool invocation:
1. Create workbook + worksheet
2. Create Text columns (utterances, expected responses, expected topics)
3. Create AgentTest column
4. Create Evaluation columns (RESPONSE_MATCH, TOPIC_ASSERTION, COHERENCE, LATENCY_ASSERTION)
5. Populate sample data
6. Return worksheet ID + column map
