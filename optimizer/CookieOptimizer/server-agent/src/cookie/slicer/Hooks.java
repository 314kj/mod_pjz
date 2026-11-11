package cookie.slicer;

import java.io.File;
import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.zip.CRC32;

import zombie.Lua.LuaEventManager;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.core.logger.ExceptionLogger;
import zombie.globalObjects.SGlobalObjects;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.network.ClientChunkRequest;
import zombie.network.GameServer;
import zombie.network.ServerMap;

/**
 * What the changed game calls do instead (server main thread only).
 *
 * The game, when a server cell is added to the world, runs for each of its chunks:
 *   for every square with objects: ... LuaEventManager.triggerEvent("LoadGridsquare", square)
 *   ... SGlobalObjects.chunkLoaded(wx, wy) ... LuaEventManager.triggerEvent("LoadChunk", chunk)
 * all in the same tick. Here those three Lua calls are written down per chunk ("batch") and
 * run later, in the same order per chunk:
 *   - after each tick, inside a time budget, chunks nearest to a player first;
 *   - at once, for a chunk a player is about to download (so the player gets it the way
 *     the game would have sent it), up to send_flush_ms per tick;
 *   - a cell that unloads (no player near any more) drops what still waits for it: the
 *     events fire again the next time the cell loads (v1 ran it all first, which made
 *     ticks of up to ~1.7 s with thousands of squares; unload=run in the settings
 *     brings that back); a save does not wait for them either (run_before_save=true does);
 *   - squares or chunks that are no longer in the world when their turn comes are skipped.
 * At the original moment OnCookieSquareNow / OnCookieChunkNow fire instead (v3), for the
 * handlers that must not wait (see now()).
 * Everything else the game does when a chunk loads (zombies, vehicles, loot, erosion,
 * pathfinding, collision) is not touched and still happens in the same tick.
 * Any error in this code turns it off: everything waiting runs, and from then on the game's
 * own way is used.
 */
public final class Hooks {
    private static final int R_TICK = 0, R_SEND = 1, R_UNLOAD = 2, R_SAVE = 3, R_OFF = 4;

    static final class Batch {
        final IsoChunk chunk;
        final int wx, wy;
        final long born, seq;
        IsoGridSquare[] sq = new IsoGridSquare[64];
        int[] xyz = new int[64 * 3];
        int n, next;
        boolean globalObjects, loadChunk, done;
        int goX, goY;
        double dist;

        Batch(IsoChunk chunk, long seq) {
            this.chunk = chunk;
            this.wx = chunk.wx;
            this.wy = chunk.wy;
            this.seq = seq;
            this.born = System.nanoTime();
        }

        void add(IsoGridSquare s) {
            if (n == sq.length) {
                sq = java.util.Arrays.copyOf(sq, n * 2);
                xyz = java.util.Arrays.copyOf(xyz, n * 6);
            }
            sq[n] = s;
            xyz[n * 3] = s.x;
            xyz[n * 3 + 1] = s.y;
            xyz[n * 3 + 2] = s.z;
            n++;
        }
    }

    private static boolean started, enabled, off, breaking;
    private static Thread mainThread;
    private static Batch cur;
    private static final ArrayList<Batch> queue = new ArrayList<>();
    private static final IdentityHashMap<IsoChunk, Batch> byChunk = new IdentityHashMap<>();
    private static int waiting;
    private static long seq;
    private static long tickStart, sendSpentNs, lastSwitchCheck, lastLog;
    private static File offFile, modeFile, gameModeFile, luaDir;
    /** what the current on/off state came from, and since when */
    private static String source = "start";
    private static long sinceMs = System.currentTimeMillis();
    private static String notWorking = "";
    private static float[] px = new float[16], py = new float[16];

    // statistics since the last status line
    private static final long[] ran = new long[5];
    private static long deferred, skipped, droppedAtUnload, luaErrors, sentEarly, maxWaiting, maxBatches;
    private static long ticks, ticksOver100, ticksOver1000, longestTickNs, longestDrainNs, saveFlushNs;
    private static long batchesDone, delaySumNs, delayMaxNs, chunksLoaded;
    private static boolean firstStatus = true;

    private Hooks() {}

    // ================================================================ game tick

