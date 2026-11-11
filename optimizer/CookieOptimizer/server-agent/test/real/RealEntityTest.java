import java.io.File;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.util.Map;

/**
 * v5 against the game's real classes (JDK 25 + projectzomboid.jar):
 *  R1 the patched EntityBucket and EngineEntityManager load and pass the JVM's bytecode check
 *  R2 the real EntityBucket, patched + fast removal on, gives exactly the lists of the
 *     unpatched one (thousands of random adds/removes, checked after every step)
 * Usage: java -cp <this dir> RealEntityTest <projectzomboid.jar> <agent classes> <real test classes> <patched classes dir>
 */
public final class RealEntityTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static final class Patched extends URLClassLoader {
        final File dir;
        Patched(URL[] urls, File dir) { super(urls, ClassLoader.getPlatformClassLoader()); this.dir = dir; }
        @Override protected Class<?> findClass(String name) throws ClassNotFoundException {
            File f = dir == null ? null : new File(dir, name.replace('.', '/') + ".class");
            if (f != null && f.isFile() && name.startsWith("zombie.")) {
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
        URL game = new File(a[0]).toURI().toURL(), agent = new File(a[1]).toURI().toURL(), real = new File(a[2]).toURI().toURL();
        File patchedDir = new File(a[3]);
        System.out.println("R1 patched classes load and verify");
        Patched pl = new Patched(new URL[] {real, agent, game}, patchedDir);
        for (String c : new String[] {"zombie.entity.EntityBucket", "zombie.entity.EngineEntityManager", "zombie.entity.EntityBucket$CustomBucket"}) {
            try {
                Class<?> k = Class.forName(c, true, pl);
                check(k.getClassLoader() == pl, c + " loaded (" + (new File(patchedDir, c.replace('.', '/') + ".class").isFile() ? "patched" : "as is") + ")");
            } catch (Throwable t) {
                check(false, c + ": " + t);
            }
        }
        System.out.println("R2 real bucket: patched + fast removal = the game's own lists");
        Patched vanilla = new Patched(new URL[] {real, game}, null);
        Class<?> ix = Class.forName("cookie.slicer.EntityIndex", true, pl);
        Method setUse = ix.getDeclaredMethod("setUse", boolean.class, Thread.class);
        setUse.setAccessible(true);
        setUse.invoke(null, true, Thread.currentThread());
        Method minute = ix.getDeclaredMethod("minute");
        minute.setAccessible(true);
        Method runP = Class.forName("zombie.entity.BucketDrive", true, pl).getMethod("run", long.class, int.class, int.class);
        Method runV = Class.forName("zombie.entity.BucketDrive", true, vanilla).getMethod("run", long.class, int.class, int.class);
        for (int[] c : new int[][] {{1, 4000, 50}, {2, 20000, 600}, {3, 8000, 5000}}) {
            String v = (String) runV.invoke(null, (long) c[0], c[1], c[2]);
            String p = (String) runP.invoke(null, (long) c[0], c[1], c[2]);
            String m = (String) minute.invoke(null);
            check(v.equals(p) && !m.startsWith("entity lists: removed 0 fast"),
                "seed " + c[0] + ", " + c[1] + " steps, " + c[2] + " entities: " + p.substring(0, Math.min(60, p.length())) + " | " + m);
        }
        // off: the patched bucket still gives the game's lists, nothing fast
        setUse.invoke(null, false, Thread.currentThread());
        String v = (String) runV.invoke(null, 9L, 5000, 300), p = (String) runP.invoke(null, 9L, 5000, 300);
        String m = (String) minute.invoke(null);
        check(v.equals(p) && m.startsWith("entity lists: removed 0 fast"), "switched off: same lists, game's own search (" + m + ")");
        System.out.println(fails == 0 ? "RealEntityTest: all passed" : "RealEntityTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
