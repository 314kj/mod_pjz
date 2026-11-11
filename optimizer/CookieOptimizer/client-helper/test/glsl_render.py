# renders the Cookie Slicer looks with the real shader files in a desktop OpenGL
# (compatibility profile) context, the same calls the helper makes in the game
import os, sys, ctypes, json
os.environ['PYOPENGL_PLATFORM'] = 'egl'
os.environ.setdefault('EGL_PLATFORM', 'surfaceless')
from OpenGL import EGL, GL
import numpy as np
from PIL import Image
from lupa import lua51
MOD = '/mnt/user-data/outputs/CookieSlicer/Contents/mods/CookieSlicer/42/media/'
W, H = 960, 540

def ctx():
    d = EGL.eglGetDisplay(EGL.EGL_DEFAULT_DISPLAY)
    EGL.eglInitialize(d, None, None)
    attrs = (EGL.EGLint * 13)(EGL.EGL_SURFACE_TYPE, EGL.EGL_PBUFFER_BIT, EGL.EGL_RED_SIZE, 8, EGL.EGL_GREEN_SIZE, 8,
                              EGL.EGL_BLUE_SIZE, 8, EGL.EGL_ALPHA_SIZE, 8, EGL.EGL_RENDERABLE_TYPE, EGL.EGL_OPENGL_BIT, EGL.EGL_NONE)
    cfg = EGL.EGLConfig(); n = EGL.EGLint()
    EGL.eglChooseConfig(d, attrs, ctypes.pointer(cfg), 1, ctypes.pointer(n))
    s = EGL.eglCreatePbufferSurface(d, cfg, (EGL.EGLint * 5)(EGL.EGL_WIDTH, W, EGL.EGL_HEIGHT, H, EGL.EGL_NONE))
    EGL.eglBindAPI(EGL.EGL_OPENGL_API)
    c = EGL.eglCreateContext(d, cfg, EGL.EGL_NO_CONTEXT, None)
    EGL.eglMakeCurrent(d, s, s, c)

def compile_prog():
    def sh(kind, path):
        src = open(path).read()
        o = GL.glCreateShader(kind)
        GL.glShaderSource(o, src)
        GL.glCompileShader(o)
        if not GL.glGetShaderiv(o, GL.GL_COMPILE_STATUS):
            raise SystemExit('compile failed ' + path + '\n' + GL.glGetShaderInfoLog(o).decode())
        log = GL.glGetShaderInfoLog(o)
        if log: print('log', path, log.decode())
        return o
    p = GL.glCreateProgram()
    GL.glAttachShader(p, sh(GL.GL_VERTEX_SHADER, MOD + 'shaders/cookie_post.vert'))
    GL.glAttachShader(p, sh(GL.GL_FRAGMENT_SHADER, MOD + 'shaders/cookie_post.frag'))
    GL.glLinkProgram(p)
    if not GL.glGetProgramiv(p, GL.GL_LINK_STATUS):
        raise SystemExit('link failed ' + GL.glGetProgramInfoLog(p).decode())
    return p

def looks():
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute('function isServer() return false end; Events = setmetatable({}, {__index = function(t, k) local e = {Add = function() end}; t[k] = e; return e end}); CookieSlicer = { settings = {}, pc = {} }')
    L.execute(open(MOD + 'lua/client/CookieSlicer_Shader.lua').read())
    out = []
    for i in range(1, L.eval('#CookieSlicer.SHADER_LOOKS') + 1):
        l = L.eval('CookieSlicer.SHADER_LOOKS[%d]' % i)
        def v4(t): return [t[1], t[2], t[3], t[4]] if t else [0, 0, 0, 0]
        out.append(dict(id=l.id, off=bool(l.off), p={k: l.p[k] for k in ('mix','exp','con','sat','warm','bloom','vig','sharp','grain')},
                        thr=l.thr or 0.6, glow=l.glow or 0, tone=l.tone or 0, fade=l.fade or 0, sh=v4(l.sh), hi=v4(l.hi)))
    return out

