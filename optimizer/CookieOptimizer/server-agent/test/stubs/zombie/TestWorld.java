package zombie;
import java.util.ArrayList;
import java.util.List;
/** Test-only fake world: records what the "game" sees. */
public final class TestWorld {
    /** the game's cache dir (Zomboid); its Lua folder holds the in-game mode + status files */
    public static String cacheDir;
    public static final List<String> log = new ArrayList<>();
    public static long costNs = 0;
    public static String throwOn = null;
    public static String revision = "3d39148846";
    public static void busy(long ns) { long end = System.nanoTime() + ns; while (System.nanoTime() < end) { } }
    private TestWorld() {}
}
