package cookie.slicer.helper;

import java.util.Map;

import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.RoomDef;
import zombie.iso.areas.IsoRoom;

/**
 * Where IsoLightSwitch.chunkLoaded asks a square for its room, after RoomPatcher (helper 1.5.0).
 *
 * When someone builds or tears down in a cell, the client makes the rooms of every player-built
 * building in that cell again (WorldRegionToMetaGrid.clientProcessBuildings; Building Clipboard's
 * pasted buildings count as player-built): new rooms, and the old ones cleared (def = null). A map
 * piece that was loading at that moment still points its squares at the old rooms, and when the game
 * finishes the piece, chunkLoaded asks every square's room hasLightSwitches(), which reads def: the
 * game stops with "this.def is null" and goes back to the main menu.
 *
 * Here a square whose room has no def is pointed at the room the map has there now, the way the
 * game's own IsoChunk.assignRoom does it (setRoomID with the RoomDef at x, y, z; no room when there is
 * none any more), the room keeps the square as the game's loading does, and that room is the answer.
 * Every other square gets the game's own answer and is not touched. If the repair itself fails, the
 * answer is "no room": that square's room lights are skipped (the game's code would have stopped).
 *
 * Called on the game's thread (IsoChunk.loadInMainThread / recalcNeighboursNow); the totals are read
 * by the helper thread for the pc file. Neighbours are not recalculated here (the game did that while
 * loading the piece, right before).
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
public final class RoomHooks {
    static final int MAX_LINES = 20; // repairs written to the game's log; the rest only counted

    static volatile long fixed, gone, failed;
    private static int lines;

    private RoomHooks() {}

    /** IsoLightSwitch.chunkLoaded: square.getRoom(), once per square of the finished map piece */
    public static IsoRoom lightsRoom(IsoGridSquare sq) {
        IsoRoom room = sq.getRoom();
        if (room == null || room.def != null) return room; // the game's own answer
        int x = sq.getX(), y = sq.getY(), z = sq.getZ();
        try {
            RoomDef rd = IsoWorld.instance.getMetaGrid().getRoomAt(x, y, z);
            sq.setRoomID(rd == null ? -1L : rd.id); // the game's assignRoom: the room for that id, made if needed
            IsoRoom live = rd == null ? null : sq.getRoom();
            sq.setRoom(live); // with no room the old one would stay behind in the square
            if (rd == null) {
                gone++;
                log(x, y, z, "no room any more");
                return null;
            }
            if (live == null || live.def == null) {
                failed++;
                log(x, y, z, "the map's room " + rd.id + " has no live room, lights skipped");
                return null;
            }
            live.addSquare(sq);
            fixed++;
            log(x, y, z, "room " + rd.id);
            return live;
        } catch (Throwable t) {
            failed++;
            log(x, y, z, "repair failed, lights skipped: " + t);
            return null;
        }
    }

    private static void log(int x, int y, int z, String what) {
        if (lines >= MAX_LINES) return;
        lines++;
        System.out.println("[CookieSlicerHelper] room fix: cleared room at " + x + "," + y + "," + z + " -> " + what
            + " (fixed " + fixed + ", gone " + gone + ", failed " + failed + ")");
    }

    /** every 2 s from the helper thread */
    static void status(Map<String, String> m) {
        m.put("room_classes", RoomPatcher.patched + "/" + RoomPatcher.TARGETS.length);
        if (!RoomPatcher.failed.isEmpty()) m.put("room_failed", RoomPatcher.failed);
        m.put("rooms_fixed", Long.toString(fixed));
        m.put("rooms_gone", Long.toString(gone));
        m.put("rooms_fix_failed", Long.toString(failed));
    }
}
