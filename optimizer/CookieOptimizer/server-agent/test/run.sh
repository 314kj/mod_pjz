#!/bin/sh
# Behaviour test of the agent's Hooks against a fake world (no game needed).
set -e
cd "$(dirname "$0")/.."
rm -rf build/test && mkdir -p build/test
javac --release 21 -d build/test $(find test/stubs -name '*.java') $(find src -name '*.java') test/cookie/slicer/SlicerTest.java
java -cp build/test cookie.slicer.SlicerTest
java -cp build/test cookie.slicer.SlicerTest wrongrev
