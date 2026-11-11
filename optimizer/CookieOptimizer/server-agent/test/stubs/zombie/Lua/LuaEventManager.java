package zombie.Lua;
import zombie.TestWorld;
import zombie.iso.IsoChunk;
import zombie.iso.IsoGridSquare;
public class LuaEventManager {
    public static void triggerEvent(String event, Object param) {
        if (param instanceof IsoGridSquare) {
            IsoGridSquare s = (IsoGridSquare) param;
            if (!"LoadGridsquare".equals(event)) { TestWorld.log.add("NOW " + s.key()); return; }
            TestWorld.log.add("LGS " + s.key());
            TestWorld.busy(TestWorld.costNs);
            if (s.key().equals(TestWorld.throwOn)) throw new RuntimeException("boom " + s.key());
        } else if (param instanceof IsoChunk) {
            String p = "LoadChunk".equals(event) ? "LC " : "NOWC ";
            TestWorld.log.add(p + ((IsoChunk) param).wx + "," + ((IsoChunk) param).wy);
        } else {
            TestWorld.log.add("EV " + event);
        }
    }
}
