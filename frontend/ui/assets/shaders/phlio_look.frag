// Phlio Looks: colour grade + Instagram-style effects, applied to a widget
// subtree through ImageFilter.shader (Impeller). Sampler 0 is the input.
//
// Grade (same maths as the Studio's server renderer):
//   c  = M * c + offset                       (3x4 matrix, rows uR/uG/uB)
//   c  = lift + (gain - lift) * pow(c, gamma) (per channel)
//   vignette, grain
// Effects (uEffect): 0 none, 1 grain, 2 light leak, 3 chromatic, 4 glitch,
// 5 VHS, 6 dreamy, 7 prism, 8 old film, 9 sparkle, 10 3D, 11 blur.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;      // 0-1
uniform float uTime;     // 2
uniform vec4 uR;         // 3-6
uniform vec4 uG;         // 7-10
uniform vec4 uB;         // 11-14
uniform vec3 uLift;      // 15-17
uniform vec3 uGamma;     // 18-20
uniform vec3 uGain;      // 21-23
uniform float uVignette; // 24
uniform float uGrain;    // 25
uniform float uEffect;   // 26
uniform float uAmount;   // 27 effect strength 0-1

uniform sampler2D uTexture;

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

vec4 tap(vec2 uv) {
  return texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
}

vec3 grade(vec3 c) {
  vec3 m = vec3(dot(uR.xyz, c) + uR.w, dot(uG.xyz, c) + uG.w, dot(uB.xyz, c) + uB.w);
  m = clamp(m, 0.0, 1.0);
  return clamp(uLift + (uGain - uLift) * pow(m, uGamma), 0.0, 1.0);
}