def render(prog, img, look, q=2, split=-1.0, t=0.37):
    # the world picture as the game left it in the frame buffer
    arr = np.asarray(img.convert('RGBA'))[::-1].copy()
    GL.glViewport(0, 0, W, H)
    GL.glWindowPos2i(0, 0) if hasattr(GL, 'glWindowPos2i') else None
    GL.glDrawPixels(W, H, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, arr)
    # helper: copy into a texture, make smaller copies when glow is on, draw the pass
    tex = GL.glGenTextures(1)
    GL.glBindTexture(GL.GL_TEXTURE_2D, tex)
    GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA8, W, H, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, None)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_S, GL.GL_CLAMP_TO_EDGE)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_WRAP_T, GL.GL_CLAMP_TO_EDGE)
    GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR)
    GL.glCopyTexSubImage2D(GL.GL_TEXTURE_2D, 0, 0, 0, 0, 0, W, H)
    p = look['p']
    levels = 0 if q == 0 or p['bloom'] <= 0 else (2 if q == 1 else 4)
    if levels > 0:
        GL.glGenerateMipmap(GL.GL_TEXTURE_2D)
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR_MIPMAP_LINEAR)
    else:
        GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR)
    GL.glUseProgram(prog)
    u = lambda n: GL.glGetUniformLocation(prog, n)
    GL.glUniform1i(u('uTex'), 0)
    GL.glUniform2f(u('uRes'), W, H)
    GL.glUniform1f(u('uTime'), t)
    GL.glUniform1f(u('uSplit'), split)
    GL.glUniform1f(u('uMix'), p['mix'])
    GL.glUniform1f(u('uLevels'), levels)
    GL.glUniform4f(u('uA'), p['exp'], p['con'], p['sat'], p['warm'])
    GL.glUniform4f(u('uB'), p['bloom'], look['thr'], look['glow'], look['tone'])
    GL.glUniform4f(u('uC'), p['vig'], p['sharp'], p['grain'], look['fade'])
    GL.glUniform4f(u('uD'), *look['sh'])
    GL.glUniform4f(u('uE'), *look['hi'])
    GL.glDisable(GL.GL_BLEND)
    GL.glBegin(GL.GL_QUADS)
    for (x, y) in ((0, 0), (1, 0), (1, 1), (0, 1)):
        GL.glTexCoord2f(x, y)
        GL.glVertex2f(x * 2 - 1, y * 2 - 1)
    GL.glEnd()
    GL.glUseProgram(0)
    err = GL.glGetError()
    data = GL.glReadPixels(0, 0, W, H, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE)
    GL.glDeleteTextures([tex])
    out = Image.frombytes('RGBA', (W, H), data).transpose(Image.FLIP_TOP_BOTTOM).convert('RGB')
    return out, err

if __name__ == '__main__':
    ctx()
    print(GL.glGetString(GL.GL_RENDERER).decode(), GL.glGetString(GL.GL_VERSION).decode())
    prog = compile_prog()
    print('compiled and linked')
    here = os.path.dirname(os.path.abspath(__file__))
    day = Image.open(here + '/day.png'); night = Image.open(here + '/night.png')
    L = looks()
    json.dump(L, open(here + '/looks.json', 'w'))
    for lk in L:
        for nm, img in (('day', day), ('night', night)):
            o, err = render(prog, img, lk)
            assert err == 0, err
            o.save(here + '/out_%s_%s.png' % (lk['id'], nm))
    # quality 0 (no glow), compare line
    o, err = render(prog, night, [l for l in L if l['id'] == 'glow'][0], q=0); o.save(here + '/out_glow_night_q0.png')
    o, err = render(prog, day, [l for l in L if l['id'] == 'golden'][0], split=0.5); o.save(here + '/out_golden_split.png')
    nat, _ = render(prog, day, [l for l in L if l['id'] == 'natural'][0])
    diff = np.abs(np.asarray(nat).astype(int) - np.asarray(day.convert('RGB')).astype(int)).max()
    print('natural (mix 0) max difference from the input:', diff)
    print('looks:', [l['id'] for l in L])
