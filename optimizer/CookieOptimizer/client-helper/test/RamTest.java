package cookie.slicer.helper;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Map;

/**
 * Less-RAM checks (helper 1.2.0).
 *  R1  class names made readable and grouped by package
 *  R2  a real class histogram of this Java -> top classes, groups, totals
 *  R3  the window's requests: RAM savers off / on (ramsave.txt), "what uses RAM" (CookieSlicer_heap.txt)
 *  R4  the pc file says whether this Java runs with the savers (run with and without them)
 * Run: java [savers] -cp <test classes> cookie.slicer.helper.RamTest <out dir> <expect ramsave_now: 1|0>
 */
public final class RamTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    public static void main(String[] a) throws Exception {
        File out = new File(a[0]);
        String expectNow = a.length > 1 ? a[1] : null;
        // ---------------------------------------------------------------- R1
        System.out.println("R1 names and groups");
        check("byte[]".equals(HeapReport.readable("[B")), "[B -> byte[]");
        check("java.lang.Object[]".equals(HeapReport.readable("[Ljava.lang.Object;")), "[Ljava.lang.Object; -> java.lang.Object[]");
        check("int[][]".equals(HeapReport.readable("[[I")), "[[I -> int[][]");
        check("zombie.iso.IsoGridSquare".equals(HeapReport.readable("zombie.iso.IsoGridSquare")), "plain class kept");
        check("byte[]".equals(HeapReport.group("byte[]")), "group byte[]");
        check("java.lang.String".equals(HeapReport.group("java.lang.String")), "group java class kept");
        check("zombie.iso.*".equals(HeapReport.group("zombie.iso.IsoGridSquare")), "group zombie.iso.*: " + HeapReport.group("zombie.iso.IsoGridSquare"));
        check("zombie.iso.sprite.*".equals(HeapReport.group("zombie.iso.sprite.IsoSprite")), "group zombie.iso.sprite.*");
        check("zombie.core.textures.*".equals(HeapReport.group("zombie.core.textures.Texture[]")), "group of an array of game objects");
        check("org.lwjgl.*".equals(HeapReport.group("org.lwjgl.system.MemoryStack")), "group org.lwjgl.*");
        check("zombie.*".equals(HeapReport.group("zombie.GameWindow")), "group zombie.*");

        // ---------------------------------------------------------------- R2
        System.out.println("R2 real histogram");
        byte[][] keep = new byte[64][];
        for (int i = 0; i < keep.length; i++) keep[i] = new byte[256 * 1024]; // 16 MB of byte[]
        long t0 = System.currentTimeMillis();
        String h = HeapReport.histogram();
        long took = System.currentTimeMillis() - t0;
        Map<String, String> m = HeapReport.summarize(h);
        System.out.println("     histogram took " + took + " ms, total " + m.get("total_mb") + " MB, " + m.get("total_objects") + " objects");
        System.out.println("     c1=" + m.get("c1") + "  g1=" + m.get("g1"));
        check("40".equals(m.get("n")), "40 top classes (" + m.get("n") + ")");
        check(Long.parseLong(m.get("total_mb")) >= 16, "total counts the 16 MB kept");
        check(m.get("c1").endsWith("|byte[]"), "byte[] is the biggest here");
        check(Integer.parseInt(m.get("gn")) > 3, "groups listed");
        long sum = 0;
        for (int i = 1; i <= 40; i++) {
            String[] p = m.get("c" + i).split("\\|");
            check(p.length == 3 && Long.parseLong(p[0]) > 0 && Long.parseLong(p[1]) > 0, "c" + i + " = bytes|count|name");
            if (fails > 0) break;
            sum += Long.parseLong(p[0]);
        }
        check(sum / Helper.MB <= Long.parseLong(m.get("total_mb")) + 1, "top 40 within the total");
        if (keep[3].length == 0) System.out.println(); // keep alive

