package cookie.slicer;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

import zombie.debug.DebugLogStream;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;

/**
 * v6 checks (stand-in game classes):
 *  V1  event loop: the game's own loop (contains after every handler) vs the loop with
 *      eventGet/eventListed - same handlers in the same order, with handlers that remove
 *      themselves, remove or add others, add twice, and fire other events (also the same one)
 *  V2  repeated errors: 3 in full, then one line every 100; different errors each counted;
 *      object addresses ignored; quiet again after the quiet time; off = all printed
 */
public final class V6Test {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    interface Handler {
        void run(World w, ArrayList<Object> list);
    }

    /** a tiny event system: several lists, handlers that change lists while they run */
    static final class World {
        final List<ArrayList<Object>> lists = new ArrayList<>();
        final StringBuilder trace = new StringBuilder();
        final Random r;
        final boolean ours;
        int depth, next;

        World(long seed, boolean ours) {
            r = new Random(seed);
            this.ours = ours;
        }

        void trigger(ArrayList<Object> callbacks) {
            if (callbacks.isEmpty()) return;
            depth++;
            for (int i = 0; i < callbacks.size(); i++) {
                Object cb = ours ? Hooks.eventGet(callbacks, i) : callbacks.get(i);
                ((Handler) cb).run(this, callbacks);
                boolean still = ours ? Hooks.eventListed(callbacks, cb) : callbacks.contains(cb);
                if (!still) i--;
            }
            depth--;
        }

        Handler make() {
            final int id = next++;
            return new Handler() {
                public void run(World w, ArrayList<Object> list) {
                    w.trace.append(id).append(',');
                    int k = w.r.nextInt(100);
                    if (k < 10) list.remove(this);                                          // removes itself
                    else if (k < 18 && list.size() > 1) list.remove(w.r.nextInt(list.size())); // removes some handler
                    else if (k < 26 && list.size() < 60) list.add(w.make());               // adds a new one
                    else if (k < 29 && !list.isEmpty() && list.size() < 60) list.add(list.get(w.r.nextInt(list.size()))); // adds one twice
                    else if (k < 34 && w.depth < 3) w.trigger(w.lists.get(w.r.nextInt(w.lists.size()))); // fires an event (maybe this one)
                }
                @Override public String toString() { return "h" + id; }
            };
        }
    }

    static String run(long seed, boolean ours) {
        World w = new World(seed, ours);
        for (int l = 0; l < 4; l++) {
            ArrayList<Object> list = new ArrayList<>();
            for (int i = 0; i < 20 + l * 10; i++) list.add(w.make());
            w.lists.add(list);
        }
        for (int tick = 0; tick < 300; tick++) w.trigger(w.lists.get(tick % 4));
        return w.trace.toString();
    }

    public static void main(String[] a) throws Exception {
        // ---------------------------------------------------------------- V1
        System.out.println("V1 event loop: same handlers, same order");
        FastEvents.use = true;
        int same = 0, n = 200;
        long len = 0;
        for (int s = 0; s < n; s++) {
            String g = run(s, false), o = run(s, true);
            if (g.equals(o)) same++;
            len += g.length();
            if (!g.equals(o) && same == s) System.out.println("     first difference, seed " + s);
        }
        String m = FastEvents.minute();
        System.out.println("     " + n + " runs of 300 events (" + len / n / 3 + " handler calls per run), " + m);
        check(same == n, same + "/" + n + " runs identical to the game's own loop");
        long fast = Long.parseLong(m.replaceAll(".*in place (\\d+),.*", "$1")), srch = Long.parseLong(m.replaceAll(".*searched (\\d+)", "$1"));
        check(fast > srch * 5, "most checks answered in place (" + fast + " vs " + srch + " searched)");
        FastEvents.use = false;
        check(run(7, true).equals(run(7, false)), "off: the game's own search, same result");
        check(FastEvents.minute().contains("in place 0,"), "off: nothing answered in place");

        // ---------------------------------------------------------------- V2
        System.out.println("V2 repeated errors");
        LogThrottle.use = true;
        LogThrottle.reset();
        DebugLogStream s = new DebugLogStream();
        DebugType.PRINTED.clear();
        RuntimeException e = new RuntimeException("attempted index: getItems of non-table: zombie.inventory.ItemPickerJava$ItemPickerContainer@780847d2");
        for (int i = 0; i < 250; i++) {
            RuntimeException e2 = new RuntimeException(e.getMessage().replace("780847d2", Integer.toHexString(0x100000 + i)));
            e2.setStackTrace(e.getStackTrace());
            Hooks.printException(s, e2, "Lua(HDF).Add> ", "Exception thrown", LogSeverity.Error);
            Hooks.luaErrorText(DebugType.General, "-----\nattempted index: getItems of non-table: X@" + Integer.toHexString(0xabcdef0 + i));
        }
        check(s.printed.size() == 3, "same Java exception (other address) printed in full 3 times: " + s.printed.size());
        long repeatLines = DebugType.PRINTED.stream().filter(x -> x.startsWith("[CookieSlicer] the same error again")).count();
        long luaFull = DebugType.PRINTED.stream().filter(x -> x.startsWith("-----")).count();
        check(luaFull == 3, "same Lua error text printed in full 3 times: " + luaFull);
        check(repeatLines == 4, "a short line at 100 and 200, for each of the two: " + repeatLines);
        check(DebugType.PRINTED.stream().anyMatch(x -> x.contains("(100 times;") && x.contains("RuntimeException: attempted index")), "the line says how often and what");
        String lm = LogThrottle.minute();
        check(lm.equals("repeated errors not printed " + (2 * 250 - 6 - 4)), lm);
        // a different error is its own
        Hooks.printException(s, new IllegalStateException("other"), "x", "y", LogSeverity.Error);
        check(s.printed.size() == 4, "a different error is printed");
        // quiet time over: counts again
        LogThrottle.quietMs = 0;
        Thread.sleep(5);
        RuntimeException e3 = new RuntimeException(e.getMessage());
        e3.setStackTrace(e.getStackTrace());
        Hooks.printException(s, e3, "Lua(HDF).Add> ", "Exception thrown", LogSeverity.Error);
        check(s.printed.size() == 5, "after the quiet time the same error prints again");
        LogThrottle.quietMs = 600_000;
        // off: everything printed
        LogThrottle.use = false;
        int before = s.printed.size();
        for (int i = 0; i < 10; i++) Hooks.printException(s, e, "a", "b", LogSeverity.Error);
        check(s.printed.size() == before + 10, "off: all printed");

        System.out.println(fails == 0 ? "V6Test: all passed" : "V6Test: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
