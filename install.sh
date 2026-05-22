#!/usr/bin/env bash
# ============================================================================
# Agentforce Grid — One-Line Installer
#
# Installs everything needed to use Agentforce Grid with Claude Code:
#   1. Salesforce CLI (sf) — installed automatically if missing
#   2. Grid MCP Server — 65+ tools for Grid workbooks
#   3. Grid Skills — column config, API guidance, agents, commands
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/chintanavs/agentforce-grid-ai-skills/main/install.sh | bash
#   curl -sSL ... | bash -s -- --org my-alias --project-dir ~/my-project
# ============================================================================
set -euo pipefail

SKILLS_REPO="https://github.com/chintanavs/agentforce-grid-ai-skills.git"
MCP_REPO="https://github.com/chintanavs/agentforce-grid-mcp.git"
INSTALL_DIR="$HOME/.agentforce-grid"

# ── Parse flags ─────────────────────────────────────────────────────────────

SKIP_SF=false
SKIP_MCP=false
SKIP_SKILLS=false
ORG_ALIAS=""
PROJECT_DIR=""

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

Install Agentforce Grid skills and MCP server for Claude Code.

Options:
  --project-dir DIR   Also install skills + .mcp.json into a project directory
  --org ALIAS         Set org alias in MCP config (default: uses sf default)
  --skip-sf           Skip Salesforce CLI installation
  --skip-mcp          Skip MCP server installation
  --skip-skills       Skip skills installation
  -h, --help          Show this help message

Examples:
  # Install everything globally
  curl -sSL .../install.sh | bash

  # Install with a specific org and project
  curl -sSL .../install.sh | bash -s -- --org my-org --project-dir ~/my-project

  # Only install skills (already have sf + MCP)
  curl -sSL .../install.sh | bash -s -- --skip-sf --skip-mcp
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-sf)       SKIP_SF=true; shift ;;
        --skip-mcp)      SKIP_MCP=true; shift ;;
        --skip-skills)   SKIP_SKILLS=true; shift ;;
        --org)           ORG_ALIAS="$2"; shift 2 ;;
        --org=*)         ORG_ALIAS="${1#*=}"; shift ;;
        --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
        --project-dir=*) PROJECT_DIR="${1#*=}"; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               shift ;;
    esac
done

# Resolve project dir to absolute path if provided
if [[ -n "$PROJECT_DIR" ]]; then
    mkdir -p "$PROJECT_DIR"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
fi

# ── Colors ──────────────────────────────────────────────────────────────────

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' NC=''
fi

