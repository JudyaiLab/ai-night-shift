#!/usr/bin/env bash
# ============================================================================
# lib/project_config.sh — Per-project configuration parser
#
# Reads .nightshift.yml from a target project directory and exports
# standardized variables for use by the night shift runner.
#
# Usage:
#   source lib/project_config.sh
#   load_project_config "/path/to/project"
#
# Exports:
#   PROJECT_LANGUAGE, PROJECT_TEST_CMD, PROJECT_BUILD_CMD, PROJECT_LINT_CMD,
#   PROJECT_BRANCH_STRATEGY, PROJECT_BASE_BRANCH, PROJECT_CI,
#   PROJECT_SCOPE_INCLUDE, PROJECT_SCOPE_EXCLUDE, PROJECT_NAME
# ============================================================================

# Parse a simple YAML file into bash variables (handles flat and one-level nesting)
# This avoids requiring python/ruby for basic YAML parsing.
_parse_nightshift_yml() {
    local file="$1"
    local prefix="$2"

    [ -f "$file" ] || return 1

    local current_section=""
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Detect section headers (e.g., "project:", "scope:")
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):$ ]] || [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key-value pairs (e.g., "  language: typescript")
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):\ *(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            # Strip quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            local var_name
            if [ -n "$current_section" ]; then
                var_name="${prefix}_${current_section}_${key}"
            else
                var_name="${prefix}_${key}"
            fi
            var_name=$(echo "$var_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            export "$var_name=$value"
        fi

        # Array items (e.g., "    - src/")
        if [[ "$line" =~ ^[[:space:]]+-\ *(.*) ]]; then
            local item="${BASH_REMATCH[1]}"
            item="${item#\"}"
            item="${item%\"}"
            # Append to a comma-separated list
            local arr_var
            if [ -n "$current_section" ]; then
                arr_var="${prefix}_${current_section}"
            else
                arr_var="${prefix}_items"
            fi
            arr_var=$(echo "$arr_var" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            local existing="${!arr_var:-}"
            if [ -n "$existing" ]; then
                export "$arr_var=${existing},${item}"
            else
                export "$arr_var=${item}"
            fi
        fi
    done < "$file"
}

# Auto-detect project type when no config file exists
_auto_detect_project() {
    local project_dir="$1"

    # Language detection
    if [ -f "$project_dir/package.json" ]; then
        if [ -f "$project_dir/tsconfig.json" ]; then
            PROJECT_LANGUAGE="typescript"
        else
            PROJECT_LANGUAGE="javascript"
        fi
    elif [ -f "$project_dir/Cargo.toml" ]; then
        PROJECT_LANGUAGE="rust"
    elif [ -f "$project_dir/go.mod" ]; then
        PROJECT_LANGUAGE="go"
    elif [ -f "$project_dir/pyproject.toml" ] || [ -f "$project_dir/setup.py" ] || [ -f "$project_dir/requirements.txt" ]; then
        PROJECT_LANGUAGE="python"
    elif [ -f "$project_dir/Gemfile" ]; then
        PROJECT_LANGUAGE="ruby"
    elif [ -f "$project_dir/pom.xml" ] || [ -f "$project_dir/build.gradle" ]; then
        PROJECT_LANGUAGE="java"
    else
        PROJECT_LANGUAGE="unknown"
    fi

    # Test command detection
    case "$PROJECT_LANGUAGE" in
        typescript|javascript)
            if [ -f "$project_dir/package.json" ]; then
                if grep -q '"test"' "$project_dir/package.json" 2>/dev/null; then
                    PROJECT_TEST_CMD="npm test"
                fi
                if grep -q '"build"' "$project_dir/package.json" 2>/dev/null; then
                    PROJECT_BUILD_CMD="npm run build"
                fi
                if grep -q '"lint"' "$project_dir/package.json" 2>/dev/null; then
                    PROJECT_LINT_CMD="npm run lint"
                fi
            fi
            ;;
        rust)
            PROJECT_TEST_CMD="cargo test"
            PROJECT_BUILD_CMD="cargo build"
            PROJECT_LINT_CMD="cargo clippy"
            ;;
        go)
            PROJECT_TEST_CMD="go test ./..."
            PROJECT_BUILD_CMD="go build ./..."
            PROJECT_LINT_CMD="golangci-lint run"
            ;;
        python)
            if [ -f "$project_dir/pyproject.toml" ]; then
                PROJECT_TEST_CMD="pytest"
                PROJECT_LINT_CMD="ruff check ."
            elif [ -d "$project_dir/tests" ]; then
                PROJECT_TEST_CMD="python -m pytest"
                PROJECT_LINT_CMD="flake8 ."
            fi
            PROJECT_BUILD_CMD=""
            ;;
        ruby)
            PROJECT_TEST_CMD="bundle exec rake test"
            PROJECT_BUILD_CMD=""
            PROJECT_LINT_CMD="bundle exec rubocop"
            ;;
        java)
            if [ -f "$project_dir/pom.xml" ]; then
                PROJECT_TEST_CMD="mvn test"
                PROJECT_BUILD_CMD="mvn package"
            elif [ -f "$project_dir/build.gradle" ]; then
                PROJECT_TEST_CMD="./gradlew test"
                PROJECT_BUILD_CMD="./gradlew build"
            fi
            PROJECT_LINT_CMD=""
            ;;
    esac

    # Base branch detection
    if git -C "$project_dir" rev-parse --git-dir &>/dev/null; then
        if git -C "$project_dir" show-ref --verify --quiet refs/heads/main; then
            PROJECT_BASE_BRANCH="main"
        elif git -C "$project_dir" show-ref --verify --quiet refs/heads/master; then
            PROJECT_BASE_BRANCH="master"
        fi
    fi
}

