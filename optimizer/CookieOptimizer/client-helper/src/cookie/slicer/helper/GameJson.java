package cookie.slicer.helper;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Looks at the game's start settings, ProjectZomboid64.json (ProjectZomboid32.json /
 * ProjectZomboid.json elsewhere) in the game folder, and reports what can stop the game
 * from starting or joining: leftovers of PZ Optimization (its jar on the class path or an
 * AOT cache - these break after every game update), other Java agents, and the game RAM
 * written there. Read only: the Windows setup (CookieSlicer-Setup, option 1) is what fixes
 * the file, with a backup.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class GameJson {
    private static final Pattern XMX = Pattern.compile("-Xmx(\\d+)([kKmMgG]?)");
    private static final Pattern AGENT = Pattern.compile("-javaagent:([^\"]+)");

    private GameJson() {}

    static File find(File gameDir) {
        for (String n : new String[] {"ProjectZomboid64.json", "ProjectZomboid32.json", "ProjectZomboid.json"}) {
            File f = new File(gameDir, n);
            if (f.isFile()) return f;
        }
        return null;
    }

    /** adds json_* lines for the mod: json_file, json_xmx_mb, json_issue (comma list) */
    static void report(File gameDir, Map<String, String> m) {
        File f = find(gameDir);
        if (f == null) {
            m.put("json_file", "none");
            return;
        }
        m.put("json_file", f.getName());
        try {
            check(new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8), m);
        } catch (IOException e) {
            m.put("json_issue", "unreadable");
        }
    }

    static void check(String text, Map<String, String> m) {
        List<String> issues = new ArrayList<>();
        String low = text.toLowerCase(Locale.ROOT);
        if (low.contains("pzopt")) issues.add("pzopt");
        if (low.contains("-xx:aotcache") || low.contains("sharedarchivefile")) issues.add("aot");
        Matcher a = AGENT.matcher(text);
        while (a.find()) {
            String path = a.group(1).replace('\\', '/');
            String name = path.substring(path.lastIndexOf('/') + 1);
            if (!name.toLowerCase(Locale.ROOT).contains("cookieslicer")) issues.add("agent:" + name);
        }
        Matcher x = XMX.matcher(text);
        if (x.find()) {
            long v = Long.parseLong(x.group(1));
            String u = x.group(2).toLowerCase(Locale.ROOT);
            long mb = u.equals("g") ? v * 1024 : u.equals("k") ? v / 1024 : u.isEmpty() ? v / (1024 * 1024) : v;
            m.put("json_xmx_mb", Long.toString(mb));
        }
        if (!looksLikeJson(text)) issues.add("broken");
        m.put("json_issue", String.join(",", issues));
    }

    /** quotes and brackets balance (enough to tell a hand-broken file) */
    static boolean looksLikeJson(String s) {
        int depth = 0;
        boolean inStr = false, esc = false;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (inStr) {
                if (esc) esc = false;
                else if (c == '\\') esc = true;
                else if (c == '"') inStr = false;
                continue;
            }
            if (c == '"') inStr = true;
            else if (c == '{' || c == '[') depth++;
            else if (c == '}' || c == ']') { if (--depth < 0) return false; }
        }
        return depth == 0 && !inStr && s.trim().startsWith("{");
    }
}
