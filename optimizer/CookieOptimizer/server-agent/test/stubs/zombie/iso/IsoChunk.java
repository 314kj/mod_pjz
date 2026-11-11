package zombie.iso;
import java.util.ArrayList;
import java.util.List;
import zombie.TestWorld;
/** Does what the patched IsoChunk.doLoadGridsquare does with the three swapped calls. */
public class IsoChunk {
    public int wx, wy;
    public final List<IsoGridSquare> squares = new ArrayList<>();
    public IsoChunk(int wx, int wy) { this.wx = wx; this.wy = wy; }
    public void doLoadGridsquare() {
        for (IsoGridSquare s : squares) cookie.slicer.Hooks.event("LoadGridsquare", s);
        cookie.slicer.Hooks.globalObjectsChunkLoaded(wx, wy);
        TestWorld.log.add("JAVA " + wx + "," + wy);
        cookie.slicer.Hooks.event("LoadChunk", this);
    }
    public void SaveLoadedChunk(zombie.network.ClientChunkRequest.Chunk c, java.util.zip.CRC32 crc) throws java.io.IOException {
        TestWorld.log.add("SEND " + wx + "," + wy);
    }
}
