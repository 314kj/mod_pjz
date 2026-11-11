# Writes day.rgba (the test picture) and ref_golden.rgba (the "golden" look drawn by the
# shader files through Mesa's OpenGL) plus the shader files into a folder, for ShaderTest.
# Needs: pip install PyOpenGL pillow numpy lupa; Mesa (EGL). usage: python3 make_reference.py <out dir>
import os, sys, shutil
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
import scene
scene.scene().save(os.path.join(out, 'day.png'))
import glsl_render as g
import numpy as np
from PIL import Image
g.ctx()
prog = g.compile_prog()
golden = [l for l in g.looks() if l['id'] == 'golden'][0]
day = Image.open(os.path.join(out, 'day.png'))
img, err = g.render(prog, day, golden, q=2)
assert err == 0
open(os.path.join(out, 'day.rgba'), 'wb').write(np.asarray(day.convert('RGBA'))[::-1].tobytes())
open(os.path.join(out, 'ref_golden.rgba'), 'wb').write(np.asarray(img.convert('RGBA'))[::-1].tobytes())
for n in ('cookie_post.vert', 'cookie_post.frag'):
    shutil.copy(g.MOD + 'shaders/' + n, out)
print('written to', out)
