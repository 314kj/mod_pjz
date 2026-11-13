package cookie.slicer.helper;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;

/**
 * Points three places in the game at SmoothHooks when the game loads the class (helper 1.4.0):
 *  - zombie/iso/IsoChunkMap.updateInternal: IsoChunk.loadGridSquare.size() x1 and .poll() x1
 *    (the map pieces that arrived and are finished on the game's thread, a few per frame)
 *  - zombie/iso/IsoWorld.sceneCullZombies: "sipush 510; if_icmpge" x1 (how many zombies on screen
 *    get a full 3D model; the rest are drawn as a flat picture by the game's own code)
 * Every place must be found exactly the expected number of times, else that class keeps the
 * game's own code (and the pc file says which). Nothing else in the class changes. With the
 * window's settings at the game's values, the hooks give exactly the game's own answers.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class SmoothPatcher implements ClassFileTransformer {
    static final String HOOK = "cookie/slicer/helper/SmoothHooks";
    static final String CHUNKMAP = "zombie/iso/IsoChunkMap";
    static final String WORLD = "zombie/iso/IsoWorld";
    static final String QUEUE = "zombie/util/CappedConcurrentQueue";
    static final String[] TARGETS = {CHUNKMAP, WORLD};
    static final int IF_ICMPGE = 0xa2;

    static volatile int patched;
    static volatile String failed = "";

    static List<ClassPatch.Redirect> plan(String cls) {
        List<ClassPatch.Redirect> rs = new ArrayList<>();
        switch (cls) {
            case CHUNKMAP:
                rs.add(new ClassPatch.Redirect("updateInternal", "()V", ClassPatch.INVOKEVIRTUAL,
                    QUEUE, "size", "()I", null, 1, "chunkQueueSize", "(L" + QUEUE + ";)I"));
                rs.add(new ClassPatch.Redirect("updateInternal", "()V", ClassPatch.INVOKEVIRTUAL,
                    QUEUE, "poll", "()Ljava/lang/Object;", null, 1, "chunkQueuePoll", "(L" + QUEUE + ";)Ljava/lang/Object;"));
                break;
            case WORLD:
                rs.add(ClassPatch.Redirect.constant("sceneCullZombies", "()V", SmoothHooks.GAME_3D, IF_ICMPGE, 1, "zombies3d"));
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
            synchronized (SmoothPatcher.class) {
                patched++;
            }
            System.out.println("[CookieSlicerHelper] smooth: " + shortName + " on");
            return out;
        } catch (Throwable t) {
            synchronized (SmoothPatcher.class) {
                failed = failed.isEmpty() ? shortName : failed + "," + shortName;
            }
            System.out.println("[CookieSlicerHelper] smooth: " + shortName + " keeps the game's own code: " + t.getMessage());
            return null;
        }
    }
}