    /** GameServer.main: ServerMap.instance.preupdate() */
    public static void preupdate(ServerMap map) {
        tickStart = System.nanoTime();
        sendSpentNs = 0;
        if (!started) start();
        map.preupdate();
    }

    /** GameServer.main: ServerMap.instance.postupdate() */
    public static void postupdate(ServerMap map) {
        map.postupdate();
        try {
            if (enabled) {
                switchCheck();
                if (!off) drain();
            }
            long now = System.nanoTime();
            if (started) {
                long t = now - tickStart;
                ticks++;
                if (t > 100_000_000L) ticksOver100++;
                if (t >= 1_000_000_000L) ticksOver1000++;
                if (t > longestTickNs) longestTickNs = t;
                if (now - lastLog >= Config.logEverySec * 1_000_000_000L) {
                    status();
                    lastLog = now;
                }
            }
        } catch (Throwable t) {
            broken(t);
        }
    }

    private static void start() {
        started = true;
        mainThread = Thread.currentThread();
        lastLog = lastSwitchCheck = System.nanoTime();
        try {
            luaDir = gameLuaDir();
            files();
            String rev = Core.getGitRevisionString();
            if (!"any".equalsIgnoreCase(Config.revision) && !Config.revision.equals(rev)) {
                notWorking = "game revision " + rev + " is not " + Config.revision;
                Log.line("game revision " + rev + " is not the one this was tested on (" + Config.revision
                    + "): the server runs the game's own way. Only tick times are logged.");
                writeStatus(null);
                return;
            }
            if (!State.ok(Patcher.MAP) || !State.ok(Patcher.SERVER)) {
                notWorking = "game code changed";
                Log.line("server map: " + State.of(Patcher.MAP) + ", main loop: " + State.of(Patcher.SERVER)
                    + " -> the server runs the game's own way. Only tick times are logged.");
                writeStatus(null);
                return;
            }
            enabled = true;
            off = wantOff();
            sinceMs = System.currentTimeMillis();
            Log.line("ready (game revision " + rev + "): "
                + (off ? "switched OFF by " + source + " - square events run the game's own way, tick times are logged"
                       : "ON - square events wait for their turn")
                + "; switches: " + where(modeFile) + ", " + where(gameModeFile) + " (the one changed last counts)"
                + (offFile != null ? ", " + where(offFile) + " (exists = always off)" : ""));
            writeStatus(null);
        } catch (Throwable t) {
            broken(t);
        }
    }

    /** Zomboid/Lua of this server (the folder the game's Lua getFileWriter writes into), or null. */
    private static File gameLuaDir() {
        try {
            String cache = zombie.ZomboidFileSystem.instance.getCacheDir();
            return cache == null || cache.isEmpty() ? null : new File(cache, "Lua");
        } catch (Throwable t) {
            Log.line("could not find the game's Lua folder (" + t + "): in-game switch and status file there are not used");
            return null;
        }
    }

    private static void files() {
        offFile = Config.resolve(Config.dir, Config.offFile);
        modeFile = Config.resolve(Config.dir, Config.modeFile);
        gameModeFile = Config.resolve(luaDir, Config.gameModeFile);
    }

    private static String where(File f) {
        return f == null ? "-" : f.getPath();
    }

    /**
     * Off while CookieSlicer.off exists, otherwise what the mode file changed last says:
     * CookieSlicer.mode next to the jar (slicer-on/off.bat) or CookieSlicer_mode.txt in the
     * game's Lua folder (in-game !onslice / !offslice). No mode file = on. Sets {@link #source}.
     */
    private static boolean wantOff() {
        if (offFile != null && offFile.exists()) { source = offFile.getName() + " (file exists)"; return true; }
        File m = newest(modeFile, gameModeFile);
        if (m == null) { source = "default (no switch file)"; return false; }
        try {
            byte[] b = java.nio.file.Files.readAllBytes(m.toPath());
            String s = new String(b, 0, Math.min(b.length, 64), java.nio.charset.StandardCharsets.UTF_8)
                .replace("\uFEFF", "").trim().toLowerCase(java.util.Locale.ROOT);
            source = m == gameModeFile ? "in game (" + m.getName() + ")" : m.getName();
            return s.startsWith("off");
        } catch (IOException e) {
            return off; // could not read it this time: keep what we have
        }
    }

