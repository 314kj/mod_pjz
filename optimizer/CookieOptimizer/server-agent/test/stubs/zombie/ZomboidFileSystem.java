package zombie;
public class ZomboidFileSystem {
    public static final ZomboidFileSystem instance = new ZomboidFileSystem();
    public String getCacheDir() { return TestWorld.cacheDir; }
}
