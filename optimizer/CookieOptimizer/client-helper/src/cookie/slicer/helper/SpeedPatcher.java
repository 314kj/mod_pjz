package cookie.slicer.helper;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;

/**
 * Points a few of the game's calls at SpeedHooks when the game loads the class (helper 1.3.0),
 * the same call sites as the server's Cookie Slicer v5/v6:
 *  - zombie/Lua/Event.trigger: callbacks.get(i) x2, callbacks.contains(handler) x2
 *  - KahluaThread.flushErrorMessage: the Lua error text (x1)
 *  - ExceptionLogger.logException: the Java error print (x1)
 *  - EntityBucket.updateMembership: list add / remove; EngineEntityManager add / remove
 * Every call must be found exactly the expected number of times, else that class keeps the
 * game's own code (and the pc file says which). Nothing else in the class changes.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class SpeedPatcher implements ClassFileTransformer {
    static final String HOOK = "cookie/slicer/helper/SpeedHooks";
    static final String EVENT = "zombie/Lua/Event";
    static final String KAHLUA = "se/krka/kahlua/vm/KahluaThread";
    static final String EXCEPTIONS = "zombie/core/logger/ExceptionLogger";
    static final String BUCKET = "zombie/entity/EntityBucket";
    static final String ENTITIES = "zombie/entity/EngineEntityManager";
    static final String ARRAY = "zombie/entity/util/Array";
    static final String[] TARGETS = {EVENT, KAHLUA, EXCEPTIONS, BUCKET, ENTITIES};

    static volatile int patched;
    static volatile String failed = "";

    static List<ClassPatch.Redirect> plan(String cls) {
        List<ClassPatch.Redirect> rs = new ArrayList<>();
        String entity = "(Lzombie/entity/GameEntity;)V";
        switch (cls) {
            case EVENT: {
                String trigger = "(Lse/krka/kahlua/vm/KahluaTable;Lse/krka/kahlua/integration/LuaCaller;[Ljava/lang/Object;)Z";
                rs.add(new ClassPatch.Redirect("trigger", trigger, ClassPatch.INVOKEVIRTUAL,
                    "java/util/ArrayList", "get", "(I)Ljava/lang/Object;", null, 2, "eventGet", "(Ljava/util/ArrayList;I)Ljava/lang/Object;"));
                rs.add(new ClassPatch.Redirect("trigger", trigger, ClassPatch.INVOKEVIRTUAL,
                    "java/util/ArrayList", "contains", "(Ljava/lang/Object;)Z", null, 2, "eventListed", "(Ljava/util/ArrayList;Ljava/lang/Object;)Z"));
                break;
            }
            case KAHLUA:
                rs.add(new ClassPatch.Redirect("flushErrorMessage", "()V", ClassPatch.INVOKEVIRTUAL,
                    "zombie/debug/DebugType", "error", "(Ljava/lang/Object;)V", null, 1, "luaErrorText", "(Lzombie/debug/DebugType;Ljava/lang/Object;)V"));
                break;
            case EXCEPTIONS:
                rs.add(new ClassPatch.Redirect("logException",
                    "(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Lzombie/debug/DebugType;Lzombie/debug/LogSeverity;)V", ClassPatch.INVOKEVIRTUAL,
                    "zombie/debug/DebugLogStream", "printException", "(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Lzombie/debug/LogSeverity;)V", null, 1,
                    "printException", "(Lzombie/debug/DebugLogStream;Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;Lzombie/debug/LogSeverity;)V"));
                break;
            case BUCKET:
                rs.add(new ClassPatch.Redirect("updateMembership", entity, ClassPatch.INVOKEVIRTUAL,
                    ARRAY, "add", "(Ljava/lang/Object;)V", null, 1, "entityListAdd", "(L" + ARRAY + ";Ljava/lang/Object;)V"));
                rs.add(new ClassPatch.Redirect("updateMembership", entity, ClassPatch.INVOKEVIRTUAL,
                    ARRAY, "removeValue", "(Ljava/lang/Object;Z)Z", null, 1, "entityListRemove", "(L" + ARRAY + ";Ljava/lang/Object;Z)Z"));
                break;
            case ENTITIES:
                rs.add(new ClassPatch.Redirect("addEntityInternal", entity, ClassPatch.INVOKEVIRTUAL,
                    ARRAY, "add", "(Ljava/lang/Object;)V", null, 1, "entityListAdd", "(L" + ARRAY + ";Ljava/lang/Object;)V"));
                rs.add(new ClassPatch.Redirect("removeEntityInternal", entity, ClassPatch.INVOKEVIRTUAL,
                    ARRAY, "removeValue", "(Ljava/lang/Object;Z)Z", null, 1, "entityListRemove", "(L" + ARRAY + ";Ljava/lang/Object;Z)Z"));
                break;
            default:
                break;
        }
        return rs;
    }

    static byte[] patch(String cls, byte[] bytes) {
        return new ClassPatch(bytes).apply(plan(cls), HOOK);
    }

    static boolean target(String cls) {
        for (String t : TARGETS) if (t.equals(cls)) return true;
        return false;
    }

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> redefined,
                            ProtectionDomain pd, byte[] bytes) {
        if (className == null || redefined != null || !target(className)) return null;
        String shortName = className.substring(className.lastIndexOf('/') + 1);
        try {
            byte[] out = patch(className, bytes);
            synchronized (SpeedPatcher.class) {
                patched++;
            }
            System.out.println("[CookieSlicerHelper] speed-ups: " + shortName + " on");
            return out;
        } catch (Throwable t) {
            synchronized (SpeedPatcher.class) {
                failed = failed.isEmpty() ? shortName : failed + "," + shortName;
            }
            System.out.println("[CookieSlicerHelper] speed-ups: " + shortName + " keeps the game's own code: " + t.getMessage());
            return null;
        }
    }
}
