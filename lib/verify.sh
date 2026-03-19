#!/usr/bin/env bash
# ============================================================================
# lib/verify.sh — Test-before-commit guardrail
#
# Runs project test/build/lint commands and reports results.
# Can optionally revert commits that break tests.
#
# Usage:
#   source lib/verify.sh
#   verify_project "/path/to/project"
#
# Requires: load_project_config to have been called first
# ============================================================================

VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-300}"  # 5 min timeout for verification commands
VERIFY_REVERT_ON_FAIL="${VERIFY_REVERT_ON_FAIL:-false}"

# Run a single verification command and capture results
_run_check() {
    local name="$1"
    local cmd="$2"
    local project_dir="$3"
    local result_file="$4"

    if [ -z "$cmd" ]; then
        echo "  $name: skipped (no command configured)" >> "$result_file"
        return 0
    fi

    local start_time
    start_time=$(date +%s)

    local output exit_code
    output=$(cd "$project_dir" && timeout "$VERIFY_TIMEOUT" bash -c "$cmd" 2>&1) || true
    exit_code=${PIPESTATUS[0]:-$?}

    local duration=$(( $(date +%s) - start_time ))

    if [ "$exit_code" -eq 0 ]; then
        echo "  $name: PASS (${duration}s)" >> "$result_file"
    elif [ "$exit_code" -eq 124 ]; then
        echo "  $name: TIMEOUT after ${VERIFY_TIMEOUT}s" >> "$result_file"
    else
        echo "  $name: FAIL (exit=$exit_code, ${duration}s)" >> "$result_file"
        # Save failure details
        echo "--- $name failure output (last 30 lines) ---" >> "${result_file}.detail"
        echo "$output" | tail -30 >> "${result_file}.detail"
        echo "--- end $name ---" >> "${result_file}.detail"
    fi

    return "$exit_code"
}

# Run all verification checks for a project
# Returns 0 if all pass, 1 if any fail
verify_project() {
    local project_dir="${1:-.}"
    local result_file="${2:-/tmp/nightshift_verify_$$.txt}"

    echo "## Verification Results" > "$result_file"
    echo "  Directory: $project_dir" >> "$result_file"
    echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')" >> "$result_file"
    : > "${result_file}.detail"

    local all_pass=true

    # Run lint check
    if [ -n "${PROJECT_LINT_CMD:-}" ]; then
        _run_check "Lint" "$PROJECT_LINT_CMD" "$project_dir" "$result_file" || all_pass=false
    fi

    # Run build check
    if [ -n "${PROJECT_BUILD_CMD:-}" ]; then
        _run_check "Build" "$PROJECT_BUILD_CMD" "$project_dir" "$result_file" || all_pass=false
    fi

    # Run test check
    if [ -n "${PROJECT_TEST_CMD:-}" ]; then
        _run_check "Tests" "$PROJECT_TEST_CMD" "$project_dir" "$result_file" || all_pass=false
    fi

    # Summary
    if [ "$all_pass" = true ]; then
        echo "  Overall: ALL CHECKS PASSED" >> "$result_file"
    else
        echo "  Overall: SOME CHECKS FAILED" >> "$result_file"

        # Optionally revert the last commit
        if [ "${VERIFY_REVERT_ON_FAIL}" = "true" ]; then
            local last_commit
            last_commit=$(git -C "$project_dir" rev-parse HEAD 2>/dev/null)
            if [ -n "$last_commit" ]; then
                echo "  Action: Reverting last commit ($last_commit)" >> "$result_file"
                git -C "$project_dir" revert --no-edit HEAD 2>/dev/null || true
            fi
        fi
    fi

    cat "$result_file"

    if [ -s "${result_file}.detail" ]; then
        echo ""
        cat "${result_file}.detail"
    fi

    if [ "$all_pass" = true ]; then
        return 0
    else
        return 1
    fi
}

# Quick check: just returns pass/fail without details
verify_quick() {
    local project_dir="${1:-.}"

    if [ -n "${PROJECT_TEST_CMD:-}" ]; then
        cd "$project_dir" && timeout "$VERIFY_TIMEOUT" bash -c "$PROJECT_TEST_CMD" >/dev/null 2>&1
        return $?
    fi
    return 0  # No tests configured = pass
}

# Format verification results for prompt injection
format_verify_results() {
    local result_file="$1"
    if [ -f "$result_file" ]; then
        cat "$result_file"
    else
        echo "No verification results available."
    fi
}
