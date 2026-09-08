#!/usr/bin/env bash
# Read-only by default. --report also persists the audit envelope.
set -euo pipefail
exec python3 "$(dirname "$0")/steward_audit.py" "$@"