# Main entry point: load project config from a directory
# Usage: load_project_config "/path/to/project"
load_project_config() {
    local project_dir="${1:-.}"

    # Defaults
    PROJECT_NAME=$(basename "$(cd "$project_dir" && pwd)")
    PROJECT_LANGUAGE=""
    PROJECT_TEST_CMD=""
    PROJECT_BUILD_CMD=""
    PROJECT_LINT_CMD=""
    PROJECT_BRANCH_STRATEGY="feature-branch"
    PROJECT_BASE_BRANCH="main"
    PROJECT_CI=""
    PROJECT_SCOPE_INCLUDE=""
    PROJECT_SCOPE_EXCLUDE=""

    local config_file="$project_dir/.nightshift.yml"

    if [ -f "$config_file" ]; then
        _parse_nightshift_yml "$config_file" "NS"

        # Map parsed variables to standard exports
        PROJECT_NAME="${NS_PROJECT_NAME:-$PROJECT_NAME}"
        PROJECT_LANGUAGE="${NS_PROJECT_LANGUAGE:-}"
        PROJECT_TEST_CMD="${NS_PROJECT_TEST_CMD:-}"
        PROJECT_BUILD_CMD="${NS_PROJECT_BUILD_CMD:-}"
        PROJECT_LINT_CMD="${NS_PROJECT_LINT_CMD:-}"
        PROJECT_BRANCH_STRATEGY="${NS_PROJECT_BRANCH_STRATEGY:-feature-branch}"
        PROJECT_BASE_BRANCH="${NS_PROJECT_BASE_BRANCH:-main}"
        PROJECT_CI="${NS_PROJECT_CI:-}"
        PROJECT_SCOPE_INCLUDE="${NS_SCOPE_INCLUDE:-${NS_INCLUDE:-}}"
        PROJECT_SCOPE_EXCLUDE="${NS_SCOPE_EXCLUDE:-${NS_EXCLUDE:-}}"
    else
        _auto_detect_project "$project_dir"
    fi

    # Export all
    export PROJECT_NAME PROJECT_LANGUAGE PROJECT_TEST_CMD PROJECT_BUILD_CMD
    export PROJECT_LINT_CMD PROJECT_BRANCH_STRATEGY PROJECT_BASE_BRANCH
    export PROJECT_CI PROJECT_SCOPE_INCLUDE PROJECT_SCOPE_EXCLUDE
}

# Format project config as text for prompt injection
format_project_config() {
    cat <<EOF
## Project Configuration
- Name: ${PROJECT_NAME:-N/A}
- Language: ${PROJECT_LANGUAGE:-auto-detected}
- Test command: ${PROJECT_TEST_CMD:-none}
- Build command: ${PROJECT_BUILD_CMD:-none}
- Lint command: ${PROJECT_LINT_CMD:-none}
- Branch strategy: ${PROJECT_BRANCH_STRATEGY:-feature-branch}
- Base branch: ${PROJECT_BASE_BRANCH:-main}
- CI: ${PROJECT_CI:-not configured}
- Scope include: ${PROJECT_SCOPE_INCLUDE:-all}
- Scope exclude: ${PROJECT_SCOPE_EXCLUDE:-none}
EOF
}
