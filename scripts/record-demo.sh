#!/usr/bin/env bash
# Regenerate assets/demo.gif from samples/demo.ts.
#
# Requirements:
#   - nvim with the typescript (and tsx) Treesitter parsers
#   - asciinema (https://github.com/asciinema/asciinema) to record
#   - agg       (https://github.com/asciinema/agg)       to render the GIF
#   - python3 (reads the recording to trim the ending)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cast="$(mktemp -d)/demo.cast"

TYPE_HIDER_ROOT="$root" asciinema record --headless --window-size 88x18 \
  -f asciicast-v2 -c "nvim -u NONE -c \"luafile $root/scripts/demo.lua\"" "$cast"

# Stop just before nvim restores the terminal, so the last frame is the result
# instead of a blank screen.
end="$(python3 - "$cast" <<'PY'
import json
import sys

last = 0.0
with open(sys.argv[1]) as handle:
    for line in handle:
        line = line.strip()
        if not line or line[0] == "{":
            continue
        try:
            event = json.loads(line)
        except Exception:
            continue
        if isinstance(event, list) and event and isinstance(event[0], (int, float)):
            last = event[0]
print(round(max(0.0, last - 0.05), 2))
PY
)"

mkdir -p "$root/assets"
agg --font-family "DejaVu Sans Mono" --font-size 16 --theme monokai \
  --idle-time-limit 3 --last-frame-duration 2.0 --select "..$end" \
  "$cast" "$root/assets/demo.gif"

echo "wrote $root/assets/demo.gif"