        // ---------------------------------------------------------------- R3
        System.out.println("R3 requests from the window");
        File lua = new File(out, "ram/Lua"), state = new File(out, "ram/app");
        lua.mkdirs();
        state.mkdirs();
        new File(state, Helper.RAMSAVE_FILE).delete();
        new File(lua, HeapReport.FILE).delete();
        Helper hp = new Helper(lua, state);
        check(hp.savedRamSave(), "no ramsave.txt = savers on");
        request(lua, "t=100\nramsave=0\n");
        hp.handleRequest();
        check(!hp.savedRamSave(), "ramsave=0 -> off for next start");
        check(read(new File(state, Helper.RAMSAVE_FILE)).contains("ramsave=0"), "ramsave.txt says 0");
        request(lua, "t=101\nramsave=1\nheap_report=1\n");
        hp.handleRequest();
        check(hp.savedRamSave(), "ramsave=1 -> on again");
        File heap = new File(lua, HeapReport.FILE);
        for (int i = 0; i < 100 && !heap.isFile(); i++) Thread.sleep(100);
        check(heap.isFile(), "CookieSlicer_heap.txt written");
        for (int i = 0; i < 50 && !"done".equals(HeapReport.state); i++) Thread.sleep(100);
        Map<String, String> f = Helper.read(heap);
        check("done".equals(HeapReport.state) && f.containsKey("c1") && f.containsKey("g1") && f.containsKey("t"), "file has t, c1.., g1..");
        request(lua, "t=101\nramsave=0\n");
        hp.handleRequest();
        check(hp.savedRamSave(), "an old request (same t) is ignored");
        check(!new File(state, Helper.HEAP_FILE).isFile(), "no heap_mb -> heap.txt untouched");

        // ---------------------------------------------------------------- R4
        System.out.println("R4 pc file");
        Map<String, String> pc = hp.measure();
        for (String k : new String[] {"heap_committed_mb", "nonheap_mb", "ramsave_now", "ramsave_next", "gc", "heap_report"}) {
            check(pc.containsKey(k), k + "=" + pc.get(k));
        }
        if (expectNow != null) check(expectNow.equals(pc.get("ramsave_now")), "ramsave_now is " + expectNow + " for this Java");
        for (String k : new String[] {"heap_peak_mb", "heap_recommend_mb", "heap_safe_mb", "ramtune"}) {
            check(pc.containsKey(k), k + "=" + pc.get(k) + " (1.2.1)");
        }
        if (expectNow != null) {
            boolean on = "1".equals(expectNow);
            check(on == "on".equals(pc.get("ramtune")) && on == pc.containsKey("soft_max_mb"),
                "soft ceiling kept by the helper only with the savers: ramtune=" + pc.get("ramtune") + " soft_max_mb=" + pc.get("soft_max_mb"));
        }

        // ---------------------------------------------------------------- R5
        System.out.println("R5 soft ceiling follows real use (1.2.1)");
        check(RamTune.target(4700, 16384, 8) == 8074, "5 GB used, 16 GB game RAM -> 8074 MB (" + RamTune.target(4700, 16384, 8) + ")");
        check(RamTune.target(500, 16384, 8) == 4096, "little used -> floor 4 GB");
        check(RamTune.target(12000, 16384, 8) == 13926, "a lot used -> 85% of game RAM");
        check(RamTune.target(3000, 8192, 4) == 6936, "4 cores: more room (x1.8 + 1.5 GB)");
        check(RamTune.target(1000, 6144, 8) == 3072, "small game RAM: floor = half");
        RamTune.reset();
        check(RamTune.next(-1, 8000, 0, 10) == 8000, "first value set at once");
        check(RamTune.next(6000, 8000, 0, 10) == 8000, "raise at once");
        check(RamTune.next(8000, 7900, 100_000, 10) == 8000, "lower by < 256 MB: stays");
        check(RamTune.next(8000, 6000, 100_000, 95) == 8000, "CPU busy: does not lower");
        check(RamTune.next(13000, 4096, 100_000, 10) == 10952, "lower at most 2 GB per step");
        Map<String, String> t = new java.util.LinkedHashMap<>();
        RamTune.tick(t, 4700, 16384, 8, 10, 30000, "ZGC", "0");
        check("off".equals(t.get("ramtune")), "savers off -> does nothing");
        t.clear();
        RamTune.tick(t, 4700, 16384, 8, 10, 30000, "G1", "1");
        check("off".equals(t.get("ramtune")), "G1 -> does nothing");
        if ("1".equals(expectNow)) {
            t.clear();
            long max = Runtime.getRuntime().maxMemory() / Helper.MB;
            long want = RamTune.target(200, max, 8);
            RamTune.tick(t, 200, max, 8, 10, 30000, "ZGC", "1");
            check("on".equals(t.get("ramtune")) && RamTune.current() == want, "this Java: SoftMaxHeapSize set to " + RamTune.current() + " MB (want " + want + ")");
        }

