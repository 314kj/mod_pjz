#!/bin/sh
# Behaviour tests.
#   HelperTest  numbers, RAM request, options (no game needed to run)
#   ShaderTest  screen looks: the game class patch, the choice file, and (with a display,
#               e.g. xvfb-run) the real drawing code in OpenGL against a reference picture
#   JoinTest    join problems: log lines -> codes, the diag file, ProjectZomboid64.json,
#               the loading screen patch (with the game jar). CONSOLE_TXT: optional real log
#   RamTest     less RAM: the "what uses RAM" list, the window's RAM-saver switch, the pc
#               file (run with the start script's savers and without them; Java 25)
# PZ_COMPILE_JAR: see build.sh. PZ_JAR: the game's projectzomboid.jar. JAVA25: a Java 25+
# runtime for running against the game's classes. SHADER_DIR: day.rgba, ref_golden.rgba
# and the two shader files (made by test/make_reference.py).
set -e
cd "$(dirname "$0")/.."
rm -rf build/test && mkdir -p build/test/out
javac --release 21 -encoding UTF-8 -cp "$PZ_COMPILE_JAR" -d build/test $(find src -name '*.java') test/HelperTest.java test/ShaderTest.java test/JoinTest.java test/RamTest.java
java -cp build/test cookie.slicer.helper.HelperTest build/test/out
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
