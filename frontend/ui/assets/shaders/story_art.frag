// Story effects — artistic.
//
// Turns the picture into art with image-processing maths: edge detection
// (Sobel), Kuwahara painting, colour-dodge sketches, halftone and Bayer
// dithering, palette mapping (duotone, tritone, thermal, 8/16-bit),
// tiling (mosaic, low poly, ASCII) and line hatching.
// Ids match lib/shared/media/story_fx_catalog.dart.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;    // 0-1
uniform float uTime;   // 2
uniform float uFx;     // 3
uniform float uAmount; // 4
uniform vec3 uInk;     // 5-7  duotone / tritone dark colour
uniform vec3 uPaper;   // 8-10 duotone / tritone light colour

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

vec3 tap(vec2 uv) {
  vec4 s = texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
  return s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
}

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }

float edges(vec2 uv, float r) {
  vec2 px = r / uSize;
  float tl = luma(tap(uv + vec2(-px.x, -px.y))), tc = luma(tap(uv + vec2(0.0, -px.y))), tr = luma(tap(uv + vec2(px.x, -px.y)));
  float ml = luma(tap(uv + vec2(-px.x, 0.0))), mr = luma(tap(uv + vec2(px.x, 0.0)));
  float bl = luma(tap(uv + vec2(-px.x, px.y))), bc = luma(tap(uv + vec2(0.0, px.y))), br = luma(tap(uv + vec2(px.x, px.y)));
  float gx = tr + 2.0 * mr + br - tl - 2.0 * ml - bl;
  float gy = bl + 2.0 * bc + br - tl - 2.0 * tc - tr;
  return length(vec2(gx, gy));
}

vec3 blur(vec2 uv, float r) {
  vec3 s = tap(uv);
  for (int i = 1; i < 12; i++) {
    float f = float(i);
    float a = f * 2.39996;
    s += tap(uv + vec2(cos(a), sin(a)) * sqrt(f / 11.0) * r / uSize);
  }
  return s / 12.0;
}

// Kuwahara filter: the calmest of four quadrants (oil paint).
vec3 kuwahara(vec2 uv, float r) {
  vec2 px = r / uSize / 2.0;
  vec3 bestMean = tap(uv);
  float bestVar = 1e9;
  for (int qd = 0; qd < 4; qd++) {
    vec2 dir = vec2(qd == 0 || qd == 3 ? -1.0 : 1.0, qd < 2 ? -1.0 : 1.0);
    vec3 sum = vec3(0.0);
    vec3 sq = vec3(0.0);
    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 3; x++) {
        vec3 s = tap(uv + vec2(float(x), float(y)) * px * dir);
        sum += s;
        sq += s * s;
      }
    }
    vec3 mean = sum / 9.0;
    vec3 v = sq / 9.0 - mean * mean;
    float var = v.r + v.g + v.b;
    if (var < bestVar) {
      bestVar = var;
      bestMean = mean;
    }
  }
  return bestMean;
}

float bayer2(vec2 a) {
  a = floor(a);
  return fract(dot(a, vec2(0.5, a.y * 0.75)));
}

float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }

// Halftone dot coverage for value v on a rotated grid of `cell` px.
float halftone(vec2 frag, float v, float cell, float angle) {
  vec2 q = mat2(cos(angle), -sin(angle), sin(angle), cos(angle)) * frag / cell;
  vec2 f = fract(q) - 0.5;
  float r = sqrt(clamp(v, 0.0, 1.0)) * 0.62;
  return smoothstep(r + 0.06, r - 0.06, length(f));
}

// Palette: nearest of a few colours (8-bit look).
vec3 palette8(vec3 c) {
  vec3 best = vec3(0.0);
  float bd = 9.0;
  for (int i = 0; i < 16; i++) {
    float f = float(i);
    vec3 p = f < 1.0 ? vec3(0.0) : f < 2.0 ? vec3(1.0) : f < 3.0 ? vec3(0.53, 0.0, 0.0) : f < 4.0 ? vec3(0.67, 1.0, 0.93)
           : f < 5.0 ? vec3(0.8, 0.27, 0.8) : f < 6.0 ? vec3(0.0, 0.8, 0.33) : f < 7.0 ? vec3(0.0, 0.0, 0.67)
           : f < 8.0 ? vec3(0.93, 0.93, 0.47) : f < 9.0 ? vec3(0.87, 0.53, 0.33) : f < 10.0 ? vec3(0.4, 0.27, 0.0)
           : f < 11.0 ? vec3(1.0, 0.47, 0.47) : f < 12.0 ? vec3(0.2) : f < 13.0 ? vec3(0.47) : f < 14.0 ? vec3(0.67, 1.0, 0.4)
           : f < 15.0 ? vec3(0.0, 0.53, 1.0) : vec3(0.73);
    float d = distance(c, p);
    if (d < bd) {
      bd = d;
      best = p;
    }
  }
  return best;
}

