package cookie.slicer.helper;

import java.io.File;
import java.nio.file.Files;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * Test tool: patches the game's classes the way SpeedPatcher does when the game loads them and
 * writes them into a folder (for RealSpeedTest), printing each class as ok / FAILED.
 * Usage: SpeedPatchWrite <projectzomboid.jar> <out dir>
 */
public final class SpeedPatchWrite {
    public static void main(String[] a) throws Exception {
        int bad = 0;
        try (ZipFile z = new ZipFile(a[0])) {
            for (String c : SpeedPatcher.TARGETS) {
                ZipEntry e = z.getEntry(c + ".class");
                byte[] in = z.getInputStream(e).readAllBytes();
                try {
                    byte[] out = SpeedPatcher.patch(c, in);
                    File f = new File(a[1], c + ".class");
                    f.getParentFile().mkdirs();
                    Files.write(f.toPath(), out);
                    System.out.println("ok       " + c + " (" + in.length + " -> " + out.length + " bytes)");
                } catch (Throwable t) {
                    bad++;
                    System.out.println("FAILED   " + c + ": " + t.getMessage());
                }
            }
        }
        System.exit(bad == 0 ? 0 : 1);
    }
}
