package cookie.slicer;

import java.io.File;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import zombie.TestWorld;
import zombie.characters.IsoPlayer;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
import zombie.network.GameServer;
import zombie.network.ServerMap;

/** Behaviour test of Hooks against a fake world (test/stubs). Run: see test/run.sh */
public final class SlicerTest {
    static int fails = 0;
    static final ServerMap map = ServerMap.instance;
    static final List<String> log = TestWorld.log;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static long count(String prefix) { return log.stream().filter(s -> s.startsWith(prefix)).count(); }

    /** One game tick; load runs inside preupdate like a cell load. Returns ms the tick took. */
    static double tick(Runnable load) {
        map.onPre = load;
        long t0 = System.nanoTime();
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        return (System.nanoTime() - t0) / 1e6;
    }

    /** Per chunk: all its LGS lines come before its GO line, and GO before LC. Each square once. */
    static void checkOrder(ServerMap.ServerCell cell, String label) {
        Map<String, Integer> pos = new HashMap<>();
        Set<String> dup = new HashSet<>();
        for (int i = 0; i < log.size(); i++) if (pos.put(log.get(i), i) != null && log.get(i).startsWith("LGS")) dup.add(log.get(i));
        boolean ok = dup.isEmpty();
        for (IsoChunk[] row : cell.chunks) for (IsoChunk c : row) {
            Integer go = pos.get("GO " + c.wx + "," + c.wy), lc = pos.get("LC " + c.wx + "," + c.wy);
            if (go == null || lc == null || go > lc) { ok = false; continue; }
            for (IsoGridSquare s : c.squares) {
                Integer p = pos.get("LGS " + s.key());
                if (p == null || p > go) ok = false;
            }
        }
        check(ok, label + ": every square once, then its chunk's GO, then LoadChunk" + (dup.isEmpty() ? "" : " dup=" + dup.size()));
    }

