#!/bin/bash
# Cookie Slicer Helper - Setup (Linux). Copyright (c) AKA / Cookie Cheetah.
# Same as CookieSlicer-Setup.bat: copies CookieSlicerHelper.jar (from the Cookie Slicer
# mod Steam downloaded) to ~/.local/share/CookieSlicer, writes run.sh there and shows the
# Steam launch option to paste once. No game file is changed. Run: bash cookieslicer-setup.sh
set -u
APP="${XDG_DATA_HOME:-$HOME/.local/share}/CookieSlicer"
JAR=CookieSlicerHelper.jar
ROOTS=("$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam")

libs() {
    for r in "${ROOTS[@]}"; do
        [ -d "$r/steamapps" ] && echo "$r"
        [ -f "$r/steamapps/libraryfolders.vdf" ] && grep -o '"path"[[:space:]]*"[^"]*"' "$r/steamapps/libraryfolders.vdf" | sed 's/.*"\([^"]*\)"$/\1/'
    done | sort -u
}

findjar() {
    local self; self="$(cd "$(dirname "$0")" && pwd)/$JAR"
    { [ -f "$self" ] && echo "$self"
      while read -r l; do ls -1 "$l"/steamapps/workshop/content/108600/*/mods/CookieSlicer/42/helper/$JAR 2>/dev/null; done < <(libs)
    } | xargs -r -d '\n' ls -1t 2>/dev/null | head -1
}

writerun() {
    cat > "$APP/run.sh" <<'RUN'
#!/bin/bash
# Cookie Slicer - game start script (Steam launch option: bash "<this file>" %command%).
# Adds the helper (jar next to this file), the RAM chosen in the Slicer window (heap.txt)
# and Java's own RAM savers (off when ramsave.txt says ramsave=0).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
opt="client"
for a in "$@"; do case "$a" in -cachedir=*) opt="$opt;cachedir=${a#-cachedir=}" ;; esac; done
[ -f "$here/CookieSlicerHelper.jar" ] && export JAVA_TOOL_OPTIONS="\"-javaagent:$here/CookieSlicerHelper.jar=$opt\""
jo=""
mb=""
if [ -f "$here/heap.txt" ]; then
    mb="$(sed -n 's/^heap_mb=\([0-9][0-9]*\).*/\1/p' "$here/heap.txt" | head -1)"
    if [ -n "$mb" ] && [ "$mb" -ge 2048 ] && [ "$mb" -le 32768 ]; then jo="-Xmx${mb}m"; else mb=""; fi
fi
if ! grep -qs 'ramsave=0' "$here/ramsave.txt"; then
    jo="$jo -XX:+IgnoreUnrecognizedVMOptions -XX:+UseCompactObjectHeaders -XX:+UseStringDeduplication -XX:ZUncommitDelay=60"
    [ -n "$mb" ] && jo="$jo -XX:SoftMaxHeapSize=$((mb * 4 / 5))m"
fi
[ -n "$jo" ] && export _JAVA_OPTIONS="${jo# }"
exec "$@"
RUN
}

echo
echo "  Cookie Slicer Helper - Setup"
echo "  [1] Install or update   [2] Uninstall   [3] Check"
read -r -p "  Type 1, 2 or 3 and press Enter: " c
line="bash \"$APP/run.sh\" %command%"
case "$c" in
1)  src="$(findjar)"
    [ -n "$src" ] || { echo "Helper file not found: join the Cookie Cheetah server once, close the game, run this again."; exit 1; }
    mkdir -p "$APP" && cp -f "$src" "$APP/$JAR" && writerun
    echo "Helper files: $APP"
    echo
    echo "Once: Steam > Project Zomboid > Properties > Launch Options - put this IN FRONT of anything already there:"
    echo "  $line"
    command -v xclip >/dev/null && printf '%s' "$line" | xclip -selection clipboard && echo "(copied)" ;;
2)  rm -f "$APP/$JAR" "$APP/heap.txt" "$APP/ramsave.txt"
    [ -f "$APP/cachedir.txt" ] && rm -f "$(head -1 "$APP/cachedir.txt")/Lua/CookieSlicer_pc.txt"
    rm -f "$HOME/Zomboid/Lua/CookieSlicer_pc.txt"
    echo "Helper removed (run.sh stays, so the game still starts)."
    echo "Steam > Project Zomboid > Properties > Launch Options: remove  $line" ;;
*)  [ -f "$APP/$JAR" ] && echo "Helper file: $APP/$JAR" || echo "Helper file: not installed"
    [ -f "$APP/heap.txt" ] && echo "Game RAM chosen in game: $(cat "$APP/heap.txt")"
    echo "Steam launch option needed: $line" ;;
esac
