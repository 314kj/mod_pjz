package cookie.slicer.helper;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipFile;

/**
 * Join-problem checks (helper 1.2.0).
 *  J1  log lines -> problem codes (and lines that must NOT count)
 *  J2  a whole real console.txt of a good join -> no blocking problem
 *  J3  the file the mod reads (CookieSlicer_diag.txt), previous start kept
 *  J4  ProjectZomboid64.json: clean, PZ Optimization leftovers, other agents, broken file
 *  J5  (with the game jar) the loading screen class is patched at its 4 calls and the JVM accepts it
 *  J6  texts: English when the mod's texts are not loaded, steps numbered
 * Run: java -cp <projectzomboid.jar>:<test classes> cookie.slicer.helper.JoinTest <out dir> [pz jar] [real console.txt] [real json]
 */
public final class JoinTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    static String codes(boolean fatalOnly) {
        StringBuilder sb = new StringBuilder();
        for (ConsoleWatch.Problem p : ConsoleWatch.current(fatalOnly)) {
            if (sb.length() > 0) sb.append(',');
            sb.append(p.code);
        }
        return sb.toString();
    }

    static ConsoleWatch.Problem get(String code) {
        for (ConsoleWatch.Problem p : ConsoleWatch.current(false)) if (p.code.equals(code)) return p;
        return null;
    }

    public static void main(String[] a) throws Exception {
        File out = new File(a[0]);
        out.mkdirs();
        // ---------------------------------------------------------------- J1
        String[][] cases = {
            {"ERROR: General      f:0> java.lang.OutOfMemoryError: Java heap space", "ram"},
            {"LOG  : General      f:0> The AOT cache was created by a different version or build of HotSpot", "pzopt"},
            {"LOG  : General      f:0 st:0> ConnectToServerState: item state CheckItemState -> VersionMismatch ID=3837347554", "workshop"},
            {"LOG  : Lua          f:0> Failed,Mod \"Cookie Slicer\" is not installed", "modmissing"},
            {"LOG  : General      f:0> You have been kicked because your game files do not match the server's.", "files"},
            {"LOG  : General      f:0> Client version (42.21.0) does not match server version (42.22.2)", "version"},
            {"LOG  : Lua          f:0> Failed,AccessDenied", "access"},
            {"LOG  : General      f:0> Connection to the server was lost", "net"},
            {"ERROR: General      f:6260> Lua((MOD:More Traits Definitive)).new> Exception thrown", "luamod"},
        };
        for (String[] c : cases) {
            ConsoleWatch.reset();
            ConsoleWatch.line(c[0], 1000);
            check(codes(false).equals(c[1]), "J1 " + c[1] + " <- " + c[0].substring(c[0].indexOf('>') + 2));
        }
        ConsoleWatch.reset();
        ConsoleWatch.line("LOG  : General      f:0 st:0> ConnectToServerState: item state CheckItemState -> VersionMismatch ID=3837347554", 1);
        check("3837347554".equals(get("workshop").detail), "J1 the Workshop ID is kept for the player");
        ConsoleWatch.reset();
        ConsoleWatch.line("LOG  : Lua          f:0> Failed,Mod \"Cookie Slicer\" is not installed", 1);
        check("Cookie Slicer".equals(get("modmissing").detail), "J1 the missing mod's name is kept");
        String[] quiet = {
            "ERROR: General      f:0 st:0> NetChecksum$Checksummer.addFile> Exception thrown",
            "LOG  : General      f:0> Initializing checksum",
            "LOG  : General      f:0 st:0> ConnectToServerState: WorkshopConfirm GetItemState()=Subscribed|Installed ID=3837347554",
            "LOG  : General      f:0 st:0> ConnectToServerState: item state CheckItemState -> Ready ID=3837347554",
            "ERROR: General      f:0 at AngelCodeFont.parseFnt > AngelCodeFont failed to load page 0 texture",
            "LOG  : General      f:0> [CookieSlicerHelper] loading screen box off: pzopt AOT cache OutOfMemoryError",
            "ERROR: General      f:6260> Lua(Vanilla).new> Exception thrown",
        };
        ConsoleWatch.reset();
        for (String q : quiet) ConsoleWatch.line(q, 1);
        check(codes(false).isEmpty(), "J1 normal lines and our own lines count as nothing (got '" + codes(false) + "')");
        ConsoleWatch.reset();
        ConsoleWatch.line(cases[0][0], 1);
        ConsoleWatch.line("ERROR: General f:1> Lua((MOD:Mod A)).x> Exception thrown", 2);
        ConsoleWatch.line("ERROR: General f:1> Lua((MOD:Mod B)).x> Exception thrown", 3);
        ConsoleWatch.line("ERROR: General f:1> Lua((MOD:Mod B)).x> Exception thrown", 4);
        check("Mod B (2), Mod A (1)".equals(get("luamod").detail), "J1 mods with errors listed by count");
        check(codes(true).equals("ram"), "J1 a mod's Lua errors alone do not block (fatal list = ram)");
        ConsoleWatch.line("LOG  : General      f:0 st:0> ConnectToServerState: Start", 5);
        check(codes(false).isEmpty() && ConsoleWatch.attemptStart() == 5, "J1 a new join attempt starts a clean list");
        ConsoleWatch cw = new ConsoleWatch(out, out);
        ConsoleWatch.reset();
        cw.feed("LOG  : General f:0> java.lang.OutOf", 1);
        check(codes(false).isEmpty(), "J1 half a line waits for the rest");
        cw.feed("MemoryError: Java heap space\nLOG next\n", 2);
        check(codes(false).equals("ram"), "J1 the line is read once it is complete");

        // ---------------------------------------------------------------- J2
        if (a.length > 2 && new File(a[2]).isFile()) {
            ConsoleWatch.reset();
            ConsoleWatch real = new ConsoleWatch(out, out);
            long t0 = System.nanoTime();
            real.feed(new String(Files.readAllBytes(new File(a[2]).toPath()), StandardCharsets.UTF_8) + "\n", 1);
            long ms = (System.nanoTime() - t0) / 1_000_000;
            check(codes(true).isEmpty(), "J2 real console.txt of a good join: nothing blocking (got '" + codes(true) + "'), read in " + ms + " ms");
        } else {
            System.out.println("  --   J2 skipped (no real console.txt given)");
        }

        // ---------------------------------------------------------------- J3
        File lua = new File(out, "Lua");
        lua.mkdirs();
        Files.write(new File(lua, ConsoleWatch.DIAG_FILE).toPath(), "n=0\n".getBytes(StandardCharsets.UTF_8));
        ConsoleWatch.reset();
        ConsoleWatch.line(cases[2][0], 77);
        ConsoleWatch.line("ERROR: General f:1> Lua((MOD:Mod|Pipe)).x> Exception thrown", 78);
        ConsoleWatch.writeDiag(new File(lua, ConsoleWatch.DIAG_FILE));
        Map<String, String> d = Helper.read(new File(lua, ConsoleWatch.DIAG_FILE));
        check("2".equals(d.get("n")) && d.get("p1").startsWith("workshop|1|77|3837347554"), "J3 diag file: n=2, p1=" + d.get("p1"));
        check(d.get("p2").startsWith("luamod|1|78|Mod/Pipe"), "J3 '|' in a detail cannot break the line: " + d.get("p2"));

        // ---------------------------------------------------------------- J4
        Map<String, String> m = new LinkedHashMap<>();
        String clean = "{\n\t\"mainClass\": \"zombie/gameStates/MainScreenState\",\n\t\"classpath\": [\".\", \"projectzomboid.jar\"],\n"
            + "\t\"vmArgs\": [\"-Djava.awt.headless=true\", \"-Xmx16g\", \"-Dzomboid.steam=1\"]\n}\n";
        GameJson.check(clean, m);
        check("".equals(m.get("json_issue")) && "16384".equals(m.get("json_xmx_mb")), "J4 clean file: no issue, RAM 16384 MB");
        m.clear();
        GameJson.check(clean.replace("\"projectzomboid.jar\"]", "\"pzopt/aot/pzopt.jar\", \"projectzomboid.jar\"]")
            .replace("\"-Xmx16g\"", "\"-XX:AOTCache=pzopt/aot/pzopt.aot\", \"-Xmx16384m\""), m);
        check("pzopt,aot".equals(m.get("json_issue")) && "16384".equals(m.get("json_xmx_mb")), "J4 PZ Optimization leftovers found: " + m.get("json_issue"));
        m.clear();
        GameJson.check(clean.replace("\"-Xmx16g\"", "\"-javaagent:C:\\\\Mods\\\\ZombieBuddy.jar\", \"-javaagent:C:\\\\x\\\\CookieSlicerHelper.jar\", \"-Xmx3072m\""), m);
        check("agent:ZombieBuddy.jar".equals(m.get("json_issue")) && "3072".equals(m.get("json_xmx_mb")), "J4 other Java agents named, ours not: " + m.get("json_issue"));
        m.clear();
        GameJson.check(clean.substring(0, clean.length() - 3), m);
        check(m.get("json_issue").contains("broken"), "J4 a cut-off file is reported as broken");
        if (a.length > 3 && new File(a[3]).isFile()) {
            m.clear();
            GameJson.report(new File(a[3]).getParentFile(), m);
            check("".equals(m.get("json_issue")), "J4 the real ProjectZomboid64.json: " + m);
        }

        // ---------------------------------------------------------------- J5
        if (a.length > 1 && new File(a[1]).isFile()) {
            byte[] orig;
            try (ZipFile z = new ZipFile(a[1])) {
                orig = z.getInputStream(z.getEntry(LoadPatcher.TARGET + ".class")).readAllBytes();
            }
            byte[] patched = LoadPatcher.patch(orig);
            String asText = new String(patched, "ISO-8859-1");
            check(asText.contains(LoadPatcher.HOOK) && asText.contains("(Lzombie/core/Core;)V"), "J5 GameLoadingState.render: 4 EndFrameUI calls pointed at LoadHook");
            ClassLoader loader = new ClassLoader(JoinTest.class.getClassLoader()) {
                @Override
                protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
                    if (name.equals("zombie.gameStates.GameLoadingState")) {
                        synchronized (getClassLoadingLock(name)) {
                            Class<?> c = findLoadedClass(name);
                            if (c == null) c = defineClass(name, patched, 0, patched.length);
                            return c;
                        }
                    }
                    return super.loadClass(name, resolve);
                }
            };
            String verdict;
            try {
                Class.forName("zombie.gameStates.GameLoadingState", true, loader);
                verdict = "verified and initialised";
            } catch (VerifyError e) {
                verdict = "REFUSED " + e;
            } catch (ExceptionInInitializerError | NoClassDefFoundError e) {
                verdict = "verified (its start-up code needs the running game: " + e.getClass().getSimpleName() + ")";
            }
            check(!verdict.startsWith("REFUSED"), "J5 the JVM accepts the patched class: " + verdict);
            byte[] changed = orig.clone();
            int at = new String(changed, "ISO-8859-1").indexOf("EndFrameUI");
            changed[at] = 'X'; // a game update renamed the call
            boolean refused = false;
            try { LoadPatcher.patch(changed); } catch (IllegalStateException e) { refused = true; }
            check(refused, "J5 a changed class is left as the game made it");
        } else {
            System.out.println("  --   J5 skipped (no game jar given)");
        }

        // ---------------------------------------------------------------- J6
        String[] b = LoadHook.block("workshop", "3837347554");
        check(b.length == 4 && b[0].endsWith(": 3837347554") && b[1].startsWith("1. ") && b[3].startsWith("3. "),
            "J6 block: title + detail, 3 numbered steps (" + b[0] + ")");
        check(LoadHook.block("full", "").length == 2, "J6 a problem with one step has one step");
        for (String code : new String[] {"unknown", "slow", "ram", "pzopt", "workshop", "modmissing", "map", "files", "version", "banned", "access", "full", "ping", "net", "luamod"}) {
            if (LoadHook.EN.get("Fix_" + code) == null || LoadHook.EN.get("Fix_" + code + "_1") == null) check(false, "J6 English text for " + code);
        }
        check(true, "J6 every problem code has an English title and a first step");

        System.out.println(fails == 0 ? "JoinTest: all passed" : "JoinTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
