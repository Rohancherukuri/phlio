// Story effects — animated and environmental.
//
// Particles and weather drawn procedurally over the picture: hearts
// (bloom, cannon, windows, frame, neon), petals, snow, rain, storms, fire,
// smoke, fog, confetti, bubbles, butterflies, fireflies, galaxies,
// lightning, magic dust and water drops on the lens. Everything is maths
// (hashed grids, signed distances, noise) — no textures needed.
// Ids match lib/shared/media/story_fx_catalog.dart.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;    // 0-1
uniform float uTime;   // 2
uniform float uFx;     // 3
uniform float uAmount; // 4

uniform sampler2D uTexture;

out vec4 fragColor;

const float PI = 3.14159265;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    s += a * noise(p);
    p = p * 2.03 + 17.1;
    a *= 0.5;
  }
  return s;
}

vec3 tap(vec2 uv) {
  vec4 s = texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
  return s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
}

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }

vec3 screen(vec3 a, vec3 b) { return 1.0 - (1.0 - a) * (1.0 - clamp(b, 0.0, 1.0)); }

mat2 rot(float a) { return mat2(cos(a), -sin(a), sin(a), cos(a)); }

// Signed distance to a heart (point down, y up, about 1 tall).
float heartSd(vec2 p) {
  p.x = abs(p.x);
  if (p.y + p.x > 1.0) return length(p - vec2(0.25, 0.75)) - 0.353553;
  vec2 a = p - vec2(0.0, 1.0);
  vec2 b = p - 0.5 * max(p.x + p.y, 0.0);
  return sqrt(min(dot(a, a), dot(b, b))) * sign(p.x - p.y);
}

// Heart of height ~2r centred at the origin (y down screen coords).
float heart(vec2 q, float r) { return heartSd(vec2(q.x, -q.y) / r * 0.5 + vec2(0.0, 0.5)); }

// Cell of a moving particle grid: (offset from particle in cell units, two randoms).
vec4 cellOf(vec2 frag, float size, vec2 drift, float seed) {
  vec2 g = frag / size + drift + seed;
  vec2 id = floor(g);
  float h = hash(id + seed);
  float h2 = hash(id + seed * 1.7 + 9.3);
  vec2 f = fract(g) - 0.5 - (vec2(h, h2) - 0.5) * 0.55;
  return vec4(f, h, h2);
}

