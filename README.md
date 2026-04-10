# Agentforce Grid AI Skills

Claude Code skill for the Agentforce Grid (AI Workbench) public Connect API.

## Overview

This skill helps configure Agentforce Grid worksheet columns and provides API guidance for `/services/data/v66.0/public/grid/` endpoints. Agentforce Grid is a spreadsheet-like interface for AI operations in Salesforce, enabling agent testing, data enrichment, prompt batch processing, and more.

## What's New in v66.0

- **Updated API version**: All endpoints now use `/services/data/v66.0/public/grid/`
- **New LLM models**: GPT 5, GPT 4.1/4.1 Mini, GPT 4 Omni Mini, O3, O4 Mini, Claude 4/4.5 Sonnet, Claude 4.5 Haiku, Gemini 2.5 Flash/Flash Lite/Pro, Amazon Nova Lite/Pro (17 models total)
- **Worksheet data response**: Uses `columnData` map (keyed by column ID) instead of cells nested in column objects
- **New endpoints**: `POST /run-worksheet` and `GET /run-worksheet/{jobId}` for running worksheets with specific inputs
- **Removed endpoint**: `PUT /worksheets/{id}/auto-update` no longer available
- **Fixed paste API**: Uses `matrix` field with `[{displayContent: "..."}]` objects
- **Cell updates**: Use `fullContent` (object) for cell updates; `displayContent` is read-only
- **Text column fix**: Empty `config: {}` no longer works - requires nested config with `type`
- **Updated response schemas**: Agent, prompt template, workbook responses simplified
- **Column ordering**: New `precedingColumnId` field for column display order
- **API behavior notes**: `GET /worksheets/{id}/data` is the reliable endpoint for reading state

## Features

- Configure all 12 column types: AI, Agent, AgentTest, Formula, Object, PromptTemplate, Action, InvocableAction, Reference, Text, Evaluation, DataModelObject
- Suggest column combinations for common use cases (agent testing, data enrichment, prompt batch processing, Flow testing)
- Complete API endpoint documentation with verified request/response schemas
- 12 evaluation types for assessing AI output quality
- Multi-turn conversation testing patterns
- 17 active LLM models across OpenAI, Anthropic (via Amazon Bedrock), Google (via Vertex AI), and Amazon providers

## Installation

Copy the `.claude/skills/agentforce-grid` directory to your project's `.claude/skills/` folder.

```bash
# Clone and copy
git clone git@git.soma.salesforce.com:tmcgrath/agentforce-grid-ai-skills.git
cp -r agentforce-grid-ai-skills/.claude/skills/agentforce-grid your-project/.claude/skills/
```

## Usage

The skill is automatically activated when you ask Claude Code about:
- Agentforce Grid / AI Workbench column configuration
- AF Grid API usage
- Agent testing workflows
- Data enrichment patterns
- Prompt template batch processing
- Evaluation types and quality assessment

## Documentation

- [Main Skill Guide](.claude/skills/agentforce-grid/SKILL.md) - Overview, column types, config rules
- [Column Configurations](.claude/skills/agentforce-grid/references/column-configs.md) - Complete JSON configs for all 12 column types
- [Evaluation Types](.claude/skills/agentforce-grid/references/evaluation-types.md) - All 12 evaluation types with examples
- [API Endpoints](.claude/skills/agentforce-grid/references/api-endpoints.md) - Complete endpoint docs with verified schemas
- [Use Case Patterns](.claude/skills/agentforce-grid/references/use-case-patterns.md) - Common workflows with step-by-step examples
- [Testing Guide](docs/TESTING.md) - API testing procedures with live environment details

## Skill Structure

```
.claude/skills/agentforce-grid/
  SKILL.md                          # Main skill file (loaded by Claude Code)
  references/
    api-endpoints.md                # Complete API endpoint documentation
    column-configs.md               # JSON configs for all 12 column types
    evaluation-types.md             # 12 evaluation types with examples
    use-case-patterns.md            # Common workflow patterns
docs/
  TESTING.md                        # API testing guide with live environment
```
