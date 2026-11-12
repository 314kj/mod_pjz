package zombie.Lua;

import java.util.ArrayList;
import java.util.Random;

import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaCallFrame;
import se.krka.kahlua.vm.LuaClosure;

/**
 * Drives the game's real Event.trigger (patched or not, by the class loader that loaded it) with
 * real Lua handlers compiled by the game's Kahlua. Each handler calls a Java function that, at
 * random, removes the handler itself or another one, adds a handler, adds one twice or fires
 * another event, and the order of the calls is returned. Also makes Lua handlers fail on purpose
 * (errors), for the repeated-error test. Compiled against the game jar; no game code here.
 */
public final class EventDrive {
    static Random r;
    static StringBuilder trace;
    static Event[] events;
    static KahluaTable env;
    static LuaCaller caller;
    static KahluaThread thread;
    static int depth, made;

    static LuaClosure handler(int id) throws Exception {
        return (LuaClosure) thread.call(LuaCompiler.loadstring("return function(a) act(" + id + ") end", "h" + id + ".lua", env), null, null, null);
    }

    static void act(int id) throws Exception {
        Event ev = current;
        ArrayList<LuaClosure> list = ev.callbacks;
        int k = r.nextInt(100);
        if (k < 8) {
            // remove the handler with this id (itself) - find by identity of the running closure is not
            // possible from here, so remove the one at a random place that the loop just called or another
            if (!list.isEmpty()) list.remove(r.nextInt(list.size()));
        } else if (k < 16 && list.size() < 50) list.add(handler(made++));
        else if (k < 19 && !list.isEmpty() && list.size() < 50) list.add(list.get(r.nextInt(list.size())));
        else if (k < 24 && depth < 3) {
            Event prev = current;
            current = events[r.nextInt(3)];
            depth++;
            current.trigger(env, caller, new Object[] {-1});
            depth--;
            current = prev;
        }
    }

    static Event current;

    /** same as run, keeping track of which event is firing */
    public static String runAll(long seed, int fires) throws Exception {
        J2SEPlatform p = new J2SEPlatform();
        env = p.newEnvironment();
        thread = new KahluaThread(p, env);
        LuaManager.thread = thread; // Event.trigger runs handlers on the game's Lua thread
        thread.debugOwnerThread = Thread.currentThread();
        caller = new LuaCaller(new KahluaConverterManager());
        r = new Random(seed);
        trace = new StringBuilder();
        depth = 0;
        made = 0;
        env.rawset("act", (JavaFunction) (LuaCallFrame f, int n) -> {
            int id = ((Double) f.get(0)).intValue();
            trace.append(id).append(',');
            try {
                act(id);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
            return 0;
        });
        events = new Event[3];
        for (int e = 0; e < 3; e++) {
            events[e] = new Event("OnCookieTest" + e, e);
            for (int i = 0; i < 15 + 10 * e; i++) events[e].callbacks.add(handler(made++));
        }
        for (int k = 0; k < fires; k++) {
            current = events[k % 3];
            current.trigger(env, caller, new Object[] {k});
        }
        return trace.toString();
    }

    /** a Lua handler that fails every time, fired n times */
    public static void errors(int n) throws Exception {
        J2SEPlatform p = new J2SEPlatform();
        env = p.newEnvironment();
        thread = new KahluaThread(p, env);
        LuaManager.thread = thread;
        thread.debugOwnerThread = Thread.currentThread();
        caller = new LuaCaller(new KahluaConverterManager());
        LuaClosure bad = (LuaClosure) thread.call(LuaCompiler.loadstring(
            "return function(a) local t = nil; return t.getItems end", "CookieBadHandler.lua", env), null, null, null);
        Event ev = new Event("OnCookieBad", 9);
        ev.callbacks.add(bad);
        for (int i = 0; i < n; i++) ev.trigger(env, caller, new Object[] {i});
    }
}
