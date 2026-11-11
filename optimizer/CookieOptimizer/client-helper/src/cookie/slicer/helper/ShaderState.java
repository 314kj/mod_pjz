package cookie.slicer.helper;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * What the player chose for the screen look (read from Zomboid/Lua/CookieSlicer_shader.txt,
 * written by the Cookie Slicer mod) and how the look is doing (shown by the mod).
 * No game classes here: this runs on the helper's own threads.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class ShaderState {
    static final String FILE = "CookieSlicer_shader.txt";

    /** one complete choice; replaced as a whole when the file changes */
    static final class Settings {
        boolean on;
        int quality = 2;        // 0 grading only, 1 glow from 2 smaller copies, 2 from 4
        float split = -1f;      // compare line, part of the width
        float mix, exp, con = 1f, sat = 1f, warm, bloom, vig, sharp, grain;
        float thr = 0.6f, glow, tone, fade;
        float[] sh = new float[4], hi = new float[4];
        String look = "natural";

        int levels() {
            if (quality <= 0 || bloom <= 0f) return 0;
            return quality == 1 ? 2 : 4;
        }
    }

    static volatile Settings settings = new Settings();

    // ---------------------------------------------------------------- status (for the mod)
    static volatile int hooked = -1;          // 1 patched, 0 failed, -1 game class not loaded yet
    static volatile String hookError;
    static volatile int compiled = -1;        // 1 ok, 0 failed, -1 not tried
    static volatile String error;
    static volatile String gpu, vendor, glVersion;
    static volatile long vramTotalKb = -1, vramFreeKb = -1;
    static volatile double msAvg = -1;        // GPU time of the pass (ms), smoothed
    static volatile long lastPassMs;          // wall clock of the last pass
    static volatile boolean infoDone;

    static boolean wantDraw() {
        if (compiled == 0 || error != null) return false;
        return settings.on || !infoDone;      // once without a look, to read the graphics card
    }

    static void fail(String why) {
        if (error == null) {
            error = why;
            System.out.println("[CookieSlicerHelper] screen looks stopped for this session: " + why);
        }
    }

    /** lines for CookieSlicer_pc.txt */
    static void status(Map<String, String> m) {
        if (hooked >= 0) m.put("shader_hook", Integer.toString(hooked));
        if (hookError != null) m.put("shader_hook_err", clean(hookError));
        if (compiled >= 0) m.put("shader_ok", error != null ? "0" : Integer.toString(compiled));
        if (error != null) m.put("shader_err", clean(error));
        if (gpu != null) m.put("gpu", clean(gpu));
        if (vendor != null) m.put("gpu_vendor", clean(vendor));
        if (glVersion != null) m.put("gl", clean(glVersion));
        if (vramTotalKb > 0) m.put("vram_total_mb", Long.toString(vramTotalKb / 1024));
        if (vramFreeKb > 0) m.put("vram_free_mb", Long.toString(vramFreeKb / 1024));
        if (msAvg >= 0) m.put("shader_ms", String.format(Locale.ROOT, "%.3f", msAvg));
        boolean active = settings.on && System.currentTimeMillis() - lastPassMs < 3000;
        m.put("shader_active", active ? "1" : "0");
        m.put("shader_q", Integer.toString(settings.quality));
    }

    static String clean(String s) {
        return s.replace('\n', ' ').replace('\r', ' ').replace('=', ':').trim();
    }

    // ---------------------------------------------------------------- reading the choice

    private static long seenModified = -1, seenLength = -1;

    /** reads the file again when it changed; returns true when the choice changed */
    static boolean poll(File luaDir) {
        File f = new File(luaDir, FILE);
        long mod = f.lastModified(), len = f.length();
        if (mod == seenModified && len == seenLength) return false;
        seenModified = mod;
        seenLength = len;
        if (!f.isFile()) {
            settings = new Settings();
            return true;
        }
        try {
            settings = parse(new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8));
            return true;
        } catch (IOException e) {
            seenModified = -1; // try again next time
            return false;
        }
    }

    static Settings parse(String text) {
        Map<String, String> m = new HashMap<>();
        for (String line : text.split("\n")) {
            int i = line.indexOf('=');
            if (i > 0) m.put(line.substring(0, i).trim(), line.substring(i + 1).trim());
        }
        Settings s = new Settings();
        s.on = "1".equals(m.get("on"));
        s.look = m.getOrDefault("look", "natural");
        s.quality = (int) clamp(f(m, "q", 2), 0, 2);
        s.split = f(m, "split", -1);
        s.mix = clamp(f(m, "mix", 0), 0, 1);
        s.exp = clamp(f(m, "exp", 0), -2, 2);
        s.con = clamp(f(m, "con", 1), 0.3f, 2);
        s.sat = clamp(f(m, "sat", 1), 0, 2.5f);
        s.warm = clamp(f(m, "warm", 0), -1.5f, 1.5f);
        s.bloom = clamp(f(m, "bloom", 0), 0, 2);
        s.vig = clamp(f(m, "vig", 0), 0, 1);
        s.sharp = clamp(f(m, "sharp", 0), 0, 1);
        s.grain = clamp(f(m, "grain", 0), 0, 1);
        s.thr = clamp(f(m, "thr", 0.6f), 0, 0.95f);
        s.glow = clamp(f(m, "glow", 0), 0, 1.5f);
        s.tone = clamp(f(m, "tone", 0), 0, 1);
        s.fade = clamp(f(m, "fade", 0), 0, 1);
        s.sh = vec4(m.get("sh"));
        s.hi = vec4(m.get("hi"));
        return s;
    }

    private static float f(Map<String, String> m, String k, float dflt) {
        String v = m.get(k);
        if (v == null) return dflt;
        try {
            float x = Float.parseFloat(v);
            return Float.isFinite(x) ? x : dflt;
        } catch (NumberFormatException e) {
            return dflt;
        }
    }

    private static float[] vec4(String v) {
        float[] out = new float[4];
        if (v == null) return out;
        String[] p = v.split(",");
        for (int i = 0; i < 4 && i < p.length; i++) {
            try { out[i] = clamp(Float.parseFloat(p[i].trim()), 0, 1); } catch (NumberFormatException ignored) { /* 0 */ }
        }
        return out;
    }

    static float clamp(float v, float lo, float hi) {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    /** a thread that reads the choice whenever the mod writes it */
    static void startWatching(File luaDir) {
        Thread t = new Thread(() -> {
            while (true) {
                try {
                    poll(luaDir);
                } catch (Throwable e) {
                    System.out.println("[CookieSlicerHelper] " + e);
                }
                try { Thread.sleep(150); } catch (InterruptedException e) { return; }
            }
        }, "CookieSlicer-Looks");
        t.setDaemon(true);
        t.setPriority(Thread.MIN_PRIORITY);
        t.start();
    }
}
