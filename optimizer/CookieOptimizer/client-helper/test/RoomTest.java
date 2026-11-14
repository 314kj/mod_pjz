package cookie.slicer.helper;

import java.io.File;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * Helper 1.5.0 room fix: RoomPatcher on the game's real IsoLightSwitch.
 *  P1-P3  the place is found once, only those 3 bytes change, the game's original is gone;
 *         with a folder argument, writes the patched class (for RealRoomTest)
 *  W1     pc file keys
 * Usage: RoomTest <projectzomboid.jar> [patched classes dir]
 */
public final class RoomTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static void real(String jar, String outDir) throws Exception {
        System.out.println("game classes (" + jar + ")");
        try (ZipFile z = new ZipFile(jar)) {
            for (String c : RoomPatcher.TARGETS) {
                byte[] in = z.getInputStream(new ZipEntry(c + ".class")).readAllBytes();
                byte[] out;
                try {
                    out = RoomPatcher.patch(c, in);
                } catch (Throwable t) {
                    check(false, "P1 " + c + ": " + t.getMessage());
                    continue;
                }
                check(true, "P1 " + c + ": the place was found once");
                int changed = SmoothTest.changedBytes(in, out);
                check(changed > 0 && changed <= 3, "P2 " + c + ": " + changed + " code bytes changed (at most 3), size " + in.length + " -> " + out.length);
                boolean gone;
                try {
                    RoomPatcher.patch(c, out);
                    gone = false;
                } catch (IllegalStateException e) {
                    gone = e.getMessage().contains("found 0");
                }
                check(gone, "P3 " + c + ": the game's original is no longer there");
                if (outDir != null) {
                    File f = new File(outDir, c + ".class");
                    f.getParentFile().mkdirs();
                    Files.write(f.toPath(), out);
                }
            }
        }
    }

    public static void main(String[] a) throws Exception {
        real(a[0], a.length > 1 ? a[1] : null);
        Map<String, String> st = new HashMap<>();
        RoomHooks.status(st);
        check(st.containsKey("room_classes") && st.containsKey("rooms_fixed") && st.containsKey("rooms_gone") && st.containsKey("rooms_fix_failed"),
            "W1 pc file keys: " + st.keySet());
        System.out.println(fails == 0 ? "RoomTest: all ok" : "RoomTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
