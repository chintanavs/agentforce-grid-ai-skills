# Agentforce Grid API Testing Guide

## Test Environment

### Authentication Setup

Before running tests, authenticate with SF CLI:

```bash
sf org login web --alias test-org --instance-url https://your-org.salesforce.com/
export SF_ORG_ALIAS=test-org
```

### Making API Calls with SF CLI

Instead of curl with Bearer tokens, use `sf api request`:

```bash
# List workbooks
sf api request rest /services/data/v66.0/public/grid/workbooks \
  --method GET \
  --target-org $SF_ORG_ALIAS

# Create workbook
sf api request rest /services/data/v66.0/public/grid/workbooks \
  --method POST \
  --target-org $SF_ORG_ALIAS \
  --body '{"name": "My Workbook"}'
```

### Base URL

```
https://orgfarm-9105f0ef69.my.salesforce-com.434jkw26uv5j1l0o5mqn1ijk.aa.crm.dev:6101/services/data/v66.0/public/grid
```

### Web UI Access

- URL: `https://login.salesforce-com.434jkw26uv5j1l0o5mqn1ijk.aa.crm.dev:6101/`
- Username: `epic.out.7dc4679a6ee8@orgfarm.salesforce.com`
- Password: `orgfarm1234`

## API Validation Results

### Verified Endpoints (v66.0)

| Endpoint | Method | Status | Notes |
|----------|--------|--------|-------|
| `/workbooks` | GET | Working | Returns `{workbooks: [{id, name, aiWorksheetList}]}` |
| `/workbooks` | POST | Working | Request: `{name}`, Response: `{id, name, aiWorksheetList}` |
| `/workbooks/{id}` | GET | Working | Returns workbook with worksheets list |
| `/workbooks/{id}` | DELETE | Working | Returns 204 |
| `/worksheets` | POST | Working | Request: `{name, workbookId}`, Response includes `cells, columns, rows` |
| `/worksheets/{id}` | GET | Partial | May return empty columns/cells - use `/data` instead |
| `/worksheets/{id}/data` | GET | Working | **Recommended** - returns full state with all cells |
| `/worksheets/{id}/columns` | POST | Working | Requires nested config with `type` field |
| `/worksheets/{id}/paste` | POST | Working | Uses `matrix` field (NOT `data`) |
| `/worksheets/{id}/trigger-row-execution` | POST | Tested | May fail with IO exception on some orgs |
| `/column-types` | GET | Working | Returns all 12 column types |
| `/evaluation-types` | GET | Working | Returns all 12 evaluation types with metadata |
| `/llm-models` | GET | Working | Returns models with `name, label, maxContentLength, encodingType` |
| `/agents` | GET | Working | Returns `{agents: [{id, name, activeVersion}]}` |
| `/prompt-templates` | GET | Working | Returns `{templates: [{id, developerName, name}]}` |
| `/sobjects` | GET | Working | Returns `{sobjects: [{apiName, label, pluralLabel}]}` |

### Key Schema Changes from v64.0

1. **Workbook response**: Simplified to `{id, name, aiWorksheetList}` (removed `createdById`, `createdByName`, `createdDate`, `lastModifiedDate`)

2. **Worksheet creation response**: Now includes `{id, name, workbookId, cells, columns, rows}` (empty arrays on creation)

3. **Column response**: Now includes `precedingColumnId` and `worksheetId` fields

4. **Agent response**: Changed from `{agentId, versions: [{versionId}]}` to `{id, name, activeVersion}`

5. **Prompt template response**: Changed to `{id, developerName, name}` (removed `label`, `type`)

6. **LLM models response**: Changed from `{modelId, modelName}` to `{name, label, maxContentLength, encodingType}`

7. **Paste API**: Field changed from `data` (string arrays) to `matrix` (object arrays with `displayContent`)

8. **Text column config**: Cannot use empty `config: {}` - requires `{type: "Text", autoUpdate: true, config: {autoUpdate: true}}`

9. **SObjects response**: Now returns `{sobjects: [{apiName, label, pluralLabel}]}`

## E2E Test Procedure

### Complete Workflow Test

