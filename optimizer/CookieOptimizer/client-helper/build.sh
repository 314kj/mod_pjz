#!/bin/sh
# Builds CookieSlicerHelper.jar with JDK 21 or newer.
# The screen-look classes compile against the game's own jar (projectzomboid.jar, which
# also holds LWJGL). The game's classes are newer than JDK 21 can read, so the build
# uses a copy whose class-file version numbers say 65 (only for compiling; nothing of
# the game goes into our jar). Set PZ_COMPILE_JAR to that copy (see test/pz-compile-jar.py).
set -e
cd "$(dirname "$0")"
: "${PZ_COMPILE_JAR:?set PZ_COMPILE_JAR (a copy of projectzomboid.jar made readable for javac 21)}"
rm -rf build && mkdir -p build/classes/cookie/slicer/helper
javac --release 21 -Xlint:all -Xlint:-options -cp "$PZ_COMPILE_JAR" -d build/classes $(find src -name '*.java')
# the shader files ride along in the jar (used when the mod's copy cannot be found)
SH=../../CookieSlicer/Contents/mods/CookieSlicer/42/media/shaders
cp "$SH/cookie_post.vert" "$SH/cookie_post.frag" build/classes/cookie/slicer/helper/
jar cfm CookieSlicerHelper.jar MANIFEST.MF -C build/classes .
echo "built CookieSlicerHelper.jar"
