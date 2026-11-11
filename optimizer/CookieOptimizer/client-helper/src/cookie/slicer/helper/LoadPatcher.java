package cookie.slicer.helper;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;

/**
 * Points the loading screen's "end of the window layer" calls at LoadHook: in
 * GameLoadingState.render() (the screen between joining a server and the world) each
 * Core.EndFrameUI() call first lets LoadHook draw its box (what went wrong and how to
 * fix it), then ends the frame as before. If the four calls are not found exactly (a game
 * update changed the method) the class keeps the game's own code and there is no box.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class LoadPatcher implements ClassFileTransformer {
    static final String TARGET = "zombie/gameStates/GameLoadingState";
    static final String HOOK = "cookie/slicer/helper/LoadHook";
    static volatile int hooked = -1; // -1 not loaded yet, 0 failed, 1 on
    static volatile String error = "";

    static List<ClassPatch.Redirect> plan() {
        List<ClassPatch.Redirect> rs = new ArrayList<>();
        rs.add(new ClassPatch.Redirect("render", "()V", ClassPatch.INVOKEVIRTUAL,
            "zombie/core/Core", "EndFrameUI", "()V", null, 4, "endFrameUI", "(Lzombie/core/Core;)V"));
        return rs;
    }

    static byte[] patch(byte[] bytes) {
        return new ClassPatch(bytes).apply(plan(), HOOK);
    }

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> redefined,
                            ProtectionDomain pd, byte[] bytes) {
        if (!TARGET.equals(className) || redefined != null) return null;
        try {
            byte[] out = patch(bytes);
            hooked = 1;
            System.out.println("[CookieSlicerHelper] loading screen: problem box on");
            return out;
        } catch (Throwable t) {
            hooked = 0;
            error = String.valueOf(t.getMessage());
            System.out.println("[CookieSlicerHelper] loading screen box off, the game keeps its own code: " + t.getMessage());
            return null;
        }
    }
}