        check(RamTune.squeeze(4700, 16384) == 5917, "PC short of RAM: 4.7 GB used -> 5917 MB (" + RamTune.squeeze(4700, 16384) + ")");
        if ("1".equals(expectNow)) {
            t.clear();
            RamTune.reset();
            long jmax = Runtime.getRuntime().maxMemory() / Helper.MB;
            RamTune.tick(t, 400, jmax, 8, 10, 30000, "ZGC", "1");
            long before = RamTune.current();
            t.clear();
            RamTune.tick(t, 400, jmax, 8, 99, 1500, "ZGC", "1");
            long sq = RamTune.current();
            check("1".equals(t.get("ram_guard")) && sq == RamTune.squeeze(400, jmax) && before == RamTune.target(400, jmax, 8) && sq < before,
                "PC under 2 GB free: squeezes at once even with CPU busy (" + before + " -> " + sq + " MB)");
            t.clear();
            RamTune.tick(t, 400, jmax, 8, 10, 2500, "ZGC", "1");
            check("1".equals(t.get("ram_guard")) && RamTune.current() == sq, "2.5 GB free a moment later: stays squeezed (no see-saw)");
        }

        // ---------------------------------------------------------------- R6
        System.out.println("R6 suggested game RAM from what the game used (1.2.1)");
        check(Helper.recommendHeapMb(16384, 0) == 8192, "16 GB PC, no data -> 8 GB");
        check(Helper.recommendHeapMb(16384, 5000) == 9216, "16 GB PC, used 5 GB -> 9 GB");
        check(Helper.recommendHeapMb(16384, 8000) == 10240, "16 GB PC, used 8 GB -> 10 GB (safe max, 6 GB left)");
        check(Helper.recommendHeapMb(131072, 4700) == 9216, "128 GB PC, used 4.7 GB -> 9 GB (" + Helper.recommendHeapMb(131072, 4700) + ")");
        check(Helper.recommendHeapMb(131072, 2000) == 6144, "used little -> at least 6 GB");
        check(Helper.safeHeapMb(131072) == 16384 && Helper.safeHeapMb(16384) == 10240 && Helper.safeHeapMb(8192) == 4096, "safe max: 16 / 10 / 4 GB");
        File st = new File(out, "ram/app2");
        st.mkdirs();
        Files.write(new File(st, Helper.STATS_FILE).toPath(), "peaks=6100,4800\n".getBytes(StandardCharsets.UTF_8));
        Helper h2 = new Helper(lua, st);
        check(h2.notePeak(3000) == 6100, "last sessions' peak counts (6100)");
        check(h2.notePeak(7000) == 7000 && read(new File(st, Helper.STATS_FILE)).startsWith("peaks=7000,6100,4800"), "new peak saved first: " + read(new File(st, Helper.STATS_FILE)).trim());

        System.out.println(fails == 0 ? "RamTest: all passed" : "RamTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }

    static void request(File lua, String s) throws Exception {
        Files.write(new File(lua, Helper.REQUEST_FILE).toPath(), s.getBytes(StandardCharsets.UTF_8));
    }

    static String read(File f) throws Exception {
        return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
    }
}
