package cookie.slicer;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.Properties;

/**
 * Settings, from CookieSlicer.properties next to the jar (optional; defaults below).
 * Times are in milliseconds. The file is read at start and again whenever it changes
 * while the server runs (checked every 5 s), except "enabled" and "revision", which
 * only count at start.
 */
final class Config {
    /** Aim: a game tick plus the waiting square work should end within this. */
    static long targetTickNs;
    /** Waiting square work always gets at least this much per tick ... */
    static long minDrainNs;
    /** ... plus this much for every 1000 squares waiting (so a long wait catches up faster) ... */
    static long pressureNsPer1000;
    /** ... but never more than this per tick. */
    static long maxDrainNs;
    /** Per tick, waiting chunks that a player is about to download are finished first, up to this. */
    static long sendFlushNs;
    /** Waiting square work of a cell that unloads: "drop" (default) or "run" it first. */
    static boolean runBeforeUnload;
    /** Run all waiting square work before the world is saved (default no). */
    static boolean runBeforeSave;
    /** Game revision this was tested on; "any" skips the check. */
    static String revision;
    /** Seconds between status lines in the log. */
    static int logEverySec;
    /** While this file exists next to the jar, everything runs the game's own way (checked every 5 s). */
    static String offFile;
    /** File next to the jar whose first word is "on" or "off" (checked every 5 s; missing = on). */
    static String modeFile;
    /** Same, in the game's Lua folder (Zomboid/Lua): written by the in-game admin command.
     *  Of the two mode files, the one changed last counts. */
    static String gameModeFile;
    /** State + last minute's numbers, written next to the jar and in the game's Lua folder. */
    static String statusFile;
    /** "false" turns the whole thing off (the game's own way) without removing the agent. */
    static boolean enabled;
    /** v5: fast removal from the game's entity lists (fast_entity_remove=false = the game's own search). */
    static boolean fastEntities;
    /** v6: Lua event handler loop without a search after every handler (fast_events=false = the game's own). */
    static boolean fastEvents;
    /** v6: the same error printed in full 3 times, then a line every 100 (quiet_repeated_errors=false = print all). */
    static boolean quietErrors;

    static File dir;
    private static long stamp = Long.MIN_VALUE;

    static {
        defaults();
    }

    private static void defaults() {
        targetTickNs = ms(80);
        minDrainNs = ms(5);
        pressureNsPer1000 = ms(1);
        maxDrainNs = ms(60);
        sendFlushNs = ms(25);
        runBeforeUnload = false;
        runBeforeSave = false;
        revision = "3d39148846";
        logEverySec = 60;
        offFile = "CookieSlicer.off";
        modeFile = "CookieSlicer.mode";
        gameModeFile = "CookieSlicer_mode.txt";
        statusFile = "CookieSlicer_status.txt";
        enabled = true;
        fastEntities = true;
        fastEvents = true;
        quietErrors = true;
    }

    private static File file() {
        return dir == null ? null : new File(dir, "CookieSlicer.properties");
    }

    private static long stampOf(File f) {
        return f != null && f.isFile() ? f.lastModified() ^ (f.length() << 40) : 0L;
    }

    static void load(File jarDir) {
        dir = jarDir;
        File f = file();
        stamp = stampOf(f);
        defaults();
        if (f == null || !f.isFile()) return;
        Properties p = read(f);
        if (p == null) return;
        apply(p);
        revision = p.getProperty("revision", revision).trim();
        enabled = !"false".equalsIgnoreCase(p.getProperty("enabled", "true").trim());
    }

    /** Called every few seconds while the server runs: reads the file again if it changed. */
    static boolean reloadIfChanged() {
        File f = file();
        long s = stampOf(f);
        if (s == stamp) return false;
        stamp = s;
        String keepRevision = revision;
        boolean keepEnabled = enabled;
        defaults();
        revision = keepRevision;
        enabled = keepEnabled;
        if (f != null && f.isFile()) {
            Properties p = read(f);
            if (p != null) apply(p);
        }
        return true;
    }

    private static Properties read(File f) {
        Properties p = new Properties();
        try (InputStream in = new FileInputStream(f)) {
            p.load(in);
            return p;
        } catch (Exception e) {
            Log.line("could not read " + f + ": " + e + " (using defaults)");
            return null;
        }
    }

    private static void apply(Properties p) {
        targetTickNs = msOr(p, "target_tick_ms", targetTickNs);
        minDrainNs = msOr(p, "min_drain_ms", minDrainNs);
        pressureNsPer1000 = msOr(p, "extra_ms_per_1000_waiting", pressureNsPer1000);
        maxDrainNs = msOr(p, "max_drain_ms", maxDrainNs);
        sendFlushNs = msOr(p, "send_flush_ms", sendFlushNs);
        runBeforeUnload = "run".equalsIgnoreCase(p.getProperty("unload", "drop").trim());
        runBeforeSave = "true".equalsIgnoreCase(p.getProperty("run_before_save", "false").trim());
        logEverySec = (int) Math.max(5, longOr(p, "log_every_s", logEverySec));
        offFile = p.getProperty("off_file", offFile).trim();
        modeFile = p.getProperty("mode_file", modeFile).trim();
        gameModeFile = p.getProperty("game_mode_file", gameModeFile).trim();
        statusFile = p.getProperty("status_file", statusFile).trim();
        fastEntities = !"false".equalsIgnoreCase(p.getProperty("fast_entity_remove", "true").trim());
        fastEvents = !"false".equalsIgnoreCase(p.getProperty("fast_events", "true").trim());
        quietErrors = !"false".equalsIgnoreCase(p.getProperty("quiet_repeated_errors", "true").trim());
    }

    /** name inside base, or name itself when it is a full path; null when there is nothing to use. */
    static File resolve(File base, String name) {
        if (name == null || name.isEmpty()) return null;
        File f = new File(name);
        if (f.isAbsolute()) return f;
        return base == null ? null : new File(base, name);
    }

    static String summary() {
        return "target tick " + toMs(targetTickNs) + " ms, square work per tick " + toMs(minDrainNs) + "-"
            + toMs(maxDrainNs) + " ms (+" + toMs(pressureNsPer1000) + " ms per 1000 waiting), before download up to "
            + toMs(sendFlushNs) + " ms, at unload " + (runBeforeUnload ? "run" : "drop") + " what waits"
            + (runBeforeSave ? ", run everything before a save" : "")
            + ", entity lists " + (fastEntities ? "fast removal" : "the game's own search")
            + ", event loop " + (fastEvents ? "checks in place" : "the game's own search")
            + ", repeated errors " + (quietErrors ? "shown 3 times then counted" : "all printed");
    }

    private static long ms(double v) { return (long) (v * 1_000_000L); }
    static String toMs(long ns) {
        double v = ns / 1e6;
        return v == Math.rint(v) ? String.valueOf((long) v) : String.format("%.1f", v);
    }

    private static long msOr(Properties p, String key, long dflt) {
        String v = p.getProperty(key);
        if (v == null) return dflt;
        try {
            double d = Double.parseDouble(v.trim());
            return d < 0 ? dflt : ms(d);
        } catch (NumberFormatException e) {
            Log.line("bad value " + key + "=" + v + " (using " + toMs(dflt) + ")");
            return dflt;
        }
    }

    private static long longOr(Properties p, String key, long dflt) {
        String v = p.getProperty(key);
        if (v == null) return dflt;
        try { return Long.parseLong(v.trim()); } catch (NumberFormatException e) { return dflt; }
    }

    private Config() {}
}
