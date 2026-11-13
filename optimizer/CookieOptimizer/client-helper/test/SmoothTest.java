package cookie.slicer.helper;

import java.io.File;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

import zombie.util.CappedConcurrentQueue;

/**
 * Helper 1.4.0 smooth: map pieces per frame and zombies in 3D.
 *  M1-M7  SmoothHooks driven by the same loop as the game's IsoChunkMap.updateInternal
 *         (count = 1 + 3 x waiting / width, poll, finish), with pieces that take a set time
 *  P1-P3  SmoothPatcher on the game's real IsoChunkMap / IsoWorld: every place found, only those
 *         bytes changed, the originals gone; with a folder argument, writes the patched classes
 *  W1-W2  the window's request: smooth.txt written and read back, values kept in range
 * Usage: SmoothTest <projectzomboid.jar> <out dir> [patched classes dir]
 */
public final class SmoothTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static final int WIDTH = 13; // a usual IsoChunkMap.chunkGridWidth

    static void spin(double ms) {
        long end = System.nanoTime() + (long) (ms * 1_000_000);
        while (System.nanoTime() < end) Thread.onSpinWait();
    }

    /** one frame of the game's loop; returns the pieces finished, in order */
    static List<Integer> frame(CappedConcurrentQueue<Integer> q, double msEach, long[] frameNs) {
        List<Integer> done = new ArrayList<>();
        long t0 = System.nanoTime();
        int n = SmoothHooks.chunkQueueSize(q);
        if (n != 0) n = 1 + n * 3 / WIDTH;
        while (n > 0) {
            Object c = SmoothHooks.chunkQueuePoll(q);
            if (c != null) {
                spin(msEach);
                done.add((Integer) c);
            }
            n--;
        }
        if (frameNs != null) frameNs[0] = System.nanoTime() - t0;
        return done;
    }

    static CappedConcurrentQueue<Integer> queue(int n) {
        CappedConcurrentQueue<Integer> q = new CappedConcurrentQueue<>(Integer.MAX_VALUE);
        for (int i = 0; i < n; i++) q.add(i);
        return q;
    }

    static int gameCount(int waiting) {
        return waiting == 0 ? 0 : 1 + waiting * 3 / WIDTH;
    }

    static void hooks() {
        System.out.println("map pieces per frame");
        // M1 the game's way (0): the same count as the game
        SmoothHooks.forceInGame = 1;
        SmoothHooks.chunkMs = 0;
        CappedConcurrentQueue<Integer> q = queue(60);
        List<Integer> f = frame(q, 1.5, null);
        check(f.size() == gameCount(60), "M1 chunk_ms 0: " + f.size() + " pieces in the frame, the game's " + gameCount(60));

        // M2 on, in game, 3 ms each, 4 ms: stops after the time, at least one, never more than the game
        SmoothHooks.chunkMs = 4;
        q = queue(60);
        long[] ns = new long[1];
        boolean allOk = true, ordered = true;
        int frames = 0, maxPer = 0, next = 0;
        double worstMs = 0;
        while (!q.isEmpty() && frames < 500) {
            int waiting = q.size();
            List<Integer> d = frame(q, 3, ns);
            frames++;
            if (d.isEmpty() || d.size() > gameCount(waiting)) allOk = false;
            for (int v : d) if (v != next++) ordered = false;
            maxPer = Math.max(maxPer, d.size());
            worstMs = Math.max(worstMs, ns[0] / 1e6);
        }
        check(q.isEmpty() && next == 60, "M2 all 60 pieces finished (" + frames + " frames, the game: " + framesGame(60) + ")");
        check(allOk, "M2 every frame: at least 1, never more than the game's count");
        check(ordered, "M2 same order as the queue");
        check(maxPer <= 2 && worstMs < 4 + 3 + 2, "M2 at most " + maxPer + " per frame, longest frame " + fmt(worstMs) + " ms (game: " + gameCount(60) + " x 3 ms = " + gameCount(60) * 3 + " ms)");
        check(SmoothHooks.chunksWaited > 0 && SmoothHooks.framesCut > 0, "M2 counted: waited " + SmoothHooks.chunksWaited + ", frames cut " + SmoothHooks.framesCut);

        // M3 a piece slower than the time: still one per frame
        q = queue(5);
        List<Integer> one = frame(q, 10, null);
        check(one.size() == 1, "M3 one 10 ms piece: 1 in the frame (keeps moving)");

        // M4 fast pieces: all the game wants fit in the time
        q = queue(40);
        f = frame(q, 0.05, null);
        check(f.size() == gameCount(40), "M4 0.05 ms pieces: " + f.size() + " = the game's " + gameCount(40));

        // M5 loading screen: the game's way even when on
        SmoothHooks.forceInGame = 0;
        q = queue(60);
        f = frame(q, 3, null);
        check(f.size() == gameCount(60), "M5 loading screen: " + f.size() + " = the game's " + gameCount(60));
        SmoothHooks.forceInGame = 1;

        // M6 empty queue: nothing, like the game
        q = queue(0);
        check(frame(q, 3, null).isEmpty(), "M6 empty queue: nothing");

        // M7 zombies in 3D
        SmoothHooks.limit3d = SmoothHooks.GAME_3D;
        check(SmoothHooks.zombies3d() == 510, "M7 default 510 (the game's own number)");
        Map<String, String> m = new HashMap<>();
        m.put("zombies3d", "200");
        SmoothHooks.set(m);
        check(SmoothHooks.zombies3d() == 200, "M7 200 from the window");
        m.put("zombies3d", "50");
        SmoothHooks.set(m);
        check(SmoothHooks.zombies3d() == 510, "M7 50 (not offered) -> 510");
        SmoothHooks.forceInGame = -1;
    }

    static int framesGame(int n) {
        int frames = 0;
        while (n > 0) { n -= Math.min(n, gameCount(n)); frames++; }
        return frames;
    }

    static String fmt(double v) { return String.format(java.util.Locale.ROOT, "%.1f", v); }

    // ---------------------------------------------------------------- the real classes

    static void real(String jar, String outDir) throws Exception {
        System.out.println("game classes (" + jar + ")");
        try (ZipFile z = new ZipFile(jar)) {
            for (String c : SmoothPatcher.TARGETS) {
                byte[] in = z.getInputStream(new ZipEntry(c + ".class")).readAllBytes();
                byte[] out;
                try {
                    out = SmoothPatcher.patch(c, in);
                } catch (Throwable t) {
                    check(false, "P1 " + c + ": " + t.getMessage());
                    continue;
                }
                int edits = c.equals(SmoothPatcher.CHUNKMAP) ? 2 : 1;
                check(true, "P1 " + c + ": all " + edits + " place(s) found");
                int changed = changedBytes(in, out);
                check(changed > 0 && changed <= 3 * edits, "P2 " + c + ": " + changed + " code bytes changed (at most " + 3 * edits + "), size " + in.length + " -> " + out.length);
                boolean gone;
                try {
                    SmoothPatcher.patch(c, out);
                    gone = false;
                } catch (IllegalStateException e) {
                    gone = e.getMessage().contains("found 0");
                }
                check(gone, "P3 " + c + ": the game's originals are no longer there");
                if (outDir != null) {
                    File f = new File(outDir, c + ".class");
                    f.getParentFile().mkdirs();
                    Files.write(f.toPath(), out);
                }
            }
        }
    }

    /** bytes that differ, the class after the constant pool lined up (the pool only grows at its end) */
    static int changedBytes(byte[] a, byte[] b) {
        int d = b.length - a.length;
        int cpEnd = 10;
        while (cpEnd < a.length && a[cpEnd] == b[cpEnd]) cpEnd++;
        int n = 0;
        for (int i = cpEnd; i < a.length; i++) if (a[i] != b[i + d]) n++;
        return n;
    }

    // ---------------------------------------------------------------- the window's request

    static void window(File out) throws Exception {
        System.out.println("window");
        File lua = new File(out, "lua"), state = new File(out, "state");
        lua.mkdirs();
        state.mkdirs();
        Helper h = new Helper(lua, state);
        Map<String, String> r = new HashMap<>();
        r.put("chunk_ms", "6");
        r.put("zombies3d", "300");
        h.setSmooth(r);
        Map<String, String> saved = Helper.read(new File(state, Helper.SMOOTH_FILE));
        check("6".equals(saved.get("chunk_ms")) && "300".equals(saved.get("zombies3d")), "W1 smooth.txt: chunk_ms=6 zombies3d=300 (now: " + SmoothHooks.chunkMs + ", " + SmoothHooks.limit3d + ")");
        r.clear();
        r.put("chunk_ms", "99");
        SmoothHooks.set(r);
        int high = SmoothHooks.chunkMs;
        r.put("chunk_ms", "1");
        SmoothHooks.set(r);
        int low = SmoothHooks.chunkMs;
        r.put("chunk_ms", "0");
        SmoothHooks.set(r);
        check(high == 16 && low == 2 && SmoothHooks.chunkMs == 0 && SmoothHooks.limit3d == 300, "W2 chunk_ms kept 2-16 or 0 (99 -> " + high + ", 1 -> " + low + "), zombies3d untouched");
        Map<String, String> st = new HashMap<>();
        SmoothHooks.status(st);
        check(st.containsKey("smooth_classes") && st.containsKey("chunks_waited") && "300".equals(st.get("zombies3d")), "W2 pc file keys: " + st.keySet());
    }

    public static void main(String[] a) throws Exception {
        hooks();
        real(a[0], a.length > 2 ? a[2] : null);
        window(new File(a[1]));
        System.out.println(fails == 0 ? "SmoothTest: all ok" : "SmoothTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
