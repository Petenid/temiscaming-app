"""Save Ontario 511 API answers as test fixtures (Milestone 7, roads).

Run by the Capture fixtures workflow ("roads"). Reads the developer key from
the ONTARIO_511_KEY environment variable (a GitHub secret) and never writes
it to disk: saved files and error notes show the URL without the key.

Ontario 511 allows 10 calls per 60 seconds; this script makes 9, 7 s apart.
Answers are trimmed to Highway 63 and the area around Témiscaming / North Bay
(the province-wide files are large); a few full closures from elsewhere are
kept as real examples of a closure.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

BASE = "https://511on.ca/api"
# lat 46.0–47.0, lon -80.0 to -78.5: Highway 63, North Bay, the Quebec border.
SOUTH, NORTH, WEST, EAST = 46.0, 47.0, -80.0, -78.5
CALLS = [
    ("v2/get/event", "en"), ("v2/get/event", "fr"),
    ("v2/get/constructionprojects", "en"), ("v2/get/constructionprojects", "fr"),
    ("v3/get/roadconditions", "en"), ("v3/get/roadconditions", "fr"),
    ("v2/get/alerts", "en"), ("v2/get/alerts", "fr"),
    ("v2/get/cameras", "en"),
]
PAUSE_S = 7


def is_63(item):
    name = str(item.get("RoadwayName") or item.get("Roadway") or "")
    return re.search(r"(?<!\d)63(?!\d)", name) is not None


def near(item):
    for lat_key, lon_key in (("Latitude", "Longitude"), ("LatitudeSecondary", "LongitudeSecondary")):
        lat, lon = item.get(lat_key), item.get(lon_key)
        if isinstance(lat, (int, float)) and isinstance(lon, (int, float)):
            if SOUTH <= lat <= NORTH and WEST <= lon <= EAST:
                return True
    return False


def trim(path, data):
    if not isinstance(data, list):
        return data, "not a list (kept whole)"
    if path.endswith("alerts"):
        return data, f"{len(data)} alerts (kept whole)"
    keep = [x for x in data if isinstance(x, dict) and (is_63(x) or near(x))]
    note = f"{len(keep)} of {len(data)} on Highway 63 or near us"
    if path.endswith(("event", "constructionprojects")):
        closures = [x for x in data if isinstance(x, dict) and x.get("IsFullClosure") and x not in keep][:5]
        keep += closures
        note += f", + {len(closures)} full closures elsewhere"
    if path.endswith("roadconditions"):
        others = [x for x in data if isinstance(x, dict) and x not in keep][:3]
        keep += others
        note += f", + {len(others)} samples elsewhere"
    return keep, note


def main(out):
    key = os.environ.get("ONTARIO_511_KEY", "").strip()
    if not key:
        print("::warning::ONTARIO_511_KEY secret not set: Ontario 511 skipped")
        return
    os.makedirs(out, exist_ok=True)
    ua = "AlloTemis-fixture-capture/1.0 (+https://github.com/%s)" % os.environ.get("GITHUB_REPOSITORY", "")
    for i, (path, lang) in enumerate(CALLS):
        if i:
            time.sleep(PAUSE_S)
        name = "on-%s-%s.json" % (path.split("/")[-1], lang)
        shown = f"{BASE}/{path}?format=json&lang={lang}&key=***"
        url = f"{BASE}/{path}?format=json&lang={lang}&key={key}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": ua})
            with urllib.request.urlopen(req, timeout=120) as r:
                body = r.read().decode("utf-8")
            data = json.loads(body)
        except urllib.error.HTTPError as e:
            text = e.read().decode("utf-8", "replace").replace(key, "***")
            with open(os.path.join(out, name + ".error.txt"), "w", encoding="utf-8") as f:
                f.write(f"HTTP {e.code} for {shown}\n\n{text}")
            print(f"::warning::HTTP {e.code} for {name} (saved {name}.error.txt)")
            continue
        except Exception as e:  # network error or not JSON
            msg = str(e).replace(key, "***")
            with open(os.path.join(out, name + ".error.txt"), "w", encoding="utf-8") as f:
                f.write(f"{type(e).__name__} for {shown}\n\n{msg}")
            print(f"::warning::{type(e).__name__} for {name} (saved {name}.error.txt)")
            continue
        kept, note = trim(path, data)
        with open(os.path.join(out, name), "w", encoding="utf-8") as f:
            json.dump(kept, f, ensure_ascii=False, indent=1)
        print(f"saved {name}: {note}")


if __name__ == "__main__":
    main(sys.argv[1])
