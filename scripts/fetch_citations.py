"""Fetch Google Scholar citation count and save to data/gs_data.json."""
import json
import sys
import time
import random
import signal
from datetime import datetime, timezone

from scholarly import scholarly, ProxyGenerator

SCHOLAR_ID = "_56aZQUAAAAJ"
OUTPUT_FILE = "data/gs_data.json"
FETCH_TIMEOUT = 120  # seconds; abort if a scrape hangs

def fetch_citations():
    # Try 1: direct connection
    try:
        author = scholarly.search_author_id(SCHOLAR_ID)
        author = scholarly.fill(author, sections=["basics"])
        citations = author.get("citedby", 0)
        if citations:
            return citations
    except Exception as e:
        print(f"Direct connection failed: {e}")

    # Try 2: free proxy
    try:
        pg = ProxyGenerator()
        if pg.FreeProxies():
            scholarly.use_proxy(pg)
            time.sleep(random.uniform(5, 10))
            author = scholarly.search_author_id(SCHOLAR_ID)
            author = scholarly.fill(author, sections=["basics"])
            citations = author.get("citedby", 0)
            if citations:
                return citations
    except Exception as e:
        print(f"Free proxy failed: {e}")

    # Try 3: another attempt with longer delay
    try:
        time.sleep(random.uniform(10, 20))
        author = scholarly.search_author_id(SCHOLAR_ID)
        author = scholarly.fill(author, sections=["basics"])
        citations = author.get("citedby", 0)
        if citations:
            return citations
    except Exception as e:
        print(f"Final attempt failed: {e}")

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
