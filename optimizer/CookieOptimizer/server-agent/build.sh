#!/bin/sh
# Builds CookieSlicer.jar with any JDK 21 or newer. The stubs are only for compiling.
set -e
cd "$(dirname "$0")"
rm -rf build && mkdir -p build/stubs build/classes
javac --release 21 -d build/stubs $(find stubs -name '*.java')
javac --release 21 -Xlint:all -cp build/stubs -d build/classes $(find src -name '*.java')
jar cfm CookieSlicer.jar MANIFEST.MF -C build/classes .
echo "built CookieSlicer.jar"
