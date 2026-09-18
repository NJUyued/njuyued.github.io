#!/bin/bash
# Opportunistically refresh Google Scholar citations: whenever the VPN is up
# and GitHub is reachable, update and push. Polled by launchd every 5 min.
set -euo pipefail

REPO="/Users/duanyue/code/njuyued.github.io"
PYTHON="/usr/bin/python3"
CLASH_CONFIG="/Users/duanyue/.config/clash/config.yaml"
STAMP="/Users/duanyue/Library/Logs/com.njuyued.update-citations.lastrun"
THROTTLE_SEC=43200   # refresh at most once every 12h

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Auto-detect the Clash mixed port (it is randomized on restart/profile switch).
PROXY_PORT=$(awk '/^[[:space:]]*mixed-port:/{gsub(/[^0-9]/,"",$0); print; exit}' "$CLASH_CONFIG" 2>/dev/null)
case "$PROXY_PORT" in
    ''|*[!0-9]*) exit 0 ;;   # config missing / not a number — VPN not ready
esac
PROXY="http://127.0.0.1:${PROXY_PORT}"

# 1. VPN up? (proxy port reachable) — otherwise nothing to do.
if ! nc -z -G 2 127.0.0.1 "$PROXY_PORT" >/dev/null 2>&1; then
    exit 0
fi

# 2. GitHub reachable through the proxy?
if ! curl -sS -o /dev/null --max-time 8 -x "$PROXY" https://github.com >/dev/null 2>&1; then
    exit 0
fi

# 3. Throttle: avoid scraping Google Scholar too often while the VPN stays on.
now=$(date +%s)
last=0
[ -f "$STAMP" ] && last=$(cat "$STAMP")
if [ $((now - last)) -lt "$THROTTLE_SEC" ]; then
    exit 0
fi

# Conditions met — refresh.
cd "$REPO"
http_proxy="$PROXY" https_proxy="$PROXY" git pull --rebase --autostash origin main

if "$PYTHON" scripts/fetch_citations.py; then
    if git diff --quiet -- data/gs_data.json; then
        echo "[$(date -u +%FT%TZ)] no change in citations"
    else
        git add data/gs_data.json
        git commit -m "Auto-update Google Scholar citations"
        http_proxy="$PROXY" https_proxy="$PROXY" git push origin main
        echo "[$(date -u +%FT%TZ)] pushed updated citations"
    fi
else
    echo "[$(date -u +%FT%TZ)] fetch failed"
fi

# Record this attempt so the next refresh waits the throttle window.
echo "$now" > "$STAMP"
