#!/usr/bin/env bash
# update-fork.sh — Sync averyaistudio-art/tradingview-mcp with upstream
# Upstream: https://github.com/atilaahmettaner/tradingview-mcp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

cd "$REPO_DIR"

echo "Fetching upstream changes from atilaahmettaner/tradingview-mcp..."
git fetch upstream

echo "Merging upstream/main into main..."
git merge upstream/main --no-edit

echo "Pushing to origin/main..."
git push origin main

echo "✓ Fork synced with upstream"
