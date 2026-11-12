package cookie.slicer;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Which game calls are pointed at Hooks. Each class is changed completely or not at all:
 * if one expected call is missing (a game update changed the method), that class keeps
 * the game's own code and the log says so.
 */
final class Patcher implements ClassFileTransformer {
    static final String HOOKS = "cookie/slicer/Hooks";

    static final String CHUNK = "zombie/iso/IsoChunk";
    static final String CELL = "zombie/network/ServerMap$ServerCell";
    static final String MAP = "zombie/network/ServerMap";
    static final String SERVER = "zombie/network/GameServer";
    static final String DOWNLOAD = "zombie/network/PlayerDownloadServer";
    static final String BUCKET = "zombie/entity/EntityBucket";
    static final String ENTITIES = "zombie/entity/EngineEntityManager";
    static final String ARRAY = "zombie/entity/util/Array";
    static final String LUA_EVENT = "zombie/Lua/Event";
    static final String KAHLUA = "se/krka/kahlua/vm/KahluaThread";
    static final String EXCEPTIONS = "zombie/core/logger/ExceptionLogger";

    private static final String EVENT = "(Ljava/lang/String;Ljava/lang/Object;)V";

    private final Map<String, List<ClassPatch.Redirect>> plan = new HashMap<>();

    Patcher() {
        // The square and chunk events a chunk fires while it is added to the world.
        add(CHUNK, new ClassPatch.Redirect("doLoadGridsquare", "()V", ClassPatch.INVOKESTATIC,
            "zombie/Lua/LuaEventManager", "triggerEvent", EVENT, "LoadGridsquare", 1, "event", EVENT));
        add(CHUNK, new ClassPatch.Redirect("doLoadGridsquare", "()V", ClassPatch.INVOKESTATIC,
            "zombie/Lua/LuaEventManager", "triggerEvent", EVENT, "LoadChunk", 1, "event", EVENT));
        add(CHUNK, new ClassPatch.Redirect("doLoadGridsquare", "()V", ClassPatch.INVOKESTATIC,
            "zombie/globalObjects/SGlobalObjects", "chunkLoaded", "(II)V", null, 1, "globalObjectsChunkLoaded", "(II)V"));
        // A server cell adds its chunks to the world.
        add(CELL, new ClassPatch.Redirect("RecalcAll2", "()V", ClassPatch.INVOKEVIRTUAL,
            CHUNK, "doLoadGridsquare", "()V", null, 1, "doLoadGridsquare", "(L" + CHUNK + ";)V"));
        // A cell that failed to load is dropped; a cell nobody is near is unloaded; the world is saved.
        add(MAP, new ClassPatch.Redirect("preupdate", "()V", ClassPatch.INVOKEVIRTUAL,
            CELL, "Unload", "()V", null, 1, "unloadDroppedCell", "(L" + CELL + ";)V"));
        add(MAP, new ClassPatch.Redirect("preupdate", "()V", ClassPatch.INVOKEVIRTUAL,
            MAP, "QueuedSaveAll", "(Z)V", null, 1, "queuedSaveAll", "(L" + MAP + ";Z)V"));
        add(MAP, new ClassPatch.Redirect("postupdate", "()V", ClassPatch.INVOKEVIRTUAL,
            CELL, "Unload", "()V", null, 1, "unloadCell", "(L" + CELL + ";)V"));
        // The server's main loop: start and end of each game tick.
        add(SERVER, new ClassPatch.Redirect("main", "([Ljava/lang/String;)V", ClassPatch.INVOKEVIRTUAL,
            MAP, "preupdate", "()V", null, 1, "preupdate", "(L" + MAP + ";)V"));
        add(SERVER, new ClassPatch.Redirect("main", "([Ljava/lang/String;)V", ClassPatch.INVOKEVIRTUAL,
            MAP, "postupdate", "()V", null, 1, "postupdate", "(L" + MAP + ";)V"));
        // A loaded chunk is written out for a player who asked for it.
        add(DOWNLOAD, new ClassPatch.Redirect("update", "()V", ClassPatch.INVOKEVIRTUAL,
            CHUNK, "SaveLoadedChunk", "(Lzombie/network/ClientChunkRequest$Chunk;Ljava/util/zip/CRC32;)V", null, 1,
            "saveLoadedChunk", "(L" + CHUNK + ";Lzombie/network/ClientChunkRequest$Chunk;Ljava/util/zip/CRC32;)V"));
        // v5: the game's entity lists (one per bucket + the entity manager's own): add / remove (see EntityIndex).
        String entity = "(Lzombie/entity/GameEntity;)V";
        add(BUCKET, new ClassPatch.Redirect("updateMembership", entity, ClassPatch.INVOKEVIRTUAL,
            ARRAY, "add", "(Ljava/lang/Object;)V", null, 1, "entityListAdd", "(L" + ARRAY + ";Ljava/lang/Object;)V"));
        add(BUCKET, new ClassPatch.Redirect("updateMembership", entity, ClassPatch.INVOKEVIRTUAL,
            ARRAY, "removeValue", "(Ljava/lang/Object;Z)Z", null, 1, "entityListRemove", "(L" + ARRAY + ";Ljava/lang/Object;Z)Z"));
        add(ENTITIES, new ClassPatch.Redirect("addEntityInternal", entity, ClassPatch.INVOKEVIRTUAL,
            ARRAY, "add", "(Ljava/lang/Object;)V", null, 1, "entityListAdd", "(L" + ARRAY + ";Ljava/lang/Object;)V"));
        add(ENTITIES, new ClassPatch.Redirect("removeEntityInternal", entity, ClassPatch.INVOKEVIRTUAL,
            ARRAY, "removeValue", "(Ljava/lang/Object;Z)Z", null, 1, "entityListRemove", "(L" + ARRAY + ";Ljava/lang/Object;Z)Z"));
        // v6: Lua event handler loop (see FastEvents) and the same error printed again and again (see LogThrottle).
        String trigger = "(Lse/krka/kahlua/vm/KahluaTable;Lse/krka/kahlua/integration/LuaCaller;[Ljava/lang/Object;)Z";
        add(LUA_EVENT, new ClassPatch.Redirect("trigger", trigger, ClassPatch.INVOKEVIRTUAL,
            "java/util/ArrayList", "get", "(I)Ljava/lang/Object;", null, 2, "eventGet", "(Ljava/util/ArrayList;I)Ljava/lang/Object;"));
        add(LUA_EVENT, new ClassPatch.Redirect("trigger", trigger, ClassPatch.INVOKEVIRTUAL,
            "java/util/ArrayList", "contains", "(Ljava/lang/Object;)Z", null, 2, "eventListed", "(Ljava/util/ArrayList;Ljava/lang/Object;)Z"));
        add(KAHLUA, new ClassPatch.Redirect("flushErrorMessage", "()V", ClassPatch.INVOKEVIRTUAL,
            "zombie/debug/DebugType", "error", "(Ljava/lang/Object;)V", null, 1, "luaErrorText", "(Lzombie/debug/DebugType;Ljava/lang/Object;)V"));
        add(EXCEPTIONS, new ClassPatch.Redirect("logException",
            "(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Lzombie/debug/DebugType;Lzombie/debug/LogSeverity;)V", ClassPatch.INVOKEVIRTUAL,
            "zombie/debug/DebugLogStream", "printException", "(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Lzombie/debug/LogSeverity;)V", null, 1,
            "printException", "(Lzombie/debug/DebugLogStream;Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Lzombie/debug/LogSeverity;)V"));
    }

