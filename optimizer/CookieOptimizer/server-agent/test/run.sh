#!/bin/sh
# Behaviour test of the agent's Hooks against a fake world (no game needed), and the v5
# entity lists against a stand-in list. With JAVA25 + PZ_JAR (+ PZ_COMPILE_JAR, a copy of
# projectzomboid.jar with class version 65 for javac 21) also against the game's real classes.
set -e
cd "$(dirname "$0")/.."
sh build.sh >/dev/null   # (build.sh starts from an empty build folder)
mkdir -p build/test
javac --release 21 -d build/test $(find test/stubs -name '*.java') $(find src -name '*.java') test/cookie/slicer/SlicerTest.java test/cookie/slicer/EntityTest.java
java -cp build/test cookie.slicer.SlicerTest
java -cp build/test cookie.slicer.SlicerTest wrongrev
java -cp build/test cookie.slicer.EntityTest stubs
if [ -n "$JAVA25" ] && [ -n "$PZ_JAR" ] && [ -n "$PZ_COMPILE_JAR" ]; then
  # the game jar is signed: patched classes cannot sit next to signed ones, so use an unsigned copy
  rm -rf build/real && mkdir -p build/real/arr build/real/drive build/real/run build/real/patched
  cp "$PZ_JAR" build/real/pz.jar
  zip -q -d build/real/pz.jar 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' || true
  cp -r build/test/cookie build/real/arr/
  "$JAVA25" -cp build/real/arr:build/real/pz.jar cookie.slicer.EntityTest real
  "$JAVA25" -jar CookieSlicer.jar check "$PZ_JAR" build/real/patched
  javac --release 21 -nowarn -cp "$PZ_COMPILE_JAR" -d build/real/drive test/real/zombie/entity/BucketDrive.java
  javac --release 21 -d build/real/run test/real/RealEntityTest.java
  "$JAVA25" -cp build/real/run RealEntityTest build/real/pz.jar build/classes build/real/drive build/real/patched
fi
