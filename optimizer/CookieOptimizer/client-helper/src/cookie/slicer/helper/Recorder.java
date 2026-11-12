package cookie.slicer.helper;

import java.io.File;
import java.lang.management.ManagementFactory;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.Map;

import javax.management.MBeanServer;
import javax.management.ObjectName;

/**
 * "Record 3 minutes" (helper 1.3.0): when the player presses the button in the Cookie Slicer
 * window, Java's own flight recorder (the same as "jcmd JFR.start") records what the game does
 * for a few minutes (which code the game's threads run, memory, pauses) into
 * Zomboid/cookie_rec_<date>-<time>.jfr. The player drives through the slow place meanwhile and
 * sends the file to the admins, who see what makes it slow there. Reads, never changes, the game;
 * costs about 1-2% while recording. Only the newest 3 recordings are kept (older cookie_rec_*.jfr
 * in that folder are removed; nothing else).
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class Recorder {
    static final String NAME = "CookieSlicerRec";
    static final String PREFIX = "cookie_rec_";
    static final int KEEP = 3;
    static int minSeconds = 30; // (tests: shorter)

    static volatile String state = "idle"; // idle, running, done, failed: ...
    static volatile long endsAt, doneAt, bytes;
    static volatile File file;

    private Recorder() {}

    /** start recording for the given seconds (30-300) into dir; false if one is running */
    static synchronized boolean start(File dir, int seconds) {
        if ("running".equals(state)) return false;
        seconds = Math.max(minSeconds, Math.min(300, seconds));
        try {
            if (!dir.isDirectory() && !dir.mkdirs()) throw new IllegalStateException("no folder " + dir);
            keepNewest(dir, KEEP - 1);
            File f = new File(dir, PREFIX + new SimpleDateFormat("yyyyMMdd-HHmmss").format(new Date()) + ".jfr");
            dcmd("jfrStart", "name=" + NAME, "settings=profile", "duration=" + seconds + "s", "filename=\"" + f.getAbsolutePath() + "\"");
            file = f;
            bytes = 0;
            endsAt = System.currentTimeMillis() + seconds * 1000L;
            state = "running";
            System.out.println("[CookieSlicerHelper] recording " + seconds + " s into " + f);
            return true;
        } catch (Throwable t) {
            state = "failed: " + String.valueOf(t.getMessage()).replace('\n', ' ');
            System.out.println("[CookieSlicerHelper] could not start the recording: " + t);
            return false;
        }
    }

    /** every 2 s: is it written? then the pc file keys */
    static void status(Map<String, String> m) {
        if ("running".equals(state)) poll();
        m.put("rec", state);
        if ("running".equals(state)) m.put("rec_left_s", Long.toString(Math.max(0, (endsAt - System.currentTimeMillis() + 999) / 1000)));
        File f = file;
        if (f != null) {
            m.put("rec_file", f.getName());
            m.put("rec_dir", f.getParent());
        }
        if (bytes > 0) m.put("rec_mb", Long.toString(Math.max(1, bytes / (1024 * 1024))));
        if (doneAt > 0) m.put("rec_t", Long.toString(doneAt));
    }

    private static synchronized void poll() {
        long now = System.currentTimeMillis();
        if (now < endsAt) return;
        File f = file;
        boolean stillOn;
        try {
            String check = dcmd("jfrCheck", "name=" + NAME);
            stillOn = check != null && !check.contains("Could not find");
        } catch (Throwable t) {
            stillOn = false;
        }
        long len = f != null && f.isFile() ? f.length() : 0;
        if (!stillOn && len > 0) {
            bytes = len;
            doneAt = now;
            state = "done";
            System.out.println("[CookieSlicerHelper] recording written: " + f + " (" + len / 1024 + " KB)");
        } else if (now > endsAt + 60_000) {
            state = "failed: no file after the recording ended";
        }
    }

    /** remove older recordings of ours so that at most n are left */
    static void keepNewest(File dir, int n) {
        File[] fs = dir.listFiles((d, name) -> name.startsWith(PREFIX) && name.endsWith(".jfr"));
        if (fs == null || fs.length <= n) return;
        List<File> list = new ArrayList<>(Arrays.asList(fs));
        list.sort((a, b) -> b.getName().compareTo(a.getName())); // newest first (the date is in the name)
        for (int i = n; i < list.size(); i++) {
            if (!list.get(i).delete()) System.out.println("[CookieSlicerHelper] could not remove an old recording " + list.get(i));
        }
    }

    static String dcmd(String op, String... args) throws Exception {
        MBeanServer s = ManagementFactory.getPlatformMBeanServer();
        ObjectName n = new ObjectName("com.sun.management:type=DiagnosticCommand");
        return (String) s.invoke(n, op, new Object[] {args}, new String[] {String[].class.getName()});
    }
}
