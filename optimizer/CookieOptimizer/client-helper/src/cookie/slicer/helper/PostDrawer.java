package cookie.slicer.helper;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

import org.lwjgl.opengl.GL;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL33;
import org.lwjgl.opengl.GLCapabilities;

import zombie.core.textures.TextureDraw;

/**
 * Runs on the game's render thread, right after the game has drawn the world picture
 * through its own screen shader (and before any window):
 *   1. copies the picture into a texture (and makes smaller copies when glow is on),
 *   2. draws it back over the same place through cookie_post.frag.
 * Every OpenGL setting it touches is put back the way it was. If anything goes wrong,
 * the look stops for this session and the game keeps drawing as usual.
 * It also reads the graphics card's name, OpenGL version and free video memory, and
 * times its own pass on the graphics card (shown as "ms per frame" in the mod).
 *
 * Video memory: one texture the size of the screen, plus a third more for the smaller
 * copies (1920x1080: about 11 MB). No extra RAM in the PC.
 * Copyright (c) AKA / Cookie Cheetah. All rights reserved.
 */
public final class PostDrawer extends TextureDraw.GenericDrawer {
    static final PostDrawer INSTANCE = new PostDrawer();

    // OpenGL numbers not in the classes above
    private static final int CLAMP_TO_EDGE = 0x812F;
    private static final int PIXEL_UNPACK_BUFFER = 0x88EC, PIXEL_UNPACK_BUFFER_BINDING = 0x88EF;
    private static final int GPU_MEMORY_TOTAL_NVX = 0x9048, GPU_MEMORY_FREE_NVX = 0x9049;
    private static final int TEXTURE_FREE_MEMORY_ATI = 0x87FC;
    private static final int ALPHA_TEST = 0x0BC0;

    /** for the self-test only: {vertex source, fragment source} */
    static volatile String[] testSources;

    private int prog, tex, texW, texH;
    private int uTex, uRes, uTime, uSplit, uMix, uLevels, uA, uB, uC, uD, uE;
    private boolean timer;
    private final int[] queries = new int[3];
    private final boolean[] pending = new boolean[3];
    private int nextQuery, frames;
    private final long started = System.nanoTime();

    private PostDrawer() {}

    @Override
    public void render() {
        try {
            draw();
        } catch (Throwable t) {
            ShaderState.fail("draw: " + t);
        }
    }

