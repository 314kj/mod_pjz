package cookie.slicer.helper;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Reads one class file and points chosen method calls at static methods in a hook class.
 *
 * Only same-size edits are made: an invokevirtual/invokestatic keeps its place and its
 * length, and gets a new constant-pool entry (appended at the end of the pool). Nothing
 * else in the class moves, so stack map frames, exception tables and line numbers stay
 * valid. The replacement takes the same values from the stack (the object the method
 * was called on becomes the first argument) and returns the same type.
 *
 * Every call to change must be found exactly the expected number of times, otherwise
 * nothing in the class is changed (see ShaderPatcher).
 */
final class ClassPatch {
    static final int INVOKEVIRTUAL = 0xb6;
    static final int INVOKESTATIC = 0xb8;

    /** One kind of call to swap. */
    static final class Redirect {
        final String inMethod;   // name of the method that contains the call
        final String inDesc;     // its descriptor
        final int opcode;        // INVOKEVIRTUAL or INVOKESTATIC, as it is now
        final String owner, name, desc; // the method called now
        final String ldc;        // when set: the call's first argument must be this String constant (ldc; aload; invoke)
        final int expected;      // how many such calls must be there
        final String newName, newDesc;  // static method in Hooks
        int found;

        Redirect(String inMethod, String inDesc, int opcode, String owner, String name, String desc,
                 String ldc, int expected, String newName, String newDesc) {
            this.inMethod = inMethod; this.inDesc = inDesc; this.opcode = opcode;
            this.owner = owner; this.name = name; this.desc = desc; this.ldc = ldc;
            this.expected = expected; this.newName = newName; this.newDesc = newDesc;
        }

        String label() {
            return inMethod + ": " + owner.substring(owner.lastIndexOf('/') + 1) + "." + name
                + (ldc != null ? "(\"" + ldc + "\")" : "");
        }
    }

    private final byte[] in;
    private int cpCount;
    private int[] cpPos;
    private int cpEnd;
    private int next;
    private final ByteArrayOutputStream extra = new ByteArrayOutputStream();
    private final Map<String, Integer> added = new HashMap<>();
    private final List<int[]> edits = new ArrayList<>(); // {position, new opcode, new cp index}

    ClassPatch(byte[] in) {
        this.in = in;
        if (in.length < 10 || u4(0) != 0xCAFEBABEL) throw new IllegalStateException("not a class file");
        readPool();
    }

    int majorVersion() { return u2(6); }

    // ---------------------------------------------------------------- reading

    private int u1(int p) { return in[p] & 0xff; }
    private int u2(int p) { return ((in[p] & 0xff) << 8) | (in[p + 1] & 0xff); }
    private long u4(int p) { return ((long) u2(p) << 16) | u2(p + 2); }
    private int s4(int p) { return (int) u4(p); }

    private void readPool() {
        cpCount = u2(8);
        cpPos = new int[cpCount];
        int p = 10;
        for (int i = 1; i < cpCount; i++) {
            cpPos[i] = p;
            int tag = u1(p);
            switch (tag) {
                case 1: p += 3 + u2(p + 1); break;                     // Utf8
                case 3: case 4: p += 5; break;                          // Integer, Float
                case 5: case 6: p += 9; i++; break;                     // Long, Double (two slots)
                case 7: case 8: case 16: case 19: case 20: p += 3; break; // Class, String, MethodType, Module, Package
                case 9: case 10: case 11: case 12: case 17: case 18: p += 5; break; // refs, NameAndType, Dynamic, InvokeDynamic
                case 15: p += 4; break;                                 // MethodHandle
                default: throw new IllegalStateException("unknown constant tag " + tag + " at " + p);
            }
        }
        cpEnd = p;
        next = cpCount;
    }

    private int tag(int idx) { return idx > 0 && idx < cpCount && cpPos[idx] != 0 ? u1(cpPos[idx]) : -1; }

    private String utf8(int idx) {
        if (tag(idx) != 1) throw new IllegalStateException("constant " + idx + " is not Utf8");
        int p = cpPos[idx];
        return new String(in, p + 3, u2(p + 1), StandardCharsets.UTF_8);
    }

