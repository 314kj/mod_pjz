package cookie.slicer.helper;

import java.io.File;
import java.io.IOException;
import java.lang.instrument.Instrumentation;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.lang.management.MemoryType;
import java.lang.management.MemoryUsage;
import java.lang.management.ThreadInfo;
import java.lang.management.ThreadMXBean;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Cookie Slicer Helper - a small Java agent for the PLAYER's game (not the server).
 *
 * Every 2 s it measures what the game's Lua cannot see
 * (CPU of the whole PC and of the game, the busiest game thread, PC RAM, the
 * game's own RAM before and after clean-up) and writes it to
 * Zomboid/Lua/CookieSlicer_pc.txt, where the Cookie Slicer mod shows it.
 * When the player presses "Give the game N GB" in the mod, the mod writes
 * Zomboid/Lua/CookieSlicer_request.txt and this helper writes heap.txt next to its
 * jar; the start script (run.ps1 / run.sh, set as the game's Steam launch option by
 * CookieSlicer-Setup) gives the game that much RAM from the next start. No game
 * file is changed.
 * Screen looks (v1.1.0): one game call is pointed at ShaderHook when the game loads the
 * class (ShaderPatcher), so the look chosen in the mod is drawn right after the game's
 * own screen shader (PostDrawer). The choice comes from Zomboid/Lua/CookieSlicer_shader.txt.
 * Join problems (v1.2.0): ConsoleWatch reads the game's log for the few problems that stop
 * a join (CookieSlicer_diag.txt for the mod) and the loading screen shows what to do
 * (LoadPatcher / LoadHook); GameJson reports what ProjectZomboid64.json holds (read only).
 * Less RAM (v1.2.0): the start script adds Java's own memory savers (smaller object headers,
 * one copy of repeated text, give unused RAM back to Windows after a minute) unless the
 * player turned them off in the window (ramsave.txt next to the jar, written here); on
 * request HeapReport lists what fills the game's memory (CookieSlicer_heap.txt).
 * 1.2.1: RamTune moves ZGC's soft ceiling with what the game really uses (live x 1.5 + 1 GB)
 * instead of 4/5 of the game RAM, so the game holds ~8 GB instead of 12-16 GB.
 * 1.3.0: the server's Cookie Slicer speed-ups on the player's PC too (SpeedPatcher / SpeedHooks:
 * Lua event loop, the same error printed 3 times then counted, entity lists), switch in the window
 * (speed.txt); "record 3 minutes" with Java's flight recorder for the admins (Recorder).
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
public final class Helper implements Runnable {
    public static final String VERSION = "1.3.0";
    static final long MB = 1024L * 1024L;
    static final String PC_FILE = "CookieSlicer_pc.txt";
    static final String REQUEST_FILE = "CookieSlicer_request.txt";
    static final String HEAP_FILE = "heap.txt";
    static final String RAMSAVE_FILE = "ramsave.txt";
    static final String STATS_FILE = "heapstats.txt"; // most RAM the game used in recent sessions
    static final String SPEED_FILE = "speed.txt"; // speed-ups on/off ("speed=0" = off; no file = on)
    static volatile boolean speedPatching; // the speed-ups were set up at this start

    final File luaDir;
    final File stateDir;
    private long lastRequestT = Long.MIN_VALUE;
    private String heapNote = null;
    private long heapNextMb = 0;
    private String ramsaveNote = null;
    private String speedNote = null;
    private long peakLive = 0, peakWritten = 0;
    private List<Long> pastPeaks;
    private static String ramsaveNow, gcName;

    // previous sample, for deltas
    private long prevWall = 0, prevGcMs = -1;
    private final Map<Long, Long> prevThreadCpu = new HashMap<>();
    private final Map<Long, String> threadNames = new HashMap<>();
    private final long[] gcWindow = new long[30]; // last 30 samples x 2 s = 1 minute
    private int gcIdx = 0;
    private Map<String, String> jsonInfo;
    private int jsonAge;

    Helper(File luaDir, File stateDir) {
        this.luaDir = luaDir;
        this.stateDir = stateDir;
    }

