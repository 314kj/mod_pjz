package zombie.iso;

import java.lang.reflect.Field;

import zombie.iso.areas.IsoRoom;
import zombie.iso.objects.IsoLightSwitch;

/**
 * Drives the game's real IsoLightSwitch.chunkLoaded (patched or not, depending on the class loader
 * that loaded it) on a real IsoChunk whose square points at a room, with a real IsoMetaGrid holding
 * the map's room. Compiled against the game jar; no game code here.
 *
 * One map cell (0, 0) with one room, "kitchen", over the whole chunk (0, 0) at level 0 (tiles 0-7);
 * the room has one room light. The chunk has one square, at 3, 4, 0, pointing at:
 *   cleared  an old room whose def is null (the game cleared it after making the rooms again) with an
 *            old id the map no longer has; the map has "kitchen" there now
 *   made     the same cleared room, the map has "kitchen" there but no live room for it yet: the game
 *            makes it (IsoMetaGrid.getRoomByID: new IsoRoom, the cell's room list, IsoBuilding.CreateFrom);
 *            "kitchen" has a light switch in its map objects
 *   gone     the same cleared room, and the map has no room there any more
 *   live     "kitchen" itself (the usual case)
 *   none     no room (outside)
 * run() returns what the square and the chunk hold afterwards, or "threw <exception>".
 */
public final class RoomDrive {
    static final long LIVE_ID = RoomID.makeID(0, 0, 0);
    static final long OLD_ID = RoomID.makeID(0, 0, 5);
    static final int LIGHT_SWITCH = 7; // MetaObject type that IsoRoom.hasLightSwitches looks for

    static IsoGridSquare square;
    static IsoChunk chunk;
    static RoomDef def;
    static IsoRoom live, cleared;
    static IsoRoomLight light;

    static void set(Object o, Class<?> c, String name, Object v) throws Exception {
        Field f = c.getDeclaredField(name);
        f.setAccessible(true);
        f.set(o, v);
    }

    /** a fresh map with the room (or without it) and a chunk with the square */
    static void setUp(String scenario) throws Exception {
        IsoMetaGrid grid = IsoWorld.instance.getMetaGrid();
        set(grid, IsoMetaGrid.class, "grid", new IsoMetaCell[1][1]);
        set(grid, IsoMetaGrid.class, "width", 1);
        set(grid, IsoMetaGrid.class, "height", 1);
        grid.minX = 0;
        grid.minY = 0;
        IsoMetaCell cell = new IsoMetaCell(0, 0);
        grid.setCell(0, 0, cell);

        RoomDef rd = new RoomDef(LIVE_ID, "kitchen");
        rd.level = 0;
        rd.x = 0;
        rd.y = 0;
        rd.x2 = 8;
        rd.y2 = 8;
        rd.rects.add(new RoomDef.RoomRect(0, 0, 8, 8));
        zombie.core.random.RandStandard.INSTANCE.init(); // BuildingDef() picks a random number
        rd.building = new BuildingDef(true);             // player-built, as Building Clipboard's pastes are
        rd.building.rooms.add(rd);
        rd.building.CalculateBounds(new java.util.ArrayList<>());
        live = new IsoRoom();
        live.def = rd;
        live.roomDef = rd.name;
        live.layer = 0;
        live.rects.addAll(rd.rects);
        light = new IsoRoomLight(live, 1, 1, 0, 2, 2);
        live.roomLights.add(light);  // createLights() keeps a room's lights once it has them
        live.lightSwitches.add(null); // the room has a light switch (hasLightSwitches only asks if any)
        def = rd;
        IsoWorld.instance.currentCell = null;
        if ("made".equals(scenario)) {
            rd.objects.add(new MetaObject(LIGHT_SWITCH, 1, 1, rd));
            cell.addRoom(rd, 0, 0);
            cell.rooms.put(LIVE_ID, rd);
            IsoWorld.instance.currentCell = new IsoCell(300, 300); // getRoomByID adds the room it makes to it
        } else if (!"gone".equals(scenario)) {
            cell.addRoom(rd, 0, 0);
            cell.rooms.put(LIVE_ID, rd);
            cell.isoRooms.put(LIVE_ID, live); // the live room the game made for that RoomDef
        }

        cleared = new IsoRoom();     // cleared by the game: def null, lists emptied
        cleared.def = null;

        chunk = new IsoChunk((IsoCell) null);
        chunk.wx = 0;
        chunk.wy = 0;
        chunk.minLevel = 0;
        chunk.maxLevel = 0;
        square = new IsoGridSquare(null, null, 3, 4, 0);
        square.chunk = chunk;
        chunk.setSquare(3, 4, 0, square);
        switch (scenario) {
            case "cleared":
            case "made":
            case "gone":
                square.setRoomID(OLD_ID);  // the map no longer has this id: no room from it
                square.setRoom(cleared);   // what the loading piece still holds
                cleared.addSquare(square); // IsoChunk.loadInMainThread adds every square to its room
                break;
            case "live":
                square.setRoomID(LIVE_ID);
                live.addSquare(square);
                break;
            default:
                break; // none
        }
    }

    public static String run(String scenario) throws Exception {
        setUp(scenario);
        IsoRoom before = square.getRoom();
        String was = before == null ? "none" : before == live ? "live" : before == cleared ? "cleared" : "other";
        try {
            IsoLightSwitch.chunkLoaded(chunk);
        } catch (Throwable t) {
            return "threw " + t;
        }
        IsoRoom r = square.getRoom();
        String now = r == null ? "none" : r == live ? "live" : r == cleared ? "cleared"
            : r.def == def ? "made(switch=" + r.hasLightSwitches() + ",building=" + (r.building != null) + ")" : "other";
        return "was=" + was
            + " room=" + now
            + " roomId=" + (square.getRoomID() == LIVE_ID ? "live" : square.getRoomID() == -1L ? "-1" : Long.toString(square.getRoomID()))
            + " roomHasSquare=" + (r != null && r.getSquares().contains(square))
            + " chunkLights=" + chunk.roomLights.size() + (chunk.roomLights.contains(light) ? "(live)" : "");
    }
}
