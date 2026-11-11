package cookie.slicer.helper;

import java.io.File;
import java.lang.management.ManagementFactory;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.management.MBeanServer;
import javax.management.ObjectName;

/**
 * "What uses the game's RAM": when the player presses the button in the Cookie Slicer
 * window, asks Java for a count of the objects in the game's memory by kind (the same
 * list as "jcmd GC.class_histogram") and writes the biggest ones to
 * Zomboid/Lua/CookieSlicer_heap.txt, for the window and for the admins (who use it to
 * pick which part of the game to make lighter). Java cleans up first, so the game stops
 * for a few seconds on a big save. Only on request; reads, never changes, the game.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class HeapReport {
    static final String FILE = "CookieSlicer_heap.txt";
    static final int TOP = 40, GROUPS = 15;
    // "   1:       1234567      123456789  [B (java.base@25.0.2)"
    private static final Pattern ROW = Pattern.compile("^\\s*\\d+:\\s+(\\d+)\\s+(\\d+)\\s+(\\S+)");
    private static final Pattern TOTAL = Pattern.compile("^\\s*Total\\s+(\\d+)\\s+(\\d+)");

    static volatile String state = "idle"; // idle, running, done, failed: ...
    static volatile long doneAt;

    private HeapReport() {}

    static synchronized void startAsync(File out) {
        if ("running".equals(state)) return;
        state = "running";
        Thread t = new Thread(() -> {
            try {
                write(out, histogram());
                doneAt = System.currentTimeMillis();
                state = "done";
            } catch (Throwable e) {
                state = "failed: " + String.valueOf(e.getMessage()).replace('\n', ' ');
            }
        }, "CookieSlicer-Heap");
        t.setDaemon(true);
        t.start();
    }

    static void status(Map<String, String> m) {
        m.put("heap_report", state);
        if (doneAt > 0) m.put("heap_report_t", Long.toString(doneAt));
    }

    /** the class histogram text from the running Java */
    static String histogram() throws Exception {
        MBeanServer s = ManagementFactory.getPlatformMBeanServer();
        ObjectName n = new ObjectName("com.sun.management:type=DiagnosticCommand");
        return (String) s.invoke(n, "gcClassHistogram", new Object[] {new String[0]}, new String[] {String[].class.getName()});
    }

    static void write(File out, String histo) throws Exception {
        long t0 = System.currentTimeMillis();
        Map<String, String> m = summarize(histo);
        m.put("t", Long.toString(t0));
        Helper.write(out, m);
    }

    /** top classes and the biggest groups (packages) as key=value lines */
    static Map<String, String> summarize(String histo) {
        List<long[]> sizes = new ArrayList<>();
        List<String> names = new ArrayList<>();
        Map<String, Long> groups = new HashMap<>();
        long totalBytes = 0, totalCount = 0;
        for (String line : histo.split("\\R")) {
            Matcher t = TOTAL.matcher(line);
            if (t.find()) {
                totalCount = Long.parseLong(t.group(1));
                totalBytes = Long.parseLong(t.group(2));
                continue;
            }
            Matcher r = ROW.matcher(line);
            if (!r.find()) continue;
            long count = Long.parseLong(r.group(1)), bytes = Long.parseLong(r.group(2));
            String name = readable(r.group(3));
            if (names.size() < TOP) {
                sizes.add(new long[] {bytes, count});
                names.add(name);
            }
            groups.merge(group(name), bytes, Long::sum);
        }
        Map<String, String> m = new LinkedHashMap<>();
        m.put("total_mb", Long.toString(totalBytes / Helper.MB));
        m.put("total_objects", Long.toString(totalCount));
        m.put("n", Integer.toString(names.size()));
        for (int i = 0; i < names.size(); i++) {
            m.put("c" + (i + 1), sizes.get(i)[0] + "|" + sizes.get(i)[1] + "|" + names.get(i));
        }
        List<Map.Entry<String, Long>> gl = new ArrayList<>(groups.entrySet());
        gl.sort((a, b) -> Long.compare(b.getValue(), a.getValue()));
        int g = 0;
        for (Map.Entry<String, Long> e : gl) {
            if (g >= GROUPS) break;
            g++;
            m.put("g" + g, e.getValue() + "|" + e.getKey());
        }
        m.put("gn", Integer.toString(g));
        return m;
    }

    /** "[B" -> "byte[]", "[Ljava.lang.Object;" -> "java.lang.Object[]" */
    static String readable(String jvm) {
        int dims = 0;
        while (dims < jvm.length() && jvm.charAt(dims) == '[') dims++;
        if (dims == 0) return jvm.replace('|', '/');
        String base = jvm.substring(dims);
        switch (base) {
            case "B": base = "byte"; break;
            case "C": base = "char"; break;
            case "S": base = "short"; break;
            case "I": base = "int"; break;
            case "J": base = "long"; break;
            case "F": base = "float"; break;
            case "D": base = "double"; break;
            case "Z": base = "boolean"; break;
            default:
                if (base.startsWith("L") && base.endsWith(";")) base = base.substring(1, base.length() - 1);
        }
        StringBuilder sb = new StringBuilder(base.replace('|', '/'));
        for (int i = 0; i < dims; i++) sb.append("[]");
        return sb.toString();
    }

    /**
     * where a class belongs: the game's own code by its first three package parts
     * (zombie.iso.sprite), arrays and Java's own classes as they are (byte[], java.lang.String),
     * other libraries by their first two parts (org.lwjgl)
     */
    static String group(String name) {
        String n = name.replace("[]", "");
        if (n.indexOf('.') < 0) return name; // byte[], int[] ...
        if (n.startsWith("java.") || n.startsWith("jdk.") || n.startsWith("sun.")) return name;
        String[] p = n.split("\\.");
        int keep = Math.min(n.startsWith("zombie.") ? 3 : 2, p.length - 1); // package only, not the class
        return String.join(".", Arrays.copyOf(p, keep)) + ".*";
    }
}
