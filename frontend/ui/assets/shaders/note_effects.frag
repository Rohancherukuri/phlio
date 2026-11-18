// Phlio Notes: animated effects around a note bubble (Bubble Editor).
// One shader, several looks picked by uMode:
//   0 confetti ("congratulations" burst)   1 sparkles   2 hearts
//   3 fireworks   4 glow (aurora halo hugging the bubble)   5 snow   6 fizz
// The canvas is the bubble's box grown by uPad on every side, so particles
// can fly outside the bubble. Output is premultiplied alpha over the UI.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;    // 0-1  canvas size (px)
uniform float uTime;   // 2    seconds
uniform float uMode;   // 3
uniform vec3 uColor;   // 4-6  bubble colour (0-1)
uniform float uPad;    // 7    px between canvas edge and bubble

out vec4 fragColor;

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

vec3 palette(float k) {
  // Party colours, nudged towards the bubble colour.
  vec3 c = 0.55 + 0.45 * cos(6.2831 * (k + vec3(0.0, 0.33, 0.67)));
  return mix(c, uColor, 0.18);
}

float sdRoundBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float heart(vec2 p, float s) {
  p /= s;
  p.y = -p.y + 0.25;
  float a = atan(p.x, p.y) / 3.14159;
  float r = length(p);
  float h = abs(a);
  float d = (13.0 * h - 22.0 * h * h + 10.0 * h * h * h) / (6.0 - 5.0 * h);
  return smoothstep(0.02, -0.02, r - d * 0.5);
}

