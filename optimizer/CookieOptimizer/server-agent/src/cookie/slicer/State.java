package cookie.slicer;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Which game classes were changed (shared by Patcher and Hooks). */
final class State {
    private static final Map<String, String> status = new ConcurrentHashMap<>();

    static void patched(String cls) { status.put(cls, "ok"); }
    static void failed(String cls, String why) { status.put(cls, "failed: " + why); }

    static boolean ok(String cls) { return "ok".equals(status.get(cls)); }

    static String of(String cls) {
        String s = status.get(cls);
        return s == null ? "not loaded yet" : s;
    }

    private State() {}
}
