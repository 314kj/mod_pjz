package cookie.slicer.helper;

import java.util.ArrayList;
import java.util.Map;

import zombie.debug.DebugLogStream;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;
import zombie.entity.util.Array;

/**
 * Where the game's calls land after SpeedPatcher (helper 1.3.0), the same three changes as the
 * server's Cookie Slicer v5/v6, on the player's PC:
 *  - Lua events: the handler loop checks the slot just called instead of searching the list
 *    after every handler (FastEvents)
 *  - the same error printed in full 3 times, then one line every 100 (LogThrottle)
 *  - the game's entity lists: an entity's place found at once instead of searched (EntityIndex)
 * Each one gives exactly the game's own result; only the time (or the printing) changes.
 *
 * The entity index may only be changed by the thread that runs the game ("MainThread"): it is
 * the first thread with that name that fires a Lua event. Switching and the numbers for the pc
 * file are done there too (syncDue, set by the helper's 2-second loop), so nothing else ever
 * touches the index. Until that thread is known, entity lists use the game's own way.
 * The switch: the Cookie Slicer window (request speed=0/1), kept in speed.txt next to the jar;
 * off when the game starts = the classes are not changed at all.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
public final class SpeedHooks {
    static volatile String mainName = "MainThread"; // the game's thread name (tests change it)
    static volatile Thread main;
    private static volatile Thread lastOther; // the last thread found not to be the main one
    private static int skips;
    static volatile boolean want = true;
    static volatile boolean syncDue;
    // totals since the game started (read by the helper thread for the pc file)
    static volatile long evFast, evSearched, errCut, entFast, entSlow, entForeign;

    private SpeedHooks() {}

    // ---------------------------------------------------------------- the game's calls

    /** Event.trigger: callbacks.get(i) */
    @SuppressWarnings("rawtypes")
    public static Object eventGet(ArrayList list, int i) {
        Thread t = Thread.currentThread();
        if (t != main) {
            // (a thread already found not to be it is asked again now and then, in case it is renamed)
            if (main == null && (t != lastOther || (++skips & 4095) == 0)) findMain(t);
        } else if (syncDue) {
            sync();
        }
        return FastEvents.get(list, i);
    }

    /** Event.trigger: callbacks.contains(handler) */
    @SuppressWarnings("rawtypes")
    public static boolean eventListed(ArrayList list, Object handler) {
        return FastEvents.listed(list, handler);
    }

    /** KahluaThread.flushErrorMessage: DebugType.General.error(message) */
    public static void luaErrorText(DebugType type, Object message) {
        LogThrottle.luaText(type, message);
    }

    /** ExceptionLogger.logException: stream.printException(t, a, b, severity) */
    public static void printException(DebugLogStream stream, Throwable t, String a, String b, LogSeverity severity) {
        LogThrottle.exception(stream, t, a, b, severity);
    }

    /** EntityBucket.updateMembership / EngineEntityManager.addEntityInternal: list.add(entity) */
    @SuppressWarnings("rawtypes")
    public static void entityListAdd(Array list, Object entity) {
        EntityIndex.add(list, entity);
    }

    /** EntityBucket.updateMembership / EngineEntityManager.removeEntityInternal: list.removeValue(entity, identity) */
    @SuppressWarnings("rawtypes")
    public static boolean entityListRemove(Array list, Object entity, boolean identity) {
        return EntityIndex.remove(list, entity, identity);
    }

    // ---------------------------------------------------------------- switching (main thread)

    private static synchronized void findMain(Thread t) {
        if (main != null) return;
        if (mainName.equals(t.getName())) {
            main = t;
            syncDue = true;
            System.out.println("[CookieSlicerHelper] speed-ups: the game's main thread found (" + t.getName() + ")");
        } else {
            lastOther = t;
        }
    }

    /** on the main thread: apply the switch, collect the numbers */
    private static void sync() {
        syncDue = false;
        try {
            boolean on = want && !EntityIndex.failed();
            if (on != EntityIndex.use) EntityIndex.setUse(on, main);
            FastEvents.use = want;
            LogThrottle.use = want;
            collect();
        } catch (Throwable t) {
            EntityIndex.setUse(false, main);
            System.out.println("[CookieSlicerHelper] speed-ups: entity lists back to the game's own way: " + t);
        }
    }

    private static void collect() {
        long f = FastEvents.fast, s = FastEvents.searched;
        FastEvents.fast = FastEvents.searched = 0;
        evFast += f;
        evSearched += s;
        long ef = EntityIndex.fastRemoved, es = EntityIndex.slowRemoved, eo = EntityIndex.foreign;
        EntityIndex.minute(); // also forgets lists the game dropped (main thread only)
        entFast += ef;
        entSlow += es;
        entForeign += eo;
        long c = LogThrottle.notPrinted;
        LogThrottle.notPrinted = 0;
        errCut += c;
    }

    // ---------------------------------------------------------------- the helper's side

    /** at start (speed.txt) and from the window: on/off now (the entity part on the main thread) */
    static void setWant(boolean on) {
        want = on;
        FastEvents.use = on;
        LogThrottle.use = on;
        syncDue = true;
    }

    /** every 2 s from the helper thread */
    static void status(Map<String, String> m) {
        syncDue = true;
        m.put("speed_classes", SpeedPatcher.patched + "/" + SpeedPatcher.TARGETS.length);
        if (!SpeedPatcher.failed.isEmpty()) m.put("speed_failed", SpeedPatcher.failed);
        m.put("speed_main", main != null ? "1" : "0");
        m.put("speed_ev_fast", Long.toString(evFast));
        m.put("speed_ev_searched", Long.toString(evSearched));
        m.put("speed_err_cut", Long.toString(errCut));
        m.put("speed_ent_fast", Long.toString(entFast));
        m.put("speed_ent_slow", Long.toString(entSlow));
        if (entForeign > 0) m.put("speed_ent_other_thread", Long.toString(entForeign));
        if (EntityIndex.failed()) m.put("speed_ent_failed", "1");
    }
}
