package zombie.network;
public class ServerMap {
    public static ServerMap instance;
    public void preupdate() { throw new UnsupportedOperationException("stub"); }
    public void postupdate() { throw new UnsupportedOperationException("stub"); }
    public void QueuedSaveAll(boolean quit) { throw new UnsupportedOperationException("stub"); }
    public zombie.iso.IsoGridSquare getGridSquare(int x, int y, int z) { throw new UnsupportedOperationException("stub"); }
    public zombie.iso.IsoChunk getChunk(int wx, int wy) { throw new UnsupportedOperationException("stub"); }
    public static final class ServerCell {
        public final zombie.iso.IsoChunk[][] chunks = new zombie.iso.IsoChunk[8][8];
        public void Unload() { throw new UnsupportedOperationException("stub"); }
    }
}
