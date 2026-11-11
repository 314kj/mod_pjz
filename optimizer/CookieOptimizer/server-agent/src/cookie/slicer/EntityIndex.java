package cookie.slicer;

import java.lang.ref.WeakReference;

import zombie.entity.util.Array;

/**
 * Faster removal from the game's entity lists (v5).
 *
 * The game keeps its "game entities" (crafting stations, Neat Building grass and other
 * objects with components) in plain lists: one list in the entity manager and one per
 * bucket. These lists are unordered: to remove an entity the game looks for it from the
 * start, one by one, and then moves the last entity into its place. With the new maps there
 * are tens of thousands of entities, and every chunk that unloads removes all of its own,
 * so while players drive this search was ~20% of the server's main thread (JFR 11 Nov,
 * 98% of the time spent unloading cells).
 *
 * Here each such list gets a small side index "entity -> position", kept up to date on every
 * add and remove. A removal finds the position at once and then removes it with the game's
 * own removeIndex, so the list ends up exactly as the game's own search would have left it
 * (same entities, same order). Before using a position it is checked (the entity really is
 * there); if not, the game's own search is used and the index is built again. Changes made
 * on another thread use the game's own way (and are caught by that check later); a list with
 * the same entity twice and ordered lists use the game's own way. Off (switch off, error, other game revision) = the game's own way; the indexes are
 * dropped and built again from the lists when it is turned on.
 * Main thread only; the cost is one hash insert per add and a few MB for the indexes.
 */
final class EntityIndex {
    /** set by Hooks on the main thread */
    static volatile boolean use;
    static volatile Thread main;
    private static volatile int foreignChanges;
    private static int seenForeign;
    private static boolean failed;

    // statistics since the last status line (main thread)
    static long fastRemoved, slowRemoved, repairs, builds, foreign;

    /** one game list and its index; weak so a list the game drops is not kept alive */
    private static final class Entry {
        final WeakReference<Array<?>> list;
        Idx idx;
        Entry(Array<?> a, Idx i) { list = new WeakReference<>(a); idx = i; }
    }

    private static Entry[] entries = new Entry[16];
    private static int nEntries;
    private static Entry last;

    private EntityIndex() {}

    // ---------------------------------------------------------------- the two changed calls

    /** list.add(entity) */
    @SuppressWarnings({"rawtypes", "unchecked"})
    static void add(Array list, Object e) {
        list.add(e);
        if (!use) return;
        if (Thread.currentThread() != main) { foreignChanges++; return; }
        try {
            checkForeign();
            Entry en = find(list);
            if (en == null || en.idx == null || en.idx.broken) return; // built at the first removal
            if (!en.idx.putNew(e, list.size - 1)) en.idx.broken = true; // the same entity twice: the game's own way for this list
        } catch (Throwable t) {
            fail(t);
        }
    }

    /** list.removeValue(entity, identity) */
    @SuppressWarnings({"rawtypes", "unchecked"})
    static boolean remove(Array list, Object e, boolean identity) {
        if (!use || !identity || list.ordered) return list.removeValue(e, identity);
        if (Thread.currentThread() != main) {
            foreignChanges++;
            return list.removeValue(e, true);
        }
        Idx x;
        int i;
        try {
            checkForeign();
            Entry en = find(list);
            if (en == null) en = keep(list);
            if (en.idx == null) en.idx = build(list);
            x = en.idx;
            if (x.broken) {
                slowRemoved++;
                return list.removeValue(e, true);
            }
            i = x.get(e);
            Object[] items = list.items;
            if (i < 0 || i >= list.size || items[i] != e) {
                // not where the index says: ask the game's own search, then rebuild if the index was wrong
                boolean r = list.removeValue(e, true);
                slowRemoved++;
                if (r || i >= 0) {
                    repairs++;
                    en.idx = build(list);
                }
                return r;
            }
        } catch (Throwable t) {
            fail(t);
            return list.removeValue(e, true);
        }
        // the game's own removal at the found position: the last entity moves into it
        int lastPos = list.size - 1;
        Object moved = list.items[lastPos];
        list.removeIndex(i);
        fastRemoved++;
        try {
            x.remove(e);
            if (i != lastPos) x.set(moved, i);
        } catch (Throwable t) {
            fail(t);
        }
        return true;
    }

    // ---------------------------------------------------------------- switching

    /** Hooks, main thread: on/off changed (off drops every index; they are built again when needed). */
    static void setUse(boolean on, Thread mainThread) {
        main = mainThread;
        if (on && failed) on = false;
        if (on != use || !on) dropAll();
        use = on;
    }

    private static void fail(Throwable t) {
        failed = true;
        use = false;
        dropAll();
        Log.line("entity lists: error, back to the game's own way for this session: " + t);
    }

    static boolean failed() { return failed; }