    // ================================================================ start

    /**
     * Agent options from the start script: "client" and, when the game was started with
     * -cachedir=..., "cachedir=<folder>" (separated by ';'). The game's own launcher
     * (ProjectZomboid64.exe) does not set sun.java.command, so that cannot be used to
     * tell the client, nor to read -cachedir.
     */
    public static void premain(String args, Instrumentation inst) {
        try {
            String opts = args == null ? "" : args;
            String cmd = System.getProperty("sun.java.command", "");
            boolean client = hasOption(opts, "client") || hasOption(opts, "test") || cmd.startsWith("zombie.gameStates.MainScreenState");
            if (!client || cmd.startsWith("zombie.network.GameServer")) {
                System.out.println("[CookieSlicerHelper] not the game client, doing nothing");
                return;
            }
            File cache = cacheDir(opts, cmd);
            File lua = new File(cache, "Lua");
            File state = stateDir();
            Helper h = new Helper(lua, state);
            h.rememberCacheDir(cache);
            if (inst != null) {
                try {
                    inst.addTransformer(new ShaderPatcher(), false);
                    ShaderState.startWatching(lua);
                } catch (Throwable t) {
                    System.out.println("[CookieSlicerHelper] screen looks off (the game runs as usual): " + t);
                }
                try {
                    inst.addTransformer(new LoadPatcher(), false);
                } catch (Throwable t) {
                    System.out.println("[CookieSlicerHelper] loading screen box off (the game runs as usual): " + t);
                }
                try {
                    if (savedSpeed(state)) {
                        inst.addTransformer(new SpeedPatcher(), false);
                        speedPatching = true;
                        SpeedHooks.setWant(true);
                    } else {
                        System.out.println("[CookieSlicerHelper] speed-ups off (speed.txt): the game's own code");
                    }
                } catch (Throwable t) {
                    System.out.println("[CookieSlicerHelper] speed-ups off (the game runs as usual): " + t);
                }
            }
            try {
                ConsoleWatch.start(cache, lua);
            } catch (Throwable t) {
                System.out.println("[CookieSlicerHelper] log check off (the game runs as usual): " + t);
            }
            gpuNames();
            Thread t = new Thread(h, "CookieSlicer-Helper");
            t.setDaemon(true);
            t.setPriority(Thread.MIN_PRIORITY);
            t.start();
            System.out.println("[CookieSlicerHelper] v" + VERSION + " on: " + new File(lua, PC_FILE) + " every 2 s");
        } catch (Throwable t) {
            System.out.println("[CookieSlicerHelper] could not start (the game runs as usual): " + t);
        }
    }

    static boolean hasOption(String opts, String name) {
        for (String o : opts.split(";")) if (o.trim().equalsIgnoreCase(name)) return true;
        return false;
    }

    /** cachedir= from the agent options, else -cachedir= on the command line, else the game's default (home/Zomboid). */
    static File cacheDir(String opts, String cmd) {
        for (String o : opts.split(";")) {
            o = o.trim();
            if (o.startsWith("cachedir=") && o.length() > 9) return new File(stripQuotes(o.substring(9)));
        }
        for (String part : cmd.split(" ")) {
            if (part.startsWith("-cachedir=")) return new File(stripQuotes(part.substring("-cachedir=".length())));
        }
        String prop = System.getProperty("deployment.user.cachedir");
        String root = prop == null || System.getProperty("os.name", "").startsWith("Win") ? System.getProperty("user.home") : prop;
        return new File(root, "Zomboid");
    }

    static String stripQuotes(String s) {
        s = s.trim();
        if (s.length() >= 2 && s.startsWith("\"") && s.endsWith("\"")) s = s.substring(1, s.length() - 1);
        return s;
    }

