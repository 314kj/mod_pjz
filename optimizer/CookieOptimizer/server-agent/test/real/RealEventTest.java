import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.URL;

/**
 * v6 against the game's real classes (JDK 25 + projectzomboid.jar):
 *  E1 the game's real Event.trigger with real Lua handlers (game's Kahlua): patched with the
 *     event loop on = exactly the calls of the unpatched one, while handlers remove, add, add
 *     twice and fire other events
 *  E2 a real Lua handler failing 250 times: unpatched prints it 250 times; patched with quiet
 *     repeated errors prints it 3 times in full + a line at 100 and 200; the game's own error
 *     counter still counts all 250
 * Usage: java -cp <this dir> RealEventTest <unsigned pz jar> <agent classes> <driver classes> <patched classes dir>
 */
public final class RealEventTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static void set(ClassLoader l, String cls, String field, Object v) throws Exception {
        Field f = Class.forName(cls, true, l).getDeclaredField(field);
        f.setAccessible(true);
        f.set(null, v);
    }

    static Object get(ClassLoader l, String cls, String field) throws Exception {
        Field f = Class.forName(cls, true, l).getDeclaredField(field);
        f.setAccessible(true);
        return f.get(null);
    }

    static String captured(ClassLoader l, Method m, Object... args) throws Exception {
        PrintStream out = System.out, err = System.err;
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        PrintStream p = new PrintStream(b, true, "UTF-8");
        System.setOut(p);
        System.setErr(p);
        try {
            m.invoke(null, args);
        } finally {
            System.setOut(out);
            System.setErr(err);
        }
        return b.toString("UTF-8");
    }

    static int countOf(String s, String what) {
        int n = 0;
        for (int i = s.indexOf(what); i >= 0; i = s.indexOf(what, i + 1)) n++;
        return n;
    }

    public static void main(String[] a) throws Exception {
        URL game = new File(a[0]).toURI().toURL(), agent = new File(a[1]).toURI().toURL(), drive = new File(a[2]).toURI().toURL();
        File patched = new File(a[3]);
        RealEntityTest.Patched pl = new RealEntityTest.Patched(new URL[] {drive, agent, game}, patched);
        RealEntityTest.Patched vl = new RealEntityTest.Patched(new URL[] {drive, game}, null);
        Class.forName("cookie.slicer.Hooks", true, pl);
        set(pl, "cookie.slicer.FastEvents", "use", true);
        set(pl, "cookie.slicer.LogThrottle", "use", true);
        Method runP = Class.forName("zombie.Lua.EventDrive", true, pl).getMethod("runAll", long.class, int.class);
        Method runV = Class.forName("zombie.Lua.EventDrive", true, vl).getMethod("runAll", long.class, int.class);

        System.out.println("E1 real Event.trigger + real Lua handlers");
        Method minute = Class.forName("cookie.slicer.FastEvents", true, pl).getDeclaredMethod("minute");
        minute.setAccessible(true);
        for (long seed = 1; seed <= 5; seed++) {
            String v = (String) runV.invoke(null, seed, 600), p = (String) runP.invoke(null, seed, 600);
            String m = (String) minute.invoke(null);
            check(v.equals(p) && v.length() > 1000, "seed " + seed + ": " + (v.length() - v.replace(",", "").length()) + " handler calls, same order | " + m);
        }

        System.out.println("E2 a real Lua handler failing 250 times");
        Method errV = Class.forName("zombie.Lua.EventDrive", true, vl).getMethod("errors", int.class);
        Method errP = Class.forName("zombie.Lua.EventDrive", true, pl).getMethod("errors", int.class);
        String ov = captured(vl, errV, 250);
        int cv0 = (Integer) get(pl, "se.krka.kahlua.vm.KahluaThread", "errorCount");
        String op = captured(pl, errP, 250);
        int cv1 = (Integer) get(pl, "se.krka.kahlua.vm.KahluaThread", "errorCount");
        // (outside the game the game's log prints nothing, so the throttle's own count is checked)
        Method lm = Class.forName("cookie.slicer.LogThrottle", true, pl).getDeclaredMethod("minute");
        lm.setAccessible(true);
        String m = (String) lm.invoke(null);
        long cut = Long.parseLong(m.replaceAll("\\D+", ""));
        System.out.println("     " + m + " (output captured: unpatched " + ov.length() + " bytes, patched " + op.length() + ")");
        // a Lua error is printed once per failure (KahluaThread.flushErrorMessage): 3 in full, a line at 100 and 200
        check(cut == 250 - 3 - 2, "patched: the game's real Lua error path reaches the throttle; all but the first 3 (+ a line per 100) not printed");
        check(cv1 - cv0 == 250, "the game's own Lua error counter still counts all 250 (" + (cv1 - cv0) + ")");
        System.out.println("E3 the game's ExceptionLogger with the same Java error 250 times");
        try {
            Class<?> el = Class.forName("zombie.core.logger.ExceptionLogger", true, pl);
            Method le = el.getMethod("logException", Throwable.class);
            RuntimeException same = new IllegalStateException("test error from a mod");
            for (int i = 0; i < 250; i++) le.invoke(null, same);
            String m3 = (String) lm.invoke(null);
            long cut3 = Long.parseLong(m3.replaceAll("\\D+", ""));
            System.out.println("     " + m3);
            check(cut3 == 250 - 3 - 2, "patched ExceptionLogger: 3 in full, a line at 100 and 200, the rest not printed");
        } catch (ExceptionInInitializerError | NoClassDefFoundError t) {
            System.out.println("     (ExceptionLogger needs the running game here: " + t.getClass().getSimpleName() + "; covered by V6Test with stand-ins)");
        }
        System.out.println(fails == 0 ? "RealEventTest: all passed" : "RealEventTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
