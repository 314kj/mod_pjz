#!/bin/sh
# Behaviour tests.
#   HelperTest  numbers, RAM request, options (no game needed to run)
#   ShaderTest  screen looks: the game class patch, the choice file, and (with a display,
#               e.g. xvfb-run) the real drawing code in OpenGL against a reference picture
#   JoinTest    join problems: log lines -> codes, the diag file, ProjectZomboid64.json,
#               the loading screen patch (with the game jar). CONSOLE_TXT: optional real log
#   RamTest     less RAM: the "what uses RAM" list, the window's RAM-saver switch, the pc
#               file (run with the start script's savers and without them; Java 25)
#   RecTest     "record 3 minutes" (Java's flight recorder)
#   SmoothTest  1.4.0 map pieces per frame + zombies in 3D (hooks; with PZ_JAR also the real classes)
#   RealSmoothTest  1.4.0 the patched IsoChunkMap / IsoWorld pass Java 25's bytecode check
#   RealSpeedTest  1.3.0 speed-ups against the game's real classes (with PZ_STDLIB, the game's
#               stdlib.lua; uses the server agent's test drivers in ../server-agent/test/real)
# PZ_COMPILE_JAR: see build.sh. PZ_JAR: the game's projectzomboid.jar. JAVA25: a Java 25+
# runtime for running against the game's classes. SHADER_DIR: day.rgba, ref_golden.rgba
# and the two shader files (made by test/make_reference.py).
set -e
cd "$(dirname "$0")/.."
rm -rf build/test && mkdir -p build/test/out
javac --release 21 -encoding UTF-8 -cp "$PZ_COMPILE_JAR" -d build/test $(find src -name '*.java') test/HelperTest.java test/ShaderTest.java test/JoinTest.java test/RamTest.java test/RecTest.java test/SpeedPatchWrite.java test/SmoothTest.java
java -cp build/test cookie.slicer.helper.HelperTest build/test/out
java -cp build/test cookie.slicer.helper.RecTest build/test/out
if [ -n "$PZ_JAR" ] && [ -n "$JAVA25" ]; then
  # the game jar is signed: patched classes cannot sit next to signed ones, so use an unsigned copy
  rm -rf build/smooth && mkdir -p build/smooth/patched build/smooth/run
  cp "$PZ_JAR" build/smooth/pz.jar
  zip -q -d build/smooth/pz.jar 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' || true
  "$JAVA25" -cp "build/test:build/smooth/pz.jar" cookie.slicer.helper.SmoothTest build/smooth/pz.jar build/test/out build/smooth/patched
  javac --release 21 -d build/smooth/run test/real/RealSmoothTest.java
  "$JAVA25" -cp build/smooth/run RealSmoothTest build/smooth/pz.jar build/test build/smooth/patched
fi
if [ -n "$PZ_JAR" ] && [ -n "$JAVA25" ]; then
  "$JAVA25" --enable-native-access=ALL-UNNAMED -cp "$PZ_JAR:build/test" cookie.slicer.helper.JoinTest build/test/out "$PZ_JAR" "${CONSOLE_TXT:-}"
fi
if [ -n "$JAVA25" ]; then
  "$JAVA25" -XX:+UseZGC -XX:+IgnoreUnrecognizedVMOptions -XX:+UseCompactObjectHeaders -XX:+UseStringDeduplication \
    -cp build/test cookie.slicer.helper.RamTest build/test/out 1
  "$JAVA25" -XX:+UseZGC -cp build/test cookie.slicer.helper.RamTest build/test/out 0
fi
if [ -n "$PZ_JAR" ] && [ -n "$JAVA25" ] && [ -n "$SHADER_DIR" ]; then
  "$JAVA25" --enable-native-access=ALL-UNNAMED -cp "$PZ_JAR:build/test" cookie.slicer.helper.ShaderTest "$PZ_JAR" "$SHADER_DIR" ${SHADER_NOGL:+nogl}
fi
if [ -n "$PZ_JAR" ] && [ -n "$JAVA25" ] && [ -n "$PZ_STDLIB" ]; then
  # the game jar is signed: patched classes cannot sit next to signed ones, so use an unsigned copy
  rm -rf build/real && mkdir -p build/real/patched build/real/drive build/real/run build/real/lua
  cp "$PZ_JAR" build/real/pz.jar
  zip -q -d build/real/pz.jar 'META-INF/*.SF' 'META-INF/*.RSA' 'META-INF/*.DSA' 'META-INF/*.EC' || true
  "$JAVA25" -cp build/test cookie.slicer.helper.SpeedPatchWrite "$PZ_JAR" build/real/patched
  D=../server-agent/test/real/zombie
  javac --release 21 -nowarn -cp "$PZ_COMPILE_JAR" -d build/real/drive $D/Lua/EventDrive.java $D/entity/BucketDrive.java
  javac --release 21 -d build/real/run test/real/RealSpeedTest.java
  cp "$PZ_STDLIB" build/real/lua/stdlib.lua
  R="$(pwd)"
  (cd build/real/lua && "$JAVA25" -cp "$R/build/real/run" RealSpeedTest "$R/build/real/pz.jar" "$R/build/test" "$R/build/real/drive" "$R/build/real/patched")
fi
