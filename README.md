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

## Quick Install

One command installs everything — Salesforce CLI, MCP server (65+ tools), and Grid skills:

```bash
curl -sSL https://raw.githubusercontent.com/chintanavs/agentforce-grid-ai-skills/main/install.sh | bash
```

Then authenticate to your org:

```bash
sf org login web --set-default --instance-url https://your-instance.salesforce.com/
```

Verify: open Claude Code and ask *"List my Grid workbooks"*.

### Options

```bash
# Target a specific org
curl -sSL ... | bash -s -- --org my-org-alias

# Skip components you already have
curl -sSL ... | bash -s -- --skip-sf        # already have sf CLI
curl -sSL ... | bash -s -- --skip-mcp       # only want skills
curl -sSL ... | bash -s -- --skip-skills    # only want MCP
```

### Manual Installation

<details>
<summary>Step-by-step if you prefer not to use the installer</summary>

**1. Salesforce CLI**

```bash
brew install sf
sf org login web --set-default --instance-url https://your-instance.salesforce.com/
```

**2. MCP Server**

```bash
git clone https://github.com/chintanavs/agentforce-grid-mcp.git
cd agentforce-grid-mcp && npm install && npm run build
```

Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "grid-connect": {
      "command": "node",
      "args": ["/path/to/agentforce-grid-mcp/dist/index.js"]
    }
  }
}
```

**3. Skills**

```bash
git clone https://github.com/chintanavs/agentforce-grid-ai-skills.git
cp -r agentforce-grid-ai-skills/agentforce-grid your-project/.claude/skills/
```

</details>

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
