# Contributing to System Monitor

Thanks for your interest in contributing.

## How to Contribute

1. Fork the repo and create a feature branch
2. Make your changes
3. Ensure `bash setup.sh --dry-run` passes
4. Submit a PR

## Development Setup

```bash
git clone https://github.com/YOUR_USER/system-monitor.git
cd system-monitor
bash setup.sh --dev
```

## Code Style

- Python: follow PEP 8
- Shell: `shellcheck` recommended
- Keep health endpoint functional: `curl http://localhost:8080/api/health`

## Reporting Bugs

Open an issue with: OS / Python version / error output / `git log -1`.

## Pull Requests

- One topic per PR
- Keep it small and focused
- Ensure CI passes before merging