    /** The existing file of the two that was changed last (a tie goes to b). */
    private static File newest(File a, File b) {
        boolean ha = a != null && a.isFile(), hb = b != null && b.isFile();
        if (!ha) return hb ? b : null;
        if (!hb) return a;
        return a.lastModified() > b.lastModified() ? a : b;
    }

    private static void switchCheck() {
        long now = System.nanoTime();
        if (now - lastSwitchCheck < 5_000_000_000L) return;
        lastSwitchCheck = now;
        if (Config.reloadIfChanged()) {
            files();
            Log.line("settings reloaded: " + Config.summary());
        }
        boolean want = wantOff();
        if (want && !off) {
            off = true;
            sinceMs = System.currentTimeMillis();
            int n = waiting;
            flushAll(R_OFF);
            Log.line("switched OFF by " + source + ": " + n
                + " waiting squares ran now; from now on square events run the game's own way");
            writeStatus(null);
        } else if (!want && off) {
            off = false;
            sinceMs = System.currentTimeMillis();
            Log.line("switched ON by " + source + ": square events wait for their turn again");
            writeStatus(null);
        }
    }

    // ================================================================ chunk loading

    private static boolean deferNow() {
        return enabled && !off && cur == null && Thread.currentThread() == mainThread && State.ok(Patcher.CHUNK);
    }

    /** ServerMap.ServerCell.RecalcAll2: chunk.doLoadGridsquare() */
    public static void doLoadGridsquare(IsoChunk chunk) {
        chunksLoaded++;
        if (!deferNow()) {
            chunk.doLoadGridsquare();
            return;
        }
        Batch b = new Batch(chunk, ++seq);
        cur = b;
        try {
            chunk.doLoadGridsquare();
        } finally {
            cur = null;
            keep(b);
        }
    }

    private static void keep(Batch b) {
        try {
            if (!enabled || off) {
                run(b, 0, R_OFF);
                return;
            }
            if (b.n == 0) {
                // no square to wait for: the chunk's own events run now, after its squares as before
                finish(b);
                return;
            }
            Batch old = byChunk.put(b.chunk, b);
            if (old != null && !old.done) run(old, 0, R_UNLOAD);
            queue.add(b);
            waiting += b.n;
            deferred += b.n;
            if (waiting > maxWaiting) maxWaiting = waiting;
            if (queue.size() > maxBatches) maxBatches = queue.size();
        } catch (Throwable t) {
            if (!b.done) {
                try { run(b, 0, R_OFF); } catch (Throwable ignored) { }
            }
            broken(t);
        }
    }

    /** IsoChunk.doLoadGridsquare: LuaEventManager.triggerEvent("LoadGridsquare" / "LoadChunk", ...) */
    public static void event(String name, Object arg) {
        Batch b = cur;
        if (b != null && Thread.currentThread() == mainThread) {
            if (arg instanceof IsoGridSquare && "LoadGridsquare".equals(name)) {
                now(NOW_SQUARE, arg);
                b.add((IsoGridSquare) arg);
                return;
            }
            if ("LoadChunk".equals(name) && arg == b.chunk) {
                now(NOW_CHUNK, arg);
                b.loadChunk = true;
                return;
            }
        }
        LuaEventManager.triggerEvent(name, arg);
    }

    /**
     * Fired at the moment the game used to fire LoadGridsquare / LoadChunk, for the few
     * handlers that must run before the game fills the chunk's rooms (CSP moves them
     * there, e.g. AliveJeem's base zombie safety; they skip the late event). With no
     * handler this costs one map lookup.
     */
    static final String NOW_SQUARE = "OnCookieSquareNow", NOW_CHUNK = "OnCookieChunkNow";

    private static void now(String event, Object arg) {
        try {
            LuaEventManager.triggerEvent(event, arg);
        } catch (Throwable t) {
            luaError(t);
        }
    }

    /** IsoChunk.doLoadGridsquare: SGlobalObjects.chunkLoaded(wx, wy) */
    public static void globalObjectsChunkLoaded(int wx, int wy) {
        Batch b = cur;
        if (b != null && Thread.currentThread() == mainThread) {
            b.globalObjects = true;
            b.goX = wx;
            b.goY = wy;
            return;
        }
        SGlobalObjects.chunkLoaded(wx, wy);
    }

    // ================================================================ running what waits

