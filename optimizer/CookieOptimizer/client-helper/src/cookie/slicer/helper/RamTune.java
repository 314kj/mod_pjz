package cookie.slicer.helper;

import java.lang.management.ManagementFactory;
import java.util.Map;

/**
 * Keeps the game's memory close to what it really uses (helper 1.2.1).
 *
 * ZGC lets garbage pile up until the heap nears its "soft" ceiling and only then cleans
 * up, so with a 16 GB game RAM the game held 12-16 GB while it really used ~5 GB. Java
 * lets SoftMaxHeapSize change while the game runs: every 2 s this sets it to what the
 * game kept after its last clean-up x 1.5 + 1 GB (x 1.8 + 1.5 GB on a PC with 4 cores or
 * fewer), at least 4 GB (or half the game RAM), at most 85% of the game RAM. ZGC then
 * cleans up earlier and gives the rest back to Windows (ZUncommitDelay from the start
 * script). The game RAM itself (-Xmx) stays the hard ceiling: when the game needs more,
 * the heap still grows past the soft ceiling at once, so nothing runs out.
 * Raising follows at once; lowering waits 30 s between steps and never happens while the
 * PC's CPU is above 85% (cleaning up more often costs CPU on the other cores).
 * When the PC itself is short of RAM (under 2 GB free) it squeezes at once: live x 1.15
 * + 0.5 GB, no waiting, so the garbage space goes back to Windows instead of the PC
 * paging to disk (stalls that end in timeouts / checksum kicks).
 * Only with ZGC and the RAM savers on (the start script added them); otherwise it does nothing.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class RamTune {
    static final long STEP_MB = 128;          // smaller changes are not worth a call
    static final long LOWER_WAIT_MS = 30_000;
    static final long BUSY_CPU = 85;
    static final long PC_LOW_MB = 2048;

    private static long lastMb = -1, lastLowerAt, guardUntil;
    private static volatile String state = "off";

    private RamTune() {}

    /** the soft ceiling for this much live data */
    static long target(long liveMb, long maxMb, int cores) {
        boolean small = cores <= 4;
        long t = Math.round(liveMb * (small ? 1.8 : 1.5)) + (small ? 1536 : 1024);
        long floor = Math.min(4096, maxMb / 2);
        long cap = maxMb * 85 / 100;
        return Math.max(floor, Math.min(cap, t));
    }

    /** PC short of RAM: just above what the game keeps */
    static long squeeze(long liveMb, long maxMb) {
        long t = Math.round(liveMb * 1.15) + 512;
        return Math.max(Math.min(2048, maxMb / 2), Math.min(maxMb * 85 / 100, t));
    }

    /** next value to set (or the current one when it should stay) */
    static long next(long last, long want, long now, long cpuTotal) {
        if (last < 0 || want >= last) return want;
        if (cpuTotal > BUSY_CPU || now - lastLowerAt < LOWER_WAIT_MS || last - want < 256) return last;
        return Math.max(want, last - 2048); // at most 2 GB down per step
    }

    static void tick(Map<String, String> m, long liveMb, long maxMb, int cores, long cpuTotal, long pcFreeMb, String gc, String saversOn) {
        if (!"ZGC".equals(gc) || !"1".equals(saversOn) || liveMb <= 0 || maxMb <= 0) {
            m.put("ramtune", "off");
            return;
        }
        long now = System.currentTimeMillis();
        // squeeze under 2 GB free; stay squeezed for a minute and until 3 GB are free (no see-saw)
        boolean low = pcFreeMb >= 0 && (pcFreeMb < PC_LOW_MB || (now < guardUntil && pcFreeMb < PC_LOW_MB + 1024));
        if (low && pcFreeMb < PC_LOW_MB) guardUntil = now + 60_000;
        long want = low ? squeeze(liveMb, maxMb) : next(lastMb, target(liveMb, maxMb, cores), now, cpuTotal);
        if (lastMb < 0 || Math.abs(want - lastMb) >= STEP_MB) {
            if (set(want)) {
                if (lastMb > 0 && want < lastMb) lastLowerAt = now;
                lastMb = want;
            }
        }
        m.put("ramtune", state);
        if (low) m.put("ram_guard", "1");
        if (lastMb > 0) m.put("soft_max_mb", Long.toString(lastMb));
    }

    static boolean set(long mb) {
        try {
            com.sun.management.HotSpotDiagnosticMXBean d = ManagementFactory.getPlatformMXBean(com.sun.management.HotSpotDiagnosticMXBean.class);
            d.setVMOption("SoftMaxHeapSize", Long.toString(mb * Helper.MB));
            state = "on";
            return true;
        } catch (Throwable t) {
            state = "err: " + String.valueOf(t.getMessage()).replace('\n', ' ');
            return false;
        }
    }

    /** current SoftMaxHeapSize in MB (for tests), or -1 */
    static long current() {
        try {
            com.sun.management.HotSpotDiagnosticMXBean d = ManagementFactory.getPlatformMXBean(com.sun.management.HotSpotDiagnosticMXBean.class);
            return Long.parseLong(d.getVMOption("SoftMaxHeapSize").getValue()) / Helper.MB;
        } catch (Throwable t) {
            return -1;
        }
    }

    /** for tests */
    static void reset() {
        lastMb = -1;
        lastLowerAt = 0;
        guardUntil = 0;
        state = "off";
    }
}