// ASCII glyph coverage for level 0-5 in a 0..1 cell.
float glyph(float level, vec2 f) {
  vec2 d = abs(f - 0.5);
  if (level < 0.5) return 0.0;
  if (level < 1.5) return step(length(f - vec2(0.5, 0.78)), 0.1);                                    // .
  if (level < 2.5) return step(length(f - vec2(0.5, 0.3)), 0.1) + step(length(f - vec2(0.5, 0.72)), 0.1); // :
  if (level < 3.5) return step(d.x, 0.07) * step(d.y, 0.32) + step(d.y, 0.07) * step(d.x, 0.32);      // +
  if (level < 4.5) return (step(abs(f.x - 0.35), 0.06) + step(abs(f.x - 0.65), 0.06)) * step(d.y, 0.38)
                        + (step(abs(f.y - 0.38), 0.06) + step(abs(f.y - 0.64), 0.06)) * step(d.x, 0.38); // #
  return step(abs(length(f - 0.5) - 0.3), 0.08) + step(length(f - 0.5), 0.12);                         // @
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
  float px = max(1.0, m / 420.0); // ~1 "design pixel"
  vec4 src = texture(uTexture, uv);
  vec3 base = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
  vec3 c = base;
  float l = luma(c);

  if (fx == 1) { // comic book: flat inks, black lines, halftone shadows
    vec3 sm = kuwahara(uv, 3.0 * px);
    float ls = luma(sm);
    vec3 flat3 = sm * (floor(ls * 4.0 + 0.5) / 4.0 + 0.06) / max(ls, 0.05);
    float dots = halftone(frag, 1.0 - l, 6.0 * px, 0.785);
    c = mix(flat3, flat3 * 0.55, dots * smoothstep(0.55, 0.25, l));
    c *= 1.0 - smoothstep(0.25, 0.55, edges(uv, 1.3 * px));
    c = mix(vec3(luma(c)), c, 1.35);
  } else if (fx == 2 || fx == 3) { // cartoon / anime: smooth cels and outlines
    vec3 smooth3 = kuwahara(uv, (fx == 2 ? 4.0 : 3.0) * px);
    float lv = luma(smooth3);
    float bands = fx == 2 ? 5.0 : 3.0;
    float cel = floor(lv * bands + 0.5) / bands;
    c = smooth3 * (cel + 0.08) / max(lv, 0.05);
    if (fx == 3) {
      c = mix(vec3(luma(c)), c, 1.45);
      c += vec3(0.04, 0.05, 0.12) * smoothstep(0.4, 0.0, uv.y) * step(0.5, c.b - c.r + 0.5); // anime skies
      c = mix(c, c * vec3(1.02, 0.98, 1.06), 0.5);
    }
    float e = smoothstep(fx == 2 ? 0.35 : 0.5, 0.9, edges(uv, 1.2 * px));
    c = mix(c, vec3(0.05, 0.04, 0.08), e);
  } else if (fx == 4) { // watercolour: bleeding pigment, dark wet edges, paper
    vec2 w = (vec2(noise(uv * 18.0), noise(uv * 18.0 + 5.0)) - 0.5) * 0.008;
    vec3 wash = kuwahara(uv + w, 3.0 * px);
    wash = mix(wash, floor(wash * 8.0 + 0.5) / 8.0, 0.5);
    float rim = smoothstep(0.1, 0.4, edges(uv + w, 2.5 * px));
    c = mix(wash, wash * 0.7, rim * 0.6);
    float paper = 0.92 + 0.08 * noise(frag * 0.35) + 0.04 * noise(frag * 0.05);
    c = mix(vec3(1.0), c, 0.88) * paper;
  } else if (fx == 5) { // oil painting: Kuwahara + brush texture
    c = kuwahara(uv, 4.0 * px);
    float stroke = noise(vec2(frag.x * 0.15, frag.y * 0.04)) * 0.5 + noise(frag * 0.08) * 0.5;
    c *= 0.9 + stroke * 0.2;
    c = mix(vec3(luma(c)), c, 1.2);
  } else if (fx == 6 || fx == 7) { // pencil sketch / charcoal
    float inv = 1.0 - luma(blur(uv, (fx == 6 ? 5.0 : 8.0) * px));
    float dodge = clamp(l / max(1.0 - inv, 0.02), 0.0, 1.0);
    if (fx == 6) {
      float paper = 0.95 + 0.05 * noise(frag * 0.6);
      c = vec3(pow(dodge, 2.2)) * paper * vec3(1.0, 0.99, 0.96);
    } else {
      float smudge = noise(frag * vec2(0.05, 0.2)) * 0.25;
      float tone = pow(dodge, 3.5) - smudge * (1.0 - dodge);
      tone = mix(tone, tone * 0.5, smoothstep(0.2, 0.6, edges(uv, 2.0 * px)));
      c = vec3(clamp(tone, 0.0, 1.0)) * vec3(0.98, 0.97, 0.95) + 0.03 * noise(frag * 0.9);
    }
  } else if (fx == 8) { // noir
    float v = smoothstep(0.12, 0.85, l);
    v = v * v * (3.0 - 2.0 * v);
    c = vec3(v) * (1.0 - 0.6 * smoothstep(0.3, 0.95, length(uv - 0.5) * 1.4));
    c += (hash(frag + fract(t) * 50.0) - 0.5) * 0.06;
  } else if (fx == 9) { // outline: glowing edges on dark
    float e = smoothstep(0.1, 0.5, edges(uv, 1.2 * px));
    c = mix(base * 0.18, base * 0.6 + 0.6, e);
  } else if (fx == 10) { // halftone
    float cell = 7.0 * px;
    vec3 ink = vec3(halftone(frag, 1.0 - c.r, cell, 0.26), halftone(frag, 1.0 - c.g, cell, 1.31),
                    halftone(frag, 1.0 - c.b, cell, 0.79));
    c = vec3(1.0) - ink * vec3(1.0, 1.0, 1.0) * 0.9;
    c = mix(c, c * vec3(0.98, 0.96, 0.9), 0.5);
  } else if (fx == 11) { // pop art: 2x2 panels, bold palettes
    vec2 cell = floor(uv * 2.0);
    vec2 q = fract(uv * 2.0);
    float v = luma(tap(q));
    float idx = cell.x + cell.y * 2.0;
    vec3 a = hue(fract(idx * 0.25 + 0.9));
    vec3 b = hue(fract(idx * 0.25 + 0.4));
    c = v > 0.62 ? vec3(1.0, 0.95, 0.4) * 0.3 + b * 0.7 : v > 0.35 ? a : vec3(0.08, 0.05, 0.2) + a * 0.15;
    c *= 1.0 - halftone(frag, 0.15, 5.0 * px, 0.785) * 0.25 * step(v, 0.35);
  } else if (fx == 12) { // duotone
    c = mix(uInk, uPaper, smoothstep(0.05, 0.95, l));
  } else if (fx == 13) { // tritone: ink, a middle tone, paper
    vec3 mid = mix(uInk, uPaper, 0.5) * vec3(1.15, 0.75, 0.9);
    c = l < 0.5 ? mix(uInk, mid, l * 2.0) : mix(mid, uPaper, (l - 0.5) * 2.0);
  } else if (fx == 14) { // posterize
    c = floor(c * 4.0 + 0.5) / 4.0;
  } else if (fx == 15 || fx == 16) { // 8-bit / 16-bit
    float cell = (fx == 15 ? 8.0 : 4.0) * px;
    vec2 q = (floor(frag / cell) + 0.5) * cell / uSize;
    vec3 s = tap(q);
    if (fx == 15) {
      c = palette8(s);
    } else {
      float d = bayer4(floor(frag / cell)) - 0.5;
      c = floor(s * 8.0 + d * 0.9 + 0.5) / 8.0;
    }
  } else if (fx == 17) { // mosaic: tiles with grout
    float cell = 14.0 * px;
    vec2 id = floor(frag / cell);
    vec2 f = fract(frag / cell);
    vec2 jitter = (vec2(hash(id), hash(id + 3.0)) - 0.5) * 0.2;
    c = tap((id + 0.5 + jitter) * cell / uSize) * (0.92 + 0.12 * hash(id + 7.0));
    float grout = step(0.08, f.x) * step(f.x, 0.92) * step(0.08, f.y) * step(f.y, 0.92);
    c = mix(vec3(0.85, 0.83, 0.78), c, grout);
  } else if (fx == 18) { // ASCII art
    float cell = 9.0 * px;
    vec2 id = floor(frag / cell);
    vec2 f = fract(frag / cell);
    vec3 s = tap((id + 0.5) * cell / uSize);
    float level = floor(clamp(luma(s), 0.0, 0.999) * 6.0);
    c = mix(vec3(0.02, 0.03, 0.03), s * 1.25 + 0.1, clamp(glyph(level, f), 0.0, 1.0));
  } else if (fx == 19) { // negative
    c = 1.0 - c;
  } else if (fx == 20) { // thermal vision
    float v = smoothstep(0.0, 1.0, l);
    c = v < 0.25 ? mix(vec3(0.0, 0.0, 0.25), vec3(0.3, 0.0, 0.6), v * 4.0)
      : v < 0.5 ? mix(vec3(0.3, 0.0, 0.6), vec3(0.95, 0.1, 0.2), (v - 0.25) * 4.0)
      : v < 0.75 ? mix(vec3(0.95, 0.1, 0.2), vec3(1.0, 0.75, 0.0), (v - 0.5) * 4.0)
      : mix(vec3(1.0, 0.75, 0.0), vec3(1.0, 1.0, 0.85), (v - 0.75) * 4.0);
  } else if (fx == 21) { // emboss
    vec2 d = 1.5 * px / uSize;
    float e = luma(tap(uv - d)) - luma(tap(uv + d));
    c = vec3(0.5 + e * 2.2) * vec3(0.98, 0.97, 0.95);
  } else if (fx == 22) { // blueprint: white lines on a blue grid
    float e = smoothstep(0.12, 0.45, edges(uv, 1.2 * px));
    vec2 g = fract(frag / (m / 18.0));
    float grid = (step(g.x, 0.03) + step(g.y, 0.03)) * 0.25;
    c = vec3(0.07, 0.24, 0.55) + vec3(0.85, 0.92, 1.0) * clamp(e + grid, 0.0, 1.0) * 0.9;
  } else if (fx == 23) { // dithering: ordered Bayer, 2-bit per channel
    float d = bayer4(floor(frag / px)) - 0.5;
    c = floor(c * 3.0 + d + 0.5) / 3.0;
  } else if (fx == 24) { // low poly: flat triangles
    float cell = 16.0 * px;
    vec2 g = frag / cell;
    vec2 id = floor(g);
    vec2 f = fract(g);
    bool upper = f.x + f.y < 1.0;
    vec2 cen = upper ? id + vec2(1.0, 1.0) / 3.0 : id + vec2(2.0, 2.0) / 3.0;
    c = tap(cen * cell / uSize);
    float shade = upper ? 1.04 : 0.95;
    c *= shade + (hash(id + (upper ? 0.0 : 5.0)) - 0.5) * 0.06;
  } else if (fx == 25) { // crosshatch: denser ink in darker tones
    float ink = 0.0;
    float s1 = mod(frag.x + frag.y, 9.0 * px);
    float s2 = mod(frag.x - frag.y, 9.0 * px);
    float s3 = mod(frag.y, 7.0 * px);
    float w = 1.2 * px;
    if (l < 0.8) ink += step(s1, w);
    if (l < 0.6) ink += step(s2, w);
    if (l < 0.4) ink += step(s3, w);
    if (l < 0.22) ink += step(mod(frag.x, 6.0 * px), w);
    c = mix(vec3(0.98, 0.97, 0.93), vec3(0.1, 0.1, 0.14), clamp(ink, 0.0, 1.0));
    c = mix(c, vec3(0.1, 0.1, 0.14), smoothstep(0.3, 0.7, edges(uv, 1.2 * px)));
  }

  c = mix(base, clamp(c, 0.0, 1.0), k);
  fragColor = vec4(c * src.a, src.a);
}