vec3 blur9(vec2 uv, float r) {
  vec2 px = r / uSize;
  vec3 s = tap(uv).rgb * 0.2;
  s += tap(uv + vec2(px.x, 0.0)).rgb * 0.1;
  s += tap(uv - vec2(px.x, 0.0)).rgb * 0.1;
  s += tap(uv + vec2(0.0, px.y)).rgb * 0.1;
  s += tap(uv - vec2(0.0, px.y)).rgb * 0.1;
  s += tap(uv + px).rgb * 0.1;
  s += tap(uv - px).rgb * 0.1;
  s += tap(uv + vec2(px.x, -px.y)).rgb * 0.1;
  s += tap(uv + vec2(-px.x, px.y)).rgb * 0.1;
  return s;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  int fx = int(uEffect + 0.5);
  float k = uAmount;
  float t = uTime;

  // -- effects that move pixels (before grading) -----------------------------------
  vec4 src = tap(uv);
  // Input is premultiplied: work on straight colour, re-premultiply at the end.
  vec3 c = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
  if (fx == 3) { // chromatic aberration
    vec2 d = (uv - 0.5) * 0.012 * k;
    c = vec3(tap(uv + d).r, c.g, tap(uv - d).b);
  } else if (fx == 4) { // glitch: jumping slices + channel split
    float band = floor(uv.y * 24.0);
    float trig = step(0.86, hash(vec2(band, floor(t * 9.0))));
    float shift = (hash(vec2(band, floor(t * 13.0))) - 0.5) * 0.12 * trig * k;
    vec2 g = vec2(uv.x + shift, uv.y);
    c = vec3(tap(g + vec2(0.006 * k, 0.0)).r, tap(g).g, tap(g - vec2(0.006 * k, 0.0)).b);
  } else if (fx == 5) { // VHS: wobble, chroma bleed, scanlines
    float wob = sin(uv.y * 40.0 + t * 6.0) * 0.0015 * k;
    vec2 v = vec2(uv.x + wob, uv.y);
    c = vec3(tap(v + vec2(0.004 * k, 0.0)).r, tap(v).g, tap(v - vec2(0.004 * k, 0.0)).b);
    c *= 1.0 - 0.08 * k * step(0.5, fract(frag.y * 0.5));
    c = mix(c, c * vec3(1.05, 0.98, 1.08), k);
  } else if (fx == 6) { // dreamy glow
    vec3 b = blur9(uv, 6.0);
    c = mix(c, 1.0 - (1.0 - c) * (1.0 - b * 0.6), 0.55 * k);
  } else if (fx == 7) { // prism: rainbow split from centre
    vec2 d = (uv - 0.5) * 0.02 * k;
    c = vec3(tap(uv + d * 1.5).r, tap(uv + d * 0.2).g, tap(uv - d).b);
    c += 0.12 * k * vec3(sin(uv.x * 6.0 + t), sin(uv.x * 6.0 + t + 2.1), sin(uv.x * 6.0 + t + 4.2)) * smoothstep(0.2, 0.9, length(uv - 0.5));
  } else if (fx == 10) { // retro 3D anaglyph
    c = vec3(tap(uv + vec2(0.008 * k, 0.0)).r, c.g, tap(uv - vec2(0.008 * k, 0.0)).b);
  } else if (fx == 11) { // blur
    c = mix(c, blur9(uv, 5.0 * k), k);
  }

  c = grade(c);

  // -- effects layered on top -----------------------------------------------------
  if (fx == 2) { // light leak: warm drifting glows, screen-blended
    vec2 p1 = vec2(0.1 + 0.15 * sin(t * 0.5), 0.2 + 0.1 * cos(t * 0.4));
    vec2 p2 = vec2(0.95, 0.85 + 0.1 * sin(t * 0.3));
    vec3 leak = vec3(1.0, 0.45, 0.2) * smoothstep(0.65, 0.0, distance(uv, p1))
              + vec3(1.0, 0.25, 0.55) * smoothstep(0.55, 0.0, distance(uv, p2));
    c = 1.0 - (1.0 - c) * (1.0 - clamp(leak, 0.0, 1.0) * 0.75 * k);
  } else if (fx == 8) { // old film: sepia, flicker, dust and scratches
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(c, vec3(l * 1.07, l * 0.95, l * 0.78), 0.8 * k);
    c *= 1.0 + 0.05 * k * sin(t * 23.0);
    float dust = step(0.9985, hash(floor(frag / 3.0) + floor(t * 12.0)));
    float scratch = step(0.997, hash(vec2(floor(frag.x / 2.0), floor(t * 8.0)))) * 0.5;
    c = mix(c, vec3(0.1), dust * k);
    c += scratch * k * 0.25;
  } else if (fx == 9) { // sparkle: twinkling glints on bright areas
    vec2 cell = floor(frag / 18.0);
    float h = hash(cell);
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    vec2 f = fract(frag / 18.0) - 0.5;
    float star = max(0.0, 1.0 - abs(f.x) * 14.0) * max(0.0, 1.0 - abs(f.y) * 3.0)
               + max(0.0, 1.0 - abs(f.y) * 14.0) * max(0.0, 1.0 - abs(f.x) * 3.0);
    float on = step(0.93, h) * smoothstep(0.6, 0.9, l) * (0.5 + 0.5 * sin(t * 4.0 + h * 40.0));
    c += vec3(1.0, 0.95, 0.85) * star * on * k;
  }

  // Vignette (same falloff as the server's).
  if (uVignette > 0.0) {
    float d = distance(uv, vec2(0.5)) * 1.414;
    c *= 1.0 - uVignette * 0.75 * smoothstep(0.35, 1.0, d);
  }
  // Grain: the look's own plus the Grain / Old film effects.
  float g = uGrain + (fx == 1 ? 0.35 * k : 0.0) + (fx == 8 ? 0.25 * k : 0.0) + (fx == 5 ? 0.12 * k : 0.0);
  if (g > 0.0) {
    c += (hash(frag + fract(t) * 91.0) - 0.5) * 0.25 * g;
  }

  fragColor = vec4(clamp(c, 0.0, 1.0) * src.a, src.a);
}
