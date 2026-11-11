package zombie.iso;
public class IsoGridSquare {
    public int x, y, z;
    public IsoGridSquare(int x, int y, int z) { this.x = x; this.y = y; this.z = z; }
    public String key() { return x + "," + y + "," + z; }
}
