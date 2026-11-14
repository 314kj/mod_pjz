package cookie.slicer.helper;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;

/**
 * Points one place in the game at RoomHooks when the game loads the class (helper 1.5.0):
 *  - zombie/iso/objects/IsoLightSwitch.chunkLoaded: IsoGridSquare.getRoom() x1
 *    (the room of each square of a map piece that was just finished, asked for its light switches)
 * The place must be found exactly once, else the class keeps the game's own code (and the pc file
 * says so). Nothing else in the class changes. For every square whose room is a live one the hook
 * gives exactly the game's own answer.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class RoomPatcher implements ClassFileTransformer {
    static final String HOOK = "cookie/slicer/helper/RoomHooks";
    static final String LIGHTSWITCH = "zombie/iso/objects/IsoLightSwitch";
    static final String SQUARE = "zombie/iso/IsoGridSquare";
    static final String ROOM = "zombie/iso/areas/IsoRoom";
    static final String[] TARGETS = {LIGHTSWITCH};

    static volatile int patched;
    static volatile String failed = "";

    static List<ClassPatch.Redirect> plan(String cls) {
        List<ClassPatch.Redirect> rs = new ArrayList<>();
        if (LIGHTSWITCH.equals(cls)) {
            rs.add(new ClassPatch.Redirect("chunkLoaded", "(Lzombie/iso/IsoChunk;)V", ClassPatch.INVOKEVIRTUAL,
                SQUARE, "getRoom", "()L" + ROOM + ";", null, 1, "lightsRoom", "(L" + SQUARE + ";)L" + ROOM + ";"));
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
            synchronized (RoomPatcher.class) {
                patched++;
            }
            System.out.println("[CookieSlicerHelper] room fix: " + shortName + " on");
            return out;
        } catch (Throwable t) {
            synchronized (RoomPatcher.class) {
                failed = failed.isEmpty() ? shortName : failed + "," + shortName;
            }
            System.out.println("[CookieSlicerHelper] room fix: " + shortName + " keeps the game's own code: " + t.getMessage());
            return null;
        }
    }
}
