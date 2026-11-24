#!/bin/bash
# Opportunistically refresh Google Scholar citations: whenever the VPN is up
# and GitHub is reachable, update and push. Polled by launchd every 5 min.
set -uo pipefail

REPO="${REPO:-/Users/duanyue/code/njuyued.github.io}"
PYTHON="${PYTHON:-/usr/bin/python3}"
CLASH_CONFIG="${CLASH_CONFIG:-/Users/duanyue/.config/clash/config.yaml}"
STAMP="${STAMP:-/Users/duanyue/Library/Logs/com.njuyued.update-citations.lastrun}"
THROTTLE_SEC=43200   # refresh at most once every 12h
RETRY_SEC=1800       # after a failed attempt, retry after 30 min

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# Auto-detect the Clash mixed port (it is randomized on restart/profile switch).
PROXY_PORT=$(awk '/^[[:space:]]*mixed-port:/{gsub(/[^0-9]/,"",$0); print; exit}' "$CLASH_CONFIG" 2>/dev/null)
case "$PROXY_PORT" in
    ''|*[!0-9]*) log "skip: no clash mixed-port found"; exit 0 ;;
esac
PROXY="http://127.0.0.1:${PROXY_PORT}"

# 1. VPN up? (proxy port reachable) — otherwise nothing to do.
if ! nc -z -G 2 127.0.0.1 "$PROXY_PORT" >/dev/null 2>&1; then
    log "skip: proxy port ${PROXY_PORT} closed (VPN down)"
    exit 0
fi

# 2. GitHub reachable through the proxy?
if ! curl -sS -o /dev/null --max-time 8 -x "$PROXY" https://github.com >/dev/null 2>&1; then
    log "skip: github unreachable through proxy ${PROXY}"
    exit 0
fi

# 3. Throttle: avoid scraping Google Scholar too often while the VPN stays on.
now=$(date +%s)
last=0
[ -f "$STAMP" ] && last=$(cat "$STAMP")
if [ $((now - last)) -lt "$THROTTLE_SEC" ]; then
    exit 0
fi

cd "$REPO" || { log "error: repo $REPO missing"; exit 0; }

if ! http_proxy="$PROXY" https_proxy="$PROXY" git pull --rebase --autostash origin main; then
    log "error: git pull failed; retrying in $((RETRY_SEC / 60)) min"
    echo $((now - THROTTLE_SEC + RETRY_SEC)) > "$STAMP"
    exit 0
fi

if "$PYTHON" scripts/fetch_citations.py; then
    if git diff --quiet -- data/gs_data.json; then
        log "no change in citations"
    else
        git add data/gs_data.json
        git commit -m "Auto-update Google Scholar citations"
    fi

    # Also push commits left behind by an earlier failed push.
    if [ -n "$(git log origin/main..HEAD --oneline 2>/dev/null)" ]; then
        if http_proxy="$PROXY" https_proxy="$PROXY" git push origin main; then
            log "pushed updated citations"
            echo "$now" > "$STAMP"
        else
            log "error: git push failed (commit kept locally); retrying in $((RETRY_SEC / 60)) min"
            echo $((now - THROTTLE_SEC + RETRY_SEC)) > "$STAMP"
        fi
    else
        echo "$now" > "$STAMP"
    fi
else
    log "fetch failed; retrying in $((RETRY_SEC / 60)) min"
    echo $((now - THROTTLE_SEC + RETRY_SEC)) > "$STAMP"
fi
