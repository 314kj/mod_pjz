package cookie.slicer.helper;

import zombie.IndieGL;
import zombie.core.SpriteRenderer;
import zombie.core.opengl.RenderSettings;

/**
 * Called by the game (see ShaderPatcher) on its main thread, where it ends the screen
 * shader while building the frame. Queues the Cookie Slicer look as one more draw step,
 * which the render thread runs right after the world picture (PostDrawer).
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
public final class ShaderHook {
    private ShaderHook() {}

    public static void endShader() {
        IndieGL.EndShader();
        try {
            if (!ShaderState.wantDraw()) return;
            if (nightVision()) return; // the goggles' green picture stays as the game draws it
            SpriteRenderer.instance.drawGeneric(PostDrawer.INSTANCE);
        } catch (Throwable t) {
            ShaderState.fail("queue: " + t);
        }
    }

    private static boolean nightVision() {
        try {
            return RenderSettings.getInstance().getPlayerSettings(0).isApplyNightVisionGoggles();
        } catch (Throwable t) {
            return false;
        }
    }
}
