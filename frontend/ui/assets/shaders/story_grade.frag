// Story effects — colour grades and film/camera textures.
//
// Drives the Classic, Modern, Vintage and Beauty effects of the story
// effects catalogue (lib/shared/media/story_fx_catalog.dart) and the
// editors' Adjust sliders. Every grade is data: the catalogue gives each
// effect its exposure, contrast, split toning… and one texture op (VHS
// scanlines, film dust, a Polaroid border, a camcorder timestamp…).
// Applied with ImageFilter.shader; sampler 0 is the picture.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;       // 0-1
uniform float uTime;      // 2
uniform float uAmount;    // 3  intensity 0-1 (mix with the original)
uniform vec4 uA;          // 4-7   exposure, brightness, contrast, saturation
uniform vec4 uB;          // 8-11  warmth, tint, highlights, shadows
uniform vec4 uC;          // 12-15 fade, vignette, grain, sharpen
uniform vec4 uD;          // 16-19 soft glow, mono, clarity, vibrance
uniform vec4 uShadowTone; // 20-23 rgb + mix
uniform vec4 uHighTone;   // 24-27 rgb + mix
uniform vec2 uTex;        // 28-29 texture op, its amount
uniform vec4 uStamp;      // 30-33 year (2 digits), month, day, minutes of day

uniform sampler2D uTexture;

out vec4 fragColor;

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

vec3 blur(vec2 uv, float r) {
  vec2 px = r / uSize;
  vec3 s = tap(uv) * 0.16;
  s += (tap(uv + vec2(px.x, 0.0)) + tap(uv - vec2(px.x, 0.0)) + tap(uv + vec2(0.0, px.y)) + tap(uv - vec2(0.0, px.y))) * 0.12;
  s += (tap(uv + px) + tap(uv - px) + tap(uv + vec2(px.x, -px.y)) + tap(uv + vec2(-px.x, px.y))) * 0.06;
  vec2 q = px * 2.0;
  s += (tap(uv + vec2(q.x, 0.0)) + tap(uv - vec2(q.x, 0.0)) + tap(uv + vec2(0.0, q.y)) + tap(uv - vec2(0.0, q.y))) * 0.03;
  return s / 0.88;
}

// 1 when bit k of n is set (no bitwise ops: keeps the Skia fallback happy).
float bit(float n, float k) { return mod(floor(n / pow(2.0, k)), 2.0); }

// One 7-segment digit in a 0..1 x 0..1 cell (y up).
float digit(float d, vec2 p) {
  if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 0.0;
  float code = d < 0.5 ? 63.0 : d < 1.5 ? 6.0 : d < 2.5 ? 91.0 : d < 3.5 ? 79.0 : d < 4.5 ? 102.0
             : d < 5.5 ? 109.0 : d < 6.5 ? 125.0 : d < 7.5 ? 7.0 : d < 8.5 ? 127.0 : 111.0;
  float w = 0.16;
  float h = step(0.15, p.x) * step(p.x, 0.85);
  float v1 = step(0.5, p.y) * step(p.y, 0.95);
  float v0 = step(0.05, p.y) * step(p.y, 0.5);
  float s = 0.0;
  s += bit(code, 0.0) * h * step(1.0 - w, p.y);                                   // a top
  s += bit(code, 1.0) * v1 * step(1.0 - w, p.x);                                  // b
  s += bit(code, 2.0) * v0 * step(1.0 - w, p.x);                                  // c
  s += bit(code, 3.0) * h * step(p.y, w);                                         // d bottom
  s += bit(code, 4.0) * v0 * step(p.x, w);                                        // e
  s += bit(code, 5.0) * v1 * step(p.x, w);                                        // f
  s += bit(code, 6.0) * h * step(abs(p.y - 0.5), w * 0.5);                        // g middle
  return clamp(s, 0.0, 1.0);
}

