package zombie.entity;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * Drives the game's real EntityBucket (patched or not, depending on the class loader that
 * loaded it) with test entities, and returns the bucket's list after every step, joined.
 * Compiled against the game jar; no game code here.
 */
public final class BucketDrive {
    static final class TE extends GameEntity {
        final int id;
        boolean ok;
        TE(int id) {
            this.id = id;
            setComps(this);
        }
        @Override public GameEntityType getGameEntityType() { return null; }
        @Override public zombie.iso.IsoGridSquare getSquare() { return null; }
        @Override public long getEntityNetID() { return id; }
        @Override public float getX() { return 0; }
        @Override public float getY() { return 0; }
        @Override public float getZ() { return 0; }
        @Override public boolean isEntityValid() { return true; }
    }

    /** the entity's own bucket bits live in its component container */
    static void setComps(GameEntity e) {
        try {
            java.lang.reflect.Field f = GameEntity.class.getDeclaredField("components");
            f.setAccessible(true);
            f.set(e, ComponentContainer.Alloc(e));
        } catch (ReflectiveOperationException x) {
            throw new IllegalStateException(x);
        }
    }

    /** a fingerprint of the bucket's list after every step + the final list */
    public static String run(long seed, int steps, int pool) {
        EntityBucket.CustomBucket b = new EntityBucket.CustomBucket(0, e -> ((TE) e).ok);
        List<TE> all = new ArrayList<>();
        for (int i = 0; i < pool; i++) all.add(new TE(i));
        Random r = new Random(seed);
        long h = 1;
        for (int s = 0; s < steps; s++) {
            TE e = all.get(r.nextInt(pool));
            e.ok = r.nextInt(100) < 55 ? !e.ok : e.ok; // flip in/out (sometimes an update with no change)
            b.updateMembership(e);
            var list = b.getEntities();
            for (int i = 0; i < list.size(); i++) h = h * 31 + ((TE) list.get(i)).id;
            h = h * 31 + list.size();
        }
        StringBuilder sb = new StringBuilder("hash ").append(h).append(" size ").append(b.getEntities().size()).append(" list");
        var list = b.getEntities();
        for (int i = 0; i < Math.min(12, list.size()); i++) sb.append(' ').append(((TE) list.get(i)).id);
        return sb.toString();
    }
}
