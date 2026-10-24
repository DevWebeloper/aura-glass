#!/usr/bin/env python3
"""
Syncs GitHub traffic data (clones) and release asset downloads,
maintains an ongoing cumulative history, and updates Shields.io
endpoint JSON files.
"""

import json
import os
import subprocess
import urllib.request

REPO = "DevWebeloper/aura-glass"
TRAFFIC_TOKEN = os.environ.get("TRAFFIC_TOKEN", "").strip()

# The stats branch's checkout, which the workflow names. Without it, .github
# beside this script, so a run by hand still has somewhere to write.
BASE_DIR = os.environ.get("STATS_DIR") or \
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRAFFIC_DIR = os.path.join(BASE_DIR, "traffic")
BADGES_DIR = os.path.join(BASE_DIR, "badges")

os.makedirs(TRAFFIC_DIR, exist_ok=True)
os.makedirs(BADGES_DIR, exist_ok=True)

HISTORY_FILE = os.path.join(TRAFFIC_DIR, "clones_history.json")
INSTALLS_BADGE = os.path.join(BADGES_DIR, "installs.json")
USERS_BADGE = os.path.join(BADGES_DIR, "users.json")


def fetch_api(path: str):
    url = f"https://api.github.com/repos/{REPO}/{path}"
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "aura-glass-traffic-bot",
    }
    token = TRAFFIC_TOKEN
    if not token:
        # Fall back to gh auth token if available
        try:
            token = subprocess.check_output(["gh", "auth", "token"]).decode().strip()
        except Exception:
            token = ""

    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        # Fall back to gh CLI if running locally
        try:
            raw = subprocess.check_output(["gh", "api", f"repos/{REPO}/{path}"]).decode()
            return json.loads(raw)
        except Exception:
            raise RuntimeError(f"Failed to fetch {url}: {e}")


def main():
    clones_data = fetch_api("traffic/clones")
    releases_data = fetch_api("releases")

    # Load existing clones history
    history = {}
    if os.path.isfile(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, "r") as f:
                history = json.load(f)
        except Exception:
            history = {}

    # Merge rolling 14-day clones into persistent history
    for entry in clones_data.get("clones", []):
        day = entry["timestamp"][:10]
        history[day] = {
            "count": entry.get("count", 0),
            "uniques": entry.get("uniques", 0),
        }

    with open(HISTORY_FILE, "w") as f:
        json.dump(history, f, indent=2, sort_keys=True)

    total_clones = sum(item["count"] for item in history.values())
    unique_cloners_recent = clones_data.get("uniques", 0)

    # Calculate release asset downloads across all releases
    release_downloads = sum(
        asset.get("download_count", 0)
        for rel in releases_data
        for asset in rel.get("assets", [])
    )

    total_installs = total_clones + release_downloads

    # Write shields.io endpoint JSON files
    installs_payload = {
        "schemaVersion": 1,
        "label": "total downloads",
        "message": f"{total_installs}+",
        "color": "blue",
    }
    with open(INSTALLS_BADGE, "w") as f:
        json.dump(installs_payload, f, indent=2)

    users_payload = {
        "schemaVersion": 1,
        "label": "unique cloners",
        "message": f"{unique_cloners_recent}+ (14d)",
        "color": "purple",
    }
    with open(USERS_BADGE, "w") as f:
        json.dump(users_payload, f, indent=2)

    print(f"Total Clones (Accumulated): {total_clones}")
    print(f"Recent Unique Cloners: {unique_cloners_recent}")
    print(f"Release Asset Downloads: {release_downloads}")
    print(f"Total Installs: {total_installs}")


if __name__ == "__main__":
    main()
