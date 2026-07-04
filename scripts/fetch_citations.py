"""Fetch Google Scholar citation count and save to data/gs_data.json."""
import json
import sys
from datetime import datetime, timezone

try:
    from scholarly import scholarly
except ImportError:
    print("scholarly not installed, installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "scholarly"])
    from scholarly import scholarly

SCHOLAR_ID = "_56aZQUAAAAJ"
OUTPUT_FILE = "data/gs_data.json"

try:
    author = scholarly.search_author_id(SCHOLAR_ID)
    author = scholarly.fill(author, sections=["basics"])
    citations = author.get("citedby", 0)
except Exception as e:
    print(f"Error fetching citations: {e}")
    sys.exit(1)

data = {
    "citations": citations,
    "updated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
}
with open(OUTPUT_FILE, "w") as f:
    json.dump(data, f)

print(f"Citations: {citations} | Saved to {OUTPUT_FILE}")