    /** Runs a batch until done or until endNs (0 = no limit). Returns true when it is finished. */
    private static boolean run(Batch b, long endNs, int reason) {
        if (b.done) return true;
        ServerMap map = ServerMap.instance;
        if (map == null || map.getChunk(b.wx, b.wy) != b.chunk) {
            drop(b);
            return true;
        }
        while (b.next < b.n) {
            if (endNs != 0 && System.nanoTime() >= endNs) return false;
            int k = b.next++;
            IsoGridSquare s = b.sq[k];
            b.sq[k] = null;
            waiting--;
            if (map.getGridSquare(b.xyz[k * 3], b.xyz[k * 3 + 1], b.xyz[k * 3 + 2]) != s) {
                skipped++;
                continue;
            }
            try {
                LuaEventManager.triggerEvent("LoadGridsquare", s);
            } catch (Throwable t) {
                luaError(t);
            }
            ran[reason]++;
        }
        finish(b);
        return true;
    }

    private static void finish(Batch b) {
        b.done = true;
        if (byChunk.get(b.chunk) == b) byChunk.remove(b.chunk);
        if (b.globalObjects) {
            try {
                SGlobalObjects.chunkLoaded(b.goX, b.goY);
            } catch (Throwable t) {
                luaError(t);
            }
        }
        if (b.loadChunk) {
            try {
                LuaEventManager.triggerEvent("LoadChunk", b.chunk);
            } catch (Throwable t) {
                luaError(t);
            }
        }
        if (b.n > 0) {
            long d = System.nanoTime() - b.born;
            batchesDone++;
            delaySumNs += d;
            if (d > delayMaxNs) delayMaxNs = d;
        }
    }

    private static void drop(Batch b) {
        int left = b.n - b.next;
        waiting -= left;
        skipped += left;
        for (int k = b.next; k < b.n; k++) b.sq[k] = null;
        b.next = b.n;
        b.done = true;
        if (byChunk.get(b.chunk) == b) byChunk.remove(b.chunk);
    }

    private static void drain() {
        if (queue.isEmpty()) return;
        long now = System.nanoTime();
        long min = Math.min(Config.maxDrainNs, Config.minDrainNs + (waiting / 1000L) * Config.pressureNsPer1000);
        long budget = Math.max(min, Math.min(Config.maxDrainNs, Config.targetTickNs - (now - tickStart)));
        long end = now + budget;
        order();
        int i = 0;
        while (i < queue.size() && run(queue.get(i), end, R_TICK)) i++;
        if (i > 0) queue.subList(0, i).clear();
        long took = System.nanoTime() - now;
        if (took > longestDrainNs) longestDrainNs = took;
    }

    /** Nearest chunk to any player first; without players, oldest first. */
    private static void order() {
        queue.removeIf(b -> b.done);
        if (queue.size() < 2) return;
        int np = 0;
        try {
            ArrayList<IsoPlayer> players = GameServer.Players;
            int count = players.size();
            if (px.length < count) {
                px = new float[count];
                py = new float[count];
            }
            for (int i = 0; i < count; i++) {
                IsoPlayer p = players.get(i);
                if (p == null) continue;
                px[np] = p.getX();
                py[np] = p.getY();
                np++;
            }
        } catch (RuntimeException e) {
            np = 0;
        }
        for (Batch b : queue) {
            double best = Double.MAX_VALUE;
            double cx = b.wx * 8 + 4, cy = b.wy * 8 + 4;
            for (int i = 0; i < np; i++) {
                double dx = cx - px[i], dy = cy - py[i];
                double d = dx * dx + dy * dy;
                if (d < best) best = d;
            }
            b.dist = best;
        }
        queue.sort((a, c) -> a.dist != c.dist ? Double.compare(a.dist, c.dist) : Long.compare(a.seq, c.seq));
    }

    private static void flushAll(int reason) {
        if (queue.isEmpty()) return;
        ArrayList<Batch> all = new ArrayList<>(queue);
        queue.clear();
        for (Batch b : all) {
            if (!b.done) run(b, 0, reason);
        }
    }

    // ================================================================ unload, save, download

    /** ServerMap.postupdate: cell.Unload() for a cell no player is near any more */
    public static void unloadCell(ServerMap.ServerCell cell) {
        if (!queue.isEmpty()) flushCell(cell, !Config.runBeforeUnload);
        cell.Unload();
    }