    public static void main(String[] args) throws Exception {
        File dir = Files.createTempDirectory("slicer").toFile();
        Config.load(dir);
        Config.dir = dir;
        Config.logEverySec = 3600;
        Log.init(dir);
        File zdir = new File(dir, "Zomboid");
        new File(zdir, "Lua").mkdirs();
        TestWorld.cacheDir = zdir.getPath();
        for (String c : new String[] { Patcher.CHUNK, Patcher.CELL, Patcher.MAP, Patcher.SERVER, Patcher.DOWNLOAD }) State.patched(c);
        if (args.length > 0 && args[0].equals("wrongrev")) { wrongRevision(); return; }

        GameServer.Players.add(new IsoPlayer(5 * 8 + 4, 3 * 8 + 4)); // stands in chunk (5,3) of cell (0,0)

        // warm-up (class loading / JIT), not measured
        map.onPre = () -> map.loadCell(40, 40, 20);
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        while (Hooks.waitingSquares() > 0) tick(null);
        log.clear();

        System.out.println("T1 a cell's square events wait, then run within the budget, nearest chunk first");
        TestWorld.costNs = 50_000; // 50 us per square, 64 chunks x 20 squares = 64 ms of "Lua"
        final ServerMap.ServerCell[] c1 = new ServerMap.ServerCell[1];
        map.onPre = () -> {
            c1[0] = map.loadCell(0, 0, 20);
            check(count("LGS") == 0, "no LoadGridsquare ran while the cell loaded");
            check(count("JAVA") == 64, "the game's own chunk work still ran for all 64 chunks");
            check(count("GO") == 0 && count("LC") == 0, "global objects / LoadChunk wait with their squares");
            check(count("NOW ") == 1280 && count("NOWC") == 64, "OnCookieSquareNow / OnCookieChunkNow fired at load time (" + count("NOW ") + ", " + count("NOWC") + ")");
            check(log.indexOf("NOWC 0,0") > log.indexOf("NOW 0,0,0") && log.indexOf("NOWC 0,0") < log.indexOf("NOW 0,8,0"), "per chunk: square now-events, then the chunk's");
        };
        long t0 = System.nanoTime();
        Hooks.preupdate(map);
        double loadMs = (System.nanoTime() - t0) / 1e6;
        int before = log.size();
        long t1 = System.nanoTime();
        Hooks.postupdate(map);
        double drainMs = (System.nanoTime() - t1) / 1e6;
        long ran1 = log.subList(before, log.size()).stream().filter(s -> s.startsWith("LGS")).count();
        check(loadMs < 30, "cell load tick took " + String.format("%.1f", loadMs) + " ms (game work only)");
        check(drainMs <= 62, "first drain took " + String.format("%.1f", drainMs) + " ms (cap 60) and ran " + ran1 + " squares");
        String firstLgs = log.subList(before, log.size()).stream().filter(s -> s.startsWith("LGS")).findFirst().orElse("");
        check(firstLgs.startsWith("LGS 40,24,"), "first square run is in the player's chunk (5,3): " + firstLgs);
        int ticks = 1;
        double worst = drainMs;
        while (Hooks.waitingSquares() > 0 && ticks < 50) { worst = Math.max(worst, tick(null)); ticks++; }
        check(Hooks.waitingSquares() == 0, "all squares ran after " + ticks + " ticks, worst tick " + String.format("%.1f", worst) + " ms");
        checkOrder(c1[0], "T1");

        System.out.println("T2 a chunk a player downloads runs first; over send_flush_ms it is sent without waiting");
        log.clear();
        TestWorld.costNs = 50_000;
        final ServerMap.ServerCell[] c2 = new ServerMap.ServerCell[1];
        map.onPre = () -> c2[0] = map.loadCell(1, 0, 20);
        Hooks.preupdate(map);
        IsoChunk d = c2[0].chunks[2][2];
        Hooks.saveLoadedChunk(d, null, null);
        int send = log.indexOf("SEND " + d.wx + "," + d.wy), lc = log.indexOf("LC " + d.wx + "," + d.wy);
        check(send > 0 && lc >= 0 && lc < send && count("LGS") == 20, "downloaded chunk's squares + LoadChunk ran before it was written");
        TestWorld.costNs = 2_000_000; // 20 squares x 2 ms = 40 ms per chunk, over the 25 ms
        IsoChunk e1 = c2[0].chunks[3][3], e2 = c2[0].chunks[4][4];
        Hooks.saveLoadedChunk(e1, null, null);
        Hooks.saveLoadedChunk(e2, null, null);
        int lcE2 = log.indexOf("LC " + e2.wx + "," + e2.wy), sendE2 = log.indexOf("SEND " + e2.wx + "," + e2.wy);
        check(log.indexOf("LC " + e1.wx + "," + e1.wy) < log.indexOf("SEND " + e1.wx + "," + e1.wy), "first big chunk still runs before its download");
        check(lcE2 < 0 && sendE2 > 0, "second one is sent without waiting (budget used up this tick)");
        TestWorld.costNs = 20_000;
        Hooks.postupdate(map);
        while (Hooks.waitingSquares() > 0) tick(null);
        checkOrder(c2[0], "T2");

        System.out.println("T3 a cell unloaded while squares wait: they are dropped (default), or run first with unload=run");
        log.clear();
        final ServerMap.ServerCell[] c3 = new ServerMap.ServerCell[1];
        map.onPre = () -> c3[0] = map.loadCell(2, 0, 10);
        Hooks.preupdate(map);
        Hooks.unloadCell(c3[0]);
        int un = log.indexOf("UNLOAD 2,0");
        check(un >= 0 && count("LGS") == 0 && count("LC") == 0, "dropped, nothing ran (" + count("LGS") + ")");
        Hooks.postupdate(map);
        check(Hooks.waitingSquares() == 0, "nothing left waiting: " + Hooks.debugState());
        // unload=run, set while running (settings file reloaded)
        Files.write(new File(dir, "CookieSlicer.properties").toPath(), "unload=run\n".getBytes("UTF-8"));
        Thread.sleep(5100);
        tick(null);
        check(Config.runBeforeUnload, "settings reloaded while running: unload=run");
        log.clear();
        final ServerMap.ServerCell[] c3b = new ServerMap.ServerCell[1];
        map.onPre = () -> c3b[0] = map.loadCell(2, 1, 10);
        Hooks.preupdate(map);
        Hooks.unloadCell(c3b[0]);
        int un2 = log.indexOf("UNLOAD 2,1");
        long lgsBefore = log.subList(0, Math.max(un2, 0)).stream().filter(s -> s.startsWith("LGS")).count();
        check(un2 > 0 && lgsBefore == 640, "unload=run: all 640 ran before UNLOAD (" + lgsBefore + ")");
        Hooks.postupdate(map);
        new File(dir, "CookieSlicer.properties").delete();
        Thread.sleep(5100);
        tick(null);
        check(!Config.runBeforeUnload, "settings file removed: back to drop");

        System.out.println("T4 a cell the game drops after a load error: its waiting squares are skipped");
        log.clear();
        final ServerMap.ServerCell[] c4 = new ServerMap.ServerCell[1];
        map.onPre = () -> c4[0] = map.loadCell(3, 0, 10);
        Hooks.preupdate(map);
        Hooks.unloadDroppedCell(c4[0]);
        check(count("LGS") == 0 && count("UNLOAD 3,0") == 1, "dropped without running");
        Hooks.postupdate(map);
        check(Hooks.waitingSquares() == 0, "nothing left waiting: " + Hooks.debugState());

        System.out.println("T5 world save: does not wait (default)");
        log.clear();
        map.onPre = () -> {
            map.loadCell(4, 0, 10);
            Hooks.queuedSaveAll(map, false);
        };
        Hooks.preupdate(map);
        check(log.indexOf("SAVE") == log.size() - 1 && count("LGS") == 0, "SAVE right away, squares still waiting");
        Hooks.postupdate(map);
        while (Hooks.waitingSquares() > 0) tick(null);
        check(count("LGS") == 640 && count("LC") == 64, "they run after the save as usual");

        System.out.println("T6 squares / chunks gone before their turn are skipped; Lua errors are logged and work goes on");
        log.clear();
        final ServerMap.ServerCell[] c6 = new ServerMap.ServerCell[1];
        map.onPre = () -> c6[0] = map.loadCell(5, 0, 10);
        Hooks.preupdate(map);
        IsoGridSquare gone = c6[0].chunks[0][0].squares.get(3);
        map.squares.remove(gone.key());
        IsoChunk goneChunk = c6[0].chunks[7][7];
        map.chunks.remove(ServerMapKey.k(goneChunk.wx, goneChunk.wy));
        TestWorld.throwOn = c6[0].chunks[1][1].squares.get(0).key();
        Hooks.postupdate(map);
        while (Hooks.waitingSquares() > 0) tick(null);
        check(!log.contains("LGS " + gone.key()), "removed square skipped");
        check(!log.contains("LC " + goneChunk.wx + "," + goneChunk.wy), "removed chunk skipped (no LoadChunk either)");
        check(count("EXC boom") == 1 && count("LGS") == 640 - 1 - 10, "error logged once, others ran (" + count("LGS") + ")");
        TestWorld.throwOn = null;

        System.out.println("T7 a chunk with no squares: its GO + LoadChunk run at once, in order");
        log.clear();
        map.onPre = () -> map.loadCell(6, 0, 0);
        Hooks.preupdate(map);
        check(count("GO") == 64 && count("LC") == 64 && log.indexOf("GO 48,0") < log.indexOf("LC 48,0"), "immediate, GO before LC");
        Hooks.postupdate(map);

        System.out.println("T7b while off, no now-events (the late events run at once, as the game does)");
        System.out.println("T8 CookieSlicer.off switches to the game's own way (and back)");
        log.clear();
        File off = new File(dir, Config.offFile);
        off.createNewFile();
        Thread.sleep(5100);
        map.onPre = () -> map.loadCell(7, 0, 10);
        Hooks.preupdate(map);
        Hooks.postupdate(map); // sees the file: runs what waits, then stops waiting
        check(Hooks.waitingSquares() == 0 && count("LGS") == 640, "waiting squares ran when switched off");
        log.clear();
        map.onPre = () -> {
            map.loadCell(8, 0, 10);
            check(count("LGS") == 640, "while off, squares run during the cell load (game's own way)");
            check(count("NOW ") == 0 && count("NOWC") == 0, "while off, no now-events");
        };
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        off.delete();
        Thread.sleep(5100);
        tick(null);
        log.clear();
        map.onPre = () -> {
            map.loadCell(9, 0, 10);
            check(count("LGS") == 0, "back on: squares wait again");
        };
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        while (Hooks.waitingSquares() > 0) tick(null);

        System.out.println("T8b CookieSlicer.mode: off / on, written by someone while the server runs");
        File mode = new File(dir, Config.modeFile);
        Files.write(mode.toPath(), "﻿off\r\n".getBytes("UTF-8"));
        map.onPre = () -> map.loadCell(10, 0, 10);
        Hooks.preupdate(map);
        Thread.sleep(5100);
        log.clear();
        Hooks.postupdate(map);
        check(Hooks.waitingSquares() == 0 && count("LGS") == 640, "mode=off (with BOM/CRLF): waiting squares ran, now the game's own way");
        log.clear();
        map.onPre = () -> {
            map.loadCell(11, 0, 10);
            check(count("LGS") == 640, "mode=off: squares run during the cell load");
        };
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        Files.write(mode.toPath(), "on".getBytes("UTF-8"));
        Thread.sleep(5100);
        tick(null);
        log.clear();
        map.onPre = () -> {
            map.loadCell(12, 0, 10);
            check(count("LGS") == 0, "mode=on: squares wait again");
        };
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        while (Hooks.waitingSquares() > 0) tick(null);

        System.out.println("T8c in-game switch (Zomboid/Lua/CookieSlicer_mode.txt): the mode file changed last counts");
        File gameMode = new File(zdir, "Lua/" + Config.gameModeFile);
        File stJar = new File(dir, Config.statusFile), stLua = new File(zdir, "Lua/" + Config.statusFile);
        check(read(stJar).contains(": ON since") && read(stLua).equals(read(stJar)), "status file next to the jar and in Zomboid/Lua at start: " + first(stJar));
        Files.write(gameMode.toPath(), "off".getBytes("UTF-8"));
        Thread.sleep(5100);
        tick(null);
        log.clear();
        map.onPre = () -> {
            map.loadCell(13, 0, 10);
            check(count("LGS") == 640, "in-game off (newer than the bat's on): squares run during the cell load");
        };
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        check(read(stLua).contains(": OFF since") && read(stLua).contains("by in game"), "status says OFF, by in game: " + first(stLua));
        Files.write(mode.toPath(), "on\r\n".getBytes("UTF-8"));
        Thread.sleep(5100);
        tick(null);
        log.clear();
        map.onPre = () -> {
            map.loadCell(14, 0, 10);
            check(count("LGS") == 0, "bat on (newer than the in-game off): squares wait again");
        };
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        while (Hooks.waitingSquares() > 0) tick(null);
        check(read(stJar).contains(": ON since") && read(stJar).contains("by CookieSlicer.mode"), "status says ON, by the bat's file: " + first(stJar));
        gameMode.delete();
        mode.delete();
        Config.logEverySec = 5;
        Thread.sleep(5100);
        tick(null);
        Config.logEverySec = 3600;
        check(read(stLua).contains("last 5 s: players 1, ticks "), "status line numbers in the status file: " + read(stLua).split("\r\n")[1]);

        System.out.println("T9 big burst (6 cells at once, 76 us per square): no tick over ~80 ms");
        log.clear();
        TestWorld.costNs = 76_000;
        GameServer.Players.get(0).x = 20 * 64 + 32;
        GameServer.Players.get(0).y = 32;
        map.onPre = () -> { for (int i = 0; i < 6; i++) map.loadCell(18 + i, 0, 60); };
        long b0 = System.nanoTime();
        Hooks.preupdate(map);
        double burstLoad = (System.nanoTime() - b0) / 1e6;
        Hooks.postupdate(map);
        double worstTick = 0;
        int n = 0;
        while (Hooks.waitingSquares() > 0 && n < 500) { worstTick = Math.max(worstTick, tick(null)); n++; }
        double game = 6 * 64 * 60 * 0.076;
        check(worstTick < 85, String.format("23040 squares (%.0f ms of Lua, vanilla = one %.1f s tick) ran over %d ticks, worst %.1f ms (load tick %.1f ms)",
            game, game / 1000, n, worstTick, burstLoad));

        Hooks.postupdate(map);
        System.out.println(fails == 0 ? "ALL PASSED" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }

    static void wrongRevision() {
        System.out.println("T10 another game revision: the game's own way");
        TestWorld.revision = "0000000000";
        map.onPre = () -> {
            map.loadCell(0, 0, 10);
            check(count("LGS") == 640, "square events ran during the load, as the game does");
        };
        Hooks.preupdate(map);
        Hooks.postupdate(map);
        File st = new File(new File(TestWorld.cacheDir, "Lua"), Config.statusFile);
        check(read(st).contains("NOT WORKING") && read(st).contains("game revision 0000000000"), "status file says it is not working: " + first(st));
        System.out.println(fails == 0 ? "ALL PASSED" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }

    static String read(File f) {
        try { return new String(Files.readAllBytes(f.toPath()), "UTF-8"); } catch (Exception e) { return ""; }
    }

    static String first(File f) {
        String s = read(f);
        int i = s.indexOf('\r');
        return i < 0 ? s : s.substring(0, i);
    }

    /** same key as the fake ServerMap */
    static final class ServerMapKey {
        static long k(int a, int b) { return ((long) a << 32) ^ (b & 0xffffffffL); }
    }

    private SlicerTest() {}
}
