#!/bin/zsh
#
# seed-simulator-cutouts.sh — give the tvOS simulator the cast cut-outs a real Apple TV makes itself.
#
#   Scripts/seed-simulator-cutouts.sh              # booted Apple TV simulator, every movie's cast
#   Scripts/seed-simulator-cutouts.sh <udid>       # a specific simulator
#
# The movie page's coins stand each actor's cut-out bust in relief, and the app cuts those out on
# device with Vision (`PortraitCutoutCache`). The tvOS simulator can't — Vision fails there with
# "Could not create inference context" — so every coin shows the plain photo. This script does the
# same segmentation on the Mac for every actor of every movie the signed-in user has, and drops the
# PNGs into the simulator app's cache under the names the app would have written
# (`Library/Caches/cutouts/<sha256 of the headshot URL>.png`), so the simulator renders exactly
# what the device would. Re-run after the library grows; existing files are skipped.
#
# Reads the server address and token from the simulator app's own preferences — nothing is printed.
set -e
UDID=${1:-$(xcrun simctl list devices booted | grep -i "apple tv" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' | head -1)}
BUNDLE=net.graficx.jellytv
[[ -n "$UDID" ]] || { echo "no booted Apple TV simulator"; exit 1 }
CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
CACHE="$CONTAINER/Library/Caches/cutouts"
mkdir -p "$CACHE"
WORK=$(mktemp -d)
HERE=${0:a:h}

# Every actor with a headshot across every movie → headshot files + the cache key each maps to.
python3 - "$CONTAINER" "$WORK" "$CACHE" <<'EOF'
import plistlib, sys, glob, urllib.request, json, hashlib, os
container, work, cache = sys.argv[1:4]
prefs = glob.glob(os.path.join(container, "Library/Preferences/*.plist"))[0]
d = plistlib.load(open(prefs, "rb"))
host, port, key, uid = d["jelly:server.host"], d.get("jelly:server.port"), d["jelly:auth.apiKey"], d["jelly:auth.userId"]
base = f"http://{host}:{port}" if port else f"http://{host}"
def get(path):
    req = urllib.request.Request(base + path, headers={"X-Emby-Token": key})
    return json.load(urllib.request.urlopen(req, timeout=30))
movies = get(f"/Users/{uid}/Items?includeItemTypes=Movie&recursive=true&fields=People")["Items"]
seen, todo, skipped = set(), [], 0
for movie in movies:
    actors = [p for p in movie.get("People", []) if p.get("Type") == "Actor"][:8]
    for a in actors:
        tag = a.get("PrimaryImageTag")
        if not tag or a["Id"] in seen: continue
        seen.add(a["Id"])
        url = f"{base}/Items/{a['Id']}/Images/Primary?quality=90&tag={tag}&maxWidth=600"
        sha = hashlib.sha256(url.encode()).hexdigest()
        if os.path.exists(os.path.join(cache, sha + ".png")):
            skipped += 1; continue
        src = os.path.join(work, sha + ".jpg")
        try:
            urllib.request.urlretrieve(url, src)
        except Exception as e:
            print(f"skip {a['Name']}: {e}"); continue
        todo.append((src, os.path.join(work, sha + ".png")))
open(os.path.join(work, "pairs.txt"), "w").write("\n".join(f"{s}\n{o}" for s, o in todo))
print(f"{len(movies)} movies, {len(seen)} actors with headshots, {skipped} already cached, {len(todo)} to cut")
EOF

PAIRS=("${(@f)$(cat "$WORK/pairs.txt")}")
if (( ${#PAIRS} > 1 )); then
    swift "$HERE/segment-headshots.swift" "${PAIRS[@]}" | grep -c "→" | sed 's/$/ cut-outs made/'
    cp "$WORK"/*.png "$CACHE"/ 2>/dev/null || true
fi
echo "cache now holds $(ls "$CACHE" | wc -l | tr -d ' ') cut-outs — relaunch the app to see them"
rm -rf "$WORK"
