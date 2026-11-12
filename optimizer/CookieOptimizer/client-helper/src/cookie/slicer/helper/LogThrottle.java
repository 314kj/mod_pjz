package cookie.slicer.helper;

import java.util.HashMap;
import java.util.regex.Pattern;

import zombie.debug.DebugLogStream;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;

/**
 * The same error printed again and again (helper 1.3.0; the same code as the server's Cookie Slicer v6).
 *
 * A mod handler that fails every time it runs prints its Java stack trace (ExceptionLogger) and its
 * Lua stack trace (KahluaThread.flushErrorMessage) every time: 30-40 lines per error, on the thread
 * that runs the game. Here an error identical to an earlier one (same exception, message and place;
 * object addresses ignored) is printed in full the first 3 times; after that one short line every
 * 100 repeats says how often it came. After 10 minutes without it, it counts from 0 again.
 * Only the printing changes: the game's error counter, its error list and the error popup still see
 * every error (they are updated by the game's code around these two prints, which is unchanged).
 * Off (the window's switch, speed.txt) = everything printed.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class LogThrottle {
    static volatile boolean use;
    static final int FULL = 3, EVERY = 100, MAX_KINDS = 2000;
    static long quietMs = 600_000; // not final: tests
    private static final Pattern ADDR = Pattern.compile("@[0-9a-fA-F]{5,}");

    private static final class Seen {
        int n;
        long last;
    }

    private static final HashMap<String, Seen> SEEN = new HashMap<>();
    static long notPrinted;

    private LogThrottle() {}

    /** ExceptionLogger: stream.printException(t, a, b, severity) */
    static void exception(DebugLogStream s, Throwable t, String a, String b, LogSeverity sev) {
        if (use && t != null) {
            try {
                StringBuilder k = new StringBuilder("J|").append(t.getClass().getName()).append('|')
                    .append(norm(t.getMessage())).append('|').append(norm(a)).append('|').append(norm(b));
                StackTraceElement[] st = t.getStackTrace();
                for (int i = 0; i < Math.min(6, st.length); i++) k.append('|').append(st[i]);
                int n = count(k.toString());
                if (n > FULL) {
                    if (n % EVERY == 0) DebugType.General.error(repeat(n, t.getClass().getSimpleName() + ": " + firstLine(t.getMessage())));
                    else notPrinted++;
                    return;
                }
            } catch (Throwable ignored) {
                // printing below as usual
            }
        }
        s.printException(t, a, b, sev);
    }

    /** KahluaThread.flushErrorMessage: DebugType.General.error(the Lua error and its Lua stack) */
    static void luaText(DebugType type, Object msg) {
        if (use && msg != null) {
            try {
                String text = msg.toString();
                int n = count("L|" + norm(text));
                if (n > FULL) {
                    if (n % EVERY == 0) type.error(repeat(n, firstLine(text)));
                    else notPrinted++;
                    return;
                }
            } catch (Throwable ignored) {
                // printing below as usual
            }
        }
        type.error(msg);
    }

    private static int count(String key) {
        long now = System.currentTimeMillis();
        synchronized (SEEN) {
            Seen s = SEEN.get(key);
            if (s == null) {
                if (SEEN.size() >= MAX_KINDS) return 1; // too many kinds: print, keep no count
                s = new Seen();
                SEEN.put(key, s);
            }
            if (now - s.last > quietMs) s.n = 0;
            s.n++;
            s.last = now;
            return s.n;
        }
    }

    private static String repeat(int n, String what) {
        return "[CookieSlicerHelper] the same error again (" + n + " times; shown in full the first " + FULL
            + " times, then a line like this every " + EVERY + "): " + what;
    }

    static String norm(String s) {
        return s == null ? "" : ADDR.matcher(s).replaceAll("@");
    }

    private static String firstLine(String s) {
        if (s == null) return "";
        s = s.strip();
        int nl = s.indexOf('\n');
        if (nl >= 0) s = s.substring(0, nl);
        return s.length() > 200 ? s.substring(0, 200) + "..." : s;
    }

    static String minute() {
        String s = "repeated errors not printed " + notPrinted;
        notPrinted = 0;
        return s;
    }

    /** for tests */
    static void reset() {
        synchronized (SEEN) {
            SEEN.clear();
        }
        notPrinted = 0;
    }
}
