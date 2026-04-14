#!/bin/bash
# ============================================================================
# Agentforce Grid — One-Line Installer
#
# Installs everything needed to use Agentforce Grid with Claude Code:
#   1. Salesforce CLI (sf) — if not already installed
#   2. Grid MCP Server — 65+ tools for Grid workbooks
#   3. Grid Skills Plugin — column config, API guidance, agents, commands
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/chintanavs/agentforce-grid-ai-skills/main/install.sh | bash
#
# Options:
#   --skip-sf      Skip Salesforce CLI installation
#   --skip-mcp     Skip MCP server installation
#   --skip-skills  Skip skills/plugin installation
#   --org ALIAS    Set default org alias for MCP config (default: uses sf default)
# ============================================================================
set -euo pipefail

SKILLS_REPO="https://github.com/chintanavs/agentforce-grid-ai-skills.git"
MCP_REPO="https://github.com/chintanavs/agentforce-grid-mcp.git"
INSTALL_DIR="$HOME/.agentforce-grid"

# Parse flags
SKIP_SF=false
SKIP_MCP=false
SKIP_SKILLS=false
ORG_ALIAS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-sf)      SKIP_SF=true; shift ;;
        --skip-mcp)     SKIP_MCP=true; shift ;;
        --skip-skills)  SKIP_SKILLS=true; shift ;;
        --org)          ORG_ALIAS="$2"; shift 2 ;;
        --org=*)        ORG_ALIAS="${1#*=}"; shift ;;
        *)              shift ;;
    esac
done

# Colors (only if terminal supports it)
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

# Need git
if ! command -v git &>/dev/null; then
    fail "git is required but not installed"
    exit 1
fi

# Need npm (for MCP build and sf CLI install)
if ! command -v npm &>/dev/null && ! command -v brew &>/dev/null; then
    fail "npm or brew is required. Install Node.js first: https://nodejs.org"
    exit 1
fi

# Need Claude Code
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
        brew install sf 2>/dev/null
    elif command -v npm &>/dev/null; then
        npm install -g @salesforce/cli 2>/dev/null
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
        git -C "$MCP_DIR" pull --quiet 2>/dev/null || true
    else
        echo -e "  Cloning MCP server..."
        git clone --quiet "$MCP_REPO" "$MCP_DIR"
    fi

    echo -e "  Installing dependencies..."
    (cd "$MCP_DIR" && npm install --silent 2>/dev/null)

    echo -e "  Building..."
    (cd "$MCP_DIR" && npm run build --silent 2>/dev/null)

    if [[ -f "$MCP_DIR/dist/index.js" ]]; then
        ok "MCP server built at $MCP_DIR"
    else
        fail "MCP build failed — check $MCP_DIR for errors"
        exit 1
    fi

    # Configure MCP in Claude Code settings
    MCP_CONFIG="$HOME/.claude/settings.json"
    MCP_ENTRY_ARGS="[\"$MCP_DIR/dist/index.js\"]"

    if [[ -n "$ORG_ALIAS" ]]; then
        MCP_ENV=", \"env\": {\"ORG_ALIAS\": \"$ORG_ALIAS\"}"
    else
        MCP_ENV=""
    fi

    # Build the MCP server config JSON
    MCP_SERVER_JSON="{\"command\": \"node\", \"args\": $MCP_ENTRY_ARGS$MCP_ENV}"

    if [[ -f "$MCP_CONFIG" ]]; then
        # Check if grid-connect already configured
        if grep -q '"grid-connect"' "$MCP_CONFIG" 2>/dev/null; then
            ok "MCP already configured in Claude Code settings"
        else
            # Add grid-connect to existing settings using node for safe JSON manipulation
            node -e "
                const fs = require('fs');
                const settings = JSON.parse(fs.readFileSync('$MCP_CONFIG', 'utf8'));
                if (!settings.mcpServers) settings.mcpServers = {};
                settings.mcpServers['grid-connect'] = $MCP_SERVER_JSON;
                fs.writeFileSync('$MCP_CONFIG', JSON.stringify(settings, null, 2) + '\n');
            " 2>/dev/null && ok "MCP added to Claude Code settings" || warn "Could not auto-configure MCP — add manually (see below)"
        fi
    else
        # Create new settings file
        node -e "
            const fs = require('fs');
            const settings = { mcpServers: { 'grid-connect': $MCP_SERVER_JSON } };
            fs.writeFileSync('$MCP_CONFIG', JSON.stringify(settings, null, 2) + '\n');
        " 2>/dev/null && ok "MCP configured in Claude Code settings" || warn "Could not create settings — add manually (see below)"
    fi
