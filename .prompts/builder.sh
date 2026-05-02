#!/usr/bin/env bash
#
# Prompt Builder - Assembles prompts from composable fragments
# Usage: ./builder.sh assemble --spec <spec.json> --vars key=value,...
#

set -euo pipefail

PROMPTS_DIR="${PROMPTS_DIR:-$(dirname "$0")}"
COMPONENTS_DIR="${PROMPTS_DIR}/components"
TEMPLATES_DIR="${PROMPTS_DIR}/templates"
GENERATED_DIR="${PROMPTS_DIR}/generated"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[BUILDER]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Load a YAML fragment and convert to env vars
load_fragment() {
    local fragment_id="$1"
    local fragment_type="$2"
    local fragment_path="${COMPONENTS_DIR}/${fragment_type}/${fragment_id}.yaml"
    
    if [[ ! -f "$fragment_path" ]]; then
        error "Fragment not found: ${fragment_path}"
    fi
    
    # Simple YAML parsing - extract key: value pairs
    # In production, use yq or a proper YAML parser
    cat "$fragment_path" | grep -E "^[a-zA-Z]" | sed 's/: /=/g' | sed 's/^/FRAG_/'
}

# Resolve fragment references in assembly spec
resolve_fragments() {
    local spec_file="$1"
    local output_dir="$2"
    
    log "Resolving fragments from ${spec_file}"
    
    # Extract fragment IDs from JSON (using grep/sed for simplicity)
    # In production, use jq
    local fragments=$(cat "$spec_file" | grep '"id":' | sed 's/.*"id": "\([^"]*\)".*/\1/')
    
    for frag_id in $fragments; do
        log "Loading fragment: ${frag_id}"
        
        # Determine fragment type from directory structure
        local frag_type=$(find "$COMPONENTS_DIR" -name "${frag_id}.yaml" -exec dirname {} \; | xargs basename)
        
        if [[ -z "$frag_type" ]]; then
            error "Fragment ${frag_id} not found in any component directory"
        fi
        
        # Export fragment content as environment variables
        eval $(load_fragment "$frag_id" "$frag_type")
    done
}

# Substitute variables into template
substitute_template() {
    local template_file="$1"
    local output_file="$2"
    shift 2
    
    log "Substituting variables into template"
    
    # Start with template content
    cp "$template_file" "$output_file"
    
    # Replace variables ({{variable}} syntax)
    for var in "$@"; do
        local key=$(echo "$var" | cut -d= -f1)
        local value=$(echo "$var" | cut -d= -f2-)
        sed -i.bak "s|{{${key}}}|${value}|g" "$output_file"
    done
    
    rm -f "${output_file}.bak"
}

# Assemble command
assemble() {
    local spec_file=""
    local vars=""
    local output_file=""
    local validate=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --spec)
                spec_file="$2"
                shift 2
                ;;
            --vars)
                vars="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --validate)
                validate=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    if [[ -z "$spec_file" ]]; then
        error "Missing required --spec argument"
    fi
    
    if [[ ! -f "$spec_file" ]]; then
        error "Spec file not found: ${spec_file}"
    fi
    
    # Generate output filename if not provided
    if [[ -z "$output_file" ]]; then
        local spec_name=$(basename "$spec_file" .json)
        output_file="${GENERATED_DIR}/${spec_name}.md"
    fi
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")"
    
    log "Assembling prompt from spec: ${spec_file}"
    log "Output will be: ${output_file}"
    
    # Resolve fragments
    resolve_fragments "$spec_file" "$GENERATED_DIR"
    
    # Get template from spec
    local template_name=$(cat "$spec_file" | grep '"template"' | sed 's/.*"template": "\([^"]*\)".*/\1/')
    local template_file="${TEMPLATES_DIR}/${template_name}.md"
    
    if [[ ! -f "$template_file" ]]; then
        error "Template not found: ${template_file}"
    fi
    
    # Convert vars string to array
    IFS=',' read -ra var_array <<< "$vars"
    
    # Build final prompt
    substitute_template "$template_file" "$output_file" "${var_array[@]}"
    
    log "Prompt assembled successfully: ${output_file}"
    
    # Validate if requested
    if [[ "$validate" == true ]]; then
        log "Validating output against schema..."
        # In production, use a JSON schema validator
        # For now, just check for required placeholders
        if grep -q '{{.*}}' "$output_file"; then
            warn "Unresolved placeholders found in output"
        else
            log "Validation passed"
        fi
    fi
    
    echo "$output_file"
}

# List available fragments
list_fragments() {
    log "Available fragments:"
    
    for type_dir in "$COMPONENTS_DIR"/*; do
        if [[ -d "$type_dir" ]]; then
            local type=$(basename "$type_dir")
            echo "  ${type}:"
            for frag in "$type_dir"/*.yaml; do
                if [[ -f "$frag" ]]; then
                    local id=$(basename "$frag" .yaml)
                    local version=$(grep "^version:" "$frag" | sed 's/version: //')
                    echo "    - ${id} (${version})"
                fi
            done
        fi
    done
}

# Show help
show_help() {
    cat <<EOF
Prompt Builder - Assemble prompts from composable fragments

Usage:
  $(basename "$0") <command> [options]

Commands:
  assemble    Assemble a prompt from a spec file
  list        List available fragments
  help        Show this help message

Assemble Options:
  --spec <file>      Path to assembly spec JSON file (required)
  --vars <k=v,...>   Comma-separated key=value variables
  --output <file>    Output file path (default: auto-generated)
  --validate         Validate output against schema

Examples:
  # Assemble RED agent prompt
  $(basename "$0") assemble \\
      --spec .prompts/assembly/tdd-red.json \\
      --vars task_id=TASK-015,correlation_id=run-001 \\
      --output .prompts/generated/task-015-red.md \\
      --validate

  # List all available fragments
  $(basename "$0") list

Environment:
  PROMPTS_DIR    Base directory for prompts (default: script location)
EOF
}

# Main entry point
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        assemble)
            assemble "$@"
            ;;
        list)
            list_fragments
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: ${command}"
            ;;
    esac
}

main "$@"