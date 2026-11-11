package zombie.network;
import java.util.HashMap;
import java.util.Map;
import zombie.TestWorld;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
public class ServerMap {
    public static ServerMap instance = new ServerMap();
    public final Map<Long, IsoChunk> chunks = new HashMap<>();
    public final Map<String, IsoGridSquare> squares = new HashMap<>();
    public Runnable onPre, onPost;
    static long k(int a, int b) { return ((long) a << 32) ^ (b & 0xffffffffL); }
    public void preupdate() { if (onPre != null) { Runnable r = onPre; onPre = null; r.run(); } }
    public void postupdate() { if (onPost != null) { Runnable r = onPost; onPost = null; r.run(); } }
    public void QueuedSaveAll(boolean quit) { TestWorld.log.add("SAVE"); }
    public IsoGridSquare getGridSquare(int x, int y, int z) { return squares.get(x + "," + y + "," + z); }
    public IsoChunk getChunk(int wx, int wy) { return chunks.get(k(wx, wy)); }

    /** Like ServerCell.Load2 -> RecalcAll2 with the patched doLoadGridsquare call. */
    public ServerCell loadCell(int cx, int cy, int squaresPerChunk) {
        ServerCell cell = new ServerCell();
        for (int i = 0; i < 8; i++) for (int j = 0; j < 8; j++) {
            IsoChunk c = new IsoChunk(cx * 8 + i, cy * 8 + j);
            for (int n = 0; n < squaresPerChunk; n++) {
                IsoGridSquare s = new IsoGridSquare(c.wx * 8 + n % 8, c.wy * 8 + (n / 8) % 8, n / 64);
                c.squares.add(s);
                squares.put(s.key(), s);
            }
            cell.chunks[i][j] = c;
            chunks.put(k(c.wx, c.wy), c);
        }
        for (int i = 0; i < 8; i++) for (int j = 0; j < 8; j++) cookie.slicer.Hooks.doLoadGridsquare(cell.chunks[i][j]);
        return cell;
    }

    public static final class ServerCell {
        public final IsoChunk[][] chunks = new IsoChunk[8][8];
        public void Unload() {
            TestWorld.log.add("UNLOAD " + chunks[0][0].wx / 8 + "," + chunks[0][0].wy / 8);
            for (IsoChunk[] row : chunks) for (IsoChunk c : row) {
                instance.chunks.remove(k(c.wx, c.wy));
                for (IsoGridSquare s : c.squares) instance.squares.remove(s.key());
            }
        }
    }
}