fi

# ── Step 3: Skills Plugin ──────────────────────────────────────────────────

step 3 "Grid Skills Plugin"

SKILLS_DIR="$INSTALL_DIR/agentforce-grid-ai-skills"

if $SKIP_SKILLS; then
    warn "Skipped (--skip-skills)"
else
    if [[ -d "$SKILLS_DIR" ]]; then
        info "Updating existing installation..."
        git -C "$SKILLS_DIR" pull --quiet 2>/dev/null || true
    else
        echo -e "  Cloning skills repo..."
        git clone --quiet "$SKILLS_REPO" "$SKILLS_DIR"
    fi

    # Install as Claude Code plugin
    if command -v claude &>/dev/null; then
        echo -e "  Installing Claude Code plugin..."
        claude plugin install --plugin-dir "$SKILLS_DIR" 2>/dev/null \
            && ok "Plugin installed" \
            || {
                # Fallback: file-copy install
                warn "Plugin install not available — using file-copy method"
                CLAUDE_SKILLS="$HOME/.claude/skills/agentforce-grid"
                mkdir -p "$HOME/.claude/skills"
                rm -rf "$CLAUDE_SKILLS"
                cp -r "$SKILLS_DIR/agentforce-grid" "$CLAUDE_SKILLS"
                ok "Skills copied to $CLAUDE_SKILLS"
            }
    else
        # File-copy fallback
        CLAUDE_SKILLS="$HOME/.claude/skills/agentforce-grid"
        mkdir -p "$HOME/.claude/skills"
        rm -rf "$CLAUDE_SKILLS"
        cp -r "$SKILLS_DIR/agentforce-grid" "$CLAUDE_SKILLS"
        ok "Skills copied to $CLAUDE_SKILLS"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo -e "${BOLD}What was installed:${NC}"
echo -e "  ${DIM}$INSTALL_DIR/${NC}"
echo -e "    agentforce-grid-mcp/     65+ MCP tools for Grid workbooks"
echo -e "    agentforce-grid-ai-skills/  Skills, agents, and commands"
echo ""

# Check if user needs to authenticate
if ! command -v sf &>/dev/null; then
    echo -e "${YELLOW}${BOLD}Next step:${NC} Install Salesforce CLI, then authenticate:"
    echo -e "  brew install sf"
    echo -e "  sf org login web --set-default --instance-url https://YOUR-INSTANCE.salesforce.com/"
elif ! sf org display 2>/dev/null | grep -q "Username" 2>/dev/null; then
    echo -e "${YELLOW}${BOLD}Next step:${NC} Authenticate to your Salesforce org:"
    echo -e "  sf org login web --set-default --instance-url https://YOUR-INSTANCE.salesforce.com/"
else
    org_user=$(sf org display 2>/dev/null | grep "Username" | awk '{print $2}')
    echo -e "${BOLD}Connected org:${NC} $org_user"
fi

echo ""
echo -e "${BOLD}Verify it works:${NC} Open Claude Code and ask:"
echo -e "  ${DIM}\"List my Grid workbooks\"${NC}"
echo ""

if ! $SKIP_MCP && ! grep -q '"grid-connect"' "$HOME/.claude/settings.json" 2>/dev/null; then
    echo -e "${YELLOW}${BOLD}Manual MCP setup needed:${NC}"
    echo -e "Add this to ~/.claude/settings.json:"
    echo ""
    echo '  {'
    echo '    "mcpServers": {'
    echo '      "grid-connect": {'
    echo '        "command": "node",'
    echo "        \"args\": [\"$MCP_DIR/dist/index.js\"]"
    echo '      }'
    echo '    }'
    echo '  }'
    echo ""
fi
