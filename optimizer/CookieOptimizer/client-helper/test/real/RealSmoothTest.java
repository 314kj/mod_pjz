import java.io.File;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;

/**
 * Helper 1.4.0 smooth against the game's real classes (the game's Java 25 + an unsigned copy of
 * projectzomboid.jar): IsoChunkMap and IsoWorld patched the way SmoothPatcher does at game start
 *  R1 both classes load and pass Java's bytecode check (a VerifyError fails; the game's own start-up
 *     code needing a running game afterwards is expected outside the game)
 *  R2 their methods resolve the hook calls: SmoothHooks.chunkQueueSize / chunkQueuePoll / zombies3d
 *     exist with the descriptors the patch wrote
 * Usage: java -cp <this dir> RealSmoothTest <unsigned pz jar> <helper classes> <patched dir>
 */
public final class RealSmoothTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static final class Patched extends URLClassLoader {
        final File dir;
        Patched(URL[] urls, File dir) { super(urls, ClassLoader.getPlatformClassLoader()); this.dir = dir; }
        @Override protected Class<?> findClass(String name) throws ClassNotFoundException {
            File f = new File(dir, name.replace('.', '/') + ".class");
            if (f.isFile()) {
                try {
                    byte[] b = Files.readAllBytes(f.toPath());
                    return defineClass(name, b, 0, b.length);
                } catch (java.io.IOException e) {
                    throw new ClassNotFoundException(name, e);
                }
            }
            return super.findClass(name);
        }
    }

    public static void main(String[] a) throws Exception {
        File dir = new File(a[2]);
        ClassLoader pl = new Patched(new URL[] {new File(a[0]).toURI().toURL(), new File(a[1]).toURI().toURL()}, dir);
        for (String c : new String[] {"zombie.iso.IsoChunkMap", "zombie.iso.IsoWorld"}) {
            String how;
            boolean ok;
            try {
                Class.forName(c, true, pl);
                ok = true;
                how = "loaded";
            } catch (VerifyError | ClassFormatError e) {
                ok = false;
                how = e.toString();
            } catch (ExceptionInInitializerError | NoClassDefFoundError | UnsatisfiedLinkError e) {
                // verified and linked; its static start-up needs the running game
                ok = !(e.getCause() instanceof VerifyError) && !String.valueOf(e).contains("VerifyError");
                how = "verified (start-up outside the game: " + e.getClass().getSimpleName() + ")";
            }
            check(ok, "R1 " + c + ": " + how);
            boolean fromDir = new File(dir, c.replace('.', '/') + ".class").isFile();
            check(fromDir, "R1 " + c + ": the patched copy was the one loaded");
        }
        Class<?> h = Class.forName("cookie.slicer.helper.SmoothHooks", false, pl);
        Class<?> q = Class.forName("zombie.util.CappedConcurrentQueue", false, pl);
        Method size = h.getMethod("chunkQueueSize", q), poll = h.getMethod("chunkQueuePoll", q), z = h.getMethod("zombies3d");
        check(size.getReturnType() == int.class && poll.getReturnType() == Object.class && z.getReturnType() == int.class,
            "R2 SmoothHooks.chunkQueueSize(Queue)I, chunkQueuePoll(Queue)Object, zombies3d()I are there");
        System.out.println(fails == 0 ? "RealSmoothTest: all ok" : "RealSmoothTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
