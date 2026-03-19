#!/usr/bin/env bash
# ============================================================================
# lib/git_workflow.sh — Branch management and PR workflow
#
# Manages feature branches and PR creation for night shift sessions.
#
# Strategies:
#   feature-branch — one branch per shift, PR at the end
#   task-branch    — one branch per task, PR per task
#   trunk-based    — commit directly to a working branch, PR at the end
#
# Usage:
#   source lib/git_workflow.sh
#   workflow_start "/path/to/project"   # Before shift
#   workflow_finish "/path/to/project"  # After shift
# ============================================================================

GIT_WORKFLOW="${GIT_WORKFLOW:-${PROJECT_BRANCH_STRATEGY:-feature-branch}}"
GIT_BASE_BRANCH="${GIT_BASE_BRANCH:-${PROJECT_BASE_BRANCH:-main}}"
GIT_PR_DRAFT="${GIT_PR_DRAFT:-true}"
GIT_BRANCH_PREFIX="${GIT_BRANCH_PREFIX:-nightshift}"

# Create a branch name from a description
_make_branch_name() {
    local desc="${1:-session}"
    local date_tag
    date_tag=$(date +%Y%m%d)
    # Sanitize: lowercase, replace spaces with dashes, remove special chars
    desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g' | head -c 40)
    echo "${GIT_BRANCH_PREFIX}/${date_tag}-${desc}"
}

# Start workflow: create branch, ensure clean state
workflow_start() {
    local project_dir="${1:-.}"
    local task_desc="${2:-session}"

    cd "$project_dir" || return 1

    # Ensure we're in a git repo
    if ! git rev-parse --git-dir &>/dev/null; then
        echo "WARN: Not a git repository, skipping workflow"
        return 0
    fi

    # Fetch latest from remote
    git fetch origin "$GIT_BASE_BRANCH" --quiet 2>/dev/null || true

    case "$GIT_WORKFLOW" in
        feature-branch|task-branch)
            local branch_name
            branch_name=$(_make_branch_name "$task_desc")

            # Check if branch already exists
            if git show-ref --verify --quiet "refs/heads/$branch_name"; then
                echo "Branch $branch_name already exists, switching to it"
                git checkout "$branch_name" 2>/dev/null
            else
                # Create from base branch
                git checkout -b "$branch_name" "origin/$GIT_BASE_BRANCH" 2>/dev/null || \
                    git checkout -b "$branch_name" "$GIT_BASE_BRANCH" 2>/dev/null || \
                    git checkout -b "$branch_name" 2>/dev/null
                echo "Created branch: $branch_name"
            fi

            # Export for later use
            export NIGHTSHIFT_BRANCH="$branch_name"
            ;;
        trunk-based)
            # Stay on current branch or create a working branch
            local current
            current=$(git branch --show-current 2>/dev/null)
            if [ "$current" = "$GIT_BASE_BRANCH" ]; then
                local work_branch="${GIT_BRANCH_PREFIX}/work-$(date +%Y%m%d)"
                git checkout -b "$work_branch" 2>/dev/null || git checkout "$work_branch" 2>/dev/null
                export NIGHTSHIFT_BRANCH="$work_branch"
            else
                export NIGHTSHIFT_BRANCH="$current"
            fi
            echo "Working on branch: $NIGHTSHIFT_BRANCH"
            ;;
    esac

    return 0
}

# Finish workflow: push and create PR
workflow_finish() {
    local project_dir="${1:-.}"
    local summary="${2:-AI Night Shift automated changes}"

    cd "$project_dir" || return 1

    if ! git rev-parse --git-dir &>/dev/null; then
        return 0
    fi

    local branch
    branch="${NIGHTSHIFT_BRANCH:-$(git branch --show-current 2>/dev/null)}"

    if [ -z "$branch" ] || [ "$branch" = "$GIT_BASE_BRANCH" ]; then
        echo "WARN: On base branch, skipping PR creation"
        return 0
    fi

    # Check if there are commits to push
    local commit_count
    commit_count=$(git rev-list --count "origin/${GIT_BASE_BRANCH}..HEAD" 2>/dev/null || echo "0")

    if [ "$commit_count" -eq 0 ]; then
        echo "No commits to push"
        return 0
    fi

    # Push the branch
    git push -u origin "$branch" 2>/dev/null || {
        echo "WARN: Failed to push branch $branch"
        return 1
    }
    echo "Pushed $commit_count commit(s) to $branch"

    # Create PR if gh is available
    if command -v gh &>/dev/null; then
        # Check if PR already exists
        local existing_pr
        existing_pr=$(gh pr list --head "$branch" --json number --jq '.[0].number' 2>/dev/null)

        if [ -n "$existing_pr" ]; then
            echo "PR #$existing_pr already exists for $branch"
            return 0
        fi

        local date_tag
        date_tag=$(date +%Y-%m-%d)
        local pr_title="Night Shift: ${summary} ($date_tag)"

        local pr_body
        pr_body=$(cat <<EOF
## Night Shift Report

**Branch:** \`$branch\`
**Commits:** $commit_count
**Date:** $date_tag

### Changes Summary
$summary

### Commits
$(git log --oneline "origin/${GIT_BASE_BRANCH}..HEAD" 2>/dev/null | head -20)

---
*This PR was created automatically by [AI Night Shift](https://github.com/JudyaiLab/ai-night-shift)*
EOF
)

        local draft_flag=""
        if [ "$GIT_PR_DRAFT" = "true" ]; then
            draft_flag="--draft"
        fi

        # shellcheck disable=SC2086
        local pr_url
        pr_url=$(gh pr create --title "$pr_title" --body "$pr_body" \
            --base "$GIT_BASE_BRANCH" --head "$branch" \
            $draft_flag 2>/dev/null) || true

        if [ -n "$pr_url" ]; then
            echo "Created PR: $pr_url"
        else
            echo "WARN: Failed to create PR (branch pushed successfully)"
        fi
    else
        echo "gh CLI not available — branch pushed, create PR manually"
    fi

    return 0
}

# Create a branch for a specific task (task-branch strategy)
workflow_task_branch() {
    local project_dir="${1:-.}"
    local task_id="$2"
    local task_desc="${3:-fix}"

    cd "$project_dir" || return 1

    local branch_name
    branch_name=$(_make_branch_name "${task_id}-${task_desc}")

    git checkout -b "$branch_name" "origin/$GIT_BASE_BRANCH" 2>/dev/null || \
        git checkout -b "$branch_name" "$GIT_BASE_BRANCH" 2>/dev/null || \
        git checkout -b "$branch_name" 2>/dev/null

    export NIGHTSHIFT_BRANCH="$branch_name"
    echo "Created task branch: $branch_name"
}