    private void draw() {
        if (!ShaderState.infoDone) info();
        ShaderState.Settings s = ShaderState.settings;
        if (!s.on || ShaderState.error != null) return;
        if (prog == 0 && !compile()) return;

        int[] vp = new int[4];
        GL11.glGetIntegerv(GL11.GL_VIEWPORT, vp);
        int x = vp[0], y = vp[1], w = vp[2], h = vp[3];
        if (w <= 0 || h <= 0) return;
        int levels = s.levels();

        // what this pass changes, to put back afterwards
        int oldProgram = GL11.glGetInteger(GL20.GL_CURRENT_PROGRAM);
        int oldActive = GL11.glGetInteger(GL13.GL_ACTIVE_TEXTURE);
        int drawFb = GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING);
        int readFb = GL11.glGetInteger(GL30.GL_READ_FRAMEBUFFER_BINDING);
        GL13.glActiveTexture(GL13.GL_TEXTURE0);
        GL11.glPushAttrib(GL11.GL_ENABLE_BIT | GL11.GL_COLOR_BUFFER_BIT | GL11.GL_DEPTH_BUFFER_BIT
            | GL11.GL_STENCIL_BUFFER_BIT | GL11.GL_TEXTURE_BIT | GL11.GL_SCISSOR_BIT | GL11.GL_POLYGON_BIT);
        int query = beginTimer();
        try {
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, texture(w, h));
            // the picture the game has just drawn
            if (readFb != drawFb) GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, drawFb);
            GL11.glCopyTexSubImage2D(GL11.GL_TEXTURE_2D, 0, 0, 0, x, y, w, h);
            if (readFb != drawFb) GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, readFb);
            if (levels > 0) {
                GL30.glGenerateMipmap(GL11.GL_TEXTURE_2D);
                GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_LINEAR_MIPMAP_LINEAR);
            } else {
                GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_LINEAR);
            }
            // draw it back through the look, over the same place
            GL11.glDisable(GL11.GL_BLEND);
            GL11.glDisable(GL11.GL_DEPTH_TEST);
            GL11.glDisable(GL11.GL_STENCIL_TEST);
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            GL11.glDisable(GL11.GL_CULL_FACE);
            GL11.glDisable(ALPHA_TEST);
            GL11.glColorMask(true, true, true, true);
            GL20.glUseProgram(prog);
            GL20.glUniform1i(uTex, 0);
            GL20.glUniform2f(uRes, w, h);
            GL20.glUniform1f(uTime, (float) (((System.nanoTime() - started) / 1e9) % 1000.0));
            GL20.glUniform1f(uSplit, s.split);
            GL20.glUniform1f(uMix, s.mix);
            GL20.glUniform1f(uLevels, levels);
            GL20.glUniform4f(uA, s.exp, s.con, s.sat, s.warm);
            GL20.glUniform4f(uB, s.bloom, s.thr, s.glow, s.tone);
            GL20.glUniform4f(uC, s.vig, s.sharp, s.grain, s.fade);
            GL20.glUniform4f(uD, s.sh[0], s.sh[1], s.sh[2], s.sh[3]);
            GL20.glUniform4f(uE, s.hi[0], s.hi[1], s.hi[2], s.hi[3]);
            GL11.glBegin(GL11.GL_QUADS);
            GL11.glTexCoord2f(0f, 0f); GL11.glVertex2f(-1f, -1f);
            GL11.glTexCoord2f(1f, 0f); GL11.glVertex2f(1f, -1f);
            GL11.glTexCoord2f(1f, 1f); GL11.glVertex2f(1f, 1f);
            GL11.glTexCoord2f(0f, 1f); GL11.glVertex2f(-1f, 1f);
            GL11.glEnd();
        } finally {
            if (query != 0) GL15.glEndQuery(GL33.GL_TIME_ELAPSED);
            GL20.glUseProgram(oldProgram);
            GL11.glPopAttrib();
            GL13.glActiveTexture(oldActive);
        }
        ShaderState.lastPassMs = System.currentTimeMillis();
        if ((++frames & 127) == 0) videoMemory();
    }

    // ---------------------------------------------------------------- setup

    private int texture(int w, int h) {
        if (tex == 0) tex = GL11.glGenTextures();
        if (w != texW || h != texH) {
            GL11.glBindTexture(GL11.GL_TEXTURE_2D, tex);
            int unpack = GL11.glGetInteger(PIXEL_UNPACK_BUFFER_BINDING);
            if (unpack != 0) GL15.glBindBuffer(PIXEL_UNPACK_BUFFER, 0); // "no pixels" must not read a buffer
            GL11.glTexImage2D(GL11.GL_TEXTURE_2D, 0, GL11.GL_RGBA8, w, h, 0, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, (ByteBuffer) null);
            if (unpack != 0) GL15.glBindBuffer(PIXEL_UNPACK_BUFFER, unpack);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, CLAMP_TO_EDGE);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, CLAMP_TO_EDGE);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_LINEAR);
            texW = w;
            texH = h;
        }
        return tex;
    }

    private boolean compile() {
        if (ShaderState.compiled == 0) return false;
        GLCapabilities caps = GL.getCapabilities();
        if (!caps.OpenGL30) {
            ShaderState.compiled = 0;
            ShaderState.fail("OpenGL 3.0 or newer needed");
            return false;
        }
        timer = caps.OpenGL33 || caps.GL_ARB_timer_query;
        int v = 0, f = 0, p = 0;
        try {
            v = shader(GL20.GL_VERTEX_SHADER, source("cookie_post.vert", 0));
            f = shader(GL20.GL_FRAGMENT_SHADER, source("cookie_post.frag", 1));
            p = GL20.glCreateProgram();
            GL20.glAttachShader(p, v);
            GL20.glAttachShader(p, f);
            GL20.glLinkProgram(p);
            if (GL20.glGetProgrami(p, GL20.GL_LINK_STATUS) == 0) {
                throw new IllegalStateException("link: " + GL20.glGetProgramInfoLog(p));
            }
            uTex = GL20.glGetUniformLocation(p, "uTex");
            uRes = GL20.glGetUniformLocation(p, "uRes");
            uTime = GL20.glGetUniformLocation(p, "uTime");
            uSplit = GL20.glGetUniformLocation(p, "uSplit");
            uMix = GL20.glGetUniformLocation(p, "uMix");
            uLevels = GL20.glGetUniformLocation(p, "uLevels");
            uA = GL20.glGetUniformLocation(p, "uA");
            uB = GL20.glGetUniformLocation(p, "uB");
            uC = GL20.glGetUniformLocation(p, "uC");
            uD = GL20.glGetUniformLocation(p, "uD");
            uE = GL20.glGetUniformLocation(p, "uE");
            if (timer) for (int i = 0; i < queries.length; i++) queries[i] = GL15.glGenQueries();
            prog = p;
            ShaderState.compiled = 1;
            System.out.println("[CookieSlicerHelper] screen looks ready (" + ShaderState.gpu + ")");
            return true;
        } catch (Throwable t) {
            if (p != 0) GL20.glDeleteProgram(p);
            ShaderState.compiled = 0;
            ShaderState.fail("shader: " + t.getMessage());
            return false;
        } finally {
            if (v != 0) GL20.glDeleteShader(v); // kept alive by the program while it is in use
            if (f != 0) GL20.glDeleteShader(f);
        }
    }

    private static int shader(int type, String src) {
        int s = GL20.glCreateShader(type);
        GL20.glShaderSource(s, src);
        GL20.glCompileShader(s);
        if (GL20.glGetShaderi(s, GL20.GL_COMPILE_STATUS) == 0) {
            String log = GL20.glGetShaderInfoLog(s);
            GL20.glDeleteShader(s);
            throw new IllegalStateException("compile: " + log);
        }
        return s;
    }

    /** the mod's copy first (it updates with the Workshop), else the copy in this jar */
    static String source(String name, int testIndex) throws IOException {
        String[] test = testSources;
        if (test != null) return test[testIndex];
        try {
            String path = zombie.ZomboidFileSystem.instance.getString("media/shaders/" + name);
            File f = new File(path);
            if (path != null && f.isFile()) {
                return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
            }
        } catch (Throwable ignored) {
            // the copy in the jar below
        }
        try (InputStream in = PostDrawer.class.getResourceAsStream(name)) {
            if (in == null) throw new IOException(name + " missing");
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    // ---------------------------------------------------------------- the graphics card

    private void info() {
        ShaderState.infoDone = true;
        ShaderState.gpu = GL11.glGetString(GL11.GL_RENDERER);
        ShaderState.vendor = GL11.glGetString(GL11.GL_VENDOR);
        ShaderState.glVersion = GL11.glGetString(GL11.GL_VERSION);
        videoMemory();
    }

    private static void videoMemory() {
        GLCapabilities caps = GL.getCapabilities();
        if (caps.GL_NVX_gpu_memory_info) {
            ShaderState.vramTotalKb = GL11.glGetInteger(GPU_MEMORY_TOTAL_NVX);
            ShaderState.vramFreeKb = GL11.glGetInteger(GPU_MEMORY_FREE_NVX);
        } else if (caps.GL_ATI_meminfo) {
            int[] v = new int[4];
            GL11.glGetIntegerv(TEXTURE_FREE_MEMORY_ATI, v);
            ShaderState.vramFreeKb = v[0];
        }
    }

    /** times the pass on the graphics card; results are read a few frames later */
    private int beginTimer() {
        if (!timer) return 0;
        if (GL15.glGetQueryi(GL33.GL_TIME_ELAPSED, GL15.GL_CURRENT_QUERY) != 0) return 0; // the game is timing something
        int slot = nextQuery;
        nextQuery = (nextQuery + 1) % queries.length;
        int id = queries[slot];
        if (pending[slot]) {
            if (GL15.glGetQueryObjecti(id, GL15.GL_QUERY_RESULT_AVAILABLE) == 0) return 0;
            double ms = GL33.glGetQueryObjecti64(id, GL15.GL_QUERY_RESULT) / 1e6;
            double avg = ShaderState.msAvg;
            ShaderState.msAvg = avg < 0 ? ms : avg * 0.95 + ms * 0.05;
            pending[slot] = false;
        }
        GL15.glBeginQuery(GL33.GL_TIME_ELAPSED, id);
        pending[slot] = true;
        return id;
    }
}
