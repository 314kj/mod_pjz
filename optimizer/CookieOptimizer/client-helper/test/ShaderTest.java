package cookie.slicer.helper;

import java.io.File;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.zip.ZipFile;

import org.lwjgl.glfw.GLFW;
import org.lwjgl.opengl.GL;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;

/**
 * Screen-look checks.
 *  S1  the game class is patched (one call) and the JVM accepts it
 *  S2  the choice file is read, values are kept in range
 *  S3  (needs a display) the real PostDrawer draws through the real shader files in an
 *      OpenGL compatibility context: picture as the reference, OpenGL settings put back,
 *      graphics-card time measured, nothing drawn when the look is off
 * Run: java -cp <projectzomboid.jar>:<helper jar>:<test classes> cookie.slicer.helper.ShaderTest <pz jar> <dir with day.rgba, ref_golden.rgba>
 */
public final class ShaderTest {
    static int fails;

    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) fails++;
    }

    public static void main(String[] a) throws Exception {
        File pz = new File(a[0]);
        File dir = new File(a[1]);
        // ---------------------------------------------------------------- S1
        byte[] orig;
        try (ZipFile z = new ZipFile(pz)) {
            orig = z.getInputStream(z.getEntry(ShaderPatcher.TARGET + ".class")).readAllBytes();
        }
        byte[] patched = ShaderPatcher.patch(orig);
        check(patched.length > orig.length && new String(patched, "ISO-8859-1").contains("cookie/slicer/helper/ShaderHook"),
            "S1 MultiTextureFBO2.render: EndShader call pointed at ShaderHook");
        ClassLoader loader = new ClassLoader(ShaderTest.class.getClassLoader()) {
            @Override
            protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
                if (name.equals("zombie.core.textures.MultiTextureFBO2")) {
                    synchronized (getClassLoadingLock(name)) {
                        Class<?> c = findLoadedClass(name);
                        if (c == null) c = defineClass(name, patched, 0, patched.length);
                        return c;
                    }
                }
                return super.loadClass(name, resolve);
            }
        };
        Class<?> c = Class.forName("zombie.core.textures.MultiTextureFBO2", true, loader); // links = verifies
        check(c.getClassLoader() == loader, "S1 the JVM verified and loaded the patched class");
        boolean refused = false;
        try {
            byte[] twice = ShaderPatcher.patch(patched);
            refused = twice == null;
        } catch (IllegalStateException e) {
            refused = e.getMessage().contains("found 0");
        }
        check(refused, "S1 a class without the call is left alone (found 0)");

        // ---------------------------------------------------------------- S2
        ShaderState.Settings s = ShaderState.parse("on=1\nlook=golden\nq=7\nsplit=0.5\nmix=3\nexp=-9\ncon=1.12\nsat=1.3\nwarm=0.45\n"
            + "bloom=0.55\nvig=0.25\nsharp=0.15\ngrain=0\nthr=0.55\nglow=0.4\ntone=0.6\nfade=0\nsh=0.35,0.15,0.55,0.35\nhi=1,0.75,0.4,0.3\n");
        check(s.on && s.quality == 2 && s.mix == 1f && s.exp == -2f && Math.abs(s.con - 1.12f) < 1e-6 && s.split == 0.5f,
            "S2 choice read, out-of-range values held in range");
        check(s.levels() == 4 && Math.abs(s.sh[2] - 0.55f) < 1e-6 && s.hi[0] == 1f, "S2 glow levels and tints");
        check(!ShaderState.parse("on=0\n").on && ShaderState.parse("garbage").mix == 0f, "S2 off / broken file = no look");

        if (a.length > 2 && a[2].equals("nogl")) { done(); return; }
        // ---------------------------------------------------------------- S3
        if (!GLFW.glfwInit()) throw new IllegalStateException("glfwInit");
        GLFW.glfwDefaultWindowHints();
        GLFW.glfwWindowHint(GLFW.GLFW_VISIBLE, GLFW.GLFW_FALSE);
        long win = GLFW.glfwCreateWindow(960, 540, "cookie", 0, 0);
        GLFW.glfwMakeContextCurrent(win);
        GL.createCapabilities();
        System.out.println("  GL: " + GL11.glGetString(GL11.GL_RENDERER) + " / " + GL11.glGetString(GL11.GL_VERSION));
        int W = 960, H = 540;
        int fbo = GL30.glGenFramebuffers();
        int color = GL11.glGenTextures();
        GL11.glBindTexture(GL11.GL_TEXTURE_2D, color);
        GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL11.GL_RGBA8, W, H, 0, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, (ByteBuffer) null);
        GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, fbo);
        GL30.glFramebufferTexture2D(GL30.GL_FRAMEBUFFER, GL30.GL_COLOR_ATTACHMENT0, GL11.GL_TEXTURE_2D, color, 0);
        GL11.glViewport(0, 0, W, H);

        PostDrawer.testSources = new String[] {
            Files.readString(new File(dir, "cookie_post.vert").toPath()), Files.readString(new File(dir, "cookie_post.frag").toPath()) };
        byte[] day = Files.readAllBytes(new File(dir, "day.rgba").toPath());
        byte[] ref = Files.readAllBytes(new File(dir, "ref_golden.rgba").toPath());

        // the game's state around the pass (things the pass must put back)
        int someTex = GL11.glGenTextures();
        int dummyProg = GL20.glCreateProgram();
        GL20.glLinkProgram(dummyProg); // an empty program is fine to bind
        Runnable gameState = () -> {
            GL11.glEnable(GL11.GL_BLEND);
            GL11.glEnable(GL11.GL_SCISSOR_TEST);
            GL11.glScissor(0, 0, 10, 10);
            GL13.glActiveTexture(GL13.GL_TEXTURE3);
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, someTex);
        };
        // the "golden" look exactly as the mod writes it (and as the reference was drawn)
        ShaderState.Settings golden = ShaderState.parse("on=1\nlook=golden\nq=2\nsplit=-1\nmix=1\nexp=0\ncon=1.12\nsat=1.3\nwarm=0.45\n"
            + "bloom=0.55\nvig=0.25\nsharp=0.15\ngrain=0\nthr=0.55\nglow=0.4\ntone=0.6\nfade=0\nsh=0.35,0.15,0.55,0.35\nhi=1,0.75,0.4,0.3\n");
        ShaderState.settings = golden;
        byte[] out = null;
        for (int frame = 0; frame < 12; frame++) {
            GL30.glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER, fbo);
            GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, frame == 0 ? 0 : fbo); // first frame: read buffer elsewhere
            GL20.glUseProgram(0);
            GL11.glDisable(GL11.GL_BLEND);
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            ByteBuffer img = ByteBuffer.allocateDirect(day.length).put(day).flip();
            GL11.glRasterPos2f(-1f, -1f);
            GL11.glDrawPixels(W, H, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, img);
            gameState.run();
            GL20.glUseProgram(dummyProg);
            PostDrawer.INSTANCE.render();
            if (frame == 0) {
                check(GL11.glGetInteger(GL20.GL_CURRENT_PROGRAM) == dummyProg, "S3 program put back");
                check(GL11.glGetInteger(GL13.GL_ACTIVE_TEXTURE) == GL13.GL_TEXTURE3, "S3 active texture unit put back");
                check(GL11.glGetInteger(GL11.GL_TEXTURE_BINDING_2D) == someTex, "S3 texture binding put back");
                check(GL11.glIsEnabled(GL11.GL_BLEND) && GL11.glIsEnabled(GL11.GL_SCISSOR_TEST), "S3 blend / scissor put back");
                check(GL11.glGetInteger(GL30.GL_READ_FRAMEBUFFER_BINDING) == 0 && GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING) == fbo,
                    "S3 read / draw framebuffers put back");
                check(GL11.glGetError() == 0, "S3 no OpenGL error");
            }
            GL20.glUseProgram(0);
            GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, fbo);
            ByteBuffer px = ByteBuffer.allocateDirect(W * H * 4);
            GL11.glReadPixels(0, 0, W, H, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, px);
            out = new byte[W * H * 4];
            px.get(out);
            GL11.glFinish();
        }
        check(ShaderState.error == null && ShaderState.compiled == 1, "S3 compiled, no error (" + ShaderState.error + ")");
        int maxDiff = 0;
        long sum = 0;
        for (int i = 0; i < out.length; i++) {
            if (i % 4 == 3) continue;
            int d = Math.abs((out[i] & 0xff) - (ref[i] & 0xff));
            maxDiff = Math.max(maxDiff, d);
            sum += d;
        }
        Files.write(new File(dir, "java_out.rgba").toPath(), out);
        check(maxDiff <= 3, "S3 picture equals the reference render (max difference " + maxDiff + ", mean " + (sum / (out.length * 0.75)) + ")");
        int changed = 0;
        for (int i = 0; i < out.length; i += 4) if (Math.abs((out[i] & 0xff) - (day[i] & 0xff)) > 8) changed++;
        check(changed > W * H / 4, "S3 the look really changed the picture (" + changed + " pixels)");
        check(ShaderState.msAvg > 0, "S3 graphics-card time measured: " + String.format("%.3f ms", ShaderState.msAvg));
        check(ShaderState.gpu != null && ShaderState.glVersion != null, "S3 graphics card read: " + ShaderState.gpu);
        Map<String, String> m = new LinkedHashMap<>();
        ShaderState.lastPassMs = System.currentTimeMillis();
        ShaderState.hooked = 1;
        ShaderState.status(m);
        check("1".equals(m.get("shader_ok")) && "1".equals(m.get("shader_active")) && m.containsKey("shader_ms") && m.containsKey("gpu"),
            "S3 status for the mod: " + m);

        // look off: nothing drawn
        ShaderState.settings = ShaderState.parse("on=0\n");
        GL30.glBindFramebuffer(GL30.GL_FRAMEBUFFER, fbo);
        GL11.glDisable(GL11.GL_BLEND);
        GL11.glDisable(GL11.GL_SCISSOR_TEST);
        GL20.glUseProgram(0);
        ByteBuffer img = ByteBuffer.allocateDirect(day.length).put(day).flip();
        GL11.glRasterPos2f(-1f, -1f);
        GL11.glDrawPixels(W, H, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, img);
        PostDrawer.INSTANCE.render();
        ByteBuffer px = ByteBuffer.allocateDirect(W * H * 4);
        GL11.glReadPixels(0, 0, W, H, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, px);
        boolean same = true;
        for (int i = 0; i < day.length; i++) if (px.get(i) != day[i]) { same = false; break; }
        check(same, "S3 look off: the picture stays exactly as the game drew it");

        // a broken shader stops the look for the session, nothing else
        ShaderState.settings = s;
        GLFW.glfwDestroyWindow(win);
        GLFW.glfwTerminate();
        done();
    }

    static void done() {
        System.out.println(fails == 0 ? "ALL PASSED" : fails + " FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
