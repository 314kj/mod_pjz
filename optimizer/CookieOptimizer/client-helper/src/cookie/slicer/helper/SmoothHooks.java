package cookie.slicer.helper;

import java.util.Map;

import zombie.GameWindow;
import zombie.gameStates.IngameState;
import zombie.util.CappedConcurrentQueue;

/**
 * Where the game's calls land after SmoothPatcher (helper 1.4.0).
 *
 * Map pieces (chunks): pieces that arrived from the server wait in IsoChunk.loadGridSquare and the
 * game's thread finishes them, 1 + 3 x (waiting) / (map width) per frame, however long that takes.
 * Driving fast, a dozen big pieces land in one frame and the picture stops. Here the game still
 * asks for the same number, but after chunkMs of finishing in this frame the queue answers "empty"
 * for the rest of the frame: the others wait for the next frames, in the same order, exactly as the
 * game already lets pieces wait between frames. At least one piece per frame, never more than the
 * game would do; pieces that unload while waiting the game takes out of the queue itself. Only in
 * the game itself: on the loading screen everything runs the game's way. chunkMs 0 = the game's way.
 *
 * Zombies in 3D: IsoWorld.sceneCullZombies gives a full 3D model to the zombies on screen that matter
 * most (nearest / most relevant, the game's own order) up to 510; the rest are drawn as a flat picture
 * by the game's own code. Here the 510 is the number chosen in the window (510 / 300 / 200 / 150).
 * Only the picture changes: what zombies do, where they are and the server are not touched.
 *
 * Both are read by the game's thread only; the window's choice (CookieSlicer_request.txt) is kept in
 * smooth.txt next to the jar and applies at once.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
public final class SmoothHooks {
    static final int GAME_3D = 510;                   // the game's own number
    static final int[] CHOICES_3D = {510, 300, 200, 150};
    static final int DEFAULT_CHUNK_MS = 4;

    static volatile int chunkMs = DEFAULT_CHUNK_MS;   // 0 = the game's way
    static volatile int limit3d = GAME_3D;
    static volatile int forceInGame = -1;              // tests: 1 / 0; -1 = ask the game

    // this frame (game thread only)
    private static long frameStart;
    private static int frameTaken;
    private static boolean frameBudget;
    // totals since the game started (read by the helper thread for the pc file)
    static volatile long chunksDone, chunksWaited, framesCut;
    private static boolean cutThisFrame;

    private SmoothHooks() {}

    // ---------------------------------------------------------------- the game's calls

    /** IsoChunkMap.updateInternal: IsoChunk.loadGridSquare.size(), once at the start of each update */
    @SuppressWarnings("rawtypes")
    public static int chunkQueueSize(CappedConcurrentQueue q) {
        frameStart = System.nanoTime();
        frameTaken = 0;
        cutThisFrame = false;
        frameBudget = chunkMs > 0 && inGame();
        return q.size();
    }

    /** IsoChunkMap.updateInternal: IsoChunk.loadGridSquare.poll(), once per piece the game wants now */
    @SuppressWarnings("rawtypes")
    public static Object chunkQueuePoll(CappedConcurrentQueue q) {
        if (frameBudget && frameTaken > 0 && System.nanoTime() - frameStart > chunkMs * 1_000_000L) {
            if (!cutThisFrame) {
                cutThisFrame = true;
                framesCut++;
            }
            chunksWaited++;
            return null; // the game's loop counts this one down and asks again; the piece stays queued
        }
        Object c = q.poll();
        if (c != null) {
            frameTaken++;
            chunksDone++;
        }
        return c;
    }

    /** IsoWorld.sceneCullZombies: the most zombies with a full 3D model (the game: 510) */
    public static int zombies3d() {
        return limit3d;
    }

    static boolean inGame() {
        int f = forceInGame;
        if (f >= 0) return f == 1;
        try {
            return GameWindow.states != null && IngameState.instance != null
                && GameWindow.states.current == IngameState.instance;
        } catch (Throwable t) {
            return false;
        }
    }

    // ---------------------------------------------------------------- the helper's side

    static int pick3d(long v) {
        for (int c : CHOICES_3D) if (c == v) return c;
        return GAME_3D;
    }

    static int pickChunkMs(long v) {
        return v <= 0 ? 0 : (int) Math.min(Math.max(v, 2), 16);
    }

    /** smooth.txt / the window: "chunk_ms" (0 = the game's way, 2-16) and "zombies3d" (510 / 300 / 200 / 150) */
    static void set(Map<String, String> m) {
        String c = m.get("chunk_ms");
        if (c != null && !c.trim().isEmpty()) chunkMs = pickChunkMs(Helper.parse(c, DEFAULT_CHUNK_MS));
        String z = m.get("zombies3d");
        if (z != null && !z.trim().isEmpty()) limit3d = pick3d(Helper.parse(z, GAME_3D));
    }

    static String save() {
        return "chunk_ms=" + chunkMs + "\nzombies3d=" + limit3d + "\n";
    }

    /** every 2 s from the helper thread */
    static void status(Map<String, String> m) {
        m.put("smooth_classes", SmoothPatcher.patched + "/" + SmoothPatcher.TARGETS.length);
        if (!SmoothPatcher.failed.isEmpty()) m.put("smooth_failed", SmoothPatcher.failed);
        m.put("chunk_ms", Integer.toString(chunkMs));
        m.put("zombies3d", Integer.toString(limit3d));
        m.put("chunks_done", Long.toString(chunksDone));
        m.put("chunks_waited", Long.toString(chunksWaited));
        m.put("chunk_frames_cut", Long.toString(framesCut));
    }
}
