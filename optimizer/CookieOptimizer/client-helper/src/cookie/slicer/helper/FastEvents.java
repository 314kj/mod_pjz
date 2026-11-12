package cookie.slicer.helper;

import java.util.ArrayList;

/**
 * Lua events: the handler loop without searching the whole list after every handler
 * (helper 1.3.0; the same code as the server's Cookie Slicer v6).
 *
 * The game's Event.trigger calls handler i, then asks callbacks.contains(handler) to see whether
 * the handler removed itself (then the next one moved into slot i). contains() searches the list
 * from the start, so an event with n handlers costs about n*n/2 comparisons each time it fires
 * (OnTick every tick). Here the slot just called is checked first: if the same handler is still
 * there, the answer is "yes" without a search; otherwise the game's own contains() answers. The
 * answer is always the same as contains() (a handler found in its slot is in the list), so the same
 * handlers run in the same order whatever a handler adds or removes.
 * Off (the window's switch, speed.txt) = the game's own search.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
final class FastEvents {
    static volatile boolean use;
    // the slot last called, for the 8 lists used most recently (a handler may fire other events
    // before its own check comes back); any mix-up is caught by the check itself
    private static final Object[] LISTS = new Object[8];
    private static final int[] SLOTS = new int[8];
    private static int nextSlot;
    static long fast, searched;

    private FastEvents() {}

    /** callbacks.get(i): the game's own, remembering which slot was called */
    static Object get(ArrayList<?> list, int i) {
        Object o = list.get(i);
        Object[] ls = LISTS;
        for (int k = 0; k < ls.length; k++) {
            if (ls[k] == list) {
                SLOTS[k] = i;
                return o;
            }
        }
        int k = nextSlot++ & 7;
        SLOTS[k] = i;
        ls[k] = list;
        return o;
    }

    /** callbacks.contains(handler) */
    static boolean listed(ArrayList<?> list, Object handler) {
        if (use) {
            Object[] ls = LISTS;
            for (int k = 0; k < ls.length; k++) {
                if (ls[k] == list) {
                    int i = SLOTS[k];
                    if (i >= 0 && i < list.size() && list.get(i) == handler) {
                        fast++;
                        return true;
                    }
                    break;
                }
            }
        }
        searched++;
        return list.contains(handler);
    }

    static String minute() {
        String s = "events: handlers checked in place " + fast + ", searched " + searched;
        fast = searched = 0;
        return s;
    }
}
