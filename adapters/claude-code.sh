#!/usr/bin/env bash
# ============================================================================
# Adapter: Claude Code (claude)
# Maps the generic agent interface to Claude Code CLI flags
#
# Enhanced features:
#   - Model selection (CLAUDE_MODEL)
#   - Max turns per round (CLAUDE_MAX_TURNS)
#   - Allowed tools restriction (CLAUDE_ALLOWED_TOOLS)
#   - Session continuation (CLAUDE_CONTINUE)
#   - System prompt support (CLAUDE_SYSTEM_PROMPT)
# ============================================================================

# Required: AGENT_BIN, PROMPT, OUTPUT_FILE
# Optional: SKIP_PERMISSIONS, EFFECTIVE_TIMEOUT, CLAUDE_MODEL, CLAUDE_MAX_TURNS,
#           CLAUDE_ALLOWED_TOOLS, CLAUDE_CONTINUE, CLAUDE_SYSTEM_PROMPT

AGENT_BIN="${AGENT_BIN:-claude}"

adapter_build_flags() {
    local flags=()
    flags+=(--print)
    flags+=(-p)

    if [ "${SKIP_PERMISSIONS:-false}" = "true" ]; then
        flags+=(--dangerously-skip-permissions)
    fi

    # Model selection
    if [ -n "${CLAUDE_MODEL:-}" ]; then
        flags+=(--model "$CLAUDE_MODEL")
    fi

    # Max turns per round
    if [ -n "${CLAUDE_MAX_TURNS:-}" ]; then
        flags+=(--max-turns "$CLAUDE_MAX_TURNS")
    fi

    # Allowed tools restriction (comma-separated list)
    if [ -n "${CLAUDE_ALLOWED_TOOLS:-}" ]; then
        IFS=',' read -ra tools <<< "$CLAUDE_ALLOWED_TOOLS"
        for tool in "${tools[@]}"; do
            tool=$(echo "$tool" | xargs)  # trim whitespace
            flags+=(--allowedTools "$tool")
        done
    fi

    # Session continuation (resume previous session)
    if [ "${CLAUDE_CONTINUE:-false}" = "true" ]; then
        flags+=(--continue)
    fi

    # System prompt
    if [ -n "${CLAUDE_SYSTEM_PROMPT:-}" ]; then
        flags+=(--system-prompt "$CLAUDE_SYSTEM_PROMPT")
    fi

    echo "${flags[@]}"
}

adapter_run() {
    local prompt="$1"
    local output_file="$2"
    local timeout_sec="${3:-9000}"

    local flags
    flags=$(adapter_build_flags)

    # shellcheck disable=SC2086
    timeout "$timeout_sec" "$AGENT_BIN" $flags "$prompt" \
        > "$output_file" 2>&1
    return $?
}

adapter_check_rate_limit() {
    local output_file="$1"
    grep -qi "rate.limit\|too many\|429\|quota" "$output_file" 2>/dev/null
}

adapter_check_completion() {
    local output_file="$1"
    local signal="${2:-NIGHT_SHIFT_COMPLETE}"
    grep -q "$signal" "$output_file" 2>/dev/null
}

adapter_name() {
    echo "Claude Code"
}

adapter_verify() {
    command -v "$AGENT_BIN" &>/dev/null
}
