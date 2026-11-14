import java.io.File;
import java.lang.reflect.Field;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.file.Files;

/**
 * Helper 1.5.0 room fix against the game's real classes (the game's Java 25 + an unsigned copy of
 * projectzomboid.jar), IsoLightSwitch patched the way RoomPatcher does at game start, driven by
 * zombie.iso.RoomDrive (a real IsoChunk, IsoGridSquare, IsoRoom and IsoMetaGrid):
 *  R1 the patched IsoLightSwitch loads and passes Java's bytecode check
 *  R2 the game's own code, square still pointing at a cleared room (def null): chunkLoaded throws
 *     (the crash players get, here outside the game)
 *  R3 patched, same square, the map has the room there now: no throw, the square points at the map's
 *     room (room and id), the room has the square, the chunk gets that room's light
 *  R3b patched, same square, the map's room has no live room yet: the game makes it (as after a
 *     rebuild in game), no throw, the square points at it, it has its building and its light switch,
 *     the chunk gets the room light the game makes for it
 *  R4 patched, cleared room and the map has no room there any more: no throw, no room (id -1)
 *  R5 patched, a square in a live room and a square outside: exactly the game's own results, nothing
 *     counted as repaired
 * Usage: java -cp <this dir> RealRoomTest <unsigned pz jar> <helper classes> <driver classes> <patched dir>
 */
public final class RealRoomTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    /** loads the game's classes from the jar, except the ones in the patched folder */
    static final class Patched extends URLClassLoader {
        final File dir;
        Patched(URL[] urls, File dir) { super(urls, ClassLoader.getPlatformClassLoader()); this.dir = dir; }
        @Override protected Class<?> findClass(String name) throws ClassNotFoundException {
            File f = dir == null ? null : new File(dir, name.replace('.', '/') + ".class");
            if (f != null && f.isFile()) {
                try {
                    byte[] b = Files.readAllBytes(f.toPath());
                    return defineClass(name, b, 0, b.length);
                } catch (java.io.IOException e) {
                    throw new ClassNotFoundException(name, e);
                }
            }
            return super.findClass(name);
        }
    }

    static String run(ClassLoader cl, String scenario) throws Exception {
        return (String) Class.forName("zombie.iso.RoomDrive", true, cl).getMethod("run", String.class).invoke(null, scenario);
    }

    static long count(ClassLoader cl, String name) throws Exception {
        Field f = Class.forName("cookie.slicer.helper.RoomHooks", true, cl).getDeclaredField(name);
        f.setAccessible(true);
        return f.getLong(null);
    }

    static String counts(ClassLoader cl) throws Exception {
        return count(cl, "fixed") + "/" + count(cl, "gone") + "/" + count(cl, "failed");
    }

    public static void main(String[] a) throws Exception {
        File dir = new File(a[3]);
        URL[] urls = {new File(a[0]).toURI().toURL(), new File(a[1]).toURI().toURL(), new File(a[2]).toURI().toURL()};
        ClassLoader game = new Patched(urls, null);
        ClassLoader pl = new Patched(urls, dir);

        String c = "zombie.iso.objects.IsoLightSwitch";
        boolean ok;
        String how;
        try {
            Class.forName(c, true, pl);
            ok = true;
            how = "loaded";
        } catch (VerifyError | ClassFormatError e) {
            ok = false;
            how = e.toString();
        } catch (ExceptionInInitializerError | NoClassDefFoundError | UnsatisfiedLinkError e) {
            ok = !(e.getCause() instanceof VerifyError) && !String.valueOf(e).contains("VerifyError");
            how = "verified (start-up outside the game: " + e.getClass().getSimpleName() + ")";
        }
        check(ok, "R1 " + c + ": " + how);
        check(new File(dir, c.replace('.', '/') + ".class").isFile()
            && Class.forName(c, false, pl).getClassLoader() == pl, "R1 " + c + ": the patched copy was the one loaded");

        String g1 = run(game, "cleared"), g2 = run(game, "gone");
        System.out.println("       game cleared: " + g1);
        System.out.println("       game gone:    " + g2);
        check(g1.startsWith("threw java.lang.NullPointerException") && g2.startsWith("threw java.lang.NullPointerException"),
            "R2 the game's own code: square on a cleared room -> chunkLoaded throws (the crash)");

        String p1 = run(pl, "cleared");
        System.out.println("       patched cleared: " + p1 + "  fixed/gone/failed " + counts(pl));
        check("was=cleared room=live roomId=live roomHasSquare=true chunkLights=1(live)".equals(p1) && "1/0/0".equals(counts(pl)),
            "R3 patched: no throw, square on the map's room (room + id), room has the square, chunk has its light");

        String g3 = run(game, "made"), p3 = run(pl, "made");
        System.out.println("       game made:       " + g3);
        System.out.println("       patched made:    " + p3 + "  fixed/gone/failed " + counts(pl));
        check(g3.startsWith("threw java.lang.NullPointerException")
            && "was=cleared room=made(switch=true,building=true) roomId=live roomHasSquare=true chunkLights=1".equals(p3)
            && "2/0/0".equals(counts(pl)),
            "R3b patched, room made by the game now: no throw, square on the new room (with building + switch), the chunk gets the light the game made for it");

        String p2 = run(pl, "gone");
        System.out.println("       patched gone:    " + p2 + "  fixed/gone/failed " + counts(pl));
        check("was=cleared room=none roomId=-1 roomHasSquare=false chunkLights=0".equals(p2) && "2/1/0".equals(counts(pl)),
            "R4 patched: room gone from the map -> no throw, no room (id -1), no lights");

        String gl = run(game, "live"), pLive = run(pl, "live"), gn = run(game, "none"), pn = run(pl, "none");
        System.out.println("       live: game " + gl + " | patched " + pLive);
        System.out.println("       none: game " + gn + " | patched " + pn);
        check(gl.equals(pLive) && gn.equals(pn) && !gl.startsWith("threw") && gl.contains("chunkLights=1(live)")
            && "2/1/0".equals(counts(pl)), "R5 patched: live room and no room give the game's own results, nothing repaired");

        System.out.println(fails == 0 ? "RealRoomTest: all ok" : "RealRoomTest: " + fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