// "12 34 56" style stamp: three 2-digit numbers starting at `o`, cell `cs` px.
float stamp3(vec2 frag, vec2 o, float cs, float a, float b, float c) {
  vec2 p = (frag - o) / cs;
  p.y = 1.0 - p.y;
  float n = 0.0;
  n += digit(floor(a / 10.0), vec2(p.x / 0.6, p.y));
  n += digit(mod(a, 10.0), vec2((p.x - 0.7) / 0.6, p.y));
  n += digit(floor(b / 10.0), vec2((p.x - 1.8) / 0.6, p.y));
  n += digit(mod(b, 10.0), vec2((p.x - 2.5) / 0.6, p.y));
  n += digit(floor(c / 10.0), vec2((p.x - 3.6) / 0.6, p.y));
  n += digit(mod(c, 10.0), vec2((p.x - 4.3) / 0.6, p.y));
  return clamp(n, 0.0, 1.0);
}

vec3 grade(vec3 c, vec2 uv) {
  float exposure = uA.x, brightness = uA.y, contrast = uA.z, saturation = uA.w;
  float warmth = uB.x, tint = uB.y, highlights = uB.z, shadows = uB.w;
  float fade = uC.x;
  float mono = uD.y, vibrance = uD.w;
  c *= exp2(exposure * 1.4);
  c += brightness * 0.22;
  c = (c - 0.5) * max(0.0, 1.0 + contrast) + 0.5;
  float l = clamp(luma(c), 0.0, 1.0);
  c += highlights * 0.32 * smoothstep(0.45, 1.0, l);
  c += shadows * 0.32 * (1.0 - smoothstep(0.0, 0.55, l));
  c += vec3(warmth * 0.11, -tint * 0.07, -warmth * 0.11 + tint * 0.03);
  c.r += tint * 0.04;
  c = clamp(c, 0.0, 1.0);
  l = luma(c);
  float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
  c = mix(vec3(l), c, max(0.0, 1.0 + saturation + vibrance * (1.0 - sat) * 1.2));
  // Split toning: tones pulled towards a colour in the shadows / highlights.
  l = clamp(luma(c), 0.0, 1.0);
  c = mix(c, c * 0.6 + uShadowTone.rgb * 0.5, uShadowTone.a * (1.0 - l) * (1.0 - l));
  c = mix(c, 1.0 - (1.0 - c) * (1.0 - uHighTone.rgb * 0.6), uHighTone.a * l * l);
  // Fade: lifted blacks, softer whites.
  c = mix(vec3(fade * 0.17), vec3(1.0 - fade * 0.07), clamp(c, 0.0, 1.0));
  c = mix(c, vec3(luma(c)), clamp(mono, 0.0, 1.0));
  return clamp(c, 0.0, 1.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
  frag.y = uSize.y - frag.y;
#endif
  float t = uTime;
  int op = int(uTex.x + 0.5);
  float k = uTex.y;
  vec4 src = texture(uTexture, uv);
  vec3 original = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
  float minSide = min(uSize.x, uSize.y);

  // -- ops that move pixels ---------------------------------------------------------
  vec2 q = uv;
  if (op == 15) { // handheld: slow drifting shake
    q += vec2(noise(vec2(t * 1.3, 1.0)) - 0.5, noise(vec2(3.0, t * 1.1)) - 0.5) * 0.018 * k;
    q = (q - 0.5) * (1.0 - 0.03 * k) + 0.5;
  } else if (op == 1) { // VHS wobble
    q.x += sin(uv.y * 38.0 + t * 5.0) * 0.0016 * k + (noise(vec2(uv.y * 80.0, t * 30.0)) - 0.5) * 0.002 * k;
  } else if (op == 2) { // VCR tracking: a band that tears sideways
    float band = fract(t * 0.13);
    float inBand = smoothstep(0.06, 0.0, abs(uv.y - band));
    q.x += inBand * (noise(vec2(uv.y * 200.0, t * 40.0)) - 0.3) * 0.06 * k;
    q.y += (step(0.97, hash(vec2(floor(t * 8.0), 2.0))) * 0.02) * k;
  } else if (op == 3 || op == 4 || op == 6) { // film gate weave
    q += vec2(noise(vec2(t * 6.0, 0.0)) - 0.5, noise(vec2(0.0, t * 5.0)) - 0.5) * (op == 4 ? 0.003 : 0.006) * k;
  } else if (op == 13) { // CRT: curved glass
    vec2 p = uv * 2.0 - 1.0;
    p *= 1.0 + vec2(p.y * p.y, p.x * p.x) * 0.09 * k;
    q = p * 0.5 + 0.5;
  } else if (op == 14 || op == 7) { // lo-res / camcorder: chunky pixels
    float cell = (op == 14 ? 7.0 : 3.0) * (0.4 + 0.6 * k) * minSide / 420.0;
    q = (floor(frag / cell) + 0.5) * cell / uSize;
  } else if (op == 16) { // Y2K: 8x8 JPEG blocks
    float cell = 3.0 * minSide / 420.0;
    q = mix(uv, (floor(frag / cell) + 0.5) * cell / uSize, 0.5 * k);
  }

  vec3 c = tap(q);
  if (op == 1 || op == 2 || op == 7) { // colour bleed
    float d = (op == 2 ? 0.006 : 0.004) * k;
    c = vec3(tap(q + vec2(d, 0.0)).r, c.g, tap(q - vec2(d, 0.0)).b);
  }
  if (op == 13) {
    c = vec3(tap(q + vec2(0.0015, 0.0)).r, c.g, tap(q - vec2(0.0015, 0.0)).b);
  }

  // -- detail: sharpen, clarity, soft glow, skin smoothing -----------------------------
  float sharpen = uC.w, soft = uD.x, clarity = uD.z;
  if (sharpen != 0.0) c += (c - blur(q, 1.2)) * sharpen * 1.6;
  if (clarity != 0.0 || op == 18) {
    float amount = clarity + (op == 18 ? 0.7 * k : 0.0);
    vec3 wide = blur(q, 7.0);
    c += (c - wide) * amount * 1.1 * (1.0 - abs(luma(c) - 0.5));
  }
  if (op == 19) { // soft skin: blur only where neighbours are alike (edges stay sharp)
    vec3 sum = c;
    float wsum = 1.0;
    vec2 px = 3.0 * minSide / 900.0 / uSize;
    for (int i = 0; i < 8; i++) {
      float a = float(i) * 0.785398;
      vec3 s = tap(q + vec2(cos(a), sin(a)) * px * (1.0 + mod(float(i), 2.0)));
      float w = exp(-dot(s - c, s - c) * 60.0);
      sum += s * w;
      wsum += w;
    }
    c = mix(c, sum / wsum, 0.85 * k);
  }
  if (soft > 0.0 || op == 21 || op == 5) { // glow / halation
    vec3 b = blur(q, op == 5 ? 4.0 : 6.0);
    float g = soft + (op == 21 ? 0.55 * k : 0.0);
    c = mix(c, 1.0 - (1.0 - c) * (1.0 - b * 0.7), g * 0.65);
    if (op == 5) c += vec3(0.25, 0.06, 0.02) * smoothstep(0.65, 1.0, luma(b)) * k; // red halation
  }

  c = grade(c, uv);

  // -- textures on top -------------------------------------------------------------
  float l = luma(c);
  if (op == 1 || op == 7) { // scanlines, tape noise
    c *= 1.0 - 0.1 * k * step(0.5, fract(frag.y / max(2.0, minSide / 360.0)));
    float line = step(0.995, hash(vec2(floor(uv.y * 240.0), floor(t * 20.0))));
    c = mix(c, vec3(0.9), line * 0.5 * k);
  } else if (op == 2) {
    float snow = step(0.86, hash(frag * 0.5 + floor(t * 30.0))) * smoothstep(0.08, 0.0, abs(uv.y - fract(t * 0.13)));
    c = mix(c, vec3(1.0), snow * 0.7 * k);
  } else if (op == 3 || op == 6 || op == 12) { // flicker, dust, scratches
    c *= 1.0 + (op == 12 ? 0.0 : 0.06) * k * (noise(vec2(t * 18.0, 0.0)) - 0.5) * 2.0;
    float dust = step(0.9988, hash(floor(frag / 2.5) + floor(t * 12.0)));
    float hair = step(0.9992, hash(vec2(floor(frag.x / 1.6), floor(t * 6.0))));
    c = mix(c, vec3(0.08), dust * k);
    c = mix(c, vec3(0.95), hair * 0.5 * k);
    if (op != 12) { // rounded gate
      vec2 p = abs(uv - 0.5) * 2.0;
      float gate = smoothstep(0.92, 1.0, pow(pow(p.x, 6.0) + pow(p.y, 6.0), 1.0 / 6.0));
      c *= 1.0 - gate * 0.9 * k;
    }
  } else if (op == 8) { // Polaroid border, deeper at the bottom
    float m = 0.055;
    float inside = step(m, uv.x) * step(uv.x, 1.0 - m) * step(m * uSize.x / uSize.y, uv.y)
                 * step(uv.y, 1.0 - 0.2);
    c = mix(vec3(0.97, 0.96, 0.93), c, mix(1.0, inside, k));
  } else if (op == 9 || op == 17) { // flash: bright centre, fast falloff
    float d = distance(uv, vec2(0.5, 0.45));
    c *= 1.0 + (op == 17 ? 0.75 : 0.45) * k * smoothstep(0.5, 0.0, d);
    c *= 1.0 - 0.55 * k * smoothstep(0.35, 0.8, d);
  } else if (op == 10) { // film burn from the edges
    float n = noise(uv * 3.0 + vec2(t * 0.25, -t * 0.18));
    float edge = smoothstep(0.2, 0.0, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)) - n * 0.12);
    vec3 burn = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.9, 0.6), edge * edge);
    c = 1.0 - (1.0 - c) * (1.0 - burn * edge * k);
  } else if (op == 11) { // light leak
    vec2 p1 = vec2(0.05 + 0.2 * sin(t * 0.45), 0.15 + 0.12 * cos(t * 0.35));
    vec2 p2 = vec2(1.0, 0.8 + 0.15 * sin(t * 0.3));
    vec3 leak = vec3(1.0, 0.42, 0.15) * smoothstep(0.7, 0.0, distance(uv, p1))
              + vec3(1.0, 0.2, 0.5) * smoothstep(0.6, 0.0, distance(uv, p2));
    c = 1.0 - (1.0 - c) * (1.0 - clamp(leak, 0.0, 1.0) * 0.8 * k);
  } else if (op == 13) { // CRT mask and off-glass black
    float mask = mod(floor(frag.x), 3.0);
    c *= mix(vec3(1.0), vec3(mask == 0.0 ? 1.15 : 0.85, mask == 1.0 ? 1.15 : 0.85, mask == 2.0 ? 1.15 : 0.85), 0.5 * k);
    c *= 1.0 - 0.18 * k * step(0.5, fract(frag.y / max(2.0, minSide / 300.0)));
    if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) c = vec3(0.0);
  } else if (op == 14) { // posterise
    c = floor(c * 6.0 + 0.5) / 6.0;
  } else if (op == 20) { // glass skin: glossy highlights
    c += vec3(1.0, 0.97, 0.95) * pow(smoothstep(0.55, 1.0, l), 2.0) * 0.35 * k;
  }

  // Timestamps: camcorder (time), disposable / Y2K (date).
  if (op == 7 || op == 9 || op == 16) {
    float cs = minSide * 0.045;
    vec3 ink = op == 7 ? vec3(1.0) : vec3(1.0, 0.55, 0.15);
    vec2 o = vec2(uSize.x - cs * 6.0, uSize.y - cs * 2.2);
    float s = op == 7
        ? stamp3(frag, o, cs, floor(uStamp.w / 60.0), mod(uStamp.w, 60.0), mod(floor(t), 60.0))
        : stamp3(frag, o, cs, uStamp.x, uStamp.y, uStamp.z);
    c = mix(c, ink, s * 0.9 * k);
    if (op == 7) { // REC dot, blinking
      float rec = smoothstep(cs * 0.45, cs * 0.35, distance(frag, vec2(cs * 1.6, cs * 1.6)));
      c = mix(c, vec3(1.0, 0.1, 0.1), rec * step(0.5, fract(t)) * k);
    }
  }

  float vignette = uC.y, grain = uC.z;
  if (vignette != 0.0) {
    float d = distance(uv, vec2(0.5)) * 1.414;
    c *= 1.0 - vignette * 0.8 * smoothstep(0.3, 1.0, d);
  }
  if (grain > 0.0) {
    float g = hash(floor(frag / max(1.0, minSide / 540.0)) + fract(t * 7.0) * 91.0) - 0.5;
    c += g * 0.28 * grain * (1.0 - abs(l - 0.5));
  }

  c = mix(original, clamp(c, 0.0, 1.0), clamp(uAmount, 0.0, 1.0));
  fragColor = vec4(c * src.a, src.a);
}
