package cookie.slicer.helper;

import java.lang.instrument.ClassFileTransformer;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.List;

/**
 * Points one game call at ShaderHook: in MultiTextureFBO2.render() (the game draws the
 * finished world picture to the screen through its own screen shader) the call that ends
 * that shader also queues the Cookie Slicer look, so it is drawn right after the game's
 * screen shader and before any window. Nothing else changes; if the call is not found
 * exactly once (a game update changed the method) the class keeps the game's own code
 * and the looks fall back to the simple colour layers.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class ShaderPatcher implements ClassFileTransformer {
    static final String TARGET = "zombie/core/textures/MultiTextureFBO2";
    static final String HOOK = "cookie/slicer/helper/ShaderHook";

    static List<ClassPatch.Redirect> plan() {
        List<ClassPatch.Redirect> rs = new ArrayList<>();
        rs.add(new ClassPatch.Redirect("render", "()V", ClassPatch.INVOKESTATIC,
            "zombie/IndieGL", "EndShader", "()V", null, 1, "endShader", "()V"));
        return rs;
    }

    /** the patched class, or an exception saying what did not match */
    static byte[] patch(byte[] bytes) {
        return new ClassPatch(bytes).apply(plan(), HOOK);
    }

    @Override
    public byte[] transform(ClassLoader loader, String className, Class<?> redefined,
                            ProtectionDomain pd, byte[] bytes) {
        if (!TARGET.equals(className) || redefined != null) return null;
        try {
            byte[] out = patch(bytes);
            ShaderState.hooked = 1;
            System.out.println("[CookieSlicerHelper] screen looks: hooked after the game's screen shader");
            return out;
        } catch (Throwable t) {
            ShaderState.hooked = 0;
            ShaderState.hookError = String.valueOf(t.getMessage());
            System.out.println("[CookieSlicerHelper] screen looks off, the game keeps its own code: " + t.getMessage());
            return null;
        }
    }
}