    /**
     * A list changed on another thread is only counted: every position is checked before use,
     * a wrong one falls back to the game's own search and rebuilds that list's index.
     */
    private static void checkForeign() {
        int f = foreignChanges;
        if (f != seenForeign) {
            foreign += f - seenForeign;
            seenForeign = f;
        }
    }

    private static void dropAll() {
        for (int i = 0; i < nEntries; i++) entries[i] = null;
        nEntries = 0;
        last = null;
    }

    private static Entry find(Array<?> a) {
        Entry l = last;
        if (l != null && l.list.get() == a) return l;
        for (int i = 0; i < nEntries; i++) {
            Entry en = entries[i];
            if (en.list.get() == a) {
                last = en;
                return en;
            }
        }
        return null;
    }

    /** forget lists the game no longer has (and the entities their indexes still point at) */
    private static void purge() {
        int j = 0;
        for (int i = 0; i < nEntries; i++) if (entries[i].list.get() != null) entries[j++] = entries[i];
        for (int i = j; i < nEntries; i++) entries[i] = null;
        nEntries = j;
        if (last != null && last.list.get() == null) last = null;
    }

    private static Entry keep(Array<?> a) {
        purge();
        if (nEntries == entries.length) entries = java.util.Arrays.copyOf(entries, nEntries * 2);
        Entry en = new Entry(a, null);
        entries[nEntries++] = en;
        last = en;
        return en;
    }

    private static Idx build(Array<?> a) {
        builds++;
        int n = a.size;
        Object[] items = a.items;
        Idx x = new Idx(n);
        for (int i = 0; i < n; i++) {
            Object o = items[i];
            if (o == null || !x.putNew(o, i)) {
                x.broken = true;
                break;
            }
        }
        return x;
    }

    // ---------------------------------------------------------------- status

    static String minute() {
        purge();
        for (int i = 0; i < nEntries; i++) if (entries[i].idx != null && entries[i].idx.broken) entries[i].idx = null; // try again
        String s = "entity lists: removed " + fastRemoved + " fast, " + slowRemoved + " the game's own way"
            + (repairs > 0 ? ", repaired " + repairs : "") + ", indexes built " + builds
            + (foreign > 0 ? ", changed on other threads " + foreign : "");
        fastRemoved = slowRemoved = repairs = builds = foreign = 0;
        return s;
    }

    static int listsKnown() { return nEntries; }

    /** entity -> position, by identity; open addressing, no boxing */
    static final class Idx {
        Object[] keys;
        int[] vals;
        int count, mask;
        boolean broken;

        Idx(int expected) {
            int cap = 16;
            while (cap < expected * 2 + 2) cap <<= 1;
            keys = new Object[cap];
            vals = new int[cap];
            mask = cap - 1;
        }

        private int slot(Object k) {
            int h = System.identityHashCode(k) * 0x9E3779B9;
            return (h ^ (h >>> 16)) & mask;
        }

        int get(Object k) {
            for (int s = slot(k); ; s = (s + 1) & mask) {
                Object o = keys[s];
                if (o == null) return -1;
                if (o == k) return vals[s];
            }
        }

        /** false if k is already there */
        boolean putNew(Object k, int v) {
            if ((count + 1) * 2 > keys.length) grow();
            for (int s = slot(k); ; s = (s + 1) & mask) {
                Object o = keys[s];
                if (o == null) {
                    keys[s] = k;
                    vals[s] = v;
                    count++;
                    return true;
                }
                if (o == k) return false;
            }
        }

        void set(Object k, int v) {
            for (int s = slot(k); ; s = (s + 1) & mask) {
                Object o = keys[s];
                if (o == k) {
                    vals[s] = v;
                    return;
                }
                if (o == null) {
                    putNew(k, v);
                    return;
                }
            }
        }

        void remove(Object k) {
            int s = slot(k);
            while (true) {
                Object o = keys[s];
                if (o == null) return;
                if (o == k) break;
                s = (s + 1) & mask;
            }
            keys[s] = null;
            count--;
            // move later entries of the same run back so lookups still find them
            int i = s;
            for (int j = (i + 1) & mask; keys[j] != null; j = (j + 1) & mask) {
                int h = slot(keys[j]);
                boolean stays = i <= j ? (i < h && h <= j) : (i < h || h <= j);
                if (!stays) {
                    keys[i] = keys[j];
                    vals[i] = vals[j];
                    keys[j] = null;
                    i = j;
                }
            }
        }

        private void grow() {
            Object[] ok = keys;
            int[] ov = vals;
            keys = new Object[ok.length * 2];
            vals = new int[ok.length * 2];
            mask = keys.length - 1;
            count = 0;
            for (int i = 0; i < ok.length; i++) if (ok[i] != null) putNew(ok[i], ov[i]);
        }
    }
}
