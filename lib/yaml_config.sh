#!/usr/bin/env bash
# ============================================================================
# lib/yaml_config.sh — YAML config system with env fallback
#
# Reads config.yml (structured YAML) and exports variables.
# Falls back to config.env for backward compatibility.
#
# Usage:
#   source lib/yaml_config.sh
#   load_config "/path/to/ai-night-shift"
# ============================================================================

load_config() {
    local base_dir="${1:-.}"
    local yaml_file="$base_dir/config.yml"
    local env_file="$base_dir/config.env"

    if [ -f "$yaml_file" ]; then
        _load_yaml_config "$yaml_file"
    elif [ -f "$env_file" ]; then
        # shellcheck source=/dev/null
        source "$env_file"
    fi
}

_load_yaml_config() {
    local file="$1"

    [ -f "$file" ] || return 1

    # Use python for reliable YAML parsing if available
    if command -v python3 &>/dev/null; then
        _load_yaml_python "$file"
        return $?
    fi

    # Fallback: basic line-by-line parser for simple YAML
    _load_yaml_basic "$file"
}

_load_yaml_python() {
    local file="$1"

    # Try PyYAML first, fall back to basic parsing
    eval "$(python3 -c "
import sys

# Try to import yaml, fall back to basic parsing
try:
    import yaml
    with open('$file') as f:
        config = yaml.safe_load(f)
except ImportError:
    # Parse basic YAML without PyYAML
    config = {}
    current_section = None
    with open('$file') as f:
        for line in f:
            line = line.rstrip()
            if not line or line.lstrip().startswith('#'):
                continue
            # Section header
            if not line.startswith(' ') and line.endswith(':'):
                current_section = line[:-1].strip()
                continue
            # Key-value in section
            stripped = line.lstrip()
            if ':' in stripped:
                key, _, value = stripped.partition(':')
                key = key.strip()
                value = value.strip().strip('\"').strip(\"'\")
                if current_section:
                    if current_section not in config:
                        config[current_section] = {}
                    config[current_section][key] = value
                else:
                    config[key] = value

def flatten(d, prefix=''):
    items = []
    for k, v in d.items():
        new_key = f'{prefix}_{k}' if prefix else k
        if isinstance(v, dict):
            items.extend(flatten(v, new_key))
        elif isinstance(v, list):
            items.append((new_key, ','.join(str(x) for x in v)))
        elif isinstance(v, bool):
            items.append((new_key, 'true' if v else 'false'))
        elif v is not None:
            items.append((new_key, str(v)))
    return items

for key, value in flatten(config):
    env_key = key.upper().replace('-', '_')
    # Escape single quotes in value
    safe_value = str(value).replace(\"'\", \"'\\''\")
    print(f\"export {env_key}='{safe_value}'\")
" 2>/dev/null)"
}

_load_yaml_basic() {
    local file="$1"
    local current_section=""

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Section header
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):$ ]] || [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key-value pair
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):\ *(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            local var_name
            if [ -n "$current_section" ]; then
                var_name="${current_section}_${key}"
            else
                var_name="$key"
            fi
            var_name=$(echo "$var_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            export "$var_name=$value"
        fi
    done < "$file"
}

# Generate config.yml from config.env (migration helper)
migrate_env_to_yaml() {
    local env_file="${1:-config.env}"
    local yaml_file="${2:-config.yml}"

    if [ ! -f "$env_file" ]; then
        echo "ERROR: $env_file not found"
        return 1
    fi

    cat > "$yaml_file" << 'HEADER'
# ============================================================================
# AI Night Shift — Configuration (YAML)
# Migrated from config.env
# ============================================================================

HEADER

    echo "general:" >> "$yaml_file"
    grep -E "^(NIGHT_SHIFT_DIR|AGENT_NAME)=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "" >> "$yaml_file"
    echo "agent:" >> "$yaml_file"
    grep -E "^(AGENT_ADAPTER|AGENT_BIN|SKIP_PERMISSIONS)=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "" >> "$yaml_file"
    echo "shift:" >> "$yaml_file"
    grep -E "^(MAX_ROUNDS|WINDOW_HOURS|ROUND_TIMEOUT|RATE_LIMIT_WAIT|SHUTDOWN_BUFFER)=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "" >> "$yaml_file"
    echo "claude:" >> "$yaml_file"
    grep -E "^(CLAUDE_MODEL|CLAUDE_MAX_TURNS|CLAUDE_ALLOWED_TOOLS|CLAUDE_CONTINUE)=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "" >> "$yaml_file"
    echo "guardrails:" >> "$yaml_file"
    grep -E "^(MAX_LINES_CHANGED|MAX_FILES_CHANGED|GUARDRAIL_ACTION)=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "" >> "$yaml_file"
    echo "projects:" >> "$yaml_file"
    grep -E "^PROJECT_DIRS=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "" >> "$yaml_file"
    echo "reporting:" >> "$yaml_file"
    grep -E "^(TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID)=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "" >> "$yaml_file"
    echo "tasks:" >> "$yaml_file"
    grep -E "^TASK_TOOL=" "$env_file" 2>/dev/null | \
        sed 's/^/  /; s/=/:\ /' >> "$yaml_file" || true

    echo "Migrated $env_file → $yaml_file"
}
