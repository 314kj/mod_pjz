package cookie.slicer;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

import zombie.entity.util.Array;

/**
 * v5 entity lists: the list after every add / remove through EntityIndex must be exactly
 * the list the game's own code makes (same entities, same order).
 * Runs against the test stand-in Array, or the game's real Array when projectzomboid.jar is
 * on the class path instead of the test stubs (run.sh does both).
 *  E1  200,000 random operations, incl. lists changed behind the index, other threads,
 *      the same entity twice, switching off/on
 *  E2  speed: 60,000 entities removed in random order
 *  E3  lists the game drops are forgotten
 *  E4  off = the game's own search, nothing indexed
 */
public final class EntityTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static final class Ent {
        final int id;
        Ent(int id) { this.id = id; }
        @Override public String toString() { return "e" + id; }
        // equals is identity, as for the game's entities
    }

    @SuppressWarnings("unchecked")
    static Array<Object> list() {
        return new Array<>(false, 16);
    }

    static boolean same(Array<Object> a, Array<Object> b) {
        if (a.size != b.size) return false;
        for (int i = 0; i < a.size; i++) if (a.items[i] != b.items[i]) return false;
        return true;
    }

    public static void main(String[] args) throws Exception {
        String label = args.length > 0 ? args[0] : "";
        System.out.println("EntityTest (" + label + ", Array from "
            + Array.class.getProtectionDomain().getCodeSource().getLocation() + ")");
        Thread main = Thread.currentThread();
        EntityIndex.setUse(true, main);

        // ---------------------------------------------------------------- E1
        System.out.println("E1 random operations, list compared after each one");
        Random r = new Random(42);
        Array<Object> game = list(), ours = list(), game2 = list(), ours2 = list();
        List<Ent> in = new ArrayList<>(), in2 = new ArrayList<>();
        int next = 0, firstBad = -1;
        String firstHalf = "";
        long ops = 200_000, removes = 0, outsideChanges = 0, otherThread = 0, twice = 0, switches = 0;
        for (long op = 0; op < ops; op++) {
            boolean second = r.nextInt(4) == 0; // two lists, like a bucket and the manager's list
            Array<Object> g = second ? game2 : game, o = second ? ours2 : ours;
            List<Ent> members = second ? in2 : in;
            int k = r.nextInt(1000);
            int target = 1500 + (int) (1000 * Math.sin(op / 20000.0)); // lists grow and shrink
            if (k < 5) {
                // changed without the index knowing (another place in the game)
                Ent e = new Ent(next++);
                g.add(e);
                o.add(e);
                members.add(e);
                outsideChanges++;
            } else if (k < 10) {
                // the same operation on another thread
                Ent e = members.isEmpty() ? new Ent(next++) : members.remove(r.nextInt(members.size()));
                boolean wasIn = g.removeValue(e, true);
                boolean[] res = new boolean[1];
                Thread t = new Thread(() -> res[0] = EntityIndex.remove(o, e, true));
                t.start();
                t.join();
                if (res[0] != wasIn) firstBad = firstBad < 0 ? (int) op : firstBad;
                otherThread++;
            } else if (k < 11) {
                // the same entity added twice (the game never does; the list must still match) - second half only
                if (op > ops / 2 && !members.isEmpty()) {
                    Ent e = members.get(r.nextInt(members.size()));
                    g.add(e);
                    EntityIndex.add(o, e);
                    members.add(e);
                    twice++;
                }
            } else if (k < 12) {
                EntityIndex.setUse(false, main);
                EntityIndex.setUse(true, main);
                switches++;
            } else if (k < 30) {
                // remove something that is not there
                Ent e = new Ent(next++);
                boolean a = g.removeValue(e, true), b = EntityIndex.remove(o, e, true);
                if (a != b) firstBad = firstBad < 0 ? (int) op : firstBad;
            } else if (members.size() < target && k < 600 || members.isEmpty()) {
                Ent e = new Ent(next++);
                g.add(e);
                EntityIndex.add(o, e);
                members.add(e);
            } else {
                Ent e = members.remove(r.nextInt(members.size()));
                boolean a = g.removeValue(e, true), b = EntityIndex.remove(o, e, true);
                if (a != b) firstBad = firstBad < 0 ? (int) op : firstBad;
                removes++;
            }
            if (!same(g, o) && firstBad < 0) firstBad = (int) op;
            if (op == ops / 2) firstHalf = EntityIndex.minute();
        }
        String m = EntityIndex.minute();
        System.out.println("     " + ops + " operations, " + removes + " removals, " + outsideChanges + " changed behind the index, "
            + otherThread + " on another thread, " + twice + " twice, " + switches + " switches; lists " + game.size + " + " + game2.size);
        System.out.println("     first half (no entity twice): " + firstHalf);
        System.out.println("     second half: " + m);
        check(firstBad < 0, "every list identical to the game's own result" + (firstBad >= 0 ? " (first difference at op " + firstBad + ")" : ""));
        long fast = Long.parseLong(firstHalf.replaceAll(".*removed (\\d+) fast.*", "$1")), slow = Long.parseLong(firstHalf.replaceAll(".*fast, (\\d+) the game.*", "$1"));
        check(fast > slow * 4, "most removals took the fast way (" + fast + " fast, " + slow + " searched)");

        // ---------------------------------------------------------------- E2
        System.out.println("E2 speed: 60,000 entities removed in random order");
        int n = 60_000;
        Ent[] es = new Ent[n];
        for (int i = 0; i < n; i++) es[i] = new Ent(i);
        long tGame = 0, tOurs = 0;
        for (int round = 0; round < 3; round++) {
            Array<Object> a = list(), b = list();
            for (Ent e : es) { a.add(e); EntityIndex.add(b, e); }
            Ent[] order = es.clone();
            Random rr = new Random(round);
            for (int i = n - 1; i > 0; i--) { int j = rr.nextInt(i + 1); Ent t = order[i]; order[i] = order[j]; order[j] = t; }
            long t0 = System.nanoTime();
            for (Ent e : order) a.removeValue(e, true);
            long t1 = System.nanoTime();
            for (Ent e : order) EntityIndex.remove(b, e, true);
            long t2 = System.nanoTime();
            if (round > 0) { tGame += t1 - t0; tOurs += t2 - t1; }
            check(a.size == 0 && b.size == 0, "round " + round + ": both empty");
        }
        System.out.printf("     the game's search: %.0f ms, with the index: %.1f ms (2 rounds)%n", tGame / 1e6, tOurs / 1e6);
        check(tOurs * 20 < tGame, "at least 20x faster");
        EntityIndex.minute();

        // ---------------------------------------------------------------- E3
        System.out.println("E3 lists the game drops are forgotten");
        int before = EntityIndex.listsKnown();
        for (int i = 0; i < 5; i++) {
            Array<Object> t = list();
            Ent e = new Ent(i);
            EntityIndex.add(t, e);
            EntityIndex.remove(t, e, true);
        }
        int with = EntityIndex.listsKnown();
        for (int i = 0; i < 5 && EntityIndex.listsKnown() > before; i++) {
            System.gc();
            Thread.sleep(50);
            EntityIndex.minute();
        }
        check(with > before && EntityIndex.listsKnown() <= before + 1, "known lists " + before + " -> " + with + " -> " + EntityIndex.listsKnown());

        // ---------------------------------------------------------------- E4
        System.out.println("E4 off: the game's own search");
        EntityIndex.setUse(false, main);
        Array<Object> a = list(), b = list();
        for (int i = 0; i < 100; i++) { Ent e = new Ent(i); a.add(e); EntityIndex.add(b, e); }
        for (int i = 0; i < 100; i += 3) { a.removeValue(a.items[i % a.size], true); }
        Array<Object> c = list();
        for (int i = 0; i < 100; i++) c.add(b.items[i]);
        for (int i = 0; i < 100; i += 3) { Object e = c.items[i % c.size]; c.removeValue(e, true); EntityIndex.remove(b, e, true); }
        String off = EntityIndex.minute();
        check(same(b, c) && off.startsWith("entity lists: removed 0 fast") && EntityIndex.listsKnown() == 0, "off: same list, nothing fast, nothing indexed (" + off + ")");

        System.out.println(fails == 0 ? "EntityTest: all passed" : "EntityTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