    private void add(String cls, ClassPatch.Redirect r) {
        plan.computeIfAbsent(cls, k -> new ArrayList<>()).add(r);
    }

    List<String> classes() { return new ArrayList<>(plan.keySet()); }

    /** Patches one class's bytes outside the JVM (used by the self-test). */
    byte[] patch(String className, byte[] bytes) {
        List<ClassPatch.Redirect> rs = plan.get(className);
        if (rs == null) return null;
        List<ClassPatch.Redirect> fresh = new ArrayList<>();
        for (ClassPatch.Redirect r : rs) {
            fresh.add(new ClassPatch.Redirect(r.inMethod, r.inDesc, r.opcode, r.owner, r.name, r.desc,
                r.ldc, r.expected, r.newName, r.newDesc));
        }
        return new ClassPatch(bytes).apply(fresh, HOOKS);
    }

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> redefined,
                            ProtectionDomain pd, byte[] bytes) {
        if (className == null || redefined != null || !plan.containsKey(className)) return null;
        try {
            byte[] out = patch(className, bytes);
            State.patched(className);
            Log.line("patched " + className.substring(className.lastIndexOf('/') + 1)
                + " (" + plan.get(className).size() + " calls)");
            return out;
        } catch (Throwable t) {
            State.failed(className, String.valueOf(t.getMessage()));
            Log.line("NOT patched " + className.substring(className.lastIndexOf('/') + 1)
                + ", it keeps the game's own code: " + t.getMessage());
            return null;
        }
    }

    static String describe() {
        return Arrays.toString(new String[] { CHUNK, CELL, MAP, SERVER, DOWNLOAD, BUCKET, ENTITIES, LUA_EVENT, KAHLUA, EXCEPTIONS });
    }
}