    /** where the setup put the jar (LOCALAPPDATA/CookieSlicer or ~/.local/share/CookieSlicer) */
    static File stateDir() {
        try {
            File jar = new File(Helper.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            return jar.isFile() ? jar.getParentFile() : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** so the setup's "uninstall" can find and remove our file in this game's Lua folder */
    void rememberCacheDir(File cache) {
        if (stateDir == null) return;
        try {
            Files.write(new File(stateDir, "cachedir.txt").toPath(), (cache.getAbsolutePath() + "\n").getBytes(StandardCharsets.UTF_8));
        } catch (IOException ignored) {
            // only used by uninstall
        }
    }

    @Override
    public void run() {
        try { Thread.sleep(3000); } catch (InterruptedException e) { return; }
        while (true) {
            try {
                tick();
            } catch (Throwable t) {
                System.out.println("[CookieSlicerHelper] " + t);
            }
            try { Thread.sleep(2000); } catch (InterruptedException e) { return; }
        }
    }

    void tick() throws IOException {
        handleRequest();
        Map<String, String> m = measure();
        write(new File(luaDir, PC_FILE), m);
    }

    // ================================================================ measuring

    Map<String, String> measure() {
        Map<String, String> m = new LinkedHashMap<>();
        long now = System.currentTimeMillis();
        m.put("t", Long.toString(now));
        m.put("helper", VERSION);
        Runtime rt = Runtime.getRuntime();
        m.put("cores", Integer.toString(rt.availableProcessors()));

        long totalMb = -1;
        java.lang.management.OperatingSystemMXBean base = ManagementFactory.getOperatingSystemMXBean();
        if (base instanceof com.sun.management.OperatingSystemMXBean) {
            com.sun.management.OperatingSystemMXBean os = (com.sun.management.OperatingSystemMXBean) base;
            double all = os.getCpuLoad(), game = os.getProcessCpuLoad();
            if (all >= 0) m.put("cpu_total", Long.toString(Math.round(all * 100)));
            if (game >= 0) m.put("cpu_game", Long.toString(Math.round(game * 100)));
            totalMb = os.getTotalMemorySize() / MB;
            m.put("ram_total_mb", Long.toString(totalMb));
            m.put("ram_free_mb", Long.toString(os.getFreeMemorySize() / MB));
        }

        MemoryUsage heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
        long maxMb = heap.getMax() > 0 ? heap.getMax() / MB : rt.maxMemory() / MB;
        m.put("heap_used_mb", Long.toString(heap.getUsed() / MB));
        m.put("heap_max_mb", Long.toString(maxMb));
        long live = liveHeapMb();
        if (live >= 0) m.put("heap_live_mb", Long.toString(live));
        long peak = notePeak(live);
        if (peak > 0) m.put("heap_peak_mb", Long.toString(peak));
        if (totalMb > 0) {
            m.put("heap_recommend_mb", Long.toString(recommendHeapMb(totalMb, peak)));
            m.put("heap_safe_mb", Long.toString(safeHeapMb(totalMb)));
        }
        // chosen in the Slicer window and not in use yet (the game must start again)
        long next = heapNextMb > 0 ? heapNextMb : savedHeapMb();
        if (next > 0 && Math.abs(next - maxMb) > 256) m.put("heap_next_mb", Long.toString(next));
        if (heapNote != null) m.put("heap_note", heapNote);
        // what Windows sees the game keep for its memory (shrinks when the RAM savers are on)
        m.put("heap_committed_mb", Long.toString(heap.getCommitted() / MB));
        m.put("nonheap_mb", Long.toString(ManagementFactory.getMemoryMXBean().getNonHeapMemoryUsage().getCommitted() / MB));
        m.put("ramsave_now", ramsaveNow());
        m.put("ramsave_next", savedRamSave() ? "1" : "0");
        if (ramsaveNote != null) m.put("ramsave_note", ramsaveNote);
        m.put("gc", gcName());
        HeapReport.status(m);
        // keep the heap near what the game really uses (1.2.1)
        long cpu = -1;
        try { cpu = Long.parseLong(m.getOrDefault("cpu_total", "-1")); } catch (NumberFormatException ignored) { }
        long free = -1;
        try { free = Long.parseLong(m.getOrDefault("ram_free_mb", "-1")); } catch (NumberFormatException ignored) { }
        RamTune.tick(m, live, maxMb, rt.availableProcessors(), cpu, free, gcName(), ramsaveNow());

        threads(m, now);
        gc(m);
        ShaderState.status(m);
        // the game's start settings: read once a minute (the file only changes when the game is closed)
        if (jsonInfo == null || ++jsonAge >= 30) {
            jsonInfo = new LinkedHashMap<>();
            GameJson.report(new File(System.getProperty("user.dir", ".")), jsonInfo);
            jsonAge = 0;
        }
        m.putAll(jsonInfo);
        m.put("load_box", Integer.toString(LoadPatcher.hooked));
        // speed-ups (1.3.0): on now / at the next start, what they did since the game started
        m.put("speed_now", speedPatching && SpeedHooks.want ? "1" : "0");
        m.put("speed_next", savedSpeed(stateDir) ? "1" : "0");
        if (speedNote != null) m.put("speed_note", speedNote);
        if (speedPatching) SpeedHooks.status(m);
        Recorder.status(m);
        if (!m.containsKey("gpu") && gpuGuess != null) m.put("gpu", gpuGuess); // before the game has drawn a frame
        if (!m.containsKey("vram_total_mb") && gpuGuessMb > 0) m.put("vram_total_mb", Long.toString(gpuGuessMb));
        prevWall = now;
        return m;
    }

    /** heap in use right after the last clean-up (what the game really keeps), or -1 */
    static long liveHeapMb() {
        long sum = 0;
        boolean any = false;
        for (MemoryPoolMXBean p : ManagementFactory.getMemoryPoolMXBeans()) {
            if (p.getType() != MemoryType.HEAP) continue;
            MemoryUsage u = p.getCollectionUsage();
            if (u == null) continue;
            sum += u.getUsed();
            any = true;
        }
        return any ? sum / MB : -1;
    }

    /** the game RAM sizes the window offers (GB) */
    static final long[] STANDARD_GB = {3, 4, 6, 8, 10, 12, 16};

    /**
     * Game RAM to suggest (1.2.1): what the game used at most in the last sessions x 1.5
     * + 1.5 GB, at least 6 GB; 8 GB before there is any data. Rounded up to one of the
     * standard sizes (3 4 6 8 10 12 16 GB), but never more than safeHeapMb (room left for
     * Windows, Discord, a browser): then the biggest standard size within it.
     */
    static long recommendHeapMb(long totalMb, long peakMb) {
        long need = peakMb > 0 ? Math.max(6144, peakMb * 3 / 2 + 1536) : 8192;
        long safe = safeHeapMb(totalMb);
        long up = -1, within = STANDARD_GB[0] * 1024;
        for (long gb : STANDARD_GB) {
            long mb = gb * 1024;
            if (up < 0 && mb >= need) up = mb;
            if (mb <= safe) within = mb;
        }
        return up > 0 && up <= safe ? up : within;
    }

    static long recommendHeapMb(long totalMb) {
        return recommendHeapMb(totalMb, 0);
    }

    /**
     * The most game RAM this PC can give without running short: 6 GB left for the rest
     * on PCs with 16 GB or more (at most 16 GB for the game), 4 GB left on smaller ones,
     * never below 3 GB.
     */
    static long safeHeapMb(long totalMb) {
        if (totalMb >= 16384) return Math.min(16384, (totalMb - 6144) / 1024 * 1024);
        return Math.max(3072, (totalMb - 4096) / 1024 * 1024);
    }

    /** the most live data seen this session and the last ones (heapstats.txt), saved when it grows */
    long notePeak(long liveMb) {
        if (pastPeaks == null) {
            pastPeaks = new ArrayList<>();
            if (stateDir != null) {
                String v = read(new File(stateDir, STATS_FILE)).get("peaks");
                if (v != null) for (String x : v.split(",")) {
                    try { long p = Long.parseLong(x.trim()); if (p > 0) pastPeaks.add(p); } catch (NumberFormatException ignored) { }
                    if (pastPeaks.size() >= 4) break;
                }
            }
        }
        if (liveMb > peakLive) peakLive = liveMb;
        if (stateDir != null && peakLive - peakWritten >= 256) {
            StringBuilder sb = new StringBuilder("peaks=").append(peakLive);
            for (long p : pastPeaks) sb.append(',').append(p);
            try {
                Files.write(new File(stateDir, STATS_FILE).toPath(), (sb + "\n").getBytes(StandardCharsets.UTF_8));
                peakWritten = peakLive;
            } catch (IOException ignored) {
                // a hint only
            }
        }
        long max = peakLive;
        for (long p : pastPeaks) max = Math.max(max, p);
        return max;
    }

    private void threads(Map<String, String> m, long now) {
        ThreadMXBean tm = ManagementFactory.getThreadMXBean();
        if (!tm.isThreadCpuTimeSupported()) return;
        if (!tm.isThreadCpuTimeEnabled()) tm.setThreadCpuTimeEnabled(true);
        long wall = now - prevWall;
        long[] ids = tm.getAllThreadIds();
        String busiest = null, busy2 = null;
        double best = -1, best2 = -1;
        Map<Long, Long> seen = new HashMap<>();
        for (long id : ids) {
            long cpu = tm.getThreadCpuTime(id);
            if (cpu < 0) continue;
            seen.put(id, cpu);
            String name = threadNames.get(id);
            if (name == null) {
                ThreadInfo info = tm.getThreadInfo(id);
                if (info == null) continue;
                name = info.getThreadName();
                threadNames.put(id, name);
            }
            Long prev = prevThreadCpu.get(id);
            if (prev == null || prevWall == 0 || wall <= 0) continue;
            double pct = (cpu - prev) / 1e6 / wall * 100.0;
            if (name.startsWith("CookieSlicer")) continue;
            if (pct > best) { best2 = best; busy2 = busiest; best = pct; busiest = name; }
            else if (pct > best2) { best2 = pct; busy2 = name; }
        }
        threadNames.keySet().retainAll(seen.keySet());
        prevThreadCpu.clear();
        prevThreadCpu.putAll(seen);
        if (busiest == null) return;
        // the busiest game thread is the one that limits the frame rate (Zomboid runs
        // most of its work on one thread); shown as "main thread" in the mod
        m.put("main_thread", Long.toString(Math.min(100, Math.round(best))));
        m.put("busiest_thread", busiest.replace('\n', ' ') + " " + Math.min(100, Math.round(best)));
        if (busy2 != null) m.put("second_thread", busy2.replace('\n', ' ') + " " + Math.min(100, Math.round(best2)));
    }

    private void gc(Map<String, String> m) {
        long total = 0;
        for (GarbageCollectorMXBean g : ManagementFactory.getGarbageCollectorMXBeans()) {
            long t = g.getCollectionTime();
            if (t > 0) total += t;
        }
        if (prevGcMs >= 0) {
            gcWindow[gcIdx] = Math.max(0, total - prevGcMs);
            gcIdx = (gcIdx + 1) % gcWindow.length;
            long sum = 0;
            for (long v : gcWindow) sum += v;
            m.put("gc_ms_per_min", Long.toString(sum));
        }
        prevGcMs = total;
    }

    // ================================================================ graphics card (before the game draws)

    static volatile String gpuGuess;
    static volatile long gpuGuessMb;

    /**
     * Windows only, once, in the background: the graphics cards Windows knows, so the mod
     * can show one on the main menu. In game the card the game really uses (from OpenGL)
     * replaces it. AdapterRAM stops at 4 GB, so it is only shown when lower.
     */
    static void gpuNames() {
        if (!System.getProperty("os.name", "").startsWith("Win")) return;
        Thread t = new Thread(() -> {
            try {
                Process p = new ProcessBuilder("powershell", "-NoProfile", "-NonInteractive", "-Command",
                    "Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + '|' + $_.AdapterRAM }")
                    .redirectErrorStream(true).start();
                if (!p.waitFor(20, java.util.concurrent.TimeUnit.SECONDS)) { p.destroyForcibly(); return; }
                String best = null;
                long bestMb = 0;
                for (String line : new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8).split("\\R")) {
                    int bar = line.lastIndexOf('|');
                    if (bar <= 0) continue;
                    String name = line.substring(0, bar).trim();
                    String low = name.toLowerCase(java.util.Locale.ROOT);
                    if (low.contains("basic") || low.contains("virtual") || low.contains("parsec") || low.contains("remote")) continue;
                    long mb = parse(line.substring(bar + 1).trim(), 0) / MB;
                    boolean own = low.contains("nvidia") || low.contains("geforce") || low.contains(" rx ") || low.contains("radeon pro") || low.contains("arc(tm) a");
                    if (best == null || own) { best = name; bestMb = mb; }
                }
                if (best != null) {
                    gpuGuess = ShaderState.clean(best);
                    gpuGuessMb = bestMb > 0 && bestMb < 4095 ? bestMb : 0;
                }
            } catch (Throwable ignored) {
                // only a hint for the main menu
            }
        }, "CookieSlicer-GPU");
        t.setDaemon(true);
        t.start();
    }

    // ================================================================ "more RAM next start"

    void handleRequest() {
        File req = new File(luaDir, REQUEST_FILE);
        if (!req.isFile()) return;
        Map<String, String> r = read(req);
        long t = parse(r.get("t"), Long.MIN_VALUE);
        if (t != Long.MIN_VALUE && t <= lastRequestT) return;
        lastRequestT = t;
        try {
            Files.move(req.toPath(), new File(luaDir, REQUEST_FILE + ".done").toPath(), StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            req.delete();
        }
        String rs = r.get("ramsave");
        if (rs != null && !rs.isEmpty()) setRamSave(!"0".equals(rs.trim()));
        if ("1".equals(r.get("heap_report"))) HeapReport.startAsync(new File(luaDir, HeapReport.FILE));
        String sp = r.get("speed");
        if (sp != null && !sp.isEmpty()) setSpeed(!"0".equals(sp.trim()));
        long rec = parse(r.get("record"), -1);
        if (rec > 0) Recorder.start(luaDir.getAbsoluteFile().getParentFile(), (int) Math.min(rec, 300));
        setHeap(parse(r.get("heap_mb"), -1));
    }

    void setHeap(long mb) {
        if (mb <= 0) return;
        long totalMb = -1;
        java.lang.management.OperatingSystemMXBean base = ManagementFactory.getOperatingSystemMXBean();
        if (base instanceof com.sun.management.OperatingSystemMXBean) {
            totalMb = ((com.sun.management.OperatingSystemMXBean) base).getTotalMemorySize() / MB;
        }
        long limit = totalMb > 0 ? Math.max(3072, totalMb - 2048) : 16384;
        if (mb < 2048 || mb > Math.min(limit, 32768)) {
            heapNote = "refused " + mb + " MB (allowed 2048-" + Math.min(limit, 32768) + ")";
            return;
        }
        if (stateDir == null) {
            heapNote = "failed: helper folder unknown";
            return;
        }
        try {
            Files.write(new File(stateDir, HEAP_FILE).toPath(), ("heap_mb=" + mb + "\n").getBytes(StandardCharsets.UTF_8));
            heapNextMb = mb;
            heapNote = "ok";
            System.out.println("[CookieSlicerHelper] game RAM " + mb + " MB from the next start (" + new File(stateDir, HEAP_FILE) + ")");
        } catch (IOException e) {
            heapNote = "failed: " + e.getMessage();
        }
    }

    // ================================================================ RAM savers (start script)

    /** on/off for the next start: ramsave.txt next to the jar ("ramsave=0" = off; no file = on) */
    void setRamSave(boolean on) {
        if (stateDir == null) {
            ramsaveNote = "failed: helper folder unknown";
            return;
        }
        try {
            Files.write(new File(stateDir, RAMSAVE_FILE).toPath(), ("ramsave=" + (on ? 1 : 0) + "\n").getBytes(StandardCharsets.UTF_8));
            ramsaveNote = "ok";
            System.out.println("[CookieSlicerHelper] RAM savers " + (on ? "on" : "off") + " from the next start");
        } catch (IOException e) {
            ramsaveNote = "failed: " + e.getMessage();
        }
    }

    // ================================================================ speed-ups (1.3.0)

    /** on/off now (when they were set up at this start) and from the next start: speed.txt next to the jar */
    void setSpeed(boolean on) {
        if (speedPatching) SpeedHooks.setWant(on);
        if (stateDir == null) {
            speedNote = "failed: helper folder unknown";
            return;
        }
        try {
            Files.write(new File(stateDir, SPEED_FILE).toPath(), ("speed=" + (on ? 1 : 0) + "\n").getBytes(StandardCharsets.UTF_8));
            speedNote = "ok";
            System.out.println("[CookieSlicerHelper] speed-ups " + (on ? "on" : "off") + (speedPatching ? " now" : " from the next start"));
        } catch (IOException e) {
            speedNote = "failed: " + e.getMessage();
        }
    }

    static boolean savedSpeed(File stateDir) {
        if (stateDir == null) return true;
        File f = new File(stateDir, SPEED_FILE);
        return !f.isFile() || !"0".equals(read(f).get("speed"));
    }

    boolean savedRamSave() {
        if (stateDir == null) return true;
        File f = new File(stateDir, RAMSAVE_FILE);
        return !f.isFile() || !"0".equals(read(f).get("ramsave"));
    }

    /** "1" when this game runs with the savers (the start script added them), "0" when not, "?" unknown */
    static String ramsaveNow() {
        if (ramsaveNow == null) {
            try {
                com.sun.management.HotSpotDiagnosticMXBean d = ManagementFactory.getPlatformMXBean(com.sun.management.HotSpotDiagnosticMXBean.class);
                boolean coh = "true".equals(d.getVMOption("UseCompactObjectHeaders").getValue());
                boolean dedup = "true".equals(d.getVMOption("UseStringDeduplication").getValue());
                ramsaveNow = coh && dedup ? "1" : "0";
            } catch (Throwable t) {
                ramsaveNow = "?";
            }
        }
        return ramsaveNow;
    }

    /** ZGC / G1 / ... (what cleans up the game's memory) */
    static String gcName() {
        if (gcName == null) {
            String g = "?";
            for (GarbageCollectorMXBean b : ManagementFactory.getGarbageCollectorMXBeans()) {
                String n = b.getName();
                if (n.startsWith("ZGC")) { g = "ZGC"; break; }
                if (n.startsWith("G1")) { g = "G1"; break; }
                if (n.startsWith("Shenandoah")) { g = "Shenandoah"; break; }
                g = n.replace(' ', '_');
            }
            gcName = g;
        }
        return gcName;
    }

    /** RAM the start script will give the game next time (heap.txt), or 0 */
    long savedHeapMb() {
        if (stateDir == null) return 0;
        File f = new File(stateDir, HEAP_FILE);
        return f.isFile() ? Math.max(0, parse(read(f).get("heap_mb"), 0)) : 0;
    }

    // ================================================================ files

    static Map<String, String> read(File f) {
        Map<String, String> m = new HashMap<>();
        try {
            for (String line : Files.readAllLines(f.toPath(), StandardCharsets.UTF_8)) {
                int i = line.indexOf('=');
                if (i > 0) m.put(line.substring(0, i).trim(), line.substring(i + 1).trim());
            }
        } catch (IOException ignored) {
            // nothing to do this time
        }
        return m;
    }

    static long parse(String s, long dflt) {
        if (s == null) return dflt;
        try { return Long.parseLong(s.trim()); } catch (NumberFormatException e) { return dflt; }
    }

    static void write(File f, Map<String, String> m) throws IOException {
        File dir = f.getParentFile();
        if (dir == null || !dir.isDirectory()) return; // the game makes Zomboid/Lua itself
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : m.entrySet()) sb.append(e.getKey()).append('=').append(e.getValue()).append('\n');
        Path tmp = new File(dir, f.getName() + ".tmp").toPath();
        Files.write(tmp, sb.toString().getBytes(StandardCharsets.UTF_8));
        try {
            Files.move(tmp, f.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            Files.write(f.toPath(), sb.toString().getBytes(StandardCharsets.UTF_8)); // the game is reading it right now
            Files.deleteIfExists(tmp);
        }
    }
}