step()    { echo -e "\n${BLUE}${BOLD}[$1/3]${NC} $2"; }
ok()      { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
fail()    { echo -e "  ${RED}✗${NC} $1"; }
info()    { echo -e "  ${DIM}$1${NC}"; }

echo -e "${BOLD}Agentforce Grid Installer${NC}"
echo -e "Skills + MCP + Salesforce CLI — one command setup"
echo ""

# ── Pre-checks ──────────────────────────────────────────────────────────────

if ! command -v git &>/dev/null; then
    fail "git is required but not installed"
    exit 1
fi
ok "git $(git --version | awk '{print $3}')"

if ! command -v node &>/dev/null; then
    fail "node is required. Install Node.js: https://nodejs.org"
    exit 1
fi
ok "node $(node --version)"

if ! command -v npm &>/dev/null && ! command -v brew &>/dev/null; then
    fail "npm or brew is required. Install Node.js first: https://nodejs.org"
    exit 1
fi

if [[ ! -d "$HOME/.claude" ]]; then
    fail "Claude Code not found (~/.claude/ missing)"
    echo "  Install Claude Code first: npm install -g @anthropic-ai/claude-code"
    exit 1
fi
ok "Claude Code found"

# ── Step 1: Salesforce CLI ──────────────────────────────────────────────────

step 1 "Salesforce CLI"

if $SKIP_SF; then
    warn "Skipped (--skip-sf)"
elif command -v sf &>/dev/null; then
    sf_version=$(sf --version 2>/dev/null | head -1)
    ok "Already installed: $sf_version"
else
    echo -e "  Installing Salesforce CLI..."
    if command -v brew &>/dev/null; then
        brew install sf
    elif command -v npm &>/dev/null; then
        npm install -g @salesforce/cli
    else
        fail "Could not install sf CLI — install manually: https://developer.salesforce.com/tools/salesforcecli"
        exit 1
    fi

    if command -v sf &>/dev/null; then
        ok "Installed: $(sf --version 2>/dev/null | head -1)"
    else
        fail "Installation failed — install manually: https://developer.salesforce.com/tools/salesforcecli"
        exit 1
    fi
fi

# ── Step 2: MCP Server ─────────────────────────────────────────────────────

step 2 "Grid MCP Server"

MCP_DIR="$INSTALL_DIR/agentforce-grid-mcp"

if $SKIP_MCP; then
    warn "Skipped (--skip-mcp)"
else
    mkdir -p "$INSTALL_DIR"

    if [[ -d "$MCP_DIR" ]]; then
        info "Updating existing installation..."
        git -C "$MCP_DIR" pull --quiet 2>/dev/null \
            || warn "Could not update MCP repo — using existing version"
    else
        echo -e "  Cloning MCP server..."
        git clone --quiet --depth 1 "$MCP_REPO" "$MCP_DIR"
    fi

    echo -e "  Installing dependencies..."
    if ! (cd "$MCP_DIR" && npm install --silent); then
        fail "npm install failed in $MCP_DIR"
        exit 1
    fi

    echo -e "  Building..."
    if ! (cd "$MCP_DIR" && npm run build --silent); then
        fail "npm run build failed in $MCP_DIR"
        exit 1
    fi

    if [[ -f "$MCP_DIR/dist/index.js" ]]; then
        ok "MCP server built at $MCP_DIR"
    else
        fail "MCP build failed — check $MCP_DIR for errors"
        exit 1
    fi

    # Configure MCP — global settings.json + optional per-project .mcp.json
    # Uses env vars passed to node to avoid shell injection
    configure_mcp() {
        local config_file="$1"
        local merge="$2"  # "merge" to merge into existing, "create" to create new

        if [[ "$merge" == "merge" ]] && [[ -f "$config_file" ]]; then
            if grep -q '"grid-connect"' "$config_file" 2>/dev/null; then
                ok "MCP already configured in $config_file"
                return 0
            fi
            MCP_INDEX="$MCP_DIR/dist/index.js" ORG="$ORG_ALIAS" TARGET="$config_file" \
            node -e '
                const fs = require("fs");
                const settings = JSON.parse(fs.readFileSync(process.env.TARGET, "utf8"));
                if (!settings.mcpServers) settings.mcpServers = {};
                const entry = { command: "node", args: [process.env.MCP_INDEX] };
                if (process.env.ORG) entry.env = { ORG_ALIAS: process.env.ORG };
                settings.mcpServers["grid-connect"] = entry;
                fs.writeFileSync(process.env.TARGET, JSON.stringify(settings, null, 2) + "\n");
            ' && ok "MCP added to $config_file" \
              || warn "Could not write $config_file — add manually (see below)"
        else
            MCP_INDEX="$MCP_DIR/dist/index.js" ORG="$ORG_ALIAS" TARGET="$config_file" \
            node -e '
                const fs = require("fs");
                const entry = { command: "node", args: [process.env.MCP_INDEX] };
                if (process.env.ORG) entry.env = { ORG_ALIAS: process.env.ORG };
                const settings = { mcpServers: { "grid-connect": entry } };
                fs.writeFileSync(process.env.TARGET, JSON.stringify(settings, null, 2) + "\n");
            ' && ok "MCP configured in $config_file" \
              || warn "Could not write $config_file — add manually (see below)"
        fi
    }

    # Global config (always)
    GLOBAL_MCP="$HOME/.claude/settings.json"
    if [[ -f "$GLOBAL_MCP" ]]; then
        configure_mcp "$GLOBAL_MCP" "merge"
    else
        configure_mcp "$GLOBAL_MCP" "create"
    fi

    # Per-project .mcp.json (if --project-dir given)
    if [[ -n "$PROJECT_DIR" ]]; then
        PROJECT_MCP="$PROJECT_DIR/.mcp.json"
        if [[ -f "$PROJECT_MCP" ]]; then
            configure_mcp "$PROJECT_MCP" "merge"
        else
            configure_mcp "$PROJECT_MCP" "create"
        fi
    fi
fi

# ── Step 3: Skills ──────────────────────────────────────────────────────────

step 3 "Grid Skills"

SKILLS_DIR="$INSTALL_DIR/agentforce-grid-ai-skills"

if $SKIP_SKILLS; then
    warn "Skipped (--skip-skills)"
else
    if [[ -d "$SKILLS_DIR" ]]; then
        info "Updating existing installation..."
        git -C "$SKILLS_DIR" pull --quiet 2>/dev/null \
            || warn "Could not update skills repo — using existing version"
    else
        echo -e "  Cloning skills repo..."
        git clone --quiet --depth 1 "$SKILLS_REPO" "$SKILLS_DIR"
    fi

    # Install globally to ~/.claude/skills/
    install_skills() {
        local target="$1/.claude/skills/agentforce-grid"
        mkdir -p "$(dirname "$target")"
        rm -rf "$target"
        if [[ -d "$SKILLS_DIR/.claude-plugin/skills/agentforce-grid" ]]; then
            cp -r "$SKILLS_DIR/.claude-plugin/skills/agentforce-grid" "$target"
        elif [[ -d "$SKILLS_DIR/agentforce-grid" ]]; then
            cp -r "$SKILLS_DIR/agentforce-grid" "$target"
        else
            warn "Could not find skills directory in cloned repo"
            return 1
        fi
        ok "Skills installed to $target"
    }

    # Try plugin install first, fall back to file copy
    if command -v claude &>/dev/null; then
        echo -e "  Installing Claude Code plugin..."
        claude plugin install --plugin-dir "$SKILLS_DIR" 2>/dev/null \
            && ok "Plugin installed" \
            || {
                warn "Plugin install not available — using file-copy method"
                install_skills "$HOME"
            }
    else
        install_skills "$HOME"
    fi

    # Also copy to project dir if specified
    if [[ -n "$PROJECT_DIR" ]]; then
        info "Copying skills to project..."
        install_skills "$PROJECT_DIR"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo -e "${BOLD}What was installed:${NC}"
echo -e "  ${DIM}$INSTALL_DIR/${NC}"
$SKIP_MCP    || echo -e "    agentforce-grid-mcp/        65+ MCP tools for Grid workbooks"
$SKIP_SKILLS || echo -e "    agentforce-grid-ai-skills/  Skills, agents, and commands"
if [[ -n "$PROJECT_DIR" ]]; then
    echo ""
    echo -e "  ${DIM}$PROJECT_DIR/${NC}"
    $SKIP_MCP    || echo -e "    .mcp.json                   MCP server config"
    $SKIP_SKILLS || echo -e "    .claude/skills/             Grid skills"
fi
echo ""

# Check SF auth status
if ! command -v sf &>/dev/null; then
    echo -e "${YELLOW}${BOLD}Next step:${NC} Install Salesforce CLI, then authenticate:"
    echo -e "  brew install sf"
    echo -e "  sf org login web --set-default --instance-url https://YOUR-INSTANCE.salesforce.com/"
else
    org_user=$(sf org display --json 2>/dev/null \
        | node -e '
            let d="";
            process.stdin.on("data",c=>d+=c);
            process.stdin.on("end",()=>{
                try{console.log(JSON.parse(d).result.username)}catch(e){}
            });
        ' 2>/dev/null)
    if [[ -n "$org_user" ]]; then
        echo -e "${BOLD}Connected org:${NC} $org_user"
    else
        echo -e "${YELLOW}${BOLD}Next step:${NC} Authenticate to your Salesforce org:"
        echo -e "  sf org login web --set-default --instance-url https://YOUR-INSTANCE.salesforce.com/"
    fi
fi

echo ""
echo -e "${BOLD}Verify it works:${NC} Open Claude Code and ask:"
echo -e "  ${DIM}\"List my Grid workbooks\"${NC}"
echo ""

# Fallback manual instructions if MCP config failed
if ! $SKIP_MCP && ! grep -q '"grid-connect"' "$HOME/.claude/settings.json" 2>/dev/null; then
    echo -e "${YELLOW}${BOLD}Manual MCP setup needed:${NC}"
    echo -e "Add this to ~/.claude/settings.json:"
    echo ""
    echo '  {'
    echo '    "mcpServers": {'
    echo '      "grid-connect": {'
    echo '        "command": "node",'
    echo "        \"args\": [\"$INSTALL_DIR/agentforce-grid-mcp/dist/index.js\"]"
    echo '      }'
    echo '    }'
    echo '  }'
    echo ""
fi