    /** ServerMap.preupdate: cell.Unload() for a cell that failed to load (the game drops it) */
    public static void unloadDroppedCell(ServerMap.ServerCell cell) {
        if (!queue.isEmpty()) flushCell(cell, true);
        cell.Unload();
    }

    private static void flushCell(ServerMap.ServerCell cell, boolean dropIt) {
        try {
            IsoChunk[][] chunks = cell.chunks;
            for (IsoChunk[] row : chunks) {
                if (row == null) continue;
                for (IsoChunk c : row) {
                    if (c == null) continue;
                    Batch b = byChunk.get(c);
                    if (b == null || b.done) continue;
                    if (dropIt) {
                        droppedAtUnload += b.n - b.next;
                        drop(b);
                    } else {
                        run(b, 0, R_UNLOAD);
                    }
                }
            }
        } catch (Throwable t) {
            broken(t);
        }
    }

    /** ServerMap.preupdate: this.QueuedSaveAll(false) (the periodic and the admin "save") */
    public static void queuedSaveAll(ServerMap map, boolean quit) {
        if (Config.runBeforeSave && !queue.isEmpty() && Thread.currentThread() == mainThread) {
            long t0 = System.nanoTime();
            try {
                flushAll(R_SAVE);
            } catch (Throwable t) {
                broken(t);
            }
            saveFlushNs += System.nanoTime() - t0;
        }
        map.QueuedSaveAll(quit);
    }

    /** PlayerDownloadServer.update: chunk.SaveLoadedChunk(...) for a player who asked for a loaded chunk */
    public static void saveLoadedChunk(IsoChunk chunk, ClientChunkRequest.Chunk request, CRC32 crc) throws IOException {
        if (!queue.isEmpty() && Thread.currentThread() == mainThread) {
            try {
                Batch b = byChunk.get(chunk);
                if (b != null && !b.done) {
                    if (sendSpentNs < Config.sendFlushNs) {
                        long t0 = System.nanoTime();
                        run(b, 0, R_SEND);
                        sendSpentNs += System.nanoTime() - t0;
                    } else {
                        sentEarly++;
                    }
                }
            } catch (Throwable t) {
                broken(t);
            }
        }
        chunk.SaveLoadedChunk(request, crc);
    }

    // ================================================================ errors and status

    private static void luaError(Throwable t) {
        luaErrors++;
        try {
            ExceptionLogger.logException(t);
        } catch (Throwable ignored) {
            // nothing else to do
        }
    }

    private static void broken(Throwable t) {
        if (breaking) return;
        breaking = true;
        try {
            StringWriter sw = new StringWriter();
            t.printStackTrace(new PrintWriter(sw));
            Log.line("error in CookieSlicer, turning it off (the server runs the game's own way from now on): " + sw);
            enabled = false;
            notWorking = "turned itself off after an error, see CookieSlicer.log";
            cur = null;
            flushAll(R_OFF);
            writeStatus(null);
        } catch (Throwable ignored) {
            enabled = false;
        } finally {
            breaking = false;
        }
    }

    private static String lastMinute = "";