```bash
# Set token
TOKEN="your-jwt-token"
BASE="https://orgfarm-9105f0ef69.my.salesforce-com.434jkw26uv5j1l0o5mqn1ijk.aa.crm.dev:6101/services/data/v66.0/public/grid"

# 1. Create workbook
sf api request rest ENDPOINT --method POST --target-org $SF_ORG_ALIAS \
  "/services/data/v66.0/public/grid/workbooks" -d '{"name": "Test Workbook"}'
# Save the workbook ID from response

# 2. Create worksheet
sf api request rest ENDPOINT --method POST --target-org $SF_ORG_ALIAS \
  "/services/data/v66.0/public/grid/worksheets" -d '{"name": "Test Sheet", "workbookId": "WORKBOOK_ID"}'
# Save the worksheet ID from response

# 3. Add Text column (MUST use nested config)
sf api request rest ENDPOINT --method POST --target-org $SF_ORG_ALIAS \
  "/services/data/v66.0/public/grid/worksheets/WORKSHEET_ID/columns" -d '{
    "name": "Input",
    "type": "Text",
    "config": {"type": "Text", "autoUpdate": true, "config": {"autoUpdate": true}}
  }'

# 4. Get worksheet data to find column ID and row IDs
sf api request rest ENDPOINT --method GET --target-org $SF_ORG_ALIAS "/services/data/v66.0/public/grid/worksheets/WORKSHEET_ID/data"

# 5. Paste data (uses matrix field with displayContent objects)
sf api request rest ENDPOINT --method POST --target-org $SF_ORG_ALIAS \
  "/services/data/v66.0/public/grid/worksheets/WORKSHEET_ID/paste" -d '{
    "startColumnId": "COLUMN_ID",
    "startRowId": "FIRST_ROW_ID",
    "matrix": [
      [{"displayContent": "Test row 1"}],
      [{"displayContent": "Test row 2"}],
      [{"displayContent": "Test row 3"}]
    ]
  }'

# 6. Verify data was pasted
sf api request rest ENDPOINT --method GET --target-org $SF_ORG_ALIAS "/services/data/v66.0/public/grid/worksheets/WORKSHEET_ID/data"

# 7. Add AI column referencing the Text column
sf api request rest ENDPOINT --method POST --target-org $SF_ORG_ALIAS \
  "/services/data/v66.0/public/grid/worksheets/WORKSHEET_ID/columns" -d '{
    "name": "AI Output",
    "type": "AI",
    "config": {
      "type": "AI",
      "queryResponseFormat": {"type": "EACH_ROW"},
      "autoUpdate": true,
      "config": {
        "autoUpdate": true,
        "mode": "llm",
        "modelConfig": {
          "modelId": "sfdc_ai__DefaultGPT4Omni",
          "modelName": "sfdc_ai__DefaultGPT4Omni"
        },
        "instruction": "Respond to: {$1}",
        "referenceAttributes": [
          {"columnId": "TEXT_COLUMN_ID", "columnName": "Input", "columnType": "TEXT"}
        ],
        "responseFormat": {"type": "PLAIN_TEXT", "options": []}
      }
    }
  }'

# 8. Poll for completion
sf api request rest ENDPOINT --method GET --target-org $SF_ORG_ALIAS "/services/data/v66.0/public/grid/worksheets/WORKSHEET_ID/data"

# 9. Clean up
sf api request rest ENDPOINT --method DELETE --target-org $SF_ORG_ALIAS "/services/data/v66.0/public/grid/workbooks/WORKBOOK_ID"
```

## Available LLM Models

As of v66.0, the following active models are available:

| Model Name | Label | Max Tokens |
|------------|-------|------------|
| `sfdc_ai__DefaultGPT41` | GPT 4.1 | 32768 |
| `sfdc_ai__DefaultGPT41Mini` | GPT 4.1 Mini | 32768 |
| `sfdc_ai__DefaultGPT4Omni` | GPT 4 Omni | 16384 |
| `sfdc_ai__DefaultGPT4OmniMini` | GPT 4 Omni Mini | 16384 |
| `sfdc_ai__DefaultGPT5` | GPT 5 | 128000 |
| `sfdc_ai__DefaultGPT5Mini` | GPT 5 Mini | 128000 |
| `sfdc_ai__DefaultO3` | O3 | 100000 |
| `sfdc_ai__DefaultO4Mini` | O4 Mini | 100000 |
| `sfdc_ai__DefaultBedrockAnthropicClaude37Sonnet` | Claude 3.7 Sonnet | 8192 |
| `sfdc_ai__DefaultBedrockAnthropicClaude3Haiku` | Claude 3 Haiku | 4096 |
| `sfdc_ai__DefaultBedrockAnthropicClaude45Haiku` | Claude 4.5 Haiku | 8192 |
| `sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet` | Claude 4.5 Sonnet | 8192 |
| `sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet` | Claude 4 Sonnet | 8192 |
| `sfdc_ai__DefaultBedrockAmazonNovaLite` | Amazon Nova Lite | 5000 |
| `sfdc_ai__DefaultBedrockAmazonNovaPro` | Amazon Nova Pro | 5000 |
| `sfdc_ai__DefaultVertexAIGemini20Flash001` | Gemini 2.0 Flash | 8192 |
| `sfdc_ai__DefaultVertexAIGemini20FlashLite001` | Gemini 2.0 Flash Lite | 8192 |
| `sfdc_ai__DefaultVertexAIGemini25Flash001` | Gemini 2.5 Flash | 65536 |
| `sfdc_ai__DefaultVertexAIGemini25FlashLite001` | Gemini 2.5 Flash Lite | 65536 |
| `sfdc_ai__DefaultVertexAIGeminiPro25` | Gemini 2.5 Pro | 65536 |
| `sfdc_ai__DefaultOpenAIGPT4OmniMini` | OpenAI GPT 4 Omni Mini | 16384 |

## Available Column Types

All 12 column types remain the same in v66.0:
- AI, FORMULA, OBJECT, AGENT, PROMPT_TEMPLATE, ACTION, REFERENCE, TEXT, EVALUATION, DATA_MODEL_OBJECT, INVOCABLE_ACTION, AGENT_TEST
