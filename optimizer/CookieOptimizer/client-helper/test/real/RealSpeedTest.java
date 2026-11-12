import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Helper 1.3.0 speed-ups against the game's real classes (JDK 25 + projectzomboid.jar), the game's
 * classes patched the way SpeedPatcher does at game start:
 *  S1 the five patched classes load and pass Java's bytecode check
 *  S2 the entity index waits for the game's main thread (found by name at its first Lua event)
 *  S3 real Event.trigger + real Lua handlers: same calls in the same order as unpatched
 *  S4 real EntityBucket: same lists as unpatched, removals found at once
 *  S5 a real Lua handler failing 250 times + the real ExceptionLogger 250 times: 3 printed in
 *     full + a line at 100 and 200 each; the game's own error counter still counts all
 *  S6 switched off in the window: the game's own way for all three, same results
 * Usage: java -cp <this dir> RealSpeedTest <unsigned pz jar> <helper classes> <driver classes> <patched dir>
 * (needs the game's stdlib.lua in the working folder, for the game's Lua)
 */
public final class RealSpeedTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    /** loads the game's classes from the jar, except the ones in the patched folder */
    static final class Patched extends URLClassLoader {
        final File dir;
        Patched(URL[] urls, File dir) { super(urls, ClassLoader.getPlatformClassLoader()); this.dir = dir; }
        @Override protected Class<?> findClass(String name) throws ClassNotFoundException {
            File f = dir == null ? null : new File(dir, name.replace('.', '/') + ".class");
            if (f != null && f.isFile()) {
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

    static ClassLoader pl;

    static Object field(String cls, String name) throws Exception {
        Field f = Class.forName(cls, true, pl).getDeclaredField(name);
        f.setAccessible(true);
        return f.get(null);
    }

    static void setField(String cls, String name, Object v) throws Exception {
        Field f = Class.forName(cls, true, pl).getDeclaredField(name);
        f.setAccessible(true);
        f.set(null, v);
    }

    static Object call(String cls, String name, Class<?>[] types, Object... args) throws Exception {
        Method m = Class.forName(cls, true, pl).getDeclaredMethod(name, types);
        m.setAccessible(true);
        return m.invoke(null, args);
    }

    static final String H = "cookie.slicer.helper.SpeedHooks";

    /** what the helper writes to the pc file, after the main thread (this one) collected the numbers */
    @SuppressWarnings("unchecked")
    static Map<String, String> status() throws Exception {
        if (field(H, "main") == Thread.currentThread()) call(H, "sync", new Class<?>[0]);
        Map<String, String> m = new LinkedHashMap<>();
        call(H, "status", new Class<?>[] {Map.class}, m);
        return m;
    }

    static long num(Map<String, String> m, String k) {
        return Long.parseLong(m.getOrDefault(k, "-1"));
    }

    public static void main(String[] a) throws Exception {
        URL game = new File(a[0]).toURI().toURL(), helper = new File(a[1]).toURI().toURL(), drive = new File(a[2]).toURI().toURL();
        File patched = new File(a[3]);
        Patched p = new Patched(new URL[] {drive, helper, game}, patched);
        Patched v = new Patched(new URL[] {drive, game}, null);
        pl = p;

        System.out.println("S1 patched classes load and verify");
        for (String c : new String[] {"zombie.Lua.Event", "se.krka.kahlua.vm.KahluaThread", "zombie.core.logger.ExceptionLogger",
                "zombie.entity.EntityBucket", "zombie.entity.EngineEntityManager"}) {
            boolean isPatched = new File(patched, c.replace('.', '/') + ".class").isFile();
            try {
                Class<?> k = Class.forName(c, true, p);
                check(isPatched && k.getClassLoader() == p, c + " loaded and verified (patched)");
            } catch (VerifyError | ClassFormatError t) {
                check(false, c + ": " + t);
            } catch (ExceptionInInitializerError | NoClassDefFoundError t) {
                check(isPatched && !(t.getCause() instanceof VerifyError), c + " verified (patched); its start-up needs the game: " + t.getClass().getSimpleName());
            }
        }

        Method runP = Class.forName("zombie.Lua.EventDrive", true, p).getMethod("runAll", long.class, int.class);
        Method runV = Class.forName("zombie.Lua.EventDrive", true, v).getMethod("runAll", long.class, int.class);
        Method bucketP = Class.forName("zombie.entity.BucketDrive", true, p).getMethod("run", long.class, int.class, int.class);
        Method bucketV = Class.forName("zombie.entity.BucketDrive", true, v).getMethod("run", long.class, int.class, int.class);
        call(H, "setWant", new Class<?>[] {boolean.class}, true);

        System.out.println("S2 the entity index waits for the game's main thread");
        // this thread is "main", not the game's "MainThread": events fire, nothing is taken as the main thread
        String v0 = (String) runV.invoke(null, 11L, 50), p0 = (String) runP.invoke(null, 11L, 50);
        String bv0 = (String) bucketV.invoke(null, 4L, 3000, 200), bp0 = (String) bucketP.invoke(null, 4L, 3000, 200);
        Map<String, String> m0 = status();
        check(v0.equals(p0) && bv0.equals(bp0) && "0".equals(m0.get("speed_main")) && field("cookie.slicer.helper.EntityIndex", "use").equals(false),
            "thread \"" + Thread.currentThread().getName() + "\": not the main thread, entity lists the game's own way, same results");
        setField(H, "mainName", Thread.currentThread().getName());
        setField(H, "lastOther", null); // (only tests rename)
        // a Lua event on another thread with another name does not count
        Thread other = new Thread(() -> {
            try { runP.invoke(null, 12L, 5); } catch (Exception e) { throw new RuntimeException(e); }
        }, "LoaderThread");
        other.start();
        other.join();
        check(field(H, "main") == null, "an event on another thread (\"LoaderThread\") is not taken as the main thread");
        setField(H, "lastOther", null);
        runP.invoke(null, 13L, 5); // the first event on the main thread
        Map<String, String> m1 = status();
        check("1".equals(m1.get("speed_main")) && field("cookie.slicer.helper.EntityIndex", "use").equals(true),
            "first event on \"" + Thread.currentThread().getName() + "\": main thread found, entity index on");

        System.out.println("S3 real Event.trigger + real Lua handlers");
        long f0 = num(status(), "speed_ev_fast");
        for (long seed = 1; seed <= 3; seed++) {
            String ov = (String) runV.invoke(null, seed, 400), op = (String) runP.invoke(null, seed, 400);
            check(ov.equals(op) && ov.length() > 1000, "seed " + seed + ": " + (ov.length() - ov.replace(",", "").length()) + " handler calls, same order");
        }
        Map<String, String> m3 = status();
        long fast = num(m3, "speed_ev_fast") - f0, searched = num(m3, "speed_ev_searched");
        check(fast > 5 * searched, "most checks answered in place (" + fast + " in place, " + searched + " searched since start)");

        System.out.println("S4 real EntityBucket");
        for (int[] c : new int[][] {{1, 4000, 50}, {2, 20000, 600}, {3, 8000, 5000}}) {
            String ov = (String) bucketV.invoke(null, (long) c[0], c[1], c[2]);
            String op = (String) bucketP.invoke(null, (long) c[0], c[1], c[2]);
            check(ov.equals(op), "seed " + c[0] + ", " + c[1] + " steps, " + c[2] + " entities: same lists");
        }
        Map<String, String> m4 = status();
        check(num(m4, "speed_ent_fast") > 1000 && num(m4, "speed_ent_fast") > 10 * Math.max(1, num(m4, "speed_ent_slow")),
            "removals found at once: " + m4.get("speed_ent_fast") + " fast, " + m4.get("speed_ent_slow") + " the game's own way");

        System.out.println("S5 the same error 250 times");
        Method errP = Class.forName("zombie.Lua.EventDrive", true, p).getMethod("errors", int.class);
        int e0 = (Integer) field("se.krka.kahlua.vm.KahluaThread", "errorCount");
        long c0 = num(status(), "speed_err_cut");
        errP.invoke(null, 250);
        int e1 = (Integer) field("se.krka.kahlua.vm.KahluaThread", "errorCount");
        long c1 = num(status(), "speed_err_cut");
        check(c1 - c0 == 245, "Lua: 3 in full, a line at 100 and 200, " + (c1 - c0) + " not printed");
        check(e1 - e0 == 250, "the game's own Lua error counter still counts all 250 (" + (e1 - e0) + ")");
        try {
            Method le = Class.forName("zombie.core.logger.ExceptionLogger", true, p).getMethod("logException", Throwable.class);
            RuntimeException same = new IllegalStateException("test error from a mod");
            for (int i = 0; i < 250; i++) le.invoke(null, same);
            long c2 = num(status(), "speed_err_cut");
            check(c2 - c1 == 245, "Java (ExceptionLogger): 3 in full, a line at 100 and 200, " + (c2 - c1) + " not printed");
        } catch (ExceptionInInitializerError | NoClassDefFoundError t) {
            System.out.println("     (ExceptionLogger needs the running game here: " + t.getClass().getSimpleName() + ")");
        }

        System.out.println("S6 switched off in the window");
        call(H, "setWant", new Class<?>[] {boolean.class}, false);
        Map<String, String> s0 = status(); // the main thread applies it
        check(field("cookie.slicer.helper.EntityIndex", "use").equals(false) && field("cookie.slicer.helper.FastEvents", "use").equals(false)
            && field("cookie.slicer.helper.LogThrottle", "use").equals(false), "all three off");
        String ov = (String) runV.invoke(null, 21L, 200), op = (String) runP.invoke(null, 21L, 200);
        String bv = (String) bucketV.invoke(null, 22L, 6000, 400), bp = (String) bucketP.invoke(null, 22L, 6000, 400);
        errP.invoke(null, 120);
        Map<String, String> s1 = status();
        check(ov.equals(op) && bv.equals(bp), "same events and lists");
        check(num(s1, "speed_ev_fast") == num(s0, "speed_ev_fast") && num(s1, "speed_ent_fast") == num(s0, "speed_ent_fast")
            && num(s1, "speed_err_cut") == num(s0, "speed_err_cut"), "nothing in place, nothing fast, every error printed");
        call(H, "setWant", new Class<?>[] {boolean.class}, true);
        status();
        bucketP.invoke(null, 23L, 3000, 300);
        check(num(status(), "speed_ent_fast") > num(s1, "speed_ent_fast"), "on again: fast again");

        System.out.println(fails == 0 ? "RealSpeedTest: all passed" : "RealSpeedTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