    /**
     * CookieSlicer_status.txt next to the jar and in the game's Lua folder (read by
     * slicer-status.bat and the in-game !slice). Never throws.
     */
    static void writeStatus(String minute) {
        try {
            if (minute != null) lastMinute = minute;
            java.text.SimpleDateFormat hm = new java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT);
            String state = enabled ? (off ? "OFF" : "ON") : "NOT WORKING";
            StringBuilder t = new StringBuilder();
            t.append("Cookie Slicer v").append(Agent.VERSION).append(": ").append(state);
            if (enabled) t.append(" since ").append(hm.format(new java.util.Date(sinceMs))).append(" (by ").append(source).append(")");
            else t.append(" - the game's own way").append(notWorking.isEmpty() ? "" : " (" + notWorking + ")");
            t.append("\r\n");
            if (!lastMinute.isEmpty()) t.append(lastMinute).append("\r\n");
            t.append("updated ").append(hm.format(new java.util.Date())).append("\r\n");
            byte[] b = t.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
            write(Config.resolve(Config.dir, Config.statusFile), b);
            if (luaDir != null) write(Config.resolve(luaDir, Config.statusFile), b);
        } catch (Throwable ignored) {
            // the log has the same information
        }
    }

    private static void write(File f, byte[] b) {
        if (f == null) return;
        try {
            File dir = f.getAbsoluteFile().getParentFile();
            if (dir == null || !dir.isDirectory()) return;
            File tmp = new File(dir, f.getName() + ".tmp");
            java.nio.file.Files.write(tmp.toPath(), b);
            try {
                java.nio.file.Files.move(tmp.toPath(), f.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    java.nio.file.StandardCopyOption.ATOMIC_MOVE);
            } catch (IOException e) {
                java.nio.file.Files.write(f.toPath(), b); // e.g. someone has it open right now
                tmp.delete();
            }
        } catch (Throwable ignored) {
            // not important enough to disturb anything
        }
    }

    private static void status() {
        StringBuilder s = new StringBuilder();
        int players = 0;
        try { players = GameServer.Players.size(); } catch (RuntimeException ignored) { }
        s.append(Config.logEverySec).append(" s: players ").append(players)
            .append(", chunks loaded ").append(chunksLoaded)
            .append("; ticks ").append(ticks)
            .append(" (over 100 ms: ").append(ticksOver100)
            .append(", 1 s or more: ").append(ticksOver1000)
            .append(", longest ").append(Config.toMs(longestTickNs / 1_000_000L * 1_000_000L)).append(" ms)");
        if (enabled) {
            long total = ran[R_TICK] + ran[R_SEND] + ran[R_UNLOAD] + ran[R_SAVE] + ran[R_OFF];
            s.append("; squares waited ").append(deferred)
                .append(", ran ").append(total)
                .append(" (in tick budget ").append(ran[R_TICK])
                .append(", before download ").append(ran[R_SEND])
                .append(", before unload ").append(ran[R_UNLOAD])
                .append(", before save ").append(ran[R_SAVE]);
            if (ran[R_OFF] > 0) s.append(", at switch-off ").append(ran[R_OFF]);
            s.append("), skipped (no longer loaded) ").append(skipped)
                .append(" of which dropped with their cell ").append(droppedAtUnload)
                .append("; waiting now ").append(waiting).append(" squares in ").append(byChunk.size()).append(" chunks")
                .append(" (most ").append(maxWaiting).append(" in ").append(maxBatches).append(")")
                .append("; longest square work in a tick ").append(Config.toMs(longestDrainNs / 100_000L * 100_000L)).append(" ms");
            if (batchesDone > 0) {
                s.append("; chunk wait avg ").append(delaySumNs / batchesDone / 1_000_000L)
                    .append(" ms, max ").append(delayMaxNs / 1_000_000L).append(" ms");
            }
            if (sentEarly > 0) s.append("; downloaded before their squares ran ").append(sentEarly).append(" chunks");
            if (saveFlushNs > 0) s.append("; before-save work ").append(saveFlushNs / 1_000_000L).append(" ms");
            if (luaErrors > 0) s.append("; Lua errors ").append(luaErrors);
            if (off) s.append("; OFF (").append(source).append(")");
        } else {
            s.append("; game's own way");
        }
        if (firstStatus) {
            firstStatus = false;
            s.append("; chunks: ").append(State.of(Patcher.CHUNK))
                .append(", cells: ").append(State.of(Patcher.CELL))
                .append(", downloads: ").append(State.of(Patcher.DOWNLOAD));
        }
        Log.line(s.toString());
        writeStatus("last " + Config.logEverySec + " s: players " + players + ", ticks " + ticks
            + ", 1 s or more " + ticksOver1000 + ", longest " + longestTickNs / 1_000_000L + " ms"
            + (enabled ? ", waiting " + waiting + " squares" + (luaErrors > 0 ? ", Lua errors " + luaErrors : "") : ""));
        for (int i = 0; i < ran.length; i++) ran[i] = 0;
        deferred = skipped = droppedAtUnload = luaErrors = sentEarly = 0;
        maxWaiting = waiting;
        maxBatches = byChunk.size();
        ticks = ticksOver100 = ticksOver1000 = longestTickNs = longestDrainNs = saveFlushNs = 0;
        batchesDone = delaySumNs = delayMaxNs = chunksLoaded = 0;
    }

    // ================================================================ for the test harness

    static String debugState() {
        return "enabled=" + enabled + " off=" + off + " waiting=" + waiting + " batches=" + byChunk.size()
            + " queue=" + queue.size();
    }

    static int waitingSquares() { return waiting; }
}
