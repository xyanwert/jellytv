#!/bin/zsh
#
# seed-anime-figures.sh — give a simulator the Anime library's figures a real Apple TV cuts itself.
#
#   Scripts/seed-anime-figures.sh                 # booted Apple TV simulator, anime + adult-anime libraries
#   Scripts/seed-anime-figures.sh <udid>          # a specific simulator (iPad and iPhone work too)
#   Scripts/seed-anime-figures.sh <udid> 40       # at most 40 newest titles per library (default 60)
#
# The Anime and Late Night screens in Poster Mode stand a title's own character on the stage,
# cut out of its thumb, poster or backdrop on device by Vision and judged as a figure
# (`FigureCutoutCache` → `FigureQuality`). The simulators can't run Vision, so this script makes
# the same cuts on the Mac (`segment-figures.swift`, the same requests and the same scoring) and
# drops them into the simulator app's cache under the names the app would have written
# (`Library/Caches/cutouts/figure-<sha256 of the image URL>.png` + `.score`, or `.miss`), so the
# simulator renders exactly what the device would. Re-run after the library grows; existing
# files are skipped. Cutting takes about a second an image.
#
# Reads the server address and token from the simulator app's own preferences — nothing is printed.
set -e
UDID=${1:-$(xcrun simctl list devices booted | grep -i "apple tv" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' | head -1)}
LIMIT=${2:-60}
BUNDLE=net.graficx.jellytv
[[ -n "$UDID" ]] || { echo "no booted Apple TV simulator"; exit 1 }
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
CACHE="$CONTAINER/Library/Caches/cutouts"
mkdir -p "$CACHE"
WORK=$(mktemp -d)
HERE=${0:a:h}

# Every anime title's thumb, poster and backdrop, at the sizes the app asks for → files + the URL each was.
python3 - "$CONTAINER" "$WORK" "$CACHE" "$LIMIT" <<'EOF'
import plistlib, sys, glob, urllib.request, json, hashlib, os, re
container, work, cache, limit = sys.argv[1:5]
prefs = glob.glob(os.path.join(container, "Library/Preferences/*.plist"))[0]
d = plistlib.load(open(prefs, "rb"))
host, port, key, uid = d["jelly:server.host"], d.get("jelly:server.port"), d["jelly:auth.apiKey"], d["jelly:auth.userId"]
base = f"http://{host}:{port}" if port else f"http://{host}"
def get(path):
    req = urllib.request.Request(base + path, headers={"Authorization": f'MediaBrowser Token="{key}"'})
    return json.load(urllib.request.urlopen(req, timeout=60))
overrides = {}
try: overrides = json.loads(d.get("jelly:library.overrides", b"{}"))
except Exception: pass
views = get(f"/Users/{uid}/Views")["Items"]
def is_anime(v):
    if overrides.get(v["Id"], {}).get("isAnime"): return True
    if overrides.get(v["Id"], {}).get("isAnime") is False: return False
    return re.search(r"anime|hentai|late.?night", v["Name"], re.I) is not None and v.get("CollectionType") in ("tvshows", "movies")
todo, skipped = [], 0
for v in [v for v in views if is_anime(v)]:
    items = get(f"/Users/{uid}/Items?parentId={v['Id']}&includeItemTypes=Series,Movie&recursive=true"
                f"&sortBy=DateCreated&sortOrder=Descending&limit={limit}&fields=BackdropImageTags")["Items"]
    for it in items:
        tags = it.get("ImageTags", {})
        # The app's own URL forms (JellyfinAPI.imageURL): quality, tag, maxWidth — in that order.
        urls = []
        if "Thumb" in tags: urls.append(f"{base}/Items/{it['Id']}/Images/Thumb?quality=90&tag={tags['Thumb']}&maxWidth=1920")
        if "Primary" in tags: urls.append(f"{base}/Items/{it['Id']}/Images/Primary?quality=90&tag={tags['Primary']}&maxWidth=1200")
        bd = it.get("BackdropImageTags") or []
        if bd: urls.append(f"{base}/Items/{it['Id']}/Images/Backdrop/0?quality=90&tag={bd[0]}&maxWidth=1920")
        for url in urls:
            sha = hashlib.sha256(url.encode()).hexdigest()
            stem = os.path.join(cache, "figure-" + sha)
            if os.path.exists(stem + ".png") or os.path.exists(stem + ".miss"):
                skipped += 1; continue
            src = os.path.join(work, sha + ".jpg")
            try:
                urllib.request.urlretrieve(url, src)
            except Exception as e:
                print(f"skip {it['Name']}: {e}"); continue
            todo.append((url, src))
    print(f"{v['Name']}: {len(items)} titles")
open(os.path.join(work, "pairs.txt"), "w").write("\n".join(f"{u}\n{s}" for u, s in todo))
print(f"{skipped} images already judged, {len(todo)} to cut")
EOF

PAIRS=("${(@f)$(cat "$WORK/pairs.txt")}")
if (( ${#PAIRS} > 1 )); then
    swift "$HERE/segment-figures.swift" "$CACHE" "${PAIRS[@]}"
fi
echo "cache now holds $(ls "$CACHE" | grep -c '^figure-.*\.png$') figures — relaunch the app to see them"
rm -rf "$WORK"
