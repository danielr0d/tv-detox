#!/bin/sh
# Sets the home screen wallpaper to a random picture from konachan.com. Needs adb, curl and jq.
#
#   sh wallpaper.sh <TV_IP>                       safe for work (default)
#   sh wallpaper.sh <TV_IP> nsfw                  questionable and explicit
#   sh wallpaper.sh <TV_IP> explicit              explicit only
#   sh wallpaper.sh <TV_IP> any                   any rating
#   sh wallpaper.sh <TV_IP> sfw "scenic sky"      extra Konachan tags
#   sh wallpaper.sh <TV_IP> file ~/pic.jpg        your own picture
#   sh wallpaper.sh <TV_IP> off                   back to the gradient
#
# New wallpaper every 30 minutes: EVERY=1800 sh wallpaper.sh <TV_IP> sfw
# The home screen picks it up the next time it's shown; if it's on screen now, it's refreshed.
set -e

TARGET="$1"; MODE="${2:-sfw}"; EXTRA="$3"
[ -n "$TARGET" ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 1; }
for c in adb curl jq; do
  command -v $c >/dev/null 2>&1 || { echo "$c is missing. Install it first." >&2; exit 1; }
done

case "$TARGET" in
  *.*.*.*:*) TV=$TARGET ;;
  *.*.*.*)   TV=$TARGET:5555 ;;
  *)         TV=$TARGET ;;
esac

PKG=com.ansub.tvhome
DIR=/sdcard/Android/data/$PKG/files
API=https://konachan.com/post.json
UA="tv-detox-wallpaper/1.0"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT INT TERM

case "$MODE" in
  sfw)      RATING="rating:s" ;;
  nsfw)     RATING="-rating:s" ;;
  explicit) RATING="rating:e" ;;
  any)      RATING="" ;;
  off|file) ;;
  *) echo "Unknown mode: $MODE (use sfw, nsfw, explicit, any, file or off)" >&2; exit 1 ;;
esac

connect() {
  case "$TV" in *:*) adb connect "$TV" >/dev/null 2>&1 || true ;; esac
  case "$(adb -s "$TV" get-state 2>&1 || true)" in
    device) ;;
    *unauthorized*) echo "Your TV is asking \"Allow debugging?\". Press Allow, then run this again." >&2; return 1 ;;
    *) echo "Can't reach $TV. Is the TV on, with network debugging on?" >&2; return 1 ;;
  esac
}

# Picks a random landscape picture at least 1920 wide and downloads it to $TMP/wall.jpg.
fetch() {
  # Never anything with minors in a sexual context, whatever the rating: filtered here and again below.
  tags="order:random width:1920.. $RATING -loli -shota $EXTRA"
  curl -fsSG "$API" -A "$UA" --data-urlencode "tags=$tags" --data-urlencode limit=40 -o "$TMP/posts.json" \
    || { echo "Konachan didn't answer." >&2; return 1; }
  url=$(jq -r '[ .[]
      | select(.width >= .height * 1.3)
      | select((" " + .tags + " ") | test(" (loli|shota|child|toddler) ") | not)
      | .jpeg_url ] | first // empty' "$TMP/posts.json")
  [ -n "$url" ] || { echo "No landscape pictures found for: $tags" >&2; return 1; }
  id=$(jq -r --arg u "$url" '.[] | select(.jpeg_url == $u) | .id' "$TMP/posts.json" | head -1)
  echo "Konachan #$id  https://konachan.com/post/show/$id"
  curl -fsSL -A "$UA" -o "$TMP/wall.jpg" "$url"
}

# Pushes next to the old one, then swaps, so the home screen never reads half a file.
push() {
  adb -s "$TV" shell mkdir -p "$DIR"
  adb -s "$TV" push "$1" "$DIR/wallpaper.tmp" >/dev/null
  adb -s "$TV" shell mv -f "$DIR/wallpaper.tmp" "$DIR/wallpaper.jpg"
}

# Only brings the home screen back if it's already on screen, so it never interrupts a show.
refresh() {
  if adb -s "$TV" shell dumpsys activity activities 2>/dev/null \
      | grep -E 'mResumedActivity|topResumedActivity' | grep -q "$PKG/"; then
    adb -s "$TV" shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1 || true
  fi
}

once() {
  connect
  case "$MODE" in
    off)  adb -s "$TV" shell rm -f "$DIR/wallpaper.jpg"; echo "Wallpaper removed." ;;
    file) [ -f "$EXTRA" ] || { echo "No such file: $EXTRA" >&2; return 1; }
          push "$EXTRA"; echo "Wallpaper set." ;;
    *)    fetch; push "$TMP/wall.jpg"; echo "Wallpaper set." ;;
  esac
  refresh
}

if [ -n "$EVERY" ]; then
  while :; do once || true; sleep "$EVERY"; done
else
  once
fi
