package cookie.slicer;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.lang.instrument.Instrumentation;
import java.util.jar.JarFile;
import java.util.zip.ZipEntry;

/**
 * Cookie Slicer - a small Java agent for the dedicated server only.
 *
 * When the server adds a map cell to the world it fires the Lua event LoadGridsquare for
 * every square of the cell in the same tick. With mods listening, one cell is hundreds of
 * milliseconds and several cells are seconds, and the server sends nothing meanwhile
 * (black map, late zombies and cars). This agent lets those events wait and runs them
 * over the next ticks inside a time budget, nearest to players first. See Hooks.
 * v5 also removes entities from the game's entity lists without searching each list from
 * the start (cell unload while driving). See EntityIndex.
 *
 * Start: add  -javaagent:cookie\CookieSlicer.jar  to the server's java command line.
 * Check a game jar without starting anything:
 *   java -jar CookieSlicer.jar check path\to\projectzomboid.jar
 */
public final class Agent {
    static final String VERSION = "5";

    public static void premain(String args, Instrumentation inst) {
        try {
            File dir = jarDir();
            Log.init(dir);
            String cmd = System.getProperty("sun.java.command", "");
            boolean test = "test".equals(args);
            if (!cmd.startsWith("zombie.network.GameServer") && !test) {
                Log.line("this is not the dedicated server (" + firstWord(cmd) + "); doing nothing");
                return;
            }
            Config.load(dir);
            if (!Config.enabled) {
                Log.line("v" + VERSION + " off (enabled=false in CookieSlicer.properties); the server runs the game's own way");
                return;
            }
            inst.addTransformer(new Patcher(), false);
            Log.line("v" + VERSION + " loaded; " + Config.summary());
        } catch (Throwable t) {
            System.out.println("[CookieSlicer] could not start, the server runs the game's own way: " + t);
        }
    }

    /** java -jar CookieSlicer.jar check <projectzomboid.jar> [dumpDir] */
    public static void main(String[] a) throws Exception {
        if (a.length < 2 || !"check".equals(a[0])) {
            System.out.println("usage: java -jar CookieSlicer.jar check <projectzomboid.jar> [folder to write patched classes]");
            return;
        }
        Patcher p = new Patcher();
        File dump = a.length > 2 ? new File(a[2]) : null;
        int bad = 0;
        try (JarFile jar = new JarFile(a[1])) {
            for (String cls : p.classes()) {
                ZipEntry e = jar.getEntry(cls + ".class");
                if (e == null) { System.out.println("MISSING  " + cls); bad++; continue; }
                byte[] in;
                try (InputStream s = jar.getInputStream(e)) { in = s.readAllBytes(); }
                try {
                    byte[] out = p.patch(cls, in);
                    System.out.println("ok       " + cls + " (" + in.length + " -> " + out.length + " bytes)");
                    if (dump != null) {
                        File f = new File(dump, cls + ".class");
                        f.getParentFile().mkdirs();
                        try (FileOutputStream o = new FileOutputStream(f)) { o.write(out); }
                    }
                } catch (Throwable t) {
                    System.out.println("CHANGED  " + cls + ": " + t.getMessage());
                    bad++;
                }
            }
        }
        System.out.println(bad == 0
            ? "All calls found. (The game revision is checked again when the server starts.)"
            : bad + " class(es) would keep the game's own code. Do not use this version of the agent with this game version.");
    }

    private static File jarDir() {
        try {
            File f = new File(Agent.class.getProtectionDomain().getCodeSource().getLocation().toURI());
            return f.isFile() ? f.getParentFile() : f;
        } catch (Exception e) {
            return null;
        }
    }

    private static String firstWord(String s) {
        int i = s.indexOf(' ');
        return i < 0 ? s : s.substring(0, i);
    }

    private Agent() {}
}
