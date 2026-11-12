package cookie.slicer.helper;

import java.io.File;
import java.nio.file.Files;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * "Record 3 minutes" (helper 1.3.0): a short recording through Java's flight recorder is written
 * into the folder (a folder name with a space), the pc keys say running -> done, a second start
 * while one runs is refused, and only the newest 3 cookie_rec_*.jfr stay (other files untouched).
 * Usage: java -cp <test classes> cookie.slicer.helper.RecTest <out dir>
 */
public final class RecTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    public static void main(String[] a) throws Exception {
        File dir = new File(a[0], "Zomboid folder");
        dir.mkdirs();
        for (File f : dir.listFiles()) f.delete();
        // older recordings + a file that is not ours
        for (String n : new String[] {"cookie_rec_20261101-100000.jfr", "cookie_rec_20261102-100000.jfr", "cookie_rec_20261103-100000.jfr", "console.txt"}) {
            Files.write(new File(dir, n).toPath(), "x".getBytes());
        }
        System.out.println("R1 a 3-second recording");
        Recorder.minSeconds = 3;
        Map<String, String> m = new LinkedHashMap<>();
        Recorder.status(m);
        check("idle".equals(m.get("rec")), "idle before: " + m);
        check(Recorder.start(dir, 3), "started");
        check(!Recorder.start(dir, 3), "a second start while one runs is refused");
        m.clear();
        Recorder.status(m);
        check("running".equals(m.get("rec")) && m.get("rec_left_s") != null && m.get("rec_file").startsWith("cookie_rec_"), "running: " + m);
        double x = 0;
        long t0 = System.currentTimeMillis();
        while (!"done".equals(m.get("rec")) && System.currentTimeMillis() - t0 < 30_000) {
            long t1 = System.currentTimeMillis();
            while (System.currentTimeMillis() - t1 < 500) x += Math.sqrt(x + 1); // something to record
            m.clear();
            Recorder.status(m);
        }
        File f = new File(m.get("rec_dir"), m.get("rec_file"));
        check("done".equals(m.get("rec")) && f.isFile() && f.length() > 10_000, "done: " + f.getName() + " " + f.length() / 1024 + " KB (" + m + ") " + (x > 0 ? "" : "."));
        String[] left = dir.list();
        java.util.Arrays.sort(left);
        check(left.length == 4 && new File(dir, "console.txt").isFile() && !new File(dir, "cookie_rec_20261101-100000.jfr").exists(),
            "newest 3 recordings kept, the oldest removed, other files untouched: " + String.join(", ", left));
        System.out.println("R2 a start that cannot work");
        Recorder.state = "idle";
        File notDir = new File(dir, "console.txt");
        check(!Recorder.start(new File(notDir, "sub"), 3), "folder cannot be made: refused");
        m.clear();
        Recorder.status(m);
        check(m.get("rec").startsWith("failed"), "pc file says failed: " + m.get("rec"));
        System.out.println("R3 the window's requests: speed-ups on/off (speed.txt), record");
        File lua = new File(dir, "Lua"), state = new File(a[0], "rec-app");
        lua.mkdirs();
        state.mkdirs();
        new File(state, Helper.SPEED_FILE).delete();
        Helper h = new Helper(lua, state);
        check(Helper.savedSpeed(state), "no speed.txt = on");
        Files.write(new File(lua, Helper.REQUEST_FILE).toPath(), "t=200\nspeed=0\n".getBytes());
        h.handleRequest();
        check(!Helper.savedSpeed(state) && new String(Files.readAllBytes(new File(state, Helper.SPEED_FILE).toPath())).contains("speed=0"), "speed=0 -> speed.txt says 0");
        Map<String, String> pc = h.measure();
        check("0".equals(pc.get("speed_now")) && "0".equals(pc.get("speed_next")) && "ok".equals(pc.get("speed_note")), "pc: speed_now=0 (not set up at this start), speed_next=0");
        Files.write(new File(lua, Helper.REQUEST_FILE).toPath(), "t=201\nspeed=1\nrecord=3\n".getBytes());
        h.handleRequest();
        pc = h.measure();
        check(Helper.savedSpeed(state) && "1".equals(pc.get("speed_next")), "speed=1 -> on from the next start");
        check("running".equals(pc.get("rec")) && new File(pc.get("rec_dir")).getAbsoluteFile().equals(dir.getAbsoluteFile()),
            "record=3 -> recording into the Zomboid folder (the Lua folder's parent): " + pc.get("rec_dir"));
        for (int i = 0; i < 60 && "running".equals(Recorder.state); i++) {
            Thread.sleep(500);
            Recorder.status(new LinkedHashMap<>());
        }
        check("done".equals(Recorder.state), "written: " + Recorder.state);
        System.out.println(fails == 0 ? "RecTest: all passed" : "RecTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
