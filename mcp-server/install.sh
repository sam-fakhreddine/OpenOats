#!/bin/bash
# Install OpenOats MCP Server
# Usage: ./install.sh [path-to-claude-config]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MCP_SERVER_DIR="${REPO_ROOT}/mcp-server"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INSTALL]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check prerequisites
check_prereqs() {
    log "Checking prerequisites..."
    
    if ! command -v node &> /dev/null; then
        echo "Error: Node.js not found. Please install Node.js 18+."
        exit 1
    fi
    
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        echo "Error: Node.js version $NODE_VERSION found, but 18+ required."
        exit 1
    fi
    
    log "✓ Node.js $(node --version)"
}

# Build server
build_server() {
    log "Building MCP server..."
    
    cd "$MCP_SERVER_DIR"
    
    if [ ! -d "node_modules" ]; then
        log "Installing dependencies..."
        npm install
    fi
    
    log "Compiling TypeScript..."
    npm run build
    
    log "✓ Build complete"
}

# Install to Claude Code
install_claude() {
    local config_path="${1:-$HOME/.config/claude/config.json}"
    
    log "Installing to Claude Code..."
    log "Config path: $config_path"
    
    # Ensure config directory exists
    mkdir -p "$(dirname "$config_path")"
    
    # Read existing config or create new
    if [ -f "$config_path" ]; then
        info "Updating existing Claude config..."
        # Use node to safely modify JSON
        node -e "
            const fs = require('fs');
            const path = '$config_path';
            let config = {};
            
            try {
                config = JSON.parse(fs.readFileSync(path, 'utf8'));
            } catch (e) {
                // File doesn't exist or is empty
            }
            
            if (!config.mcpServers) config.mcpServers = {};
            
            config.mcpServers.openoats = {
                command: 'node',
                args: ['${MCP_SERVER_DIR}/dist/index.js'],
                env: {
                    OPENOATS_REPO_ROOT: '${REPO_ROOT}'
                },
                description: 'OpenOats TDD orchestration server'
            };
            
            fs.writeFileSync(path, JSON.stringify(config, null, 2));
            console.log('Config updated successfully');
        "
    else
        info "Creating new Claude config..."
        cat > "$config_path" <<EOF
{
  "mcpServers": {
    "openoats": {
      "command": "node",
      "args": ["${MCP_SERVER_DIR}/dist/index.js"],
      "env": {
        "OPENOATS_REPO_ROOT": "${REPO_ROOT}"
      },
      "description": "OpenOats TDD orchestration server"
    }
  }
}
EOF
    fi
    
    log "✓ Installed to Claude Code config"
}

# Install to Cursor
install_cursor() {
    log "Installing to Cursor..."
    
    local cursor_config="$HOME/.cursor/mcp.json"
    mkdir -p "$(dirname "$cursor_config")"
    
    cat > "$cursor_config" <<EOF
{
  "mcpServers": {
    "openoats": {
      "command": "node",
      "args": ["${MCP_SERVER_DIR}/dist/index.js"],
      "env": {
        "OPENOATS_REPO_ROOT": "${REPO_ROOT}"
      }
    }
  }
}
EOF
    
    log "✓ Installed to Cursor config"
}

# Print usage examples
print_usage() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Installation Complete!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "The MCP server is now configured. You can use:"
    echo ""
    echo "  1. generate_prompt - Build phase-specific prompts"
    echo "     Example: generate_prompt(phase='RED', task_id='TASK-015')"
    echo ""
    echo "  2. get_task_info - Read task specifications"
    echo "     Example: get_task_info(epic='swift6-compliance', task_id='TASK-015')"
    echo ""
    echo "  3. list_components - See available Lego pieces"
    echo "     Example: list_components(type='skills')"
    echo ""
    echo "Resources available:"
    echo "  - prompts://master (The One Prompt)"
    echo "  - prompts://components/{type}/{id} (Lego pieces)"
    echo "  - tasks://{epic}/{task_id} (Task specs)"
    echo ""
    echo "Prompts available:"
    echo "  - tdd_red (Write failing tests)"
    echo "  - tdd_green (Minimal implementation)"
    echo "  - tdd_refactor (Optimize and clean)"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# Main
main() {
    log "Installing OpenOats MCP Server..."
    log "Repository: $REPO_ROOT"
    
    check_prereqs
    build_server
    
    # Install to available tools
    if command -v claude &> /dev/null || [ -d "$HOME/.config/claude" ]; then
        install_claude "$1"
    fi
    
    if command -v cursor &> /dev/null || [ -d "$HOME/.cursor" ]; then
        install_cursor
    fi
    
    print_usage
    
    log "Done! Restart your AI tool to load the MCP server."
}

# Handle arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [claude-config-path]"
        echo ""
        echo "Installs the OpenOats MCP Server to your AI tools."
        echo ""
        echo "Arguments:"
        echo "  claude-config-path    Path to Claude Code config (default: ~/.config/claude/config.json)"
        echo ""
        echo "Options:"
        echo "  --help, -h           Show this help"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac