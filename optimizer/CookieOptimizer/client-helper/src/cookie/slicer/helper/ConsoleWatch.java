package cookie.slicer.helper;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Reads the game's own log (Zomboid/console.txt) while the game runs and picks out the
 * few problems that stop a player from joining or loading the server (not enough RAM,
 * PZ Optimization left in the game, a Workshop item out of date, a mod or map missing,
 * game files that do not match the server, a kick, a lost connection, a mod's Lua error
 * while loading). Each one has a code; the mod (pre-join panel) and the loading-screen
 * box (LoadHook) show what it means and how to fix it.
 *
 * Results go to Zomboid/Lua/CookieSlicer_diag.txt (the previous game start's results are
 * kept as CookieSlicer_diag_prev.txt, so the main menu can say why the game closed last
 * time). A new attempt to join ("ConnectToServerState: Start") starts a new list.
 * Only reads files; never changes the log.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class ConsoleWatch implements Runnable {
    static final String DIAG_FILE = "CookieSlicer_diag.txt";
    static final String PREV_FILE = "CookieSlicer_diag_prev.txt";
    static final int MAX_READ = 1 << 20;

    /** One kind of problem seen in the log. */
    static final class Problem {
        final String code;
        String detail = "";
        int count;
        long first, last;

        Problem(String code) { this.code = code; }

        boolean fatal() { return !"luamod".equals(code); }
    }

    /** a line of the log that means one problem; group 1 (if any) is the detail */
    private static final class Rule {
        final String code;
        final Pattern p;
        Rule(String code, String regex) { this.code = code; this.p = Pattern.compile(regex); }
    }

    // order matters: the first rule that matches a line wins
    private static final Rule[] RULES = {
        new Rule("ram", "(?i)(?:OutOfMemoryError|Java heap space|GC overhead limit exceeded)"),
        new Rule("pzopt", "(?i)(?:AOT ?cache|pzopt[/\\\\]|Unable to map shared spaces|SharedArchiveFile)"),
        new Rule("workshop", "(?i)(?:Workshop item version is different|item state CheckItemState -> (?:VersionMismatch|Fail\\w*|Error\\w*) ID=(\\d+))"),
        new Rule("modmissing", "(?i)Mod \"([^\"]+)\" is not installed"),
        new Rule("map", "(?i)(?:A map is missing|MapNotFound)"),
        new Rule("files", "(?i)(?:files do not match the server|KickChecksum|doesn't exist on the server(?::\\s*(\\S+))?)"),
        new Rule("version", "(?i)(?:does not match server version|ClientVersionMismatch)"),
        new Rule("banned", "(?i)(?:banned from this server|SteamIDBanned)"),
        new Rule("already", "(?i)(?:is already connected to the server|AlreadyConnected)"),
        new Rule("access", "(?i)(?:Access denied|AccessDenied|Wrong username or password|Unknown account username|InvalidServerPassword)"),
        new Rule("full", "(?i)(?:The server is full|ServerFull)"),
        new Rule("ping", "(?i)ping is too high"),
        new Rule("net", "(?i)(?:Connection to the server was lost|ConnectionLost|ServerFailedToRespond|P2PSessionConnectFail|Failed connection to TCP download port|FailedTCPTest)"),
        new Rule("luamod", "Lua\\(\\(MOD:([^)]+)\\)\\)"),
    };
    private static final Pattern NEW_ATTEMPT = Pattern.compile("ConnectToServerState: Start");

    // what has been seen since the last attempt to join (or since the game started)
    private static final Map<String, Problem> problems = new LinkedHashMap<>();
    private static final Map<String, Integer> modErrors = new LinkedHashMap<>();
    private static long attemptStart = System.currentTimeMillis();
    private static volatile boolean dirty;

    private final File console;
    private final File luaDir;
    private long offset;
    private final StringBuilder partial = new StringBuilder();

    ConsoleWatch(File cacheDir, File luaDir) {
        this.console = new File(cacheDir, "console.txt");
        this.luaDir = luaDir;
    }

    static void start(File cacheDir, File luaDir) {
        // last game start's results: kept for the main menu ("why did the game close")
        File cur = new File(luaDir, DIAG_FILE);
        if (cur.isFile()) {
            try {
                Files.move(cur.toPath(), new File(luaDir, PREV_FILE).toPath(), StandardCopyOption.REPLACE_EXISTING);
            } catch (IOException ignored) {
                // the old file is only a hint
            }
        }
        Thread t = new Thread(new ConsoleWatch(cacheDir, luaDir), "CookieSlicer-Log");
        t.setDaemon(true);
        t.setPriority(Thread.MIN_PRIORITY);
        t.start();
    }

    @Override
    public void run() {
        while (true) {
            try {
                poll();
                if (dirty) writeDiag(new File(luaDir, DIAG_FILE));
            } catch (Throwable t) {
                // the log is read again next second
            }
            try { Thread.sleep(1000); } catch (InterruptedException e) { return; }
        }
    }

    /** reads what the game added to the log since last time */
    void poll() throws IOException {
        if (!console.isFile()) return;
        long len = console.length();
        if (len < offset) { offset = 0; partial.setLength(0); } // a new log (the game started again)
        if (len == offset) return;
        try (RandomAccessFile f = new RandomAccessFile(console, "r")) {
            long from = Math.max(offset, len - MAX_READ);
            int n = (int) (len - from);
            byte[] buf = new byte[n];
            f.seek(from);
            f.readFully(buf);
            offset = len;
            feed(new String(buf, StandardCharsets.UTF_8), System.currentTimeMillis());
        }
    }

    void feed(String text, long now) {
        partial.append(text);
        int start = 0;
        for (int i = 0; i < partial.length(); i++) {
            if (partial.charAt(i) == '\n') {
                line(partial.substring(start, i), now);
                start = i + 1;
            }
        }
        partial.delete(0, start);
    }

    static void line(String line, long now) {
        if (line.contains("CookieSlicer")) return; // our own lines
        if (NEW_ATTEMPT.matcher(line).find()) {
            synchronized (problems) {
                problems.clear();
                modErrors.clear();
                attemptStart = now;
            }
            dirty = true;
            return;
        }
        for (Rule r : RULES) {
            Matcher m = r.p.matcher(line);
            if (!m.find()) continue;
            String detail = m.groupCount() >= 1 && m.group(1) != null ? m.group(1).trim() : "";
            add(r.code, detail, now);
            return;
        }
    }

    static void add(String code, String detail, long now) {
        synchronized (problems) {
            if ("luamod".equals(code)) modErrors.merge(detail, 1, Integer::sum);
            Problem p = problems.get(code);
            if (p == null) {
                p = new Problem(code);
                p.first = now;
                problems.put(code, p);
            }
            p.count++;
            p.last = now;
            if ("luamod".equals(code)) p.detail = topMods(3);
            else if (!detail.isEmpty()) p.detail = detail;
        }
        dirty = true;
    }

    /** "Mod A (12), Mod B (3)" - the mods with the most Lua errors */
    static String topMods(int max) {
        List<Map.Entry<String, Integer>> l = new ArrayList<>(modErrors.entrySet());
        l.sort((a, b) -> b.getValue() - a.getValue());
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < l.size() && i < max; i++) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(l.get(i).getKey()).append(" (").append(l.get(i).getValue()).append(')');
        }
        return sb.toString();
    }

    /** problems since the last attempt to join, the most important first */
    static List<Problem> current(boolean fatalOnly) {
        List<Problem> out = new ArrayList<>();
        synchronized (problems) {
            for (Rule r : RULES) {
                Problem p = problems.get(r.code);
                if (p == null || (fatalOnly && !p.fatal())) continue;
                out.add(p);
            }
        }
        return out;
    }

    static long attemptStart() {
        synchronized (problems) { return attemptStart; }
    }

    static void writeDiag(File f) throws IOException {
        dirty = false;
        Map<String, String> m = new LinkedHashMap<>();
        m.put("t", Long.toString(System.currentTimeMillis()));
        m.put("attempt", Long.toString(attemptStart()));
        int i = 0;
        for (Problem p : current(false)) {
            i++;
            m.put("p" + i, p.code + "|" + p.count + "|" + p.last + "|" + p.detail.replace('|', '/').replace('\n', ' '));
        }
        m.put("n", Integer.toString(i));
        Helper.write(f, m);
    }

    /** for tests */
    static void reset() {
        synchronized (problems) {
            problems.clear();
            modErrors.clear();
            attemptStart = 0;
        }
    }
}
