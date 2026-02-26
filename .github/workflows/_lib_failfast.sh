#!/usr/bin/env bash
set -euo pipefail

require_env () {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Missing required environment variable/secret: $name"
    exit 2
  fi
}
