# Agentforce Grid Cockpit: Data Visualization & Grid Rendering Spec

> Design philosophy: Boris Cherny's type-safe composability meets Ivan Zhao's block-based information architecture. Every view is a composable block. Every block has a clear type contract. The user never wonders "what is happening in my grid."

---

## Table of Contents

1. [Core Data Model for Rendering](#1-core-data-model-for-rendering)
2. [CLI Grid Visualization (Claude Code)](#2-cli-grid-visualization-claude-code)
3. [Desktop Artifact Visualization (Claude Desktop)](#3-desktop-artifact-visualization-claude-desktop)
4. [State Awareness & Communication](#4-state-awareness--communication)
5. [Polling & Async Strategies](#5-polling--async-strategies)

---

## 1. Core Data Model for Rendering

Before any visualization, the skill must transform raw API responses into a normalized render model. This is the contract between data fetching and display.

### 1.1 Canonical Grid State

The skill should internally build this structure from `GET /worksheets/{id}/data`:

```
GridState {
  worksheet: { id, name, workbookId }
  columns: Column[]        -- ordered by precedingColumnId chain
  rows: string[]           -- ordered row IDs
  cells: Map<columnId, Map<rowId, Cell>>
  summary: GridSummary      -- computed
}

Column {
  id, name, type, status
  config: ColumnConfig
  position: number          -- resolved from precedingColumnId
  dependsOn: string[]       -- column IDs this column references
}

Cell {
  id, displayContent, fullContent, status, statusMessage
  evaluationResult?: { passed: boolean, score?: number, reason?: string }
}

GridSummary {
  totalRows, totalColumns
  statusCounts: Map<Status, number>
  evalPassRate?: number
  evalScoreDistribution?: { p25, p50, p75, p90, p99 }
  latencyDistribution?: { p50, p90, p99 }    -- from LATENCY_ASSERTION cells
  errorsByColumn: Map<columnId, number>
  staleCells: number
}
```

### 1.2 Column Dependency Resolution

Columns reference other columns via `referenceAttributes`, `inputColumnReference`, `referenceColumnReference`, and `conversationHistory`. The skill should resolve these into a dependency DAG:

```
Text("Utterances") --> AgentTest("Output") --> Evaluation("Match")
                   \                        \-> Evaluation("Coherence")
                    --> Text("Expected")  --/
```

This DAG drives: rendering order, staleness propagation, and dependency graph views.

---

## 2. CLI Grid Visualization (Claude Code)

### 2.1 Design Principles for Terminal Rendering

- **Scan, don't read**: A user should understand grid health in under 2 seconds
- **Progressive disclosure**: Summary first, then table, then cell detail on request
- **Respect terminal width**: Auto-truncate, never wrap into unreadable noise
- **Unicode box-drawing**: Use `│ ─ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼` for clean tables

### 2.2 The Three-Layer Cockpit View

Claude should present grid state in three progressive layers:

#### Layer 1: Grid Summary Banner

Always show this first when asked about a worksheet. One glance = full situational awareness.

```
┌─────────────────────────────────────────────────────────────────┐
│  WORKSHEET: Sales Agent Tests                                   │
│  Workbook:  Agent Test Suite           ID: 1W1xx0000004Abc      │
├─────────────────────────────────────────────────────────────────┤
│  Columns: 7    Rows: 50    Cells: 350                           │
│                                                                 │
│  Status:  Complete 298  InProgress 12  Failed 8  Stale 32       │
│           =========================================             │
│           [########################################----xxxx~~~] │
│                                                                 │
│  Evals:   42/50 passed (84.0%)    Avg Score: 3.7/5             │
│  Latency: P50=1.2s  P90=3.4s  P99=8.1s                        │
│  Errors:  8 failures in "Agent Output" (col 4)                  │
└─────────────────────────────────────────────────────────────────┘
```

The status bar is a mini inline chart:
- `#` = Complete
- `-` = InProgress
- `x` = Failed
- `~` = Stale
- `.` = New/Empty

#### Layer 2: Column Header Strip

Shows the column pipeline structure with type badges and per-column health.

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

Column type badges:
```
[TXT]       Text
[AI]        AI
[AGT]       Agent
[AGT-TEST]  AgentTest
[OBJ]       Object
[EVAL]      Evaluation
[REF]       Reference
[FORMULA]   Formula
[PROMPT]    PromptTemplate
[ACTION]    Action
[IA]        InvocableAction
[DMO]       DataModelObject
```

#### Layer 3: Data Grid Table

The full cell-level view. This is where truncation strategy matters most.

```
┌────┬──────────────────┬──────────────────┬──────────────────┬──────────────┬───────┬───────┬───────┐
│ ## │ Test Utterances   │ Expected Resp... │ Expected Topics  │ Agent Output │ Match │ Topic │ Qual. │
│    │ [TXT]             │ [TXT]            │ [TXT]            │ [AGT-TEST]   │[EVAL] │[EVAL] │[EVAL] │
├────┼──────────────────┼──────────────────┼──────────────────┼──────────────┼───────┼───────┼───────┤
│  1 │ Help me reset    │ I can help yo... │ Password_Reset   │ Sure, I'll...│ PASS  │ PASS  │ 4/5   │
│    │ my password      │                  │                  │   [OK]       │  [OK] │  [OK] │  [OK] │
├────┼──────────────────┼──────────────────┼──────────────────┼──────────────┼───────┼───────┼───────┤
│  2 │ What's my        │ Your account ... │ Account_Inquiry  │ Let me look..│ PASS  │ PASS  │ 3/5   │
│    │ account balance  │                  │                  │   [OK]       │  [OK] │  [OK] │  [OK] │
├────┼──────────────────┼──────────────────┼──────────────────┼──────────────┼───────┼───────┼───────┤
│  3 │ Transfer $500    │ I've initiated.. │ Money_Transfer   │              │       │       │       │
│    │ to savings       │                  │                  │   [..]       │  [..]│  [..] │  [..] │
├────┼──────────────────┼──────────────────┼──────────────────┼──────────────┼───────┼───────┼───────┤
│  4 │ Cancel my sub    │ Your subscript.. │ Cancellation     │ ERROR: Time..│       │       │       │
│    │                  │                  │                  │   [XX]       │  [~~] │  [~~] │  [~~] │
└────┴──────────────────┴──────────────────┴──────────────────┴──────────────┴───────┴───────┴───────┘

Legend: [OK] Complete  [..] InProgress  [XX] Failed  [~~] Stale  [  ] New/Empty
```

### 2.3 Truncation Strategy

Terminal width is finite. The algorithm:

1. **Reserve** 6 chars for row number column (`│ ## │`)
2. **Reserve** 7 chars per evaluation column (enough for `PASS` / `FAIL` / `4/5`)
3. **Distribute remaining width** proportionally among non-eval columns, with a minimum of 12 chars each
4. **Truncate** cell content with `...` when it exceeds column width
5. **If terminal < 80 chars**, switch to vertical card view (see 2.6)

Column name truncation: prefer abbreviation over ellipsis. "Expected Responses" -> "Exp. Resp." if space is tight.

### 2.4 Status Indicators

Cell status rendered consistently everywhere:

```
Complete    [OK]    (green if terminal supports color)
InProgress  [..]    (yellow/blue)
Failed      [XX]    (red)
Stale       [~~]    (dim/gray)
New         [  ]    (no color)
Empty       [  ]    (no color)
Skipped     [--]    (dim)
```

For evaluation cells, replace the generic status with the result:

```
Pass:   PASS   or score (e.g., 4/5, 92%)    (green)
Fail:   FAIL   or score (e.g., 1/5, 23%)    (red)
Mixed:  score shown in yellow if between thresholds
```

### 2.5 Evaluation Summary Table

When a worksheet has evaluation columns, always offer a summary:

```
EVALUATION SUMMARY (50 test cases)
┌────────────────────┬────────┬────────┬────────┬─────────┬──────────────────────┐
│ Evaluation         │ Type   │ Passed │ Failed │ Rate    │ Distribution         │
├────────────────────┼────────┼────────┼────────┼─────────┼──────────────────────┤
│ Response Match     │ RESP.  │   42   │    8   │  84.0%  │ ############--       │
│ Topic Check        │ TOPIC  │   48   │    2   │  96.0%  │ ###############-     │
│ Quality Score      │ COHER. │   --   │   --   │  avg 3.7│ ..###########....    │
│ Latency            │ LAT.   │   45   │    5   │  90.0%  │ ##############--     │
├────────────────────┼────────┼────────┼────────┼─────────┼──────────────────────┤
│ OVERALL            │        │        │        │  84.0%  │                      │
└────────────────────┴────────┴────────┴────────┴─────────┴──────────────────────┘

Latency: P50=1.2s  P90=3.4s  P99=8.1s  Max=12.3s
Failures concentrated in rows: 4, 12, 18, 23, 31, 37, 44, 49
```

The "Distribution" column is a sparkline-style inline histogram using block characters.

### 2.6 Vertical Card View (Narrow Terminals or Detail Mode)

When terminal is narrow, or when user asks to inspect a specific row:

```
ROW 4 OF 50
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Test Utterances [TXT]
    "Cancel my subscription immediately"

  Expected Responses [TXT]
    "Your subscription has been cancelled. You'll retain
     access until the end of your billing period on..."

  Expected Topics [TXT]
    "Cancellation"

  Agent Output [AGT-TEST]  [XX FAILED]
    ERROR: Timeout after 30s - agent did not respond
    Status: Failed
    Duration: 30.0s

  Response Match [EVAL]  [~~ STALE]
    (blocked by failed dependency: Agent Output)

  Topic Check [EVAL]  [~~ STALE]
    (blocked by failed dependency: Agent Output)

  Quality Score [EVAL]  [~~ STALE]
    (blocked by failed dependency: Agent Output)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 2.7 Diff View (After Reprocessing)

When cells are reprocessed, show what changed:

```
REPROCESS DIFF: Agent Output (column 4)
Reprocessed at 2026-03-06 14:23:07 UTC

  Row 4:
    Status:  [XX] Failed  -->  [OK] Complete
    Content: ERROR: Timeout...
         --> "I understand you'd like to cancel your subscription.
              I can help with that. Your subscription will remain
              active until March 31..."

  Row 12:
    Status:  [XX] Failed  -->  [OK] Complete
    Content: ERROR: Rate limited
         --> "Here's your recent transaction history..."

  Cascade: 2 rows changed --> 6 eval cells now need reprocessing
           Response Match: 2 cells now [~~] Stale
           Topic Check:    2 cells now [~~] Stale
           Quality Score:  2 cells now [~~] Stale
```

### 2.8 Column Dependency View (ASCII DAG)

```
COLUMN DEPENDENCIES
━━━━━━━━━━━━━━━━━━━

  Test Utterances [TXT] ──────────┐
                                  ├──> Agent Output [AGT-TEST] ──┬──> Response Match [EVAL]
  Expected Responses [TXT] ───────┼─────────────────────────────>┘
                                  │                              ├──> Topic Check [EVAL]
  Expected Topics [TXT] ──────────┼─────────────────────────────>┘
                                  │                              └──> Quality Score [EVAL]
                                  │
                                  └── (inputUtterance reference)
```

Or in compact tabular form:

```
  Column               Depends On                    Depended On By
  ────────────────────────────────────────────────────────────────────
  Test Utterances      (none)                        Agent Output
  Expected Responses   (none)                        Response Match
  Expected Topics      (none)                        Topic Check
  Agent Output         Test Utterances               Response Match, Topic Check, Quality Score
  Response Match       Agent Output, Expected Resp.  (none)
  Topic Check          Agent Output, Expected Topics (none)
  Quality Score        Agent Output                  (none)
```

---

## 3. Desktop Artifact Visualization (Claude Desktop)

Claude Desktop supports HTML/React artifacts. This unlocks interactive, rich visualizations.

### 3.1 Interactive Grid Table (HTML Artifact)

A full interactive data table as an HTML artifact.

**Features:**
- Sortable columns (click header to sort)
- Filterable by status (dropdown: All / Complete / Failed / Stale)
- Resizable columns (drag borders)
- Cell expansion on click (shows `fullContent` in a slide-out panel)
- Sticky header row and row number column
- Color-coded cells by status
- Evaluation cells show pass/fail with color backgrounds

**Example HTML structure:**

```html
<div class="grid-cockpit">
  <!-- Summary Banner -->
  <header class="grid-summary">
    <h2>Sales Agent Tests</h2>
    <div class="stats-bar">
      <span class="stat">7 columns</span>
      <span class="stat">50 rows</span>
      <span class="stat status-complete">298 complete</span>
      <span class="stat status-failed">8 failed</span>
      <span class="stat eval-pass">84% pass rate</span>
    </div>
    <div class="progress-bar">
      <div class="segment complete" style="width:85.1%"></div>
      <div class="segment in-progress" style="width:3.4%"></div>
      <div class="segment failed" style="width:2.3%"></div>
      <div class="segment stale" style="width:9.1%"></div>
    </div>
  </header>

  <!-- Filter Controls -->
  <nav class="grid-filters">
    <select id="status-filter">
      <option>All Statuses</option>
      <option>Complete</option>
      <option>Failed</option>
      <option>Stale</option>
      <option>InProgress</option>
    </select>
    <input type="search" placeholder="Search cell content..." />
  </nav>

  <!-- Data Table -->
  <table class="grid-table">
    <thead>
      <tr>
        <th class="row-num">#</th>
        <th class="col-text" data-sort="asc">Test Utterances<br/><span class="badge">TXT</span></th>
        <!-- ... -->
        <th class="col-eval">Match<br/><span class="badge eval">EVAL</span></th>
      </tr>
    </thead>
    <tbody>
      <tr class="row-complete">
        <td>1</td>
        <td>Help me reset my password</td>
        <!-- ... -->
        <td class="eval-pass">PASS</td>
      </tr>
      <tr class="row-failed">
        <td>4</td>
        <td>Cancel my subscription</td>
        <!-- ... -->
        <td class="eval-blocked">--</td>
      </tr>
    </tbody>
  </table>
</div>
```

**CSS color system:**

```css
:root {
  --status-complete:    #059669;  /* green-600 */
  --status-in-progress: #2563eb;  /* blue-600 */
  --status-failed:      #dc2626;  /* red-600 */
  --status-stale:       #9ca3af;  /* gray-400 */
  --status-new:         #e5e7eb;  /* gray-200 */
  --eval-pass:          #059669;
  --eval-fail:          #dc2626;
  --eval-warn:          #d97706;  /* amber-600 */
}
```

### 3.2 Evaluation Dashboard (HTML Artifact)

A dedicated dashboard artifact for evaluation analysis. This is the "cockpit's instrument panel."

**Panel 1: Pass Rate Overview**

A horizontal bar chart showing each evaluation column's pass rate:

```
Response Match    [====================          ]  84%  (42/50)
Topic Check       [============================= ]  96%  (48/50)
Action Assertion  [========================      ]  80%  (40/50)
Latency           [============================  ]  90%  (45/50)
```

Rendered as SVG or HTML divs with proportional widths, color-coded (green > 90%, yellow 70-90%, red < 70%).

**Panel 2: Score Distribution Histogram**

For numeric evaluations (COHERENCE, CONCISENESS, etc.), show a histogram:

```
Quality Score Distribution (n=50)
  5 |  ########           (16)
  4 |  ##############     (28)
  3 |  ####               (4)
  2 |  #                  (1)
  1 |  #                  (1)
    +--------------------
     mean=3.7  median=4  std=0.8
```

In desktop, render as an actual SVG bar chart with hover tooltips.

**Panel 3: Failure Analysis**

Group failures by error type and show distribution:

```
Failure Breakdown (8 failures)
┌─────────────────────────┬───────┬─────────────────────────────────┐
│ Error Type              │ Count │ Affected Rows                   │
├─────────────────────────┼───────┼─────────────────────────────────┤
│ Timeout (30s)           │   5   │ 4, 18, 23, 37, 49              │
│ Rate Limited            │   2   │ 12, 44                         │
│ Invalid Response Format │   1   │ 31                             │
└─────────────────────────┴───────┴─────────────────────────────────┘
```

**Panel 4: Latency Distribution**

For LATENCY_ASSERTION evaluations, render a percentile chart:

```
Response Latency (n=50)
  P50:  1.2s  [====|                              ]
  P75:  2.1s  [========|                          ]
  P90:  3.4s  [=============|                     ]
  P95:  5.7s  [=====================|             ]
  P99:  8.1s  [============================__|    ]
  Max: 12.3s  [==================================|]
              0s        5s        10s       15s
```

In desktop, render as a proper SVG percentile/box plot.

**Panel 5: Evaluation Trend (Multi-Run)**

If the user runs evaluations multiple times (reprocess), track results over time:

```
Pass Rate Over Time
  100% |                          *
   90% |        *     *   *
   80% |  *  *
   70% |
       +--+--+--+--+--+--+--+--+--
        R1 R2 R3 R4 R5 R6 R7 R8 R9
```

Note: The API does not natively store historical runs. The skill would need to cache prior results in conversation context or suggest the user keep a local log.

### 3.3 Column Dependency Graph (HTML Artifact)

An interactive directed graph visualization.

**Rendering approach:** Use a simple SVG-based DAG layout (no external libraries needed in artifacts).

```
  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
  │ Utterances   │───>│ Agent Output │───>│ Resp. Match  │
  │ [TXT]        │    │ [AGT-TEST]   │    │ [EVAL]       │
  └──────────────┘    └──────┬───────┘    └──────────────┘
                             │
  ┌──────────────┐           ├──────────>┌──────────────┐
  │ Exp. Topics  │───────────┼──────────>│ Topic Check  │
  │ [TXT]        │           │           │ [EVAL]       │
  └──────────────┘           │           └──────────────┘
                             │
  ┌──────────────┐           └──────────>┌──────────────┐
  │ Exp. Resp.   │──────────────────────>│ Quality      │
  │ [TXT]        │                       │ [EVAL]       │
  └──────────────┘                       └──────────────┘
```

Each node shows:
- Column name
- Type badge with color
- Status indicator (small colored dot)
- Cell completion count (e.g., "42/50")

Interactive: clicking a node highlights its upstream and downstream dependencies.

### 3.4 Heatmap View (HTML Artifact)

For worksheets with multiple evaluation columns, render a row-by-evaluation heatmap:

```
         Resp.Match  Topic  Coherence  Latency
Row  1      4.2       PASS    4/5       1.1s     [green  ][green ][green ][green ]
Row  2      3.8       PASS    3/5       1.4s     [green  ][green ][yellow][green ]
Row  3      1.2       FAIL    2/5       2.1s     [red    ][red   ][red   ][green ]
Row  4       --        --      --        --      [gray   ][gray  ][gray  ][gray  ]
Row  5      4.5       PASS    5/5       0.8s     [green  ][green ][green ][green ]
...
```

Color scale: Red (0-2) -> Yellow (2-3.5) -> Green (3.5-5) for scored evals; binary red/green for pass/fail.

Enables instant visual pattern recognition: "rows 3, 12, 18 are consistently failing across all evals."

### 3.5 Processing Timeline (HTML Artifact)

A Gantt-chart-style view showing when each column's cells were processed:

```
Time -->  0s     5s     10s    15s    20s    25s    30s
          |------|------|------|------|------|------|

Object    [======]
AI Col    [      ][=================]
Agent     [      ][========================]
Eval 1    [                          ][====]
Eval 2    [                          ][======]
Eval 3    [                          ][===]
```

This helps users understand:
- Total pipeline execution time
- Which columns are the bottleneck
- Whether parallelism opportunities exist

Note: The API provides per-cell status but not timestamps. The skill can approximate this by polling and recording timestamps locally during an active processing session.

---

## 4. State Awareness & Communication

### 4.1 The "Worksheet Briefing"

When a user asks about a worksheet, Claude should always lead with a structured briefing, not raw JSON. This is the cockpit's primary readout.

**Template for Claude's response:**

```
Here's the current state of your worksheet "Sales Agent Tests":

STRUCTURE: 7 columns x 50 rows (350 total cells)
  Input:      Test Utterances, Expected Responses, Expected Topics  [all populated]
  Processing: Agent Output                                          [38/50 complete, 8 failed, 4 in progress]
  Evaluation: Response Match, Topic Check, Quality Score            [32/50 scored, 18 stale]

HEALTH:
  - 8 agent failures concentrated in rows 4, 12, 18, 23, 31, 37, 44, 49
  - Primary error: Timeout (5 cells), Rate limiting (2 cells), Format error (1 cell)
  - 18 evaluation cells are stale (blocked by upstream failures)

EVAL RESULTS (of 32 completed):
  - Response Match:  28/32 passed (87.5%)
  - Topic Check:     31/32 passed (96.9%)
  - Quality Score:   avg 3.8/5 (P50=4, P90=5)

RECOMMENDED ACTIONS:
  1. Reprocess "Agent Output" column to retry 8 failed cells
  2. After reprocess, 18 stale eval cells will auto-update
  3. Consider increasing timeout if timeouts persist
```

### 4.2 Data Freshness Indicators

Every time Claude presents grid data, it should annotate freshness:

```
Data fetched: 2026-03-06 14:23:07 UTC (43 seconds ago)
Active processing: Yes (4 cells still InProgress in "Agent Output")
Recommendation: Re-fetch in ~30s to see updated results
```

If data is more than 5 minutes old and there were InProgress cells:

```
WARNING: Data was fetched 8 minutes ago and had active processing.
Results shown may be outdated. Shall I re-fetch the current state?
```

### 4.3 Error Aggregation

Never dump raw error messages. Always aggregate and categorize:

```
ERROR SUMMARY: 8 failures across 1 column

  "Agent Output" [AGT-TEST]:
    Timeout (30s exceeded)       5 cells   rows 4, 18, 23, 37, 49
    Rate limited (429)           2 cells   rows 12, 44
    Invalid response format      1 cell    row 31

  Root cause analysis:
    - 5/8 failures are timeouts, suggesting agent is slow for certain inputs
    - Timeout rows have longer utterances (avg 42 words vs 18 words for passing)
    - Rate limiting hit during burst processing of rows 10-15
```

### 4.4 Proactive State Alerts

When fetching data, Claude should automatically flag anomalies:

- **All Failed Column**: "Warning: Column 'Agent Output' has 0% completion. Check agent configuration (agentId, agentVersion)."
- **Stale Cascade**: "18 evaluation cells are stale because their input column 'Agent Output' has failures. Fix the upstream column first."
- **Schema Drift**: "Column 'Response Match' references column ID 'xxx' which no longer exists in the worksheet."
- **Empty Inputs**: "15 rows have empty 'Test Utterances' cells. Agent Output will skip these rows."

---

## 5. Polling & Async Strategies

### 5.1 Processing Lifecycle

When Claude triggers processing (via `trigger-row-execution` or `reprocess`), it enters a polling loop:

```
Phase 1: TRIGGER
  POST /worksheets/{id}/trigger-row-execution
  Response: 204 (fire-and-forget)

Phase 2: POLL
  Loop:
    GET /worksheets/{id}/data
    Count statuses: { Complete, InProgress, Failed, Stale, New }

    If InProgress > 0:
      Report progress: "Processing: {Complete}/{Total} complete, {InProgress} in progress..."
      Wait (adaptive interval, see 5.2)
      Continue loop

    If InProgress == 0:
      Break loop

Phase 3: REPORT
  Show updated grid state with diff from pre-trigger snapshot
  Highlight newly completed cells and any new failures
```

### 5.2 Adaptive Poll Interval

```
Poll 1:   2 seconds   (initial fast check)
Poll 2:   3 seconds
Poll 3:   5 seconds
Poll 4+:  8 seconds   (steady state)
Max:     10 seconds   (never go higher)

Bail out after: 5 minutes total (configurable)
  "Processing is taking longer than expected.
   {InProgress} cells still running after 5 minutes.
   I'll stop polling. Check back with: show worksheet status"
```

### 5.3 Progress Reporting During Polls

Each poll cycle, Claude should emit a compact progress line (not a full table):

```
[14:23:12] Processing: 12/50 complete (24%), 38 in progress...
[14:23:15] Processing: 18/50 complete (36%), 32 in progress...
[14:23:20] Processing: 31/50 complete (62%), 19 in progress...
[14:23:28] Processing: 42/50 complete (84%), 4 in progress, 4 failed
[14:23:36] Processing: 46/50 complete (92%), 0 in progress, 4 failed
[14:23:36] Done. 46 passed, 4 failed. Evaluations now processing...
[14:23:44] Evaluations: 46/46 complete.

Final results:
  [shows Layer 1 summary banner + eval summary]
```

### 5.4 Selective Data Fetching

For large worksheets, avoid fetching all data on every poll:

- **During polling**: Use `GET /columns/{columnId}/data` to fetch only the processing column's cells (not the entire worksheet). This is cheaper and faster.
- **After completion**: Do one full `GET /worksheets/{id}/data` to get the complete picture.
- **For detail inspection**: Use `GET /columns/{columnId}/data` for the specific column of interest.

### 5.5 Concurrent Column Processing

When multiple columns are processing simultaneously (e.g., after adding an Agent column that triggers cascading Evaluation columns), track per-column progress:

```
Processing Pipeline:
  Agent Output   [AGT-TEST]  ████████████████████░░░░  42/50  (84%)
  Response Match [EVAL]      ██████████░░░░░░░░░░░░░░  20/50  (40%)  waiting on Agent
  Topic Check    [EVAL]      ████████░░░░░░░░░░░░░░░░  16/50  (32%)  waiting on Agent
  Quality Score  [EVAL]      ██████████████░░░░░░░░░░  28/50  (56%)
```

---

## Appendix A: Implementation Notes for the Skill

### A.1 How the Skill Should Be Updated

The current skill at `SKILL.md` needs a new section called **"Cockpit Views"** that teaches Claude:

1. **Always lead with the summary briefing** when asked about worksheet state
2. **Auto-compute GridSummary** from the raw API response before presenting data
3. **Resolve column ordering** by walking the `precedingColumnId` linked list
4. **Build the dependency DAG** from column configs' reference attributes
5. **Classify cells by status** and aggregate counts per column
6. **Detect evaluation results** from `displayContent` of Evaluation columns (pass/fail, scores)
7. **Use progressive disclosure**: summary -> table -> detail, not raw JSON dumps

### A.2 Data Extraction Patterns

The skill should document how to extract evaluation results from cell data:

```
Evaluation cell displayContent patterns:
  - Pass/Fail binary: "Pass" or "Fail"
  - Numeric score:    "4" or "3.7"  (out of 5)
  - Percentage:       "92%"
  - Latency:          "1.2s"
  - Expression:       "true" or "false"

The fullContent object may contain structured data:
  {
    "result": "Pass",
    "score": 4.2,
    "reason": "Response accurately addresses the query...",
    "latencyMs": 1234
  }
```

### A.3 Terminal Width Detection

Claude Code can determine terminal width via environment. The skill should advise:

- **>= 160 chars**: Full table view with generous column widths
- **120-159 chars**: Standard table with moderate truncation
- **80-119 chars**: Compact table, abbreviate column names, max 5 visible columns
- **< 80 chars**: Switch to vertical card view

### A.4 Claude Desktop Artifact Guidelines

When generating HTML artifacts for Claude Desktop:

- **Self-contained**: No external dependencies (no CDN links). Inline all CSS/JS.
- **Responsive**: Use CSS Grid or Flexbox, not fixed widths.
- **Accessible**: Include `aria-label` on interactive elements, proper table markup with `<thead>`/`<tbody>`.
- **Print-friendly**: Include `@media print` styles that remove interactive chrome.
- **Data limit**: Keep artifact HTML under 100KB. For large worksheets (>100 rows), paginate client-side.

---

## Appendix B: Example API Response to Rendered Output

### Raw API Response (abbreviated)

```json
{
  "id": "1W1xx0000004Abc",
  "name": "Sales Agent Tests",
  "columns": [
    {"id": "col-1", "name": "Test Utterances", "type": "Text", "status": "Complete", "precedingColumnId": null},
    {"id": "col-2", "name": "Expected Responses", "type": "Text", "status": "Complete", "precedingColumnId": "col-1"},
    {"id": "col-3", "name": "Agent Output", "type": "AgentTest", "status": "InProgress", "precedingColumnId": "col-2"},
    {"id": "col-4", "name": "Quality Score", "type": "Evaluation", "status": "Stale", "precedingColumnId": "col-3"}
  ],
  "rows": ["row-1", "row-2", "row-3"],
  "columnData": {
    "col-1": [
      {"worksheetRowId": "row-1", "displayContent": "Help me reset my password", "status": "Complete"},
      {"worksheetRowId": "row-2", "displayContent": "What is my account balance", "status": "Complete"},
      {"worksheetRowId": "row-3", "displayContent": "Transfer money to savings", "status": "Complete"}
    ],
    "col-3": [
      {"worksheetRowId": "row-1", "displayContent": "Sure, I can help you reset...", "status": "Complete"},
      {"worksheetRowId": "row-2", "displayContent": "", "status": "InProgress"},
      {"worksheetRowId": "row-3", "displayContent": "ERROR: Timeout", "status": "Failed", "statusMessage": "Agent timeout after 30s"}
    ],
    "col-4": [
      {"worksheetRowId": "row-1", "displayContent": "4", "status": "Complete"},
      {"worksheetRowId": "row-2", "displayContent": "", "status": "Stale"},
      {"worksheetRowId": "row-3", "displayContent": "", "status": "Stale"}
    ]
  }
}
```

### Rendered CLI Output

```
┌─────────────────────────────────────────────────────────────┐
│  WORKSHEET: Sales Agent Tests                               │
│  ID: 1W1xx0000004Abc                                        │
├─────────────────────────────────────────────────────────────┤
│  Columns: 4    Rows: 3    Cells: 12                         │
│  Status:  Complete 7  InProgress 1  Failed 1  Stale 2       │
│           [#######..x~~]                                    │
│  Evals:   1/3 scored (Quality: 4/5)                         │
└─────────────────────────────────────────────────────────────┘

 #  Column Name         Type        Health
 1  Test Utterances     [TXT]       3/3
 2  Expected Responses  [TXT]       3/3
 3  Agent Output        [AGT-TEST]  1/3 (1 err, 1 running)
 4  Quality Score       [EVAL]      1/3 (2 stale)

┌────┬────────────────────┬────────────────────┬────────────────────┬─────────┐
│  # │ Test Utterances     │ Expected Responses │ Agent Output       │ Quality │
│    │ [TXT]               │ [TXT]              │ [AGT-TEST]         │ [EVAL]  │
├────┼────────────────────┼────────────────────┼────────────────────┼─────────┤
│  1 │ Help me reset my   │ I can help you ... │ Sure, I can hel... │  4/5    │
│    │ password            │                    │              [OK]  │  [OK]   │
├────┼────────────────────┼────────────────────┼────────────────────┼─────────┤
│  2 │ What is my account │ Your account bal.. │                    │         │
│    │ balance             │                    │              [..]  │  [~~]   │
├────┼────────────────────┼────────────────────┼────────────────────┼─────────┤
│  3 │ Transfer money to  │ I've initiated ... │ ERROR: Timeout     │         │
│    │ savings             │                    │              [XX]  │  [~~]   │
└────┴────────────────────┴────────────────────┴────────────────────┴─────────┘

Active processing: 1 cell in progress. Re-fetch in ~8s for updates.
1 failure in "Agent Output": Timeout on row 3.
2 eval cells stale (waiting on Agent Output).
```

---

## Appendix C: Glossary of View Types

| View Name             | Surface       | Trigger                                      |
|-----------------------|---------------|----------------------------------------------|
| Summary Banner        | CLI + Desktop | Any worksheet query                          |
| Column Header Strip   | CLI           | "show worksheet", "grid status"              |
| Data Grid Table       | CLI + Desktop | "show data", "show grid"                     |
| Vertical Card         | CLI           | "show row N", narrow terminal                |
| Eval Summary Table    | CLI + Desktop | "show evaluations", "eval results"           |
| Diff View             | CLI           | After reprocess completes                    |
| Dependency Graph      | CLI + Desktop | "show dependencies", "column graph"          |
| Eval Dashboard        | Desktop       | "show eval dashboard", "evaluation report"   |
| Heatmap               | Desktop       | "show heatmap", "quality heatmap"            |
| Processing Timeline   | Desktop       | "show timeline", "processing timeline"       |
| Progress Reporter     | CLI           | Automatic during polling                     |
