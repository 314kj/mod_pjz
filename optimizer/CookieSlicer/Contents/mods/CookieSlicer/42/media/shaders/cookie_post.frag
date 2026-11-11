#version 120
// Cookie Slicer screen look: colour grading, light glow, vignette, sharpening and film
// grain on the finished picture of the world (windows are drawn after it, so they
// keep their colours). Runs after the game's own screen shader, which stays as it is.
// Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
//
// uTex     the world picture this frame (with smaller copies when glow is on)
// uA       exposure (stops), contrast, saturation, warmth (-1 cool .. 1 warm)
// uB       glow strength, glow threshold, night glow (lights stand out in the dark), film curve
// uC       vignette, sharpen, grain, fade (lifted blacks)
// uD, uE   shadow tint rgb + amount, highlight tint rgb + amount
// uMix     how much of the look (0 = picture as the game drew it)
// uLevels  how many smaller copies the glow may use (0 = no glow)
// uSplit   compare line (part of the width; left = before, right = after), < 0 = none

uniform sampler2D uTex;
uniform vec2 uRes;
uniform float uTime;
uniform float uSplit;
uniform float uMix;
uniform float uLevels;
uniform vec4 uA;
uniform vec4 uB;
uniform vec4 uC;
uniform vec4 uD;
uniform vec4 uE;
varying vec2 vUv;

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// smooth film curve (bright parts roll off instead of clipping)
vec3 filmCurve(vec3 x) {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 px = 1.0 / uRes;
    vec3 src = texture2D(uTex, vUv, -0.5).rgb;
    vec3 c = src;

    // sharpen: push each pixel away from the average of its four neighbours
    if (uC.y > 0.0) {
        vec3 n = texture2D(uTex, vUv + vec2(px.x, 0.0), -0.5).rgb
               + texture2D(uTex, vUv - vec2(px.x, 0.0), -0.5).rgb
               + texture2D(uTex, vUv + vec2(0.0, px.y), -0.5).rgb
               + texture2D(uTex, vUv - vec2(0.0, px.y), -0.5).rgb;
        c = clamp(c + (c - n * 0.25) * uC.y * 1.5, 0.0, 1.0);
    }

    // whole picture average from the smallest copy (only there when glow is on)
    float avg = uLevels > 0.5 ? luma(texture2D(uTex, vec2(0.5), 12.0).rgb) : 0.4;

    // glow: blurred light from the smaller copies, only what is brighter than the threshold
    if (uLevels > 0.5 && uB.x > 0.0) {
        float night = clamp(1.0 - avg * 3.5, 0.0, 1.0);
        vec3 b = vec3(0.0);
        float w = 0.0;
        for (int i = 1; i <= 4; i++) {
            if (float(i) > uLevels) break;
            b += texture2D(uTex, vUv, float(i) + 1.0).rgb * float(i);
            w += float(i);
        }
        b /= max(w, 1.0);
        float thr = mix(uB.y, uB.y * 0.45, night * uB.z);
        vec3 bright = max(b - vec3(thr), 0.0) / max(1.0 - thr, 0.05);
        float bl = luma(bright);
        bright = max(mix(vec3(bl), bright, 1.0 + uB.z * 0.4), 0.0);   // coloured lights stay coloured
        c += bright * uB.x * (1.0 + night * uB.z * 1.5);
    }

    // exposure and film curve, worked out in linear light
    vec3 lin = pow(max(c, 0.0), vec3(2.2)) * exp2(uA.x);
    if (uB.w > 0.0) lin = mix(lin, filmCurve(lin * 0.8), uB.w);
    c = pow(lin, vec3(1.0 / 2.2));

    // contrast around the picture's own middle (so night scenes keep their detail)
    c = mix(vec3(clamp(avg, 0.15, 0.5)), c, uA.y);
    float l = luma(c);
    c = mix(vec3(l), c, uA.z);
    c *= vec3(1.0 + uA.w * 0.10, 1.0 + uA.w * 0.02, 1.0 - uA.w * 0.12);

    // colour in the shadows and in the highlights
    float l2 = clamp(luma(c), 0.0, 1.0);
    c += uD.rgb * uD.a * (1.0 - l2) * 0.25;
    c += uE.rgb * uE.a * l2 * 0.25;

    // fade: lifted blacks like an old print
    c = c * (1.0 - 0.15 * uC.w) + vec3(0.11 * uC.w);

    // vignette (round, also on wide screens)
    vec2 d = vUv - 0.5;
    d.x *= uRes.x / uRes.y;
    c *= mix(1.0, smoothstep(0.95, 0.30, length(d)), uC.x);

    // film grain, moving every frame
    c += (noise(vUv * uRes + fract(uTime) * 91.7) - 0.5) * uC.z * 0.09;

    c = mix(src, clamp(c, 0.0, 1.0), uMix);

    // compare: left of the line = before
    if (uSplit >= 0.0) {
        if (vUv.x < uSplit) c = src;
        if (abs(vUv.x - uSplit) < px.x * 1.5) c = vec3(0.31, 0.96, 0.78);
    }
    gl_FragColor = vec4(c, 1.0);
}
