# Makes a copy of projectzomboid.jar that javac 21 can read (class-file version set to 65).
# Only for compiling the helper; nothing of the game goes into CookieSlicerHelper.jar.
# usage: python3 pz-compile-jar.py <projectzomboid.jar> <out.jar>
import sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(out, 'w', zipfile.ZIP_STORED) as zo:
    for info in zi.infolist():
        if not info.filename.endswith('.class') or info.filename.startswith('META-INF/'):
            continue
        d = bytearray(zi.read(info))
        if d[:4] == b'\xca\xfe\xba\xbe' and int.from_bytes(d[6:8], 'big') > 65:
            d[6:8] = (65).to_bytes(2, 'big')
        zo.writestr(info.filename, bytes(d))
