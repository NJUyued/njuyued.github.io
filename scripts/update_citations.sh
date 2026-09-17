#!/bin/bash
# Fetch Google Scholar citations and push the update if the count changed.
set -euo pipefail

REPO="/Users/duanyue/code/njuyued.github.io"
PYTHON="/usr/bin/python3"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# VPN proxy for GitHub access only (Clash mixed port). Update if it changes.
PROXY="http://127.0.0.1:50248"

cd "$REPO"

# Sync with remote so we never push a stale/conflicting history.
http_proxy="$PROXY" https_proxy="$PROXY" git pull --rebase --autostash origin main

# Fetch fresh citations directly (no proxy): Google Scholar is reachable from
# this network and blocks VPN datacenter IPs. Exits non-zero on failure.
if ! "$PYTHON" scripts/fetch_citations.py; then
    echo "[$(date -u +%FT%TZ)] fetch failed; nothing to commit"
    exit 1
fi

if git diff --quiet -- data/gs_data.json; then
    echo "[$(date -u +%FT%TZ)] no change in citations"
    exit 0
fi

git add data/gs_data.json
git commit -m "Auto-update Google Scholar citations"
http_proxy="$PROXY" https_proxy="$PROXY" git push origin main
echo "[$(date -u +%FT%TZ)] pushed updated citations"
