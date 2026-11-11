package cookie.slicer.helper;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Map;

/** Run: see test/run.sh (argv[0] = scratch folder). */
public final class HelperTest {
    static int fails = 0;
    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    public static void main(String[] a) throws Exception {
        File out = new File(a[0]);

        System.out.println("H2 recommended RAM for the game");
        check(Helper.recommendHeapMb(8 * 1024) == 4096, "8 GB PC -> 4 GB");
        check(Helper.recommendHeapMb(16 * 1024) == 8192, "16 GB PC -> 8 GB");
        check(Helper.recommendHeapMb(32 * 1024) == 16384, "32 GB PC -> 16 GB");
        check(Helper.recommendHeapMb(64 * 1024) == 16384, "64 GB PC -> 16 GB (max)");
        check(Helper.recommendHeapMb(6 * 1024) == 3072, "6 GB PC -> 3 GB (4 GB left would be too much)");

        System.out.println("H3 a running helper: numbers + the RAM request");
        File lua = new File(out, "Zomboid/Lua");
        lua.mkdirs();
        File state = new File(out, "CookieSlicer");
        state.mkdirs();
        Helper h = new Helper(lua, state);
        h.tick();
        Thread.sleep(1200);
        long end = System.nanoTime() + 300_000_000L; long x = 0; while (System.nanoTime() < end) x += System.nanoTime() % 7; // some CPU
        h.tick();
        Map<String, String> pc = Helper.read(new File(lua, Helper.PC_FILE));
        for (String k : new String[] { "t", "helper", "cores", "cpu_total", "cpu_game", "ram_total_mb", "ram_free_mb", "heap_used_mb", "heap_max_mb", "heap_recommend_mb", "main_thread", "busiest_thread" }) {
            check(pc.containsKey(k), "pc file has " + k + "=" + pc.get(k));
        }
        check(pc.get("busiest_thread") != null && pc.get("busiest_thread").startsWith("main"), "busiest thread is the one burning CPU: " + pc.get("busiest_thread") + " (x=" + (x % 2) + ")");
        Files.write(new File(lua, Helper.REQUEST_FILE).toPath(), ("heap_mb=3072\nt=" + System.currentTimeMillis() + "\n").getBytes(StandardCharsets.UTF_8));
        h.tick();
        File heapFile = new File(state, Helper.HEAP_FILE);
        pc = Helper.read(new File(lua, Helper.PC_FILE));
        check(heapFile.isFile() && "3072".equals(Helper.read(heapFile).get("heap_mb")), "request: heap.txt says 3072 for the start script");
        check("3072".equals(pc.get("heap_next_mb")) && "ok".equals(pc.get("heap_note")), "pc says heap_next_mb=3072 ok (" + pc.get("heap_note") + ")");
        check(!new File(lua, Helper.REQUEST_FILE).exists() && new File(lua, Helper.REQUEST_FILE + ".done").exists(), "request moved to .done");
        Files.write(new File(lua, Helper.REQUEST_FILE).toPath(), ("heap_mb=999999\nt=" + (System.currentTimeMillis() + 5) + "\n").getBytes(StandardCharsets.UTF_8));
        h.tick();
        pc = Helper.read(new File(lua, Helper.PC_FILE));
        check("3072".equals(Helper.read(heapFile).get("heap_mb")) && pc.get("heap_note").startsWith("refused 999999"), "too big: refused, heap.txt unchanged (" + pc.get("heap_note") + ")");
        Files.write(new File(lua, Helper.REQUEST_FILE).toPath(), ("heap_mb=4096\nt=1\n").getBytes(StandardCharsets.UTF_8));
        h.tick();
        check("3072".equals(Helper.read(heapFile).get("heap_mb")), "old request (t not newer) ignored");
        Helper h2 = new Helper(lua, state);
        h2.tick();
        pc = Helper.read(new File(lua, Helper.PC_FILE));
        check("3072".equals(pc.get("heap_next_mb")), "a new start still shows the saved choice while it is not in use");
        Files.write(heapFile.toPath(), ("heap_mb=" + (Runtime.getRuntime().maxMemory() / Helper.MB) + "\n").getBytes(StandardCharsets.UTF_8));
        Helper h3 = new Helper(lua, state);
        h3.tick();
        pc = Helper.read(new File(lua, Helper.PC_FILE));
        check(!pc.containsKey("heap_next_mb"), "choice in use (= current max): no 'from next start' note");

        System.out.println("H4 cache dir from the command line");
        check(Helper.cacheDir("client;cachedir=P:\\Zomboid", "").getPath().equals("P:\\Zomboid"), "cachedir= from the start script (game exe sets no sun.java.command)");
        check(Helper.cacheDir("client;cachedir=\"D:\\My Games\\Zomboid\"", "").getPath().equals("D:\\My Games\\Zomboid"), "quoted folder with a space");
        check(Helper.cacheDir("", "zombie.gameStates.MainScreenState -cachedir=P:\\Zomboid -debug").getPath().equals("P:\\Zomboid"), "-cachedir= on the java command line");
        check(Helper.cacheDir("client", "").getPath().endsWith("Zomboid"), "default: home/Zomboid");
        check(Helper.hasOption("client;cachedir=x", "client") && !Helper.hasOption("cachedir=client", "client"), "client option");

        System.out.println(fails == 0 ? "ALL PASSED" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }

    private HelperTest() {}
}
