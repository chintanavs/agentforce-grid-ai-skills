---
name: grid-models
description: "List available LLM models in the Salesforce org for use in AI and PromptTemplate columns. Use when the user asks what models are available or needs a model name for configuration."
---

# /grid-models

## Purpose

List all available LLM models that can be used in AI and PromptTemplate column configurations.

## Behavior

1. Call `get_llm_models` MCP tool (GET /llm-models endpoint).
2. Display as a table:

| Model Name | Label | Max Tokens | Status |
|------------|-------|------------|--------|
| sfdc_ai__DefaultGPT4Omni | GPT 4 Omni | 16384 | Active |
| sfdc_ai__DefaultGPT41 | GPT 4.1 | 32768 | Active |
| sfdc_ai__DefaultBedrockAnthropicClaude4Sonnet | Claude Sonnet 4 on Amazon | 8192 | Active |
| sfdc_ai__DefaultVertexAIGemini25Flash001 | Google Gemini 2.5 Flash | 65536 | Active |

3. Indicate which models are recommended (high-capability, active).
4. Remind the user that `modelConfig` requires the model `name` for BOTH `modelId` and `modelName` fields:

```json
"modelConfig": {
  "modelId": "sfdc_ai__DefaultGPT4Omni",
  "modelName": "sfdc_ai__DefaultGPT4Omni"
}
```
