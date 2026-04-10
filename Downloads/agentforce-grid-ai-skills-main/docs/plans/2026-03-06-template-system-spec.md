> **Status:** SUPERSEDED | Last updated: 2026-03-06
> **Relation to master plan:** [grid-hybrid-tooling-implementation-plan.md](grid-hybrid-tooling-implementation-plan.md) -- N/A (superseded)
> **What changed:** This entire spec is superseded by the YAML DSL + `apply_grid` approach. The YAML DSL ([grid-yaml-dsl-spec.md](grid-yaml-dsl-spec.md)) provides declarative grid definitions that replace JSON templates. The `apply_grid` tool ([grid-mcp-tools-spec.md](grid-mcp-tools-spec.md) Section A) replaces the `create_from_template` tool. The resolution engine ([grid-resolution-engine-spec.md](grid-resolution-engine-spec.md)) replaces the template resolution algorithm.

# Agentforce Grid Template System Specification -- SUPERSEDED

**Version:** 1.0.0
**Date:** 2026-03-06
**Status:** ~~Draft~~ SUPERSEDED by YAML DSL + apply_grid

---

## Table of Contents

1. [Overview](#1-overview)
2. [Template Schema](#2-template-schema)
3. [Template Resolution Algorithm](#3-template-resolution-algorithm)
4. [Template Definitions](#4-template-definitions)
   - 4.1 agent-test-suite.json
   - 4.2 data-enrichment.json
   - 4.3 prompt-evaluation.json
   - 4.4 ab-testing.json
   - 4.5 flow-testing.json
   - 4.6 data-classification.json
   - 4.7 multi-turn-conversation.json
5. [Template Usage Guide](#5-template-usage-guide)

---

## 1. Overview

The Agentforce Grid Template System provides pre-built worksheet configurations that automate the creation of common Grid patterns. Each template defines a set of columns with their inter-dependencies, parameter placeholders for user-provided values, and optional sample data. A resolution engine reads the template, topologically sorts columns by their dependency graph, creates them sequentially via the Grid API, and wires up real column IDs at each step.

### Design Goals

- **Zero-config quick starts.** A user names a template and provides only the required parameters (e.g., `agentId`). Everything else has sensible defaults.
- **Portable and versionable.** Templates are plain JSON files stored in `templates/` and tracked in source control.
- **Dependency-safe.** The `$ref` pointer system guarantees columns are created in the correct order and wired to real IDs before any dependent column is submitted to the API.
- **Extensible.** Users can author custom templates following the same schema.

---

## 2. Template Schema

### 2.1 Top-Level Structure

```json
{
  "templateVersion": "1.0.0",
  "name": "template-slug-name",
  "displayName": "Human-Readable Template Name",
  "description": "What this template creates and when to use it.",
  "parameters": { ... },
  "columns": [ ... ],
  "sampleData": { ... }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `templateVersion` | String | Yes | Semver version of the template format. Currently `"1.0.0"`. |
| `name` | String | Yes | Machine-readable slug. Must match filename without `.json`. |
| `displayName` | String | Yes | Human-readable name shown in template listings. |
| `description` | String | Yes | One-paragraph description of the template's purpose. |
| `parameters` | Object | Yes | Map of parameter definitions (see 2.2). |
| `columns` | Array | Yes | Ordered list of column definitions (see 2.3). |
| `sampleData` | Object | No | Default test data to populate via the paste endpoint (see 2.5). |

### 2.2 Parameter Definitions

Each key in `parameters` is the parameter name used in `{{paramName}}` interpolation.

```json
"parameters": {
  "agentId": {
    "type": "string",
    "required": true,
    "description": "The 18-character Salesforce Agent definition ID (0Xx prefix).",
    "pattern": "^0Xx[A-Za-z0-9]{15}$"
  },
  "agentVersion": {
    "type": "string",
    "required": true,
    "description": "The 18-character Agent version ID (0Xy prefix)."
  },
  "model": {
    "type": "string",
    "required": false,
    "default": "sfdc_ai__DefaultGPT4Omni",
    "description": "LLM model name for AI/evaluation columns."
  },
  "numberOfRows": {
    "type": "integer",
    "required": false,
    "default": 50,
    "description": "Number of rows to provision."
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `type` | `"string"` `"integer"` `"boolean"` | Yes | Parameter value type. |
| `required` | Boolean | Yes | Whether the caller must supply a value. |
| `default` | Any | No | Default value when not supplied. Ignored if `required: true`. |
| `description` | String | Yes | Displayed to the user when prompting for values. |
| `pattern` | String | No | Regex for input validation (string parameters only). |
| `enum` | Array | No | Allowed values for the parameter. |

### 2.3 Column Definitions

Each entry in the `columns` array defines one Grid column. Columns use a `ref` key for internal cross-referencing and `$ref` pointers to declare dependencies on other columns.

```json
{
  "ref": "utterances",
  "name": "Test Utterances",
  "type": "Text",
  "config": {
    "type": "Text",
    "autoUpdate": true,
    "config": {
      "autoUpdate": true
    }
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ref` | String | Yes | Unique key within the template. Used as target for `$ref` pointers. Never sent to the API. |
| `name` | String | Yes | Column display name. Supports `{{paramName}}` interpolation. |
| `type` | String | Yes | Grid column type (`Text`, `AI`, `AgentTest`, `Agent`, `Evaluation`, `Object`, `Reference`, `Formula`, `PromptTemplate`, `InvocableAction`, `Action`, `DataModelObject`). |
| `config` | Object | Yes | The full nested config following the Grid API's `config.config` pattern. Contains `$ref` pointers and `{{paramName}}` placeholders. |

### 2.4 The `$ref` Pointer System

Any place in `config` where a column ID or ReferenceAttribute is needed, the template uses a `$ref` pointer instead of a literal ID. The resolution engine replaces these with real values after each column is created.

**Syntax:** `{"$ref": "#/columns/<ref-name>"}`

This resolves to the **column ID** returned by the API when the referenced column was created.

**Syntax for ReferenceAttribute:** `{"$ref": "#/columns/<ref-name>", "columnName": "...", "columnType": "...", "fieldName": "..."}`

When `columnName`, `columnType`, or `fieldName` are present alongside `$ref`, the resolver constructs a full ReferenceAttribute object, substituting only the `columnId` from the resolved ID.

**Examples:**

```json
// Resolves to just a column ID string (e.g., for referenceColumnId)
"referenceColumnId": {"$ref": "#/columns/agent-output"}

// Resolves to a full ReferenceAttribute object
"inputColumnReference": {
  "$ref": "#/columns/agent-output",
  "columnName": "Agent Output",
  "columnType": "AGENT_TEST"
}

// ReferenceAttribute with fieldName (for Object columns)
"referenceAttributes": [
  {
    "$ref": "#/columns/accounts",
    "columnName": "Accounts",
    "columnType": "OBJECT",
    "fieldName": "Name"
  }
]
```

### 2.5 Parameter Interpolation

`{{paramName}}` tokens are replaced with user-provided or default parameter values during resolution. They can appear in any string value within `name` or `config`.

```json
"agentId": "{{agentId}}",
"agentVersion": "{{agentVersion}}",
"modelConfig": {
  "modelId": "{{model}}",
  "modelName": "{{model}}"
}
```

### 2.6 Sample Data Section

The optional `sampleData` object maps column `ref` keys to arrays of string values. During resolution, these are translated into a paste API call.

```json
"sampleData": {
  "utterances": [
    "I need help resetting my password",
    "What is my account balance?",
    "How do I upgrade my plan?"
  ],
  "expected-responses": [
    "I can help you reset your password...",
    "Let me look up your account balance...",
    "Here are the available upgrade options..."
  ]
}
```

Only Text columns should have sample data entries. The resolution engine uses the paste endpoint (`POST /worksheets/{id}/paste`) with the `matrix` format.

---

## 3. Template Resolution Algorithm

### 3.1 High-Level Flow

```
                    +-------------------+
                    |  Load Template    |
                    |  JSON from disk   |
                    +--------+----------+
                             |
                             v
                    +-------------------+
                    |  Validate & Merge |
                    |  Parameters       |
                    +--------+----------+
                             |
                             v
                    +-------------------+
                    | Build Dependency  |
                    | Graph from $ref   |
                    +--------+----------+
                             |
                             v
                    +-------------------+
                    | Topological Sort  |
                    | (Kahn's Algo)     |
                    +--------+----------+
                             |
                             v
                    +-------------------+
                    | For each column   |
                    | in sorted order:  |
                    |  1. Interpolate   |
                    |     {{params}}    |
                    |  2. Resolve $ref  |
                    |     pointers      |
                    |  3. POST column   |
                    |  4. Capture ID    |
                    +--------+----------+
                             |
                             v
                    +-------------------+
                    | Paste sampleData  |
                    | (if present)      |
                    +-------------------+
```

### 3.2 Step 1: Parse Template and Validate Parameters

1. Read the template JSON file.
2. Validate against the template schema (check required fields, valid types).
3. Merge user-supplied parameters with defaults:
   - For each parameter defined in `parameters`:
     - If `required: true` and no user value provided, raise an error.
     - If `required: false` and no user value provided, use `default`.
     - If `pattern` is defined, validate the supplied value.
     - If `enum` is defined, verify the value is in the allowed set.
4. Produce a resolved parameter map: `{ paramName: resolvedValue, ... }`.

### 3.3 Step 2: Topological Sort by Dependency Graph

1. For each column, scan its `config` tree recursively for `$ref` pointers.
2. Build a directed graph: an edge from column A to column B means B contains a `$ref` pointing to A.
3. Run Kahn's algorithm (BFS-based topological sort):
   - Initialize in-degree counts for all columns.
   - Seed the queue with columns having zero in-degree (no dependencies).
   - Dequeue, append to sorted list, decrement in-degrees of dependents.
   - If the sorted list length does not equal the column count, there is a cycle -- raise an error.
4. The output is the creation order.

### 3.4 Step 3: Create Columns Sequentially

For each column in topologically sorted order:

1. **Interpolate parameters.** Walk all string values and replace `{{paramName}}` with the resolved parameter value.
2. **Resolve `$ref` pointers.** Walk the config tree:
   - When a `$ref` object is found with only `"$ref"` key, replace the entire object with the resolved column ID string.
   - When a `$ref` object has additional keys (`columnName`, `columnType`, optional `fieldName`), construct a ReferenceAttribute:
     ```json
     {
       "columnId": "<resolved-id>",
       "columnName": "<from-template>",
       "columnType": "<from-template>",
       "fieldName": "<from-template, if present>"
     }
     ```
3. **Strip the `ref` key.** Remove it from the payload before sending to the API.
4. **POST to the Grid API.**
   ```
   POST /services/data/v66.0/public/grid/worksheets/{worksheetId}/columns
   ```
5. **Capture the returned column ID.** Store it in the resolution map: `refName -> columnId`.
6. **Verify creation.** If the API returns an error status but the column may still have been created (known Grid API behavior), call `GET /worksheets/{id}/data` to confirm.

### 3.5 Step 4: Populate Sample Data

If `sampleData` is present:

1. Retrieve the worksheet data to get the first row ID: `GET /worksheets/{id}/data`.
2. Determine the starting column. Find the first column `ref` that has sample data entries. Look up its resolved ID.
3. Build the paste matrix. For each row index `i`:
   - For each column that has sample data (in column creation order), include `{"displayContent": sampleData[ref][i]}`.
   - For columns without sample data, include `{"displayContent": ""}`.
4. POST the paste request:
   ```json
   POST /services/data/v66.0/public/grid/worksheets/{worksheetId}/paste
   {
     "startColumnId": "<first-text-column-id>",
     "startRowId": "<first-row-id>",
     "matrix": [ ... ]
   }
   ```

### 3.6 Error Handling

| Error Condition | Behavior |
|----------------|----------|
| Missing required parameter | Raise `ParameterError` with parameter name and description |
| Cycle in dependency graph | Raise `DependencyCycleError` listing the cycle path |
| `$ref` to undefined column ref | Raise `UnresolvedReferenceError` with the ref name |
| Column creation API failure | Retry once, then verify via `/data` endpoint, raise `ColumnCreationError` if truly failed |
| Paste data row count mismatch | Pad shorter arrays with empty strings, truncate longer arrays to shortest |

---

## 4. Template Definitions

### 4.1 agent-test-suite.json

**Purpose:** Test an agent with utterances and evaluate responses across four dimensions: response accuracy, topic routing, coherence, and latency.

**Dependency DAG:**

```
utterances ─────────────────────────┐
                                    ├──> agent-output ──┬──> eval-response-match
expected-responses ─────────────────┤                   ├──> eval-topic-assertion
                                    │                   ├──> eval-coherence
expected-topics ────────────────────┘                   └──> eval-latency
                                    │
          (eval-response-match depends on agent-output + expected-responses)
          (eval-topic-assertion depends on agent-output + expected-topics)
```

```
  utterances        expected-responses     expected-topics
      |                    |                     |
      +--------------------+---------------------+
                           |
                      agent-output
                     /    |    \       \
                    /     |     \       \
    eval-response-match   |  eval-coherence  eval-latency
          |               |
   (+ expected-responses) |
                   eval-topic-assertion
                          |
                   (+ expected-topics)
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `agentId` | string | yes | -- | Agent definition ID |
| `agentVersion` | string | yes | -- | Agent version ID |
| `numberOfRows` | integer | no | 50 | Row count |

**Complete Template JSON:**

```json
{
  "templateVersion": "1.0.0",
  "name": "agent-test-suite",
  "displayName": "Agent Test Suite",
  "description": "Comprehensive agent testing with utterances, expected responses, expected topics, and four evaluations: response match, topic assertion, coherence, and latency.",
  "parameters": {
    "agentId": {
      "type": "string",
      "required": true,
      "description": "18-character Agent definition ID (0Xx prefix)."
    },
    "agentVersion": {
      "type": "string",
      "required": true,
      "description": "18-character Agent version ID (0Xy prefix)."
    },
    "numberOfRows": {
      "type": "integer",
      "required": false,
      "default": 50,
      "description": "Number of rows to provision in the worksheet."
    }
  },
  "columns": [
    {
      "ref": "utterances",
      "name": "Test Utterances",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "expected-responses",
      "name": "Expected Responses",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "expected-topics",
      "name": "Expected Topics",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "agent-output",
      "name": "Agent Output",
      "type": "AgentTest",
      "config": {
        "type": "AgentTest",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "agentId": "{{agentId}}",
          "agentVersion": "{{agentVersion}}",
          "inputUtterance": {
            "$ref": "#/columns/utterances",
            "columnName": "Test Utterances",
            "columnType": "TEXT"
          },
          "contextVariables": []
        }
      }
    },
    {
      "ref": "eval-response-match",
      "name": "Response Match",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "RESPONSE_MATCH",
          "inputColumnReference": {
            "$ref": "#/columns/agent-output",
            "columnName": "Agent Output",
            "columnType": "AGENT_TEST"
          },
          "referenceColumnReference": {
            "$ref": "#/columns/expected-responses",
            "columnName": "Expected Responses",
            "columnType": "TEXT"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-topic-assertion",
      "name": "Topic Assertion",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "TOPIC_ASSERTION",
          "inputColumnReference": {
            "$ref": "#/columns/agent-output",
            "columnName": "Agent Output",
            "columnType": "AGENT_TEST"
          },
          "referenceColumnReference": {
            "$ref": "#/columns/expected-topics",
            "columnName": "Expected Topics",
            "columnType": "TEXT"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-coherence",
      "name": "Coherence",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "COHERENCE",
          "inputColumnReference": {
            "$ref": "#/columns/agent-output",
            "columnName": "Agent Output",
            "columnType": "AGENT_TEST"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-latency",
      "name": "Latency",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "LATENCY_ASSERTION",
          "inputColumnReference": {
            "$ref": "#/columns/agent-output",
            "columnName": "Agent Output",
            "columnType": "AGENT_TEST"
          },
          "autoEvaluate": true
        }
      }
    }
  ],
  "sampleData": {
    "utterances": [
      "I need help resetting my password",
      "What is my current account balance?",
      "How do I upgrade my subscription plan?",
      "I want to cancel my order #12345",
      "Can you transfer me to a human agent?"
    ],
    "expected-responses": [
      "I can help you reset your password. Please check your email for a reset link.",
      "Let me look up your account balance right away.",
      "Here are the available upgrade options for your current plan.",
      "I can help you cancel order #12345. Let me pull up the details.",
      "I will transfer you to a live agent now. Please hold."
    ],
    "expected-topics": [
      "Password_Reset",
      "Account_Inquiry",
      "Plan_Upgrade",
      "Order_Cancellation",
      "Agent_Transfer"
    ]
  }
}
```

---

### 4.2 data-enrichment.json

**Purpose:** Query Salesforce Account or Contact records and enrich them with AI-generated summaries, classifications, and extracted reference fields.

**Dependency DAG:**

```
  accounts
     |
     +-----+------+------+
     |      |      |      |
     v      v      v      v
  ref-name  ref-industry  ai-summary  ai-classification
```

```
  accounts ──┬──> ref-name
             ├──> ref-industry
             ├──> ai-summary
             └──> ai-classification
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `objectApiName` | string | no | `"Account"` | SObject to query |
| `model` | string | no | `"sfdc_ai__DefaultGPT4Omni"` | LLM model name |
| `numberOfRows` | integer | no | 50 | Row count |

**Complete Template JSON:**

```json
{
  "templateVersion": "1.0.0",
  "name": "data-enrichment",
  "displayName": "Data Enrichment Pipeline",
  "description": "Query Salesforce Account or Contact records and enrich them with AI-generated summaries and classifications, plus reference columns for key fields.",
  "parameters": {
    "objectApiName": {
      "type": "string",
      "required": false,
      "default": "Account",
      "description": "Salesforce SObject API name to query (e.g., Account, Contact)."
    },
    "model": {
      "type": "string",
      "required": false,
      "default": "sfdc_ai__DefaultGPT4Omni",
      "description": "LLM model name for AI columns."
    },
    "numberOfRows": {
      "type": "integer",
      "required": false,
      "default": 50,
      "description": "Number of rows to provision."
    }
  },
  "columns": [
    {
      "ref": "accounts",
      "name": "{{objectApiName}}s",
      "type": "Object",
      "config": {
        "type": "Object",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {
          "type": "WHOLE_COLUMN",
          "splitByType": "OBJECT_PER_ROW"
        },
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "objectApiName": "{{objectApiName}}",
          "fields": [
            {"name": "Id", "type": "id"},
            {"name": "Name", "type": "string"},
            {"name": "Industry", "type": "picklist"},
            {"name": "Description", "type": "textarea"},
            {"name": "AnnualRevenue", "type": "currency"}
          ],
          "filters": []
        }
      }
    },
    {
      "ref": "ref-name",
      "name": "Name",
      "type": "Reference",
      "config": {
        "type": "Reference",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "referenceColumnId": {"$ref": "#/columns/accounts"},
          "referenceField": "Name"
        }
      }
    },
    {
      "ref": "ref-industry",
      "name": "Industry",
      "type": "Reference",
      "config": {
        "type": "Reference",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "referenceColumnId": {"$ref": "#/columns/accounts"},
          "referenceField": "Industry"
        }
      }
    },
    {
      "ref": "ai-summary",
      "name": "AI Summary",
      "type": "AI",
      "config": {
        "type": "AI",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "mode": "llm",
          "modelConfig": {
            "modelId": "{{model}}",
            "modelName": "{{model}}"
          },
          "instruction": "Write a concise 2-3 sentence business summary for this company.\n\nCompany Name: {$1}\nIndustry: {$2}\nDescription: {$3}\nAnnual Revenue: {$4}\n\nFocus on market position, key strengths, and business characteristics.",
          "referenceAttributes": [
            {
              "$ref": "#/columns/accounts",
              "columnName": "{{objectApiName}}s",
              "columnType": "OBJECT",
              "fieldName": "Name"
            },
            {
              "$ref": "#/columns/accounts",
              "columnName": "{{objectApiName}}s",
              "columnType": "OBJECT",
              "fieldName": "Industry"
            },
            {
              "$ref": "#/columns/accounts",
              "columnName": "{{objectApiName}}s",
              "columnType": "OBJECT",
              "fieldName": "Description"
            },
            {
              "$ref": "#/columns/accounts",
              "columnName": "{{objectApiName}}s",
              "columnType": "OBJECT",
              "fieldName": "AnnualRevenue"
            }
          ],
          "responseFormat": {
            "type": "PLAIN_TEXT",
            "options": []
          }
        }
      }
    },
    {
      "ref": "ai-classification",
      "name": "Segment",
      "type": "AI",
      "config": {
        "type": "AI",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "mode": "llm",
          "modelConfig": {
            "modelId": "{{model}}",
            "modelName": "{{model}}"
          },
          "instruction": "Classify this company into a market segment based on the following data.\n\nCompany Name: {$1}\nIndustry: {$2}\nAnnual Revenue: {$3}",
          "referenceAttributes": [
            {
              "$ref": "#/columns/accounts",
              "columnName": "{{objectApiName}}s",
              "columnType": "OBJECT",
              "fieldName": "Name"
            },
            {
              "$ref": "#/columns/accounts",
              "columnName": "{{objectApiName}}s",
              "columnType": "OBJECT",
              "fieldName": "Industry"
            },
            {
              "$ref": "#/columns/accounts",
              "columnName": "{{objectApiName}}s",
              "columnType": "OBJECT",
              "fieldName": "AnnualRevenue"
            }
          ],
          "responseFormat": {
            "type": "SINGLE_SELECT",
            "options": [
              {"label": "Enterprise", "value": "enterprise"},
              {"label": "Mid-Market", "value": "mid_market"},
              {"label": "SMB", "value": "smb"},
              {"label": "Startup", "value": "startup"}
            ]
          }
        }
      }
    }
  ],
  "sampleData": {}
}
```

---

### 4.3 prompt-evaluation.json

**Purpose:** Run a prompt template across varied inputs and contexts, then evaluate output quality for coherence, completeness, and instruction following.

**Dependency DAG:**

```
  inputs       context
     \          /
      \        /
    prompt-output ──┬──> eval-coherence
                    ├──> eval-completeness
                    └──> eval-instruction-following
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `promptTemplateDevName` | string | yes | -- | Developer name of the GenAI prompt template |
| `promptTemplateType` | string | no | `"flex"` | Prompt template type |
| `model` | string | no | `"sfdc_ai__DefaultGPT4Omni"` | LLM model name |
| `numberOfRows` | integer | no | 50 | Row count |

**Complete Template JSON:**

```json
{
  "templateVersion": "1.0.0",
  "name": "prompt-evaluation",
  "displayName": "Prompt Template Evaluation",
  "description": "Execute a GenAI prompt template across varied inputs and contexts, then evaluate output quality for coherence, completeness, and instruction following.",
  "parameters": {
    "promptTemplateDevName": {
      "type": "string",
      "required": true,
      "description": "Developer name of the GenAI prompt template to evaluate."
    },
    "promptTemplateType": {
      "type": "string",
      "required": false,
      "default": "flex",
      "description": "Prompt template type (e.g., flex)."
    },
    "model": {
      "type": "string",
      "required": false,
      "default": "sfdc_ai__DefaultGPT4Omni",
      "description": "LLM model name."
    },
    "numberOfRows": {
      "type": "integer",
      "required": false,
      "default": 50,
      "description": "Number of rows to provision."
    }
  },
  "columns": [
    {
      "ref": "inputs",
      "name": "Inputs",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "context",
      "name": "Context",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "prompt-output",
      "name": "Prompt Output",
      "type": "PromptTemplate",
      "config": {
        "type": "PromptTemplate",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "promptTemplateDevName": "{{promptTemplateDevName}}",
          "promptTemplateType": "{{promptTemplateType}}",
          "modelConfig": {
            "modelId": "{{model}}",
            "modelName": "{{model}}"
          },
          "promptTemplateInputConfigs": [
            {
              "referenceName": "Input",
              "definition": "Primary input for the prompt template",
              "referenceAttribute": {
                "$ref": "#/columns/inputs",
                "columnName": "Inputs",
                "columnType": "TEXT"
              }
            },
            {
              "referenceName": "Context",
              "definition": "Additional context for the prompt template",
              "referenceAttribute": {
                "$ref": "#/columns/context",
                "columnName": "Context",
                "columnType": "TEXT"
              }
            }
          ]
        }
      }
    },
    {
      "ref": "eval-coherence",
      "name": "Coherence",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "COHERENCE",
          "inputColumnReference": {
            "$ref": "#/columns/prompt-output",
            "columnName": "Prompt Output",
            "columnType": "PROMPT_TEMPLATE"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-completeness",
      "name": "Completeness",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "COMPLETENESS",
          "inputColumnReference": {
            "$ref": "#/columns/prompt-output",
            "columnName": "Prompt Output",
            "columnType": "PROMPT_TEMPLATE"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-instruction-following",
      "name": "Instruction Following",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "INSTRUCTION_FOLLOWING",
          "inputColumnReference": {
            "$ref": "#/columns/prompt-output",
            "columnName": "Prompt Output",
            "columnType": "PROMPT_TEMPLATE"
          },
          "autoEvaluate": true
        }
      }
    }
  ],
  "sampleData": {
    "inputs": [
      "Write a welcome email for a new enterprise customer",
      "Draft a renewal reminder for an expiring subscription",
      "Create an apology message for a service outage",
      "Compose a feature announcement for existing users",
      "Write a follow-up email after a product demo"
    ],
    "context": [
      "Customer: Acme Corp, Plan: Enterprise, Onboarding date: 2026-03-01",
      "Customer: Beta Inc, Plan: Professional, Expiry: 2026-04-15",
      "Service: Payment Processing, Duration: 2 hours, Resolved: Yes",
      "Feature: Advanced Analytics Dashboard, Release: Q2 2026",
      "Prospect: Gamma LLC, Demo date: 2026-03-05, Interest: High"
    ]
  }
}
```

---

### 4.4 ab-testing.json

**Purpose:** Compare two agent versions (or two AI model configurations) side by side on the same inputs, with paired evaluation columns for response match, coherence, completeness, and latency.

**Dependency DAG:**

```
                    utterances
                   /          \
                  /            \
    expected-responses    expected-topics
          |       \          /       |
          |        \        /        |
          |    agent-a    agent-b    |
          |      |   \    /   |      |
          |      |    \  /    |      |
          |      |     \/     |      |
          |      |     /\     |      |
          +------+----/--\----+------+
          |      |   /    \   |      |
  eval-a-resp  eval-a-coh  eval-b-resp  eval-b-coh
                eval-a-latency    eval-b-latency
```

```
  utterances ──────────────────────┐
  expected-responses ──────────────┤
  expected-topics ─────────────────┤
                                   |
              +--------------------+--------------------+
              |                                         |
          agent-a                                   agent-b
         /   |    \                                /   |    \
        /    |     \                              /    |     \
  eval-a   eval-a  eval-a                  eval-b   eval-b  eval-b
  -resp    -coh    -latency                -resp    -coh    -latency
    |                                        |
  (+ expected-responses)                   (+ expected-responses)
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `agentIdA` | string | yes | -- | Agent definition ID for variant A |
| `agentVersionA` | string | yes | -- | Agent version ID for variant A |
| `agentIdB` | string | yes | -- | Agent definition ID for variant B |
| `agentVersionB` | string | yes | -- | Agent version ID for variant B |
| `numberOfRows` | integer | no | 50 | Row count |

**Complete Template JSON:**

```json
{
  "templateVersion": "1.0.0",
  "name": "ab-testing",
  "displayName": "A/B Agent Testing",
  "description": "Compare two agent versions side by side on the same utterances with paired evaluations for response match, coherence, and latency.",
  "parameters": {
    "agentIdA": {
      "type": "string",
      "required": true,
      "description": "Agent definition ID for variant A."
    },
    "agentVersionA": {
      "type": "string",
      "required": true,
      "description": "Agent version ID for variant A."
    },
    "agentIdB": {
      "type": "string",
      "required": true,
      "description": "Agent definition ID for variant B (can be same agent, different version)."
    },
    "agentVersionB": {
      "type": "string",
      "required": true,
      "description": "Agent version ID for variant B."
    },
    "numberOfRows": {
      "type": "integer",
      "required": false,
      "default": 50,
      "description": "Number of rows to provision."
    }
  },
  "columns": [
    {
      "ref": "utterances",
      "name": "Test Utterances",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "expected-responses",
      "name": "Expected Responses",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "expected-topics",
      "name": "Expected Topics",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "agent-a",
      "name": "Agent A Output",
      "type": "AgentTest",
      "config": {
        "type": "AgentTest",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "agentId": "{{agentIdA}}",
          "agentVersion": "{{agentVersionA}}",
          "inputUtterance": {
            "$ref": "#/columns/utterances",
            "columnName": "Test Utterances",
            "columnType": "TEXT"
          },
          "contextVariables": []
        }
      }
    },
    {
      "ref": "agent-b",
      "name": "Agent B Output",
      "type": "AgentTest",
      "config": {
        "type": "AgentTest",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "agentId": "{{agentIdB}}",
          "agentVersion": "{{agentVersionB}}",
          "inputUtterance": {
            "$ref": "#/columns/utterances",
            "columnName": "Test Utterances",
            "columnType": "TEXT"
          },
          "contextVariables": []
        }
      }
    },
    {
      "ref": "eval-a-response-match",
      "name": "A: Response Match",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "RESPONSE_MATCH",
          "inputColumnReference": {
            "$ref": "#/columns/agent-a",
            "columnName": "Agent A Output",
            "columnType": "AGENT_TEST"
          },
          "referenceColumnReference": {
            "$ref": "#/columns/expected-responses",
            "columnName": "Expected Responses",
            "columnType": "TEXT"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-b-response-match",
      "name": "B: Response Match",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "RESPONSE_MATCH",
          "inputColumnReference": {
            "$ref": "#/columns/agent-b",
            "columnName": "Agent B Output",
            "columnType": "AGENT_TEST"
          },
          "referenceColumnReference": {
            "$ref": "#/columns/expected-responses",
            "columnName": "Expected Responses",
            "columnType": "TEXT"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-a-coherence",
      "name": "A: Coherence",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "COHERENCE",
          "inputColumnReference": {
            "$ref": "#/columns/agent-a",
            "columnName": "Agent A Output",
            "columnType": "AGENT_TEST"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-b-coherence",
      "name": "B: Coherence",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "COHERENCE",
          "inputColumnReference": {
            "$ref": "#/columns/agent-b",
            "columnName": "Agent B Output",
            "columnType": "AGENT_TEST"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-a-latency",
      "name": "A: Latency",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "LATENCY_ASSERTION",
          "inputColumnReference": {
            "$ref": "#/columns/agent-a",
            "columnName": "Agent A Output",
            "columnType": "AGENT_TEST"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-b-latency",
      "name": "B: Latency",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "LATENCY_ASSERTION",
          "inputColumnReference": {
            "$ref": "#/columns/agent-b",
            "columnName": "Agent B Output",
            "columnType": "AGENT_TEST"
          },
          "autoEvaluate": true
        }
      }
    }
  ],
  "sampleData": {
    "utterances": [
      "I need to reset my password",
      "What products do you offer?",
      "I want to file a complaint about my recent order",
      "Can you help me update my billing address?",
      "What are your business hours?"
    ],
    "expected-responses": [
      "I can help you reset your password. Let me send a reset link to your email.",
      "We offer a range of products including...",
      "I am sorry to hear about your experience. Let me help you file a complaint.",
      "I can help you update your billing address. Please provide the new address.",
      "Our business hours are Monday through Friday, 9 AM to 5 PM."
    ],
    "expected-topics": [
      "Password_Reset",
      "Product_Inquiry",
      "Complaint",
      "Account_Update",
      "General_Inquiry"
    ]
  }
}
```

---

### 4.5 flow-testing.json

**Purpose:** Test a Salesforce Flow with varying inputs and extract specific output fields via Reference columns.

**Dependency DAG:**

```
  input-subject    input-description    input-priority
        \                |                  /
         \               |                 /
          +──────────────+────────────────+
                         |
                    flow-result
                    /         \
                   /           \
            ref-case-id     ref-status
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `flowApiName` | string | yes | -- | Flow API name |
| `flowLabel` | string | no | `"Test Flow"` | Display label for the flow |
| `outputField1` | string | no | `"outputValues.caseId"` | JSON path for first output extraction |
| `outputField2` | string | no | `"outputValues.status"` | JSON path for second output extraction |
| `numberOfRows` | integer | no | 50 | Row count |

**Complete Template JSON:**

```json
{
  "templateVersion": "1.0.0",
  "name": "flow-testing",
  "displayName": "Flow Testing Pipeline",
  "description": "Test a Salesforce Flow with three text inputs, execute via InvocableAction, and extract two output fields via Reference columns.",
  "parameters": {
    "flowApiName": {
      "type": "string",
      "required": true,
      "description": "API name of the Flow to test."
    },
    "flowLabel": {
      "type": "string",
      "required": false,
      "default": "Test Flow",
      "description": "Display label for the Flow column."
    },
    "outputField1": {
      "type": "string",
      "required": false,
      "default": "outputValues.caseId",
      "description": "JSON path for the first output field to extract."
    },
    "outputField2": {
      "type": "string",
      "required": false,
      "default": "outputValues.status",
      "description": "JSON path for the second output field to extract."
    },
    "numberOfRows": {
      "type": "integer",
      "required": false,
      "default": 50,
      "description": "Number of rows to provision."
    }
  },
  "columns": [
    {
      "ref": "input-subject",
      "name": "Subject",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "input-description",
      "name": "Description",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "input-priority",
      "name": "Priority",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "flow-result",
      "name": "{{flowLabel}}",
      "type": "InvocableAction",
      "config": {
        "type": "InvocableAction",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "actionInfo": {
            "actionType": "FLOW",
            "actionName": "{{flowApiName}}",
            "url": "/services/data/v66.0/actions/custom/flow/{{flowApiName}}",
            "label": "{{flowLabel}}"
          },
          "inputPayload": "{\"Subject\": \"{$1}\", \"Description\": \"{$2}\", \"Priority\": \"{$3}\"}",
          "referenceAttributes": [
            {
              "$ref": "#/columns/input-subject",
              "columnName": "Subject",
              "columnType": "TEXT"
            },
            {
              "$ref": "#/columns/input-description",
              "columnName": "Description",
              "columnType": "TEXT"
            },
            {
              "$ref": "#/columns/input-priority",
              "columnName": "Priority",
              "columnType": "TEXT"
            }
          ]
        }
      }
    },
    {
      "ref": "ref-output-1",
      "name": "Output: Field 1",
      "type": "Reference",
      "config": {
        "type": "Reference",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "referenceColumnId": {"$ref": "#/columns/flow-result"},
          "referenceField": "{{outputField1}}"
        }
      }
    },
    {
      "ref": "ref-output-2",
      "name": "Output: Field 2",
      "type": "Reference",
      "config": {
        "type": "Reference",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "referenceColumnId": {"$ref": "#/columns/flow-result"},
          "referenceField": "{{outputField2}}"
        }
      }
    }
  ],
  "sampleData": {
    "input-subject": [
      "Login page not loading",
      "Payment failed during checkout",
      "Cannot access reports dashboard",
      "Email notifications not received",
      "Mobile app crashes on startup"
    ],
    "input-description": [
      "Customer reports blank screen when navigating to login page on Chrome.",
      "Payment gateway returns error 502 during final checkout step.",
      "Reports dashboard shows 403 Forbidden error for admin users.",
      "No email notifications received for the past 48 hours.",
      "iOS app crashes immediately after splash screen on iPhone 15."
    ],
    "input-priority": [
      "High",
      "Critical",
      "Medium",
      "Low",
      "High"
    ]
  }
}
```

---

### 4.6 data-classification.json

**Purpose:** Query Salesforce records and run three independent AI classifiers on them, then compute an agreement score using a Formula column to measure inter-classifier consistency.

**Dependency DAG:**

```
  records ──┬──> classifier-sentiment
            ├──> classifier-urgency
            ├──> classifier-category
            │
            │    classifier-sentiment ──┐
            │    classifier-urgency  ───┼──> formula-agreement
            │    classifier-category ───┘
            │
            └──> (records feeds all three classifiers)
```

```
          records
         /   |   \
        /    |    \
  classifier classifier classifier
  -sentiment -urgency  -category
        \    |    /
         \   |   /
      formula-agreement
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `objectApiName` | string | no | `"Case"` | SObject to query |
| `model` | string | no | `"sfdc_ai__DefaultGPT4Omni"` | LLM model name |
| `numberOfRows` | integer | no | 50 | Row count |

**Complete Template JSON:**

```json
{
  "templateVersion": "1.0.0",
  "name": "data-classification",
  "displayName": "Multi-Classifier Data Classification",
  "description": "Query Salesforce records and run three independent AI classifiers (sentiment, urgency, category), then compute an agreement score via Formula to measure inter-classifier consistency.",
  "parameters": {
    "objectApiName": {
      "type": "string",
      "required": false,
      "default": "Case",
      "description": "SObject API name to classify."
    },
    "model": {
      "type": "string",
      "required": false,
      "default": "sfdc_ai__DefaultGPT4Omni",
      "description": "LLM model name for classification columns."
    },
    "numberOfRows": {
      "type": "integer",
      "required": false,
      "default": 50,
      "description": "Number of rows to provision."
    }
  },
  "columns": [
    {
      "ref": "records",
      "name": "{{objectApiName}} Records",
      "type": "Object",
      "config": {
        "type": "Object",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {
          "type": "WHOLE_COLUMN",
          "splitByType": "OBJECT_PER_ROW"
        },
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "objectApiName": "{{objectApiName}}",
          "fields": [
            {"name": "Id", "type": "id"},
            {"name": "Subject", "type": "string"},
            {"name": "Description", "type": "textarea"},
            {"name": "Status", "type": "picklist"},
            {"name": "Priority", "type": "picklist"}
          ],
          "filters": []
        }
      }
    },
    {
      "ref": "classifier-sentiment",
      "name": "Sentiment",
      "type": "AI",
      "config": {
        "type": "AI",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "mode": "llm",
          "modelConfig": {
            "modelId": "{{model}}",
            "modelName": "{{model}}"
          },
          "instruction": "Classify the sentiment of this case based on the subject and description.\n\nSubject: {$1}\nDescription: {$2}",
          "referenceAttributes": [
            {
              "$ref": "#/columns/records",
              "columnName": "{{objectApiName}} Records",
              "columnType": "OBJECT",
              "fieldName": "Subject"
            },
            {
              "$ref": "#/columns/records",
              "columnName": "{{objectApiName}} Records",
              "columnType": "OBJECT",
              "fieldName": "Description"
            }
          ],
          "responseFormat": {
            "type": "SINGLE_SELECT",
            "options": [
              {"label": "Positive", "value": "positive"},
              {"label": "Negative", "value": "negative"},
              {"label": "Neutral", "value": "neutral"}
            ]
          }
        }
      }
    },
    {
      "ref": "classifier-urgency",
      "name": "Urgency",
      "type": "AI",
      "config": {
        "type": "AI",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "mode": "llm",
          "modelConfig": {
            "modelId": "{{model}}",
            "modelName": "{{model}}"
          },
          "instruction": "Assess the urgency level of this support case.\n\nSubject: {$1}\nDescription: {$2}",
          "referenceAttributes": [
            {
              "$ref": "#/columns/records",
              "columnName": "{{objectApiName}} Records",
              "columnType": "OBJECT",
              "fieldName": "Subject"
            },
            {
              "$ref": "#/columns/records",
              "columnName": "{{objectApiName}} Records",
              "columnType": "OBJECT",
              "fieldName": "Description"
            }
          ],
          "responseFormat": {
            "type": "SINGLE_SELECT",
            "options": [
              {"label": "Critical", "value": "critical"},
              {"label": "High", "value": "high"},
              {"label": "Medium", "value": "medium"},
              {"label": "Low", "value": "low"}
            ]
          }
        }
      }
    },
    {
      "ref": "classifier-category",
      "name": "Category",
      "type": "AI",
      "config": {
        "type": "AI",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "mode": "llm",
          "modelConfig": {
            "modelId": "{{model}}",
            "modelName": "{{model}}"
          },
          "instruction": "Categorize this support case into the most appropriate department.\n\nSubject: {$1}\nDescription: {$2}",
          "referenceAttributes": [
            {
              "$ref": "#/columns/records",
              "columnName": "{{objectApiName}} Records",
              "columnType": "OBJECT",
              "fieldName": "Subject"
            },
            {
              "$ref": "#/columns/records",
              "columnName": "{{objectApiName}} Records",
              "columnType": "OBJECT",
              "fieldName": "Description"
            }
          ],
          "responseFormat": {
            "type": "SINGLE_SELECT",
            "options": [
              {"label": "Billing", "value": "billing"},
              {"label": "Technical Support", "value": "technical"},
              {"label": "Account Management", "value": "account"},
              {"label": "Product Feedback", "value": "product"},
              {"label": "Sales", "value": "sales"}
            ]
          }
        }
      }
    },
    {
      "ref": "formula-agreement",
      "name": "Agreement Score",
      "type": "Formula",
      "config": {
        "type": "Formula",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "formula": "IF(AND(NOT(ISBLANK({$1})), NOT(ISBLANK({$2})), NOT(ISBLANK({$3}))), 'all_classified', IF(OR(ISBLANK({$1}), ISBLANK({$2}), ISBLANK({$3})), 'incomplete', 'partial'))",
          "returnType": "string",
          "referenceAttributes": [
            {
              "$ref": "#/columns/classifier-sentiment",
              "columnName": "Sentiment",
              "columnType": "AI"
            },
            {
              "$ref": "#/columns/classifier-urgency",
              "columnName": "Urgency",
              "columnType": "AI"
            },
            {
              "$ref": "#/columns/classifier-category",
              "columnName": "Category",
              "columnType": "AI"
            }
          ]
        }
      }
    }
  ],
  "sampleData": {}
}
```

---

### 4.7 multi-turn-conversation.json

**Purpose:** Test multi-turn agent conversations where the second turn receives the conversation history from the first turn, with evaluation columns to assess both turns.

**Dependency DAG:**

```
  turn1-utterance    turn2-utterance
        |                  |
        v                  |
  turn1-response           |
        |                  |
        +------------------+
        |
        v
  turn2-response
        |
        +-------+
        |       |
        v       v
  eval-coherence eval-completeness
```

```
  turn1-utterance ──> turn1-response ──┐
                                       ├──> turn2-response ──┬──> eval-coherence
  turn2-utterance ─────────────────────┘                     └──> eval-completeness
```

**Parameters:**

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `agentId` | string | yes | -- | Agent definition ID |
| `agentVersion` | string | yes | -- | Agent version ID |
| `numberOfRows` | integer | no | 50 | Row count |

**Complete Template JSON:**

```json
{
  "templateVersion": "1.0.0",
  "name": "multi-turn-conversation",
  "displayName": "Multi-Turn Conversation Test",
  "description": "Test multi-turn agent conversations where the second turn receives conversation history from the first turn, with coherence and completeness evaluations on the final response.",
  "parameters": {
    "agentId": {
      "type": "string",
      "required": true,
      "description": "18-character Agent definition ID (0Xx prefix)."
    },
    "agentVersion": {
      "type": "string",
      "required": true,
      "description": "18-character Agent version ID (0Xy prefix)."
    },
    "numberOfRows": {
      "type": "integer",
      "required": false,
      "default": 50,
      "description": "Number of rows to provision."
    }
  },
  "columns": [
    {
      "ref": "turn1-utterance",
      "name": "Turn 1 Utterance",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "turn2-utterance",
      "name": "Turn 2 Utterance",
      "type": "Text",
      "config": {
        "type": "Text",
        "autoUpdate": true,
        "config": {
          "autoUpdate": true
        }
      }
    },
    {
      "ref": "turn1-response",
      "name": "Turn 1 Response",
      "type": "Agent",
      "config": {
        "type": "Agent",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "agentId": "{{agentId}}",
          "agentVersion": "{{agentVersion}}",
          "utterance": "{$1}",
          "utteranceReferences": [
            {
              "$ref": "#/columns/turn1-utterance",
              "columnName": "Turn 1 Utterance",
              "columnType": "TEXT"
            }
          ]
        }
      }
    },
    {
      "ref": "turn2-response",
      "name": "Turn 2 Response",
      "type": "Agent",
      "config": {
        "type": "Agent",
        "numberOfRows": "{{numberOfRows}}",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "agentId": "{{agentId}}",
          "agentVersion": "{{agentVersion}}",
          "utterance": "{$1}",
          "utteranceReferences": [
            {
              "$ref": "#/columns/turn2-utterance",
              "columnName": "Turn 2 Utterance",
              "columnType": "TEXT"
            }
          ],
          "conversationHistory": {
            "$ref": "#/columns/turn1-response",
            "columnName": "Turn 1 Response",
            "columnType": "AGENT",
            "fieldName": "conversationHistory"
          }
        }
      }
    },
    {
      "ref": "eval-coherence",
      "name": "Turn 2 Coherence",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "COHERENCE",
          "inputColumnReference": {
            "$ref": "#/columns/turn2-response",
            "columnName": "Turn 2 Response",
            "columnType": "AGENT"
          },
          "autoEvaluate": true
        }
      }
    },
    {
      "ref": "eval-completeness",
      "name": "Turn 2 Completeness",
      "type": "Evaluation",
      "config": {
        "type": "Evaluation",
        "queryResponseFormat": {"type": "EACH_ROW"},
        "autoUpdate": true,
        "config": {
          "autoUpdate": true,
          "evaluationType": "COMPLETENESS",
          "inputColumnReference": {
            "$ref": "#/columns/turn2-response",
            "columnName": "Turn 2 Response",
            "columnType": "AGENT"
          },
          "autoEvaluate": true
        }
      }
    }
  ],
  "sampleData": {
    "turn1-utterance": [
      "I need help with my recent order",
      "What subscription plans do you offer?",
      "I am having trouble logging into my account",
      "Can you explain your return policy?",
      "I would like to speak with someone about a billing issue"
    ],
    "turn2-utterance": [
      "The order number is #98765. Can you check its status?",
      "What is the difference between Professional and Enterprise?",
      "I already tried resetting my password but the link expired",
      "My item arrived damaged. How do I start a return?",
      "I was charged twice for my last invoice. Can you fix that?"
    ]
  }
}
```

---

## 5. Template Usage Guide

### 5.1 Discovering Templates

Templates are stored in the `templates/` directory at the project root. Each file is a self-contained JSON document.

**Listing available templates:**

```
templates/
  agent-test-suite.json
  data-enrichment.json
  prompt-evaluation.json
  ab-testing.json
  flow-testing.json
  data-classification.json
  multi-turn-conversation.json
```

The resolver can enumerate templates by scanning this directory. Each template exposes `displayName` and `description` for human-readable listings.

**Programmatic discovery:**

```
listTemplates() -> [
  { name: "agent-test-suite",        displayName: "Agent Test Suite",                  description: "..." },
  { name: "data-enrichment",         displayName: "Data Enrichment Pipeline",          description: "..." },
  { name: "prompt-evaluation",       displayName: "Prompt Template Evaluation",        description: "..." },
  { name: "ab-testing",              displayName: "A/B Agent Testing",                 description: "..." },
  { name: "flow-testing",            displayName: "Flow Testing Pipeline",             description: "..." },
  { name: "data-classification",     displayName: "Multi-Classifier Data Classification", description: "..." },
  { name: "multi-turn-conversation", displayName: "Multi-Turn Conversation Test",      description: "..." }
]
```

### 5.2 Resolving a Template at Creation Time

When a user selects a template, the resolution process is:

1. **Load the template** from `templates/{name}.json`.
2. **Prompt for parameters.** Display each parameter's `description`. Pre-fill with `default` values where available. Validate `required` parameters.
3. **Create the workbook and worksheet** via the Grid API.
4. **Run the resolution algorithm** (Section 3):
   - Topological sort.
   - Create columns one by one, capturing IDs.
   - Resolve `$ref` pointers with real IDs.
   - Paste sample data.
5. **Return the worksheet URL** or ID to the user.

**Example invocation:**

```
resolveTemplate("agent-test-suite", {
  worksheetId: "1W5xx0000004xxxx",
  parameters: {
    agentId: "0XxRM000000abc123",
    agentVersion: "0XyRM000000def456"
  }
})
```

### 5.3 Creating Custom Templates

Users can author their own templates following the schema defined in Section 2. The process is:

1. **Create a new JSON file** in `templates/` with a descriptive slug name.
2. **Define metadata:** `templateVersion`, `name`, `displayName`, `description`.
3. **Define parameters** for any values that should be configurable at resolution time.
4. **Define columns** in logical order:
   - Assign a unique `ref` key to each column.
   - Use `$ref` pointers wherever a column ID dependency exists.
   - Use `{{paramName}}` for user-configurable values.
   - Follow the Grid API's nested `config.config` structure exactly.
   - Use UPPERCASE `columnType` in all ReferenceAttribute objects.
5. **Optionally add `sampleData`** keyed by column `ref` names.
6. **Validate the template** by running it through the resolver in dry-run mode (resolve all `$ref` pointers and `{{params}}` without making API calls).

**Validation checklist for custom templates:**

| Check | Rule |
|-------|------|
| Unique `ref` keys | No two columns share the same `ref` |
| Valid `$ref` targets | Every `$ref` points to a `ref` that exists in the columns array |
| No dependency cycles | Topological sort succeeds |
| Required config fields | Each column type has its mandatory fields (e.g., AI requires `mode`, `modelConfig`, `instruction`, `responseFormat`) |
| Correct `columnType` casing | All `columnType` values in ReferenceAttributes are UPPERCASE |
| Nested config pattern | Every column has `config.type` matching the outer `type`, and a nested `config.config` object |
| Parameter coverage | Every `{{paramName}}` token maps to a key in `parameters` |
| Sample data alignment | Every key in `sampleData` maps to a Text column `ref`; all arrays are the same length |

### 5.4 How Templates Interact with the Grid-Builder Agent

The Claude Code grid-builder agent uses templates as accelerators. The interaction flow is:

```
User: "Create an agent test suite for my Sales Agent"

Agent: 1. Identifies intent -> template: "agent-test-suite"
       2. Checks which parameters are required
       3. Asks user for agentId and agentVersion (required params)
       4. Optionally asks if they want to customize numberOfRows
       5. Creates workbook + worksheet via Grid API
       6. Calls resolveTemplate() with the worksheet ID and parameters
       7. Reports back: "Created worksheet with 8 columns and 5 sample rows"
```

**Agent decision logic for template selection:**

| User Intent | Template |
|-------------|----------|
| "test my agent" / "agent test suite" / "evaluate agent responses" | `agent-test-suite` |
| "enrich records" / "summarize accounts" / "classify contacts" | `data-enrichment` |
| "evaluate my prompt template" / "test prompt quality" | `prompt-evaluation` |
| "compare two agents" / "A/B test" / "compare versions" | `ab-testing` |
| "test my flow" / "test apex action" / "run flow with inputs" | `flow-testing` |
| "classify data" / "multi-classifier" / "categorize records" | `data-classification` |
| "multi-turn test" / "conversation test" / "test follow-up" | `multi-turn-conversation` |

**When the agent should NOT use a template:**

- The user's request does not match any template pattern.
- The user explicitly asks for a custom column layout.
- The user wants to modify an existing worksheet (templates are for creation only).
- The user needs column types or configurations not covered by any template.

In these cases, the agent falls back to manual column-by-column creation using the Grid API directly.

### 5.5 Template Versioning

Templates use semantic versioning in `templateVersion`:

- **Patch** (1.0.x): Fix typos, update sample data, adjust default values.
- **Minor** (1.x.0): Add optional parameters, add columns that do not break existing parameter contracts.
- **Major** (x.0.0): Remove or rename parameters, change column structure, alter dependency graph.

The resolver should check `templateVersion` and warn if it encounters a version newer than it supports.

---

## Appendix A: Template File Inventory

| Filename | Columns | Parameters (required) | Dependencies |
|----------|---------|----------------------|--------------|
| `agent-test-suite.json` | 8 (3 Text, 1 AgentTest, 4 Evaluation) | `agentId`, `agentVersion` | AgentTest -> 3 Text; 4 Eval -> AgentTest + Text |
| `data-enrichment.json` | 5 (1 Object, 2 Reference, 2 AI) | none | AI -> Object; Reference -> Object |
| `prompt-evaluation.json` | 6 (2 Text, 1 PromptTemplate, 3 Evaluation) | `promptTemplateDevName` | PromptTemplate -> 2 Text; 3 Eval -> PromptTemplate |
| `ab-testing.json` | 11 (3 Text, 2 AgentTest, 6 Evaluation) | `agentIdA`, `agentVersionA`, `agentIdB`, `agentVersionB` | 2 AgentTest -> Text; 6 Eval -> AgentTest + Text |
| `flow-testing.json` | 6 (3 Text, 1 InvocableAction, 2 Reference) | `flowApiName` | InvocableAction -> 3 Text; 2 Reference -> InvocableAction |
| `data-classification.json` | 5 (1 Object, 3 AI, 1 Formula) | none | 3 AI -> Object; Formula -> 3 AI |
| `multi-turn-conversation.json` | 6 (2 Text, 2 Agent, 2 Evaluation) | `agentId`, `agentVersion` | Agent1 -> Text1; Agent2 -> Text2 + Agent1; 2 Eval -> Agent2 |

## Appendix B: Grid API Quick Reference (v66.0)

All endpoints are under `/services/data/v66.0/public/grid/`.

| Operation | Method | Path |
|-----------|--------|------|
| Create workbook | POST | `/workbooks` |
| Create worksheet | POST | `/worksheets` |
| Add column | POST | `/worksheets/{wsId}/columns` |
| Get worksheet data | GET | `/worksheets/{wsId}/data` |
| Paste data | POST | `/worksheets/{wsId}/paste` |
| Reprocess column | POST | `/worksheets/{wsId}/columns/{colId}/reprocess` |
| List LLM models | GET | `/llm-models` |