// Jagged lightning bolt x position at height y.
float boltX(float y, float seed, float t) {
  float x = 0.0;
  float amp = 0.08;
  for (int i = 0; i < 4; i++) {
    float f = pow(2.0, float(i));
    x += (noise(vec2(y * 6.0 * f, seed + floor(t * 3.0) * 7.0)) - 0.5) * amp;
    amp *= 0.55;
  }
  return x;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
  frag.y = uSize.y - frag.y;
#endif
  int fx = int(uFx + 0.5);
  float k = clamp(uAmount, 0.0, 1.0);
  float t = uTime;
  float m = min(uSize.x, uSize.y);
  float aspect = uSize.x / uSize.y;
  vec4 src = texture(uTexture, uv);
  vec3 c = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
  vec3 base = c;

  if (fx == 1 || fx == 2) { // heart bloom (rising) / heart cannon (streams from the corners)
    for (int layer = 0; layer < 3; layer++) {
      float fl = float(layer);
      float size = m / (5.0 + fl * 3.0);
      vec2 drift = fx == 1 ? vec2(sin(t * 0.7 + fl) * 0.1, t * (0.25 + fl * 0.12))
                           : vec2((uv.x < 0.5 ? -1.0 : 1.0) * t * 0.6, t * 1.1);
      vec4 cl = cellOf(frag, size, drift, fl * 3.1);
      if (fx == 2) cl.xy = rot((uv.x < 0.5 ? 0.5 : -0.5)) * cl.xy;
      float on = step(fx == 1 ? 0.6 : 0.45, cl.z);
      if (fx == 2) on *= smoothstep(0.0, 0.5, uv.y) * smoothstep(0.55, 0.0, abs(uv.x - 0.5) - 0.05 * fl);
      float d = heart(cl.xy * rot(sin(t * 2.0 + cl.w * 6.0) * 0.3), 0.2 + 0.1 * cl.w);
      vec3 col = mix(vec3(1.0, 0.2, 0.4), vec3(1.0, 0.55, 0.75), cl.w);
      c = mix(c, col, smoothstep(0.03, -0.03, d) * on * k * (1.0 - fl * 0.2));
    }
  } else if (fx == 3) { // heart windows: the photo seen through hearts
    float size = m / 2.6;
    vec2 g = frag / size;
    g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5; // brick rows
    vec2 id = floor(g);
    float d = heart(fract(g) - 0.5, 0.36 + 0.03 * sin(t * 2.0 + hash(id) * 6.0));
    vec3 paper = mix(vec3(1.0, 0.72, 0.8), vec3(1.0, 0.85, 0.9), uv.y);
    c = mix(c, mix(paper, c, smoothstep(0.02, -0.02, d)), k);
  } else if (fx == 4) { // heart frame
    vec2 e = min(uv, 1.0 - uv) * uSize / m;
    float edge = min(e.x, e.y);
    float along = edge == e.x ? uv.y * uSize.y / m : uv.x * uSize.x / m;
    vec2 q = vec2(fract(along * 9.0) - 0.5, (edge - 0.05) * 9.0);
    float d = heart(q, 0.32 + 0.04 * sin(t * 3.0 + floor(along * 9.0)));
    float band = smoothstep(0.11, 0.09, edge);
    c = mix(c, mix(c * vec3(1.0, 0.85, 0.9), vec3(1.0), 0.25), band * 0.5 * k);
    c = mix(c, vec3(1.0, 0.25, 0.45), smoothstep(0.03, -0.03, d) * k);
  } else if (fx == 5) { // neon valentine: a glowing heart outline, pulsing
    vec2 q = (uv - vec2(0.5, 0.5)) * vec2(aspect, 1.0);
    float beat = 1.0 + 0.06 * pow(abs(sin(t * 2.4)), 6.0);
    float d = abs(heart(q, 0.28 * beat));
    vec3 neon = vec3(1.0, 0.2, 0.55) * (smoothstep(0.03, 0.0, d) * 1.4 + smoothstep(0.25, 0.0, d) * 0.6);
    c = screen(mix(c, c * vec3(0.55, 0.45, 0.65), 0.5 * k), neon * k);
  } else if (fx == 6) { // love letter: pink paper glow, little hearts drifting
    c = mix(c, screen(c * vec3(1.0, 0.9, 0.92), vec3(0.25, 0.05, 0.12)), 0.6 * k);
    vec4 cl = cellOf(frag, m / 7.0, vec2(sin(t * 0.5) * 0.2, t * 0.15), 7.0);
    float d = heart(cl.xy, 0.12);
    c = mix(c, vec3(0.95, 0.3, 0.45), smoothstep(0.03, -0.03, d) * step(0.75, cl.z) * k);
    float vig = smoothstep(0.3, 0.9, length((uv - 0.5) * vec2(aspect, 1.0)));
    c = mix(c, vec3(1.0, 0.75, 0.8), vig * 0.45 * k);
  } else if (fx == 7 || fx == 20) { // spring bloom / cherry blossom: falling petals
    for (int layer = 0; layer < 3; layer++) {
      float fl = float(layer);
      float size = m / (6.0 + fl * 4.0);
      vec4 cl = cellOf(frag, size, vec2(sin(t * 0.8 + fl) * 0.3 - t * 0.1, -t * (0.18 + fl * 0.08)), fl * 5.3);
      vec2 q = rot(t * (1.0 + cl.w) + cl.z * 6.0) * cl.xy;
      float petal = length(q * vec2(1.0, 2.2 + sin(t * 3.0 + cl.w * 9.0))) - 0.13;
      vec3 col = fx == 20 ? mix(vec3(1.0, 0.75, 0.82), vec3(1.0, 0.9, 0.93), cl.w)
                          : hue(fract(cl.w * 0.35 + 0.85)) * 0.45 + vec3(0.55, 0.5, 0.45);
      c = mix(c, col, smoothstep(0.02, -0.02, petal) * step(0.55, cl.z) * k);
    }
    if (fx == 7) c = mix(c, c * vec3(1.04, 1.04, 0.95), 0.4 * k);
  } else if (fx == 8 || fx == 10) { // winter sparkle / snow
    if (fx == 8) c = mix(c, c * vec3(0.9, 0.97, 1.12) + vec3(0.03, 0.04, 0.07), k);
    for (int layer = 0; layer < 3; layer++) {
      float fl = float(layer);
      float size = m / (8.0 + fl * 6.0);
      vec4 cl = cellOf(frag, size, vec2(sin(t * 0.6 + fl * 2.0) * 0.4, -t * (0.35 + fl * 0.15)), fl * 2.9);
      float r = 0.07 + 0.08 * cl.w * (1.0 - fl * 0.25);
      float flake = smoothstep(r, r * 0.4, length(cl.xy));
      float tw = fx == 8 ? 0.5 + 0.5 * sin(t * 5.0 + cl.z * 40.0) : 1.0;
      c = mix(c, vec3(1.0), flake * step(0.45, cl.z) * k * tw * (1.0 - fl * 0.2));
    }
  } else if (fx == 9) { // starfield
    for (int layer = 0; layer < 3; layer++) {
      float fl = float(layer);
      vec4 cl = cellOf(frag, m / (14.0 + fl * 10.0), vec2(t * 0.01 * (fl + 1.0), 0.0), fl * 4.4);
      float tw = 0.4 + 0.6 * pow(0.5 + 0.5 * sin(t * (2.0 + cl.w * 4.0) + cl.z * 30.0), 3.0);
      float star = smoothstep(0.1, 0.0, length(cl.xy)) * 1.4 + smoothstep(0.02, 0.0, abs(cl.x)) * smoothstep(0.25, 0.0, abs(cl.y)) * 0.4
                 + smoothstep(0.02, 0.0, abs(cl.y)) * smoothstep(0.25, 0.0, abs(cl.x)) * 0.4;
      c = screen(c, vec3(0.9, 0.95, 1.0) * star * tw * step(0.65, cl.z) * k);
    }
    c = mix(c, c * vec3(0.8, 0.85, 1.05), 0.35 * k);
  } else if (fx == 11 || fx == 12) { // rain / thunderstorm
    c = mix(c, c * vec3(0.78, 0.84, 0.95), (fx == 12 ? 0.6 : 0.35) * k);
    for (int layer = 0; layer < 3; layer++) {
      float fl = float(layer);
      vec2 g = vec2(frag.x + frag.y * 0.15, frag.y) / vec2(m / (40.0 + fl * 25.0), m / 6.0) + vec2(0.0, -t * (5.0 + fl * 2.0)) + fl * 7.0;
      vec2 id = floor(g);
      vec2 f = fract(g);
      float h = hash(id);
      float streak = smoothstep(0.08, 0.0, abs(f.x - 0.5)) * smoothstep(0.0, 0.3, f.y) * smoothstep(1.0, 0.7, f.y);
      c = mix(c, vec3(0.85, 0.9, 1.0), streak * step(0.6, h) * 0.55 * k);
    }
    if (fx == 12) {
      float strike = step(0.985, hash(vec2(floor(t * 4.0), 1.0)));
      c += vec3(0.75, 0.8, 1.0) * strike * k * 0.8 * (0.6 + 0.4 * sin(t * 80.0));
    }
  } else if (fx == 13) { // fire: flames licking up from the bottom
    vec2 q = vec2(uv.x * 3.0 * aspect, uv.y * 2.0 + t * 1.4);
    float n = fbm(q + vec2(0.0, t * 0.5));
    float height = (uv.y - 0.6) * 1.8 + n * 0.8;
    float flame = smoothstep(0.45, 1.05, height);
    vec3 col = mix(vec3(0.9, 0.1, 0.0), vec3(1.0, 0.85, 0.3), smoothstep(0.5, 1.0, flame));
    c = screen(c, col * flame * 1.1 * k);
  } else if (fx == 14 || fx == 15) { // smoke / fog
    vec2 q = uv * vec2(aspect, 1.0) * (fx == 14 ? 2.5 : 1.6) + vec2(t * 0.06, fx == 14 ? -t * 0.12 : 0.0);
    float n = fbm(q + fbm(q + t * 0.05));
    float amount = fx == 14 ? smoothstep(0.3, 0.75, n) * smoothstep(-0.2, 0.7, uv.y) : smoothstep(0.2, 0.9, n) * 0.85;
    c = mix(c, fx == 14 ? vec3(0.78, 0.78, 0.8) : vec3(0.88, 0.9, 0.93), amount * k);
    if (fx == 15) c = mix(c, vec3(luma(c)) * 0.3 + c * 0.7 + 0.08, 0.5 * k);
  } else if (fx == 16) { // confetti
    for (int layer = 0; layer < 3; layer++) {
      float fl = float(layer);
      vec4 cl = cellOf(frag, m / (7.0 + fl * 4.0), vec2(sin(t + fl) * 0.2, -t * (0.3 + fl * 0.1)), fl * 6.6);
      vec2 q = rot(t * (2.0 + cl.w * 4.0) + cl.z * 6.0) * cl.xy;
      q.y *= 1.0 / max(0.15, abs(cos(t * 3.0 + cl.w * 9.0)));
      float piece = step(abs(q.x), 0.1) * step(abs(q.y), 0.05);
      c = mix(c, hue(fract(cl.w * 7.0)), piece * step(0.5, cl.z) * k);
    }
  } else if (fx == 17) { // bubbles: refracting rings rising
    for (int layer = 0; layer < 2; layer++) {
      float fl = float(layer);
      float size = m / (4.0 + fl * 4.0);
      vec4 cl = cellOf(frag, size, vec2(sin(t * 0.9 + fl) * 0.15, t * (0.2 + fl * 0.1)), fl * 3.7);
      float r = 0.18 + 0.1 * cl.w;
      float d = length(cl.xy);
      if (d < r && cl.z > 0.55) {
        vec2 lens = cl.xy / r;
        vec3 inside = tap(uv - lens * 0.02 * k);
        float rim = smoothstep(r * 0.8, r, d);
        vec3 film = hue(fract(d * 6.0 + t * 0.3)) * 0.35;
        vec3 bubble = inside + (vec3(1.0) * rim * 0.45 + film * rim)
                    + vec3(1.0) * smoothstep(0.08, 0.0, length(lens - vec2(-0.45, -0.45))) * 0.8;
        c = mix(c, bubble, k);
      }
    }
  } else if (fx == 18) { // butterflies: flapping wings drifting
    for (int layer = 0; layer < 2; layer++) {
      float fl = float(layer);
      vec4 cl = cellOf(frag, m / (3.5 + fl * 2.5), vec2(t * 0.08 + sin(t * 0.5) * 0.1, t * 0.06 + sin(t * 0.7 + fl) * 0.1), fl * 8.8);
      if (cl.z > 0.6) {
        vec2 q = rot(-0.3 + cl.w * 0.6) * cl.xy;
        float flap = 0.35 + 0.65 * abs(sin(t * 7.0 + cl.w * 20.0));
        vec2 w = vec2(abs(q.x) / flap, q.y);
        float upper = length((w - vec2(0.11, -0.06)) * vec2(1.0, 1.3)) - 0.1;
        float lower = length((w - vec2(0.08, 0.07)) * vec2(1.2, 1.0)) - 0.07;
        float wing = min(upper, lower);
        float body = length(q * vec2(5.0, 1.0)) - 0.06;
        vec3 col = hue(fract(cl.w * 0.6 + 0.5));
        col = mix(col, vec3(0.05), smoothstep(-0.02, 0.0, wing) * 0.5);
        c = mix(c, col, smoothstep(0.01, -0.01, wing) * k);
        c = mix(c, vec3(0.08), smoothstep(0.01, -0.01, body) * k);
      }
    }
  } else if (fx == 19 || fx == 23) { // fireflies / magic dust
    c = mix(c, c * (fx == 19 ? vec3(0.75, 0.8, 0.9) : vec3(0.95, 0.9, 1.05)), 0.4 * k);
    for (int layer = 0; layer < 3; layer++) {
      float fl = float(layer);
      vec2 wander = vec2(sin(t * 0.4 + fl * 2.0), cos(t * 0.3 + fl)) * 0.3 + (fx == 23 ? vec2(-t * 0.1, t * 0.08) : vec2(0.0));
      vec4 cl = cellOf(frag, m / (6.0 + fl * 5.0), wander, fl * 1.9);
      float pulse = pow(0.5 + 0.5 * sin(t * (1.5 + cl.w * 2.0) + cl.z * 30.0), 2.0);
      float d = length(cl.xy);
      vec3 col = fx == 19 ? vec3(0.85, 1.0, 0.45) : hue(fract(cl.w + t * 0.1)) * 0.6 + 0.4;
      c = screen(c, col * (smoothstep(0.08, 0.0, d) * 1.3 + smoothstep(0.35, 0.0, d) * 0.5) * pulse * step(0.45, cl.z) * k);
    }
  } else if (fx == 21) { // galaxy: nebula and stars
    vec2 q = uv * vec2(aspect, 1.0) * 2.2;
    float n = fbm(q + vec2(t * 0.03, 0.0) + fbm(q * 1.5 - t * 0.02));
    vec3 neb = mix(vec3(0.35, 0.08, 0.6), vec3(0.15, 0.55, 1.0), n) * smoothstep(0.3, 0.8, n) * 1.8;
    neb += vec3(1.0, 0.5, 0.8) * smoothstep(0.7, 0.95, n) * 0.6;
    vec4 cl = cellOf(frag, m / 26.0, vec2(0.0), 2.2);
    float star = smoothstep(0.07, 0.0, length(cl.xy)) * step(0.7, cl.z) * (0.6 + 0.4 * sin(t * 3.0 + cl.w * 40.0));
    c = screen(mix(c, c * 0.6, 0.5 * k), (neb + star) * k);
  } else if (fx == 22) { // lightning bolts
    c = mix(c, c * vec3(0.7, 0.75, 0.9), 0.5 * k);
    float phase = fract(t * 0.7);
    float flash = smoothstep(0.0, 0.03, phase) * smoothstep(0.2, 0.05, phase);
    for (int b = 0; b < 2; b++) {
      float seed = float(b) * 11.0 + floor(t * 0.7) * 3.0;
      float x0 = 0.25 + 0.5 * hash(vec2(seed, 1.0));
      float x = x0 + boltX(uv.y, seed, t * 0.0);
      float d = abs(uv.x - x) * uSize.x / m;
      float bolt = smoothstep(0.006, 0.0, d) + smoothstep(0.05, 0.0, d) * 0.35;
      bolt *= step(uv.y, 0.4 + 0.6 * hash(vec2(seed, 2.0)));
      c = screen(c, vec3(0.75, 0.85, 1.0) * bolt * flash * 1.5 * k);
    }
    c += vec3(0.5, 0.55, 0.7) * flash * 0.25 * k;
  } else if (fx == 24) { // water droplets on the lens
    for (int layer = 0; layer < 2; layer++) {
      float fl = float(layer);
      vec4 cl = cellOf(frag, m / (5.0 + fl * 5.0), vec2(0.0, -t * 0.015 * fl), fl * 5.5);
      float r = 0.12 + 0.14 * cl.w;
      vec2 q = cl.xy * vec2(1.0, 0.9);
      float d = length(q);
      if (d < r && cl.z > 0.45) {
        vec2 n = q / r;
        vec3 inside = tap(uv - n * 0.06 * k + vec2(0.0, 0.02)) * 1.08;
        float edge = smoothstep(r * 0.75, r, d);
        vec3 drop = mix(inside, inside * 0.55, edge) + vec3(1.0) * smoothstep(0.12, 0.0, length(n - vec2(-0.35, -0.4))) * 0.7;
        c = mix(c, drop, k);
      }
    }
  }

  c = mix(base, clamp(c, 0.0, 1.0), 1.0);
  fragColor = vec4(clamp(c, 0.0, 1.0) * src.a, src.a);
}
