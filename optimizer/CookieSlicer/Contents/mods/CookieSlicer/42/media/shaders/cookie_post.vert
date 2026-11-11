#version 120
// Cookie Slicer screen look: full-screen pass after the game's own screen shader.
// Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
varying vec2 vUv;

void main() {
    vUv = gl_MultiTexCoord0.xy;
    gl_Position = vec4(gl_Vertex.xy, 0.0, 1.0);
}
