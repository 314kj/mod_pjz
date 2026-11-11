package cookie.slicer.helper;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import zombie.GameWindow;
import zombie.core.Core;
import zombie.core.SpriteRenderer;
import zombie.core.Translator;
import zombie.gameStates.GameLoadingState;
import zombie.ui.TextManager;
import zombie.ui.UIFont;

/**
 * Called by the game's loading screen (see LoadPatcher) once per frame, just before the
 * frame is finished. When something went wrong (the game shows "unexpected error" or a
 * kick / lost connection), when the log shows a problem that stops the join (ConsoleWatch),
 * or when loading takes much longer than usual, it draws a box: what happened and what to
 * do, in the player's language (texts from the mod's Translate files, English if those
 * are not loaded). Otherwise it draws nothing.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
public final class LoadHook {
    static final long GAP_MS = 5000;        // no frame this long = a new loading screen
    static final long SLOW_MS = 180_000;    // "taking long" after 3 minutes
    static final int MAX_PROBLEMS = 2;

    private static volatile boolean off;
    private static long lastCall, loadStart;
    private static Field unexpectedField;
    private static String lastKick;

    private LoadHook() {}

    public static void endFrameUI(Core core) {
        if (!off) {
            try {
                draw(core);
            } catch (Throwable t) {
                off = true;
                System.out.println("[CookieSlicerHelper] loading screen box off: " + t);
            }
        }
        core.EndFrameUI();
    }

    // ---------------------------------------------------------------- what to show

    static void draw(Core core) {
        long now = System.currentTimeMillis();
        if (now - lastCall > GAP_MS) loadStart = now;
        lastCall = now;
        boolean unexpected = unexpectedError();
        boolean kicked = GameWindow.serverDisconnected;
        if (kicked) {
            String reason = GameWindow.kickReason;
            if (reason != null && !reason.equals(lastKick)) {
                lastKick = reason;
                ConsoleWatch.line(reason, now);
            }
        }
        boolean slow = now - loadStart > SLOW_MS;
        List<ConsoleWatch.Problem> ps = ConsoleWatch.current(!(unexpected || slow));
        List<String[]> blocks = new ArrayList<>();
        for (ConsoleWatch.Problem p : ps) {
            if (blocks.size() >= MAX_PROBLEMS) break;
            blocks.add(block(p.code, p.detail));
        }
        if (blocks.isEmpty()) {
            if (unexpected || kicked) blocks.add(block("unknown", ""));
            else if (slow) blocks.add(block("slow", ""));
            else return;
        }
        int sw = core.getScreenWidth(), sh = core.getScreenHeight();
        // under the game's own red message when there is one, else at the top
        int y = (unexpected || kicked) ? sh / 2 + 70 : 40;
        box(blocks, sw, sh, y);
    }

    static boolean unexpectedError() {
        try {
            if (unexpectedField == null) {
                unexpectedField = GameLoadingState.class.getDeclaredField("unexpectedError");
                unexpectedField.setAccessible(true);
            }
            return unexpectedField.getBoolean(null);
        } catch (Throwable t) {
            return false;
        }
    }

    /** title line + up to three steps for one problem */
    static String[] block(String code, String detail) {
        String title = text("Fix_" + code);
        if (detail != null && !detail.isEmpty()) title = title + ": " + detail;
        List<String> out = new ArrayList<>();
        out.add(title);
        for (int i = 1; i <= 3; i++) {
            String s = textOrNull("Fix_" + code + "_" + i);
            if (s != null && !s.isEmpty()) out.add(i + ". " + s);
        }
        return out.toArray(new String[0]);
    }

    // ---------------------------------------------------------------- drawing

    static void box(List<String[]> blocks, int sw, int sh, int y) {
        TextManager tm = TextManager.instance;
        UIFont big = UIFont.Medium, small = UIFont.Small;
        int hb = tm.getFontHeight(big), hs = tm.getFontHeight(small);
        int w = Math.min(980, sw - 60);
        int pad = 16, inner = w - 2 * pad;
        List<Object[]> lines = new ArrayList<>(); // {text, font, r, g, b}
        lines.add(new Object[] {text("Fix_Head"), big, 0.31f, 0.96f, 0.78f});
        for (String[] b : blocks) {
            for (String s : wrap(b[0], small, inner)) lines.add(new Object[] {s, small, 1.0f, 0.78f, 0.34f});
            for (int i = 1; i < b.length; i++) {
                for (String s : wrap(b[i], small, inner - 12)) lines.add(new Object[] {"   " + s, small, 0.91f, 0.95f, 0.94f});
            }
        }
        for (String s : wrap(text("Fix_Foot"), small, inner)) lines.add(new Object[] {s, small, 0.62f, 0.70f, 0.68f});
        int h = pad * 2;
        for (Object[] l : lines) h += (l[1] == big ? hb + 6 : hs + 2);
        if (y + h > sh - 10) y = Math.max(10, sh - 10 - h);
        int x = (sw - w) / 2;
        SpriteRenderer sr = SpriteRenderer.instance;
        sr.renderi(null, x, y, w, h, 0.03f, 0.05f, 0.05f, 0.94f, null);
        sr.renderi(null, x, y, w, 3, 0.31f, 0.96f, 0.78f, 1f, null);
        int ty = y + pad;
        for (Object[] l : lines) {
            UIFont f = (UIFont) l[1];
            tm.DrawString(f, x + pad, ty, (String) l[0], (float) l[2], (float) l[3], (float) l[4], 1.0);
            ty += (f == big ? hb + 6 : hs + 2);
        }
    }

    /** breaks at spaces; a run without spaces (Thai) is broken where it no longer fits */
    static List<String> wrap(String s, UIFont font, int maxW) {
        List<String> out = new ArrayList<>();
        TextManager tm = TextManager.instance;
        StringBuilder line = new StringBuilder();
        for (String word : s.split(" ")) {
            String trial = line.length() == 0 ? word : line + " " + word;
            if (tm.MeasureStringX(font, trial) <= maxW) { line.setLength(0); line.append(trial); continue; }
            if (line.length() > 0) { out.add(line.toString()); line.setLength(0); }
            String rest = word;
            while (tm.MeasureStringX(font, rest) > maxW && rest.length() > 1) {
                int cut = rest.length() - 1;
                while (cut > 1 && tm.MeasureStringX(font, rest.substring(0, cut)) > maxW) cut--;
                out.add(rest.substring(0, cut));
                rest = rest.substring(cut);
            }
            line.append(rest);
        }
        if (line.length() > 0) out.add(line.toString());
        return out;
    }

    // ---------------------------------------------------------------- texts

    static String text(String key) {
        String s = textOrNull(key);
        return s != null ? s : key;
    }

    /** the mod's text (Translate/<language>/UI.json), else the English one below */
    static String textOrNull(String key) {
        try {
            String s = Translator.getTextOrNull("UI_CookieSlicer_" + key);
            if (s != null && !s.isEmpty()) return s;
        } catch (Throwable ignored) {
            // English below
        }
        return EN.get(key);
    }

    static final Map<String, String> EN = new HashMap<>();
    static {
        EN.put("Fix_Head", "Cookie Slicer: what went wrong and how to fix it");
        EN.put("Fix_Foot", "Full details: Zomboid/console.txt (send it to an admin on Discord)");
        EN.put("Fix_unknown", "The game could not finish loading");
        EN.put("Fix_unknown_1", "Close the game and join again");
        EN.put("Fix_unknown_2", "Still the same: send Zomboid/console.txt to an admin on Discord");
        EN.put("Fix_slow", "Loading is taking longer than usual");
        EN.put("Fix_slow_1", "The first join after mod updates can take 3-5 minutes");
        EN.put("Fix_slow_2", "Over 10 minutes: close the game and join again");
        EN.put("Fix_ram", "Not enough memory (RAM) for the game");
        EN.put("Fix_ram_1", "Close the game, run CookieSlicer-Setup and press 1 (sets the game RAM for your PC)");
        EN.put("Fix_ram_2", "Close other programs that use a lot of RAM (browser, recording)");
        EN.put("Fix_pzopt", "PZ Optimization is still in the game (it breaks after game updates)");
        EN.put("Fix_pzopt_1", "Close the game, run CookieSlicer-Setup and press 1 (repairs ProjectZomboid64.json)");
        EN.put("Fix_pzopt_2", "Or Steam: Project Zomboid > Properties > Installed Files > Verify integrity");
        EN.put("Fix_workshop", "A mod on your PC is not the server's version");
        EN.put("Fix_workshop_1", "Close the game and restart Steam so it updates the mods (see Downloads)");
        EN.put("Fix_workshop_2", "Still the same: Unsubscribe that item and Subscribe again");
        EN.put("Fix_workshop_3", "Everyone has it: ask an admin to restart the server");
        EN.put("Fix_modmissing", "A mod the server needs is not installed");
        EN.put("Fix_modmissing_1", "Subscribe to it on the Workshop, wait for Steam, then join again");
        EN.put("Fix_map", "A map the server uses is not installed");
        EN.put("Fix_map_1", "Subscribe to the server's map mods on the Workshop, then join again");
        EN.put("Fix_files", "Game or mod files on your PC do not match the server");
        EN.put("Fix_files_1", "Remove mod folders you copied yourself into Zomboid/mods (same names as the server's)");
        EN.put("Fix_files_2", "Steam: Verify integrity of game files");
        EN.put("Fix_files_3", "Unsubscribe and Subscribe the server's mods again");
        EN.put("Fix_version", "Your game version is not the server's");
        EN.put("Fix_version_1", "Let Steam update the game; do not use a beta branch");
        EN.put("Fix_banned", "This account is banned on the server");
        EN.put("Fix_banned_1", "Contact an admin on Discord");
        EN.put("Fix_already", "This account is still connected on the server");
        EN.put("Fix_already_1", "Wait 1-2 minutes, then join again");
        EN.put("Fix_access", "Not allowed in (not on the whitelist yet, or wrong name / password)");
        EN.put("Fix_access_1", "Check the name and password the admins gave you");
        EN.put("Fix_access_2", "Ask for the whitelist on Discord");
        EN.put("Fix_full", "The server is full");
        EN.put("Fix_full_1", "Wait a moment and join again");
        EN.put("Fix_ping", "Your ping is above the server's limit");
        EN.put("Fix_ping_1", "Stop downloads / streams, use a cable instead of Wi-Fi");
        EN.put("Fix_net", "The connection to the server was lost");
        EN.put("Fix_net_1", "Check your internet, turn off VPN");
        EN.put("Fix_net_2", "Check Discord: the server may be restarting");
        EN.put("Fix_luamod", "Mods with errors while loading");
        EN.put("Fix_luamod_1", "Unsubscribe and Subscribe that mod again");
        EN.put("Fix_luamod_2", "Still the same: send Zomboid/console.txt to an admin on Discord");
    }
}
