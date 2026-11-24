"""Fetch Google Scholar citation count and save to data/gs_data.json."""
import json
import random
import signal
import socket
import sys
import time
from datetime import datetime, timezone

from scholarly import scholarly, ProxyGenerator

SCHOLAR_ID = "_56aZQUAAAAJ"
OUTPUT_FILE = "data/gs_data.json"
FETCH_TIMEOUT = 180  # hard cap for the whole run
REQUEST_TIMEOUT = 25  # per-socket timeout, so a stalled proxy fails fast

# requests/scholarly pass no timeout, so a half-open connection to Google
# would otherwise block forever and eat the whole FETCH_TIMEOUT budget.
socket.setdefaulttimeout(REQUEST_TIMEOUT)


def _citedby():
    author = scholarly.search_author_id(SCHOLAR_ID)
    author = scholarly.fill(author, sections=["basics"])
    return author.get("citedby", 0)


def fetch_citations():
    # Try 1: direct connection (honours http_proxy/https_proxy from the caller).
    for attempt in (1, 2):
        try:
            citations = _citedby()
            if citations:
                return citations
            print(f"Attempt {attempt}: got no citation count")
        except Exception as e:
            print(f"Attempt {attempt} failed: {e}")
        if attempt == 1:
            time.sleep(random.uniform(3, 7))

    # Try 2: free proxy (last resort; Google usually blocks these too).
    try:
        pg = ProxyGenerator()
        if pg.FreeProxies():
            scholarly.use_proxy(pg)
            time.sleep(random.uniform(3, 6))
            citations = _citedby()
            if citations:
                return citations
            print("Free proxy attempt: got no citation count")
        else:
            print("Free proxy attempt: no proxies available")
    except Exception as e:
        print(f"Free proxy failed: {e}")

    return None


def _timeout_handler(signum, frame):
    print(f"Fetch timed out after {FETCH_TIMEOUT}s")
    sys.exit(1)


signal.signal(signal.SIGALRM, _timeout_handler)
signal.alarm(FETCH_TIMEOUT)
citations = fetch_citations()
signal.alarm(0)

if citations is None:
    print("All attempts failed, keeping existing data unchanged.")
    sys.exit(1)

data = {
    "citations": citations,
    "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
}
with open(OUTPUT_FILE, "w") as f:
    json.dump(data, f)

print(f"Citations: {citations} | Saved to {OUTPUT_FILE}")