    private String className(int idx) {
        if (tag(idx) != 7) throw new IllegalStateException("constant " + idx + " is not a class");
        return utf8(u2(cpPos[idx] + 1));
    }

    /** {owner, name, desc} of a Methodref, or null if idx is something else. */
    private String[] methodRef(int idx) {
        if (tag(idx) != 10) return null;
        int p = cpPos[idx];
        int nat = u2(p + 3);
        if (tag(nat) != 12) return null;
        int q = cpPos[nat];
        return new String[] { className(u2(p + 1)), utf8(u2(q + 1)), utf8(u2(q + 3)) };
    }

    private String stringConst(int idx) {
        return tag(idx) == 8 ? utf8(u2(cpPos[idx] + 1)) : null;
    }

    // ---------------------------------------------------------------- finding calls

    /** Finds the calls; returns the patched class, or throws if a call is missing or extra. */
    byte[] apply(List<Redirect> redirects, String hooksClass) {
        int p = cpEnd + 6;                       // access_flags, this_class, super_class
        p += 2 + 2 * u2(p);                      // interfaces
        int fields = u2(p); p += 2;
        for (int i = 0; i < fields; i++) p = skipMember(p);
        int methods = u2(p); p += 2;
        for (int i = 0; i < methods; i++) {
            String mName = utf8(u2(p + 2));
            String mDesc = utf8(u2(p + 4));
            int attrs = u2(p + 6);
            int a = p + 8;
            for (int j = 0; j < attrs; j++) {
                int len = s4(a + 2);
                if ("Code".equals(utf8(u2(a)))) {
                    int codeLen = s4(a + 10);
                    scan(a + 14, codeLen, mName, mDesc, redirects, hooksClass);
                }
                a += 6 + len;
            }
            p = a;
        }
        StringBuilder bad = new StringBuilder();
        for (Redirect r : redirects) {
            if (r.found != r.expected) {
                if (bad.length() > 0) bad.append("; ");
                bad.append(r.label()).append(" found ").append(r.found).append(", expected ").append(r.expected);
            }
        }
        if (bad.length() > 0) throw new IllegalStateException(bad.toString());
        return build();
    }

    private int skipMember(int p) {
        int attrs = u2(p + 6);
        int a = p + 8;
        for (int j = 0; j < attrs; j++) a += 6 + s4(a + 2);
        return a;
    }

