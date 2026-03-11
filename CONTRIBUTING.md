# Contributing to AI Night Shift

Thank you for your interest in contributing! This project welcomes contributions of all kinds.

## Ways to Contribute

- **New plugins** — extend the framework with useful automation
- **New templates** — prompt templates for specific use cases
- **Bug fixes** — found something broken? Fix it!
- **Documentation** — improve guides, add examples, fix typos
- **Dashboard improvements** — make the monitoring UI better
- **New agent modules** — add support for other AI CLI tools

## Development Setup

```bash
git clone https://github.com/judyailab/ai-night-shift.git
cd ai-night-shift
bash install.sh --no-cron  # Install without scheduling
```

## Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-plugin`)
3. Make your changes
4. Test your changes (`bash claude-code/night_shift.sh --max-rounds 1`)
5. Commit with a clear message
6. Open a Pull Request

## Plugin Development

The easiest way to contribute is by creating a new plugin:

```bash
#!/usr/bin/env bash
# PLUGIN_NAME: My Awesome Plugin
# PLUGIN_PHASE: post
# PLUGIN_DESCRIPTION: What it does

set -euo pipefail
NIGHT_SHIFT_DIR="${NIGHT_SHIFT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Your code here
```

Place it in `plugins/examples/` and submit a PR.

## Code Style

- **Bash scripts:** Use `set -euo pipefail`, quote variables, use `[[ ]]` for tests
- **Documentation:** Markdown with clear headers and code examples
- **Commits:** Descriptive messages, one logical change per commit

## Security

- Never commit secrets, API keys, or credentials
- Never include real file paths from personal systems
- Report security issues privately (see SECURITY.md)

## Questions?

Open an issue with the "question" label.