float star(vec2 p, float s) {
  p = abs(p) / s;
  float d = min(p.x * 6.0 + p.y, p.y * 6.0 + p.x);
  return clamp(1.0 - d, 0.0, 1.0) + 0.6 * exp(-dot(p, p) * 18.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 size = uSize;
  vec2 center = size * 0.5;
  vec2 bubbleHalf = max(center - vec2(uPad), vec2(4.0));
  float unit = min(bubbleHalf.x, bubbleHalf.y);
  float t = uTime;
  vec3 col = vec3(0.0);
  float a = 0.0;
  int mode = int(uMode + 0.5);

  if (mode == 0) {
    // Confetti cannon from under the bubble, every 2.8 s.
    float cycle = 2.8;
    float ct = mod(t, cycle);
    vec2 origin = vec2(center.x, center.y + bubbleHalf.y * 0.6);
    for (int i = 0; i < 46; i++) {
      float fi = float(i);
      float ang = -1.5708 + (hash(fi) - 0.5) * 2.6;
      float spd = (0.9 + 1.4 * hash(fi + 3.1)) * size.y * 0.9;
      vec2 v = vec2(cos(ang), sin(ang)) * spd;
      vec2 pos = origin + v * ct + vec2(0.0, 0.5 * size.y * 2.2 * ct * ct);
      pos.x += sin(ct * 6.0 + fi) * 6.0;
      float rot = ct * (4.0 + 8.0 * hash(fi + 7.0)) + fi;
      vec2 d = frag - pos;
      d = mat2(cos(rot), -sin(rot), sin(rot), cos(rot)) * d;
      float w = 2.4 + 2.0 * hash(fi + 9.0);
      float m = step(abs(d.x), w) * step(abs(d.y), w * 0.45 + 0.8 * abs(sin(rot)));
      float fade = 1.0 - smoothstep(cycle * 0.65, cycle, ct);
      if (m * fade > a) { a = m * fade; col = palette(hash(fi + 1.7)); }
    }
  } else if (mode == 1) {
    // Twinkling stars scattered around the bubble.
    for (int i = 0; i < 18; i++) {
      float fi = float(i);
      vec2 pos = vec2(hash(fi + 0.3), hash(fi + 5.9)) * size;
      float tw = 0.5 + 0.5 * sin(t * (2.0 + 2.0 * hash(fi + 2.2)) + fi * 3.0);
      float s = (4.0 + 6.0 * hash(fi + 8.8)) * tw;
      float m = star(frag - pos, s) * tw;
      if (m > a) { a = min(m, 1.0); col = mix(vec3(1.0), vec3(1.0, 0.85, 0.45), hash(fi + 4.4)); }
    }
  } else if (mode == 2) {
    // Hearts floating up and swaying.
    for (int i = 0; i < 14; i++) {
      float fi = float(i);
      float speed = 0.25 + 0.25 * hash(fi + 1.1);
      float ph = fract(t * speed + hash(fi));
      vec2 pos = vec2(hash(fi + 2.3) * size.x + sin(t * 2.0 + fi) * 8.0, size.y * (1.05 - ph * 1.1));
      float s = 6.0 + 7.0 * hash(fi + 6.6);
      float m = heart(frag - pos, s) * (1.0 - ph) * smoothstep(0.0, 0.1, ph);
      if (m > a) { a = m; col = mix(vec3(1.0, 0.25, 0.45), vec3(1.0, 0.55, 0.8), hash(fi + 3.3)); }
    }
  } else if (mode == 3) {
    // Three staggered firework bursts.
    for (int b = 0; b < 3; b++) {
      float fb = float(b);
      float cycle = 2.4;
      float ct = mod(t + fb * 0.8, cycle);
      float seed = floor((t + fb * 0.8) / cycle) * 7.0 + fb * 13.0;
      vec2 c = vec2(hash(seed) * size.x, (0.15 + 0.5 * hash(seed + 1.0)) * size.y);
      float r = ct / cycle;
      float radius = (1.0 - (1.0 - r) * (1.0 - r)) * unit * 1.6;
      vec3 bc = palette(hash(seed + 2.0));
      for (int i = 0; i < 16; i++) {
        float ang = float(i) / 16.0 * 6.2831;
        vec2 p = c + vec2(cos(ang), sin(ang)) * radius + vec2(0.0, r * r * 18.0);
        float m = exp(-dot(frag - p, frag - p) / 5.0) * (1.0 - r);
        if (m > a) { a = m; col = bc; }
      }
    }
  } else if (mode == 4) {
    // Aurora halo hugging the bubble outline.
    vec2 p = frag - center;
    float d = sdRoundBox(p, bubbleHalf, min(bubbleHalf.y, 22.0));
    float ang = atan(p.y, p.x);
    vec3 hue = 0.55 + 0.45 * cos(6.2831 * (ang / 6.2831 + t * 0.25 + vec3(0.0, 0.33, 0.67)));
    float ring = exp(-max(d, 0.0) / (uPad * 0.35)) * step(-1.5, d);
    float pulse = 0.65 + 0.35 * sin(t * 2.4);
    a = ring * pulse * 0.9;
    col = mix(hue, uColor + 0.3, 0.2);
  } else if (mode == 5) {
    // Gentle snowfall.
    for (int i = 0; i < 30; i++) {
      float fi = float(i);
      float ph = fract(t * (0.12 + 0.12 * hash(fi)) + hash(fi + 9.1));
      vec2 pos = vec2(hash(fi + 4.2) * size.x + sin(t + fi) * 6.0, ph * size.y);
      float s = 1.2 + 2.2 * hash(fi + 1.9);
      float m = smoothstep(s, s * 0.3, length(frag - pos)) * 0.9;
      if (m > a) { a = m; col = vec3(1.0); }
    }
  } else {
    // Fizz: bubbles rising out of the note.
    for (int i = 0; i < 24; i++) {
      float fi = float(i);
      float ph = fract(t * (0.3 + 0.3 * hash(fi)) + hash(fi + 2.0));
      vec2 pos = vec2(center.x + (hash(fi + 3.0) - 0.5) * bubbleHalf.x * 2.2 + sin(t * 3.0 + fi) * 3.0,
                      center.y + bubbleHalf.y - ph * size.y);
      float s = 2.0 + 3.5 * hash(fi + 5.0);
      float dd = length(frag - pos);
      float m = (smoothstep(s, s - 1.2, dd) - smoothstep(s - 1.2, s - 2.4, dd) * 0.7) * (1.0 - ph);
      if (m > a) { a = m; col = mix(vec3(0.75, 0.95, 1.0), uColor + 0.4, 0.3); }
    }
  }

  a = clamp(a, 0.0, 1.0);
  fragColor = vec4(clamp(col, 0.0, 1.0) * a, a);
}