    private void scan(int start, int len, String mName, String mDesc, List<Redirect> redirects, String hooksClass) {
        boolean wanted = false;
        for (Redirect r : redirects) if (r.inMethod.equals(mName) && r.inDesc.equals(mDesc)) wanted = true;
        if (!wanted) return;

        int pc = 0;
        int op1 = -1, op2 = -1;          // the two previous opcodes (op1 = just before)
        String str1 = null, str2 = null; // String constant they pushed, if ldc
        while (pc < len) {
            int at = start + pc;
            int op = u1(at);
            int size;
            String str = null;
            switch (op) {
                case 0x10: case 0xa9: case 0xbc: size = 2; break;              // bipush, ret, newarray
                case 0x12: size = 2; str = stringConst(u1(at + 1)); break;      // ldc
                case 0x13: size = 3; str = stringConst(u2(at + 1)); break;      // ldc_w
                case 0x11: case 0x14: case 0x84: case 0xbb: case 0xbd: case 0xc0: case 0xc1:
                case 0xb2: case 0xb3: case 0xb4: case 0xb5: case 0xb6: case 0xb7: case 0xb8:
                case 0xc6: case 0xc7: size = 3; break;
                case 0xb9: case 0xba: case 0xc8: case 0xc9: size = 5; break;    // invokeinterface, invokedynamic, goto_w, jsr_w
                case 0xc5: size = 4; break;                                     // multianewarray
                case 0xc4: size = u1(at + 1) == 0x84 ? 6 : 4; break;            // wide
                case 0xaa: {                                                    // tableswitch
                    int q = start + ((pc + 4) & ~3);
                    int low = s4(q + 4), high = s4(q + 8);
                    size = (q - at) + 12 + 4 * (high - low + 1);
                    break;
                }
                case 0xab: {                                                    // lookupswitch
                    int q = start + ((pc + 4) & ~3);
                    size = (q - at) + 8 + 8 * s4(q + 4);
                    break;
                }
                default:
                    if ((op >= 0x15 && op <= 0x19) || (op >= 0x36 && op <= 0x3a)) size = 2; // loads/stores with index
                    else if (op >= 0x99 && op <= 0xa8) size = 3;                          // if*, goto, jsr
                    else if (op > 0xc9) throw new IllegalStateException("unknown opcode " + op + " in " + mName);
                    else size = 1;
            }
            if (op == INVOKEVIRTUAL || op == INVOKESTATIC) {
                String[] ref = methodRef(u2(at + 1));
                if (ref != null) {
                    for (Redirect r : redirects) {
                        if (!r.inMethod.equals(mName) || !r.inDesc.equals(mDesc) || r.opcode != op) continue;
                        if (!r.owner.equals(ref[0]) || !r.name.equals(ref[1]) || !r.desc.equals(ref[2])) continue;
                        if (r.ldc != null) {
                            boolean aload1 = op1 == 0x19 || (op1 >= 0x2a && op1 <= 0x2d);
                            boolean ldc2 = (op2 == 0x12 || op2 == 0x13) && r.ldc.equals(str2);
                            if (!aload1 || !ldc2) continue;
                        }
                        r.found++;
                        edits.add(new int[] { at, INVOKESTATIC, methodref(hooksClass, r.newName, r.newDesc) });
                    }
                }
            }
            op2 = op1; str2 = str1;
            op1 = op; str1 = str;
            pc += size;
        }
        if (pc != len) throw new IllegalStateException("code walk overran in " + mName);
    }

    // ---------------------------------------------------------------- adding constants

    private int put(String key, byte[] entry) {
        Integer have = added.get(key);
        if (have != null) return have;
        if (next >= 0xffff) throw new IllegalStateException("constant pool full");
        extra.write(entry, 0, entry.length);
        int idx = next++;
        added.put(key, idx);
        return idx;
    }

    private int utf8Const(String s) {
        byte[] b = s.getBytes(StandardCharsets.UTF_8); // our names are ASCII, so this is valid modified UTF-8
        byte[] e = new byte[3 + b.length];
        e[0] = 1; e[1] = (byte) (b.length >> 8); e[2] = (byte) b.length;
        System.arraycopy(b, 0, e, 3, b.length);
        return put("U:" + s, e);
    }

    private static byte[] two(int tag, int a) { return new byte[] { (byte) tag, (byte) (a >> 8), (byte) a }; }
    private static byte[] four(int tag, int a, int b) {
        return new byte[] { (byte) tag, (byte) (a >> 8), (byte) a, (byte) (b >> 8), (byte) b };
    }

    private int methodref(String owner, String name, String desc) {
        int cls = put("C:" + owner, two(7, utf8Const(owner)));
        int nat = put("N:" + name + desc, four(12, utf8Const(name), utf8Const(desc)));
        return put("M:" + owner + "." + name + desc, four(10, cls, nat));
    }

    private byte[] build() {
        byte[] add = extra.toByteArray();
        byte[] out = new byte[in.length + add.length];
        System.arraycopy(in, 0, out, 0, 8);
        out[8] = (byte) (next >> 8);
        out[9] = (byte) next;
        System.arraycopy(in, 10, out, 10, cpEnd - 10);
        System.arraycopy(add, 0, out, cpEnd, add.length);
        System.arraycopy(in, cpEnd, out, cpEnd + add.length, in.length - cpEnd);
        for (int[] e : edits) {
            int at = e[0] + add.length;
            out[at] = (byte) e[1];
            out[at + 1] = (byte) (e[2] >> 8);
            out[at + 2] = (byte) e[2];
        }
        return out;
    }
}
