// Story effects — lighting and particles.
//
// Glows, flares, rays and glitter drawn over the picture: bloom, sparkle,
// glitter (gold, purple, iridescent), starbursts, light streaks, lens
// flare, bokeh, neon, spotlight, god rays, palm shade, cyberpunk, aura and
// holographic. Ids match lib/shared/media/story_fx_catalog.dart.
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
  for (int i = 0; i < 4; i++) {
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

// Highlights only (for glows): brightness above `th`, soft knee.
vec3 bright(vec2 uv, float th) {
  vec3 c = tap(uv);
  return c * smoothstep(th, th + 0.2, luma(c));
}

// Blurred highlights around uv (radius r px), 12 taps.
vec3 glow(vec2 uv, float r, float th) {
  vec3 s = bright(uv, th);
  for (int i = 1; i < 12; i++) {
    float f = float(i);
    float a = f * 2.39996;
    s += bright(uv + vec2(cos(a), sin(a)) * sqrt(f / 11.0) * r / uSize, th);
  }
  return s / 12.0;
}

// A four-point star glint (cell units).
float glint(vec2 f, float size) {
  vec2 a = abs(f) / size;
  return max(0.0, 1.0 - a.x * 6.0) * max(0.0, 1.0 - a.y) + max(0.0, 1.0 - a.y * 6.0) * max(0.0, 1.0 - a.x)
       + smoothstep(0.35, 0.0, length(a));
}

// Sobel edge strength.
float edges(vec2 uv) {
  vec2 px = 1.5 / uSize;
  float tl = luma(tap(uv + vec2(-px.x, -px.y))), tc = luma(tap(uv + vec2(0.0, -px.y))), tr = luma(tap(uv + vec2(px.x, -px.y)));
  float ml = luma(tap(uv + vec2(-px.x, 0.0))), mr = luma(tap(uv + vec2(px.x, 0.0)));
  float bl = luma(tap(uv + vec2(-px.x, px.y))), bc = luma(tap(uv + vec2(0.0, px.y))), br = luma(tap(uv + vec2(px.x, px.y)));
  float gx = tr + 2.0 * mr + br - tl - 2.0 * ml - bl;
  float gy = bl + 2.0 * bc + br - tl - 2.0 * tc - tr;
  return length(vec2(gx, gy));
}

// Glitter layer: sparkles that twinkle, denser on bright areas.
vec3 glitter(vec2 frag, float l, vec3 tint, bool rainbow, float t) {
  vec3 s = vec3(0.0);
  float size = min(uSize.x, uSize.y) / 60.0;
  for (int layer = 0; layer < 2; layer++) {
    float sc = size * (layer == 0 ? 1.0 : 0.55);
    vec2 g = frag / sc + float(layer) * 13.7;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = hash(id);
    float tw = 0.5 + 0.5 * sin(t * (3.0 + h * 5.0) + h * 40.0);
    float on = step(0.72 - 0.25 * l, h) * tw * tw;
    vec3 col = rainbow ? hue(fract(h * 3.0 + t * 0.1 + frag.x / uSize.x)) : tint;
    s += col * glint(f - (vec2(hash(id + 3.1), hash(id + 5.7)) - 0.5) * 0.5, 0.35) * on;
  }
  return s;
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
  float aspect = uSize.x / uSize.y;
  vec4 src = texture(uTexture, uv);
  vec3 c = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
  float l = luma(c);
  vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

  if (fx == 1) { // bloom
    c = screen(c, glow(uv, 22.0, 0.55) * 1.6 * k);
  } else if (fx == 2) { // sparkle: big animated stars on highlights
    float size = min(uSize.x, uSize.y) / 14.0;
    vec2 g = frag / size;
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = hash(id);
    float tw = pow(0.5 + 0.5 * sin(t * 2.5 + h * 30.0), 3.0);
    float on = step(0.55, h) * smoothstep(0.35, 0.8, luma(tap((id + 0.5) * size / uSize)) + 0.25);
    c += vec3(1.0, 0.96, 0.85) * glint(f, 0.4) * on * tw * k;
  } else if (fx >= 3 && fx <= 6) { // glitter, golden, purple, iridescent
    vec3 tint = fx == 4 ? vec3(1.0, 0.8, 0.35) : fx == 5 ? vec3(0.75, 0.45, 1.0) : vec3(1.0);
    if (fx == 4) c = mix(c, c * vec3(1.08, 0.98, 0.82), 0.4 * k);
    if (fx == 5) c = mix(c, c * vec3(1.0, 0.9, 1.12), 0.4 * k);
    c += glitter(frag, l, tint, fx == 6, t) * k;
  } else if (fx == 7 || fx == 8) { // starburst / LED starburst: rays from highlights
    vec3 rays = vec3(0.0);
    for (int d = 0; d < 4; d++) {
      float a = float(d) * PI / 4.0 + 0.3;
      vec2 dir = vec2(cos(a), sin(a)) / uSize * 6.0;
      for (int i = 1; i < 10; i++) {
        float w = 1.0 - float(i) / 10.0;
        rays += (bright(uv + dir * float(i), 0.75) + bright(uv - dir * float(i), 0.75)) * w;
      }
    }
    rays /= 14.0;
    if (fx == 8) rays *= hue(fract(atan(p.y, p.x) / (2.0 * PI) + t * 0.2)) * 1.6;
    c = screen(c, rays * 2.2 * k);
  } else if (fx == 9) { // rayburst: beams from the centre
    float a = atan(p.y, p.x);
    float beams = pow(0.5 + 0.5 * sin(a * 14.0 + t * 0.6), 6.0) * smoothstep(0.0, 0.9, length(p));
    c = screen(c, vec3(1.0, 0.92, 0.7) * beams * 0.8 * k);
  } else if (fx == 10) { // prism light: a rainbow band sweeping
    float band = uv.x * 0.8 + uv.y * 0.5 - 0.3 - 0.25 * sin(t * 0.4);
    vec3 rainbow = hue(fract(band * 2.5)) * smoothstep(0.35, 0.0, abs(band - 0.2));
    c = screen(c, rainbow * 0.5 * k);
  } else if (fx == 11) { // light streak: anamorphic horizontal smear of highlights
    vec3 s = vec3(0.0);
    for (int i = -12; i <= 12; i++) {
      float f = float(i);
      s += bright(uv + vec2(f * 10.0 / uSize.x, 0.0), 0.7) * (1.0 - abs(f) / 13.0);
    }
    c = screen(c, s / 4.0 * vec3(0.7, 0.85, 1.0) * k);
  } else if (fx == 12) { // lens flare from a moving light
    vec2 light = vec2(0.25 + 0.08 * sin(t * 0.3), 0.18) - 0.5;
    light.x *= aspect;
    vec2 axis = -light;
    vec3 flare = vec3(1.0, 0.9, 0.7) * pow(max(0.0, 1.0 - length(p - light) * 3.0), 3.0);
    for (int i = 1; i < 6; i++) {
      float f = float(i) * 0.38;
      vec2 ghost = light + axis * f * 2.0;
      float d = length(p - ghost);
      flare += hue(fract(f * 1.7)) * smoothstep(0.06 + f * 0.02, 0.0, d) * 0.35;
    }
    flare += vec3(1.0, 0.85, 0.6) * 0.15 * pow(max(0.0, 1.0 - abs(p.y - light.y) * 40.0), 2.0);
    c = screen(c, flare * k);
  } else if (fx == 13) { // bokeh: soft discs of light
    vec3 b = vec3(0.0);
    for (int layer = 0; layer < 2; layer++) {
      float size = min(uSize.x, uSize.y) / (layer == 0 ? 5.0 : 9.0);
      vec2 g = frag / size + vec2(0.0, t * 0.04 * float(layer + 1));
      vec2 id = floor(g);
      vec2 f = fract(g) - 0.5 - (vec2(hash(id), hash(id + 9.1)) - 0.5) * 0.5;
      float h = hash(id + 4.4);
      float disc = smoothstep(0.32, 0.28, length(f)) * (0.6 + 0.4 * smoothstep(0.1, 0.3, length(f)));
      vec3 col = tap((id + 0.5) * size / uSize) * 1.2 + 0.2;
      b += col * disc * step(0.55, h) * (0.4 + 0.3 * sin(t + h * 20.0));
    }
    c = screen(mix(c, c * 0.85, k), b * 0.6 * k);
  } else if (fx == 14 || fx == 21) { // neon glow / aura: glowing outlines
    float e = 0.0;
    for (int i = 0; i < 6; i++) {
      float a = float(i) * 1.0472;
      e += edges(uv + vec2(cos(a), sin(a)) * 3.0 / uSize);
    }
    e = smoothstep(fx == 14 ? 0.25 : 0.35, 0.9, e / 6.0);
    vec3 col = fx == 14 ? hue(fract(uv.y * 0.6 + t * 0.15)) : mix(vec3(1.0, 0.85, 0.5), vec3(0.75, 0.5, 1.0), 0.5 + 0.5 * sin(t));
    if (fx == 14) c = mix(c, c * 0.6, k);
    c = screen(c, col * e * (fx == 14 ? 1.1 : 0.7) * k);
  } else if (fx == 15) { // neon frame
    vec2 d = min(uv, 1.0 - uv) * vec2(aspect, 1.0);
    float edge = min(d.x, d.y);
    float line = smoothstep(0.012, 0.0, abs(edge - 0.04));
    float halo = smoothstep(0.08, 0.0, abs(edge - 0.04)) * 0.5;
    vec3 col = hue(fract(t * 0.12 + (uv.x + uv.y) * 0.5));
    c = screen(c, col * (line * 1.5 + halo) * k);
  } else if (fx == 16) { // RGB lighting: coloured lights from each side
    vec3 left = vec3(1.0, 0.15, 0.55) * smoothstep(0.8, 0.0, uv.x);
    vec3 right = vec3(0.1, 0.5, 1.0) * smoothstep(0.2, 1.0, uv.x);
    vec3 lit = c * (0.55 + (left + right) * 0.9 * (0.85 + 0.15 * sin(t * 2.0)));
    c = mix(c, lit, k);
  } else if (fx == 17) { // spotlight
    float d = length(p - vec2(0.0, -0.05));
    float spot = smoothstep(0.42, 0.12, d);
    c = mix(c, c * (0.25 + spot * 1.15), k);
  } else if (fx == 18) { // god rays from the top
    vec2 sun = vec2(0.5 + 0.2 * sin(t * 0.2), -0.1);
    vec3 s = vec3(0.0);
    for (int i = 0; i < 20; i++) {
      float f = float(i) / 20.0;
      s += bright(mix(uv, sun, f * 0.6), 0.5) * (1.0 - f);
    }
    float shafts = 0.6 + 0.4 * noise(vec2(atan(uv.x - sun.x, uv.y - sun.y) * 12.0, t * 0.2));
    c = screen(c, (s / 10.0 + vec3(1.0, 0.92, 0.75) * 0.08 * smoothstep(1.0, 0.0, uv.y)) * shafts * k);
  } else if (fx == 19) { // palm shade: swaying leaf shadows
    // Leaflets: thin stripes along curving fronds, in dappled patches.
    vec2 q = mat2(0.82, -0.57, 0.57, 0.82) * (uv * vec2(aspect, 1.0)) + vec2(sin(t * 0.5) * 0.02, 0.0);
    float bend = fbm(q * 2.0 + t * 0.05) * 3.0;
    float stripes = smoothstep(0.1, 0.6, sin(q.x * 70.0 + bend * 6.0 + q.y * 8.0));
    float fronds = smoothstep(0.36, 0.5, fbm(q * vec2(1.2, 3.5) + vec2(0.0, t * 0.04)));
    float leaf = stripes * fronds;
    c = mix(c, c * mix(vec3(1.0), vec3(0.45, 0.42, 0.5), clamp(leaf, 0.0, 1.0)), k);
    c = mix(c, c * vec3(1.06, 1.0, 0.9), 0.4 * k);
  } else if (fx == 20) { // cyberpunk: pink / teal split light
    float lc = luma(c);
    vec3 cyber = mix(vec3(0.05, 0.75, 0.95) * lc * 1.3, vec3(1.0, 0.2, 0.75) * (lc * 1.2 + 0.1), smoothstep(0.3, 0.75, lc));
    cyber = screen(cyber, glow(uv, 14.0, 0.6) * vec3(1.0, 0.3, 0.8));
    c = mix(c, cyber, 0.85 * k);
  } else if (fx == 22) { // holographic sheen
    float sheen = fract(uv.x * 1.2 + uv.y * 0.8 + l * 0.6 + t * 0.15);
    vec3 holo = hue(sheen) * (0.35 + 0.65 * smoothstep(0.2, 0.9, l));
    c = mix(c, screen(c * 0.85, holo * 0.65), k);
  }

  fragColor = vec4(clamp(c, 0.0, 1.0) * src.a, src.a);
}
