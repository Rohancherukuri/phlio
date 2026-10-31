// Phlio moment templates: GPU backdrops behind photos and text.
//
// One shader, ten looks (uStyle):
//   0 mesh      four colour fields drifting into each other (mesh gradient)
//   1 aurora    ribbons of A/B/C over a dark D sky
//   2 paper     A paper stock with fibres, grain and a soft vignette
//   3 halftone  A→B gradient printed as dots on C
//   4 grid      Y2K perspective grid in C over an A→B sky
//   5 sunburst  A/B rays from the centre with a C glow
//   6 holo      holographic thin-film sheen tinted by A
//   7 film      warm light leaks (A, B) over dark D, with dust
//   8 linear    clean A→B diagonal gradient
//   9 checker   soft A/B checkerboard washed with C
// uGrain adds film grain to any style. uTime animates (0 = still).
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;    // 0-1
uniform float uTime;   // 2
uniform float uStyle;  // 3
uniform vec3 uA;       // 4-6
uniform vec3 uB;       // 7-9
uniform vec3 uC;       // 10-12
uniform vec3 uD;       // 13-15
uniform float uGrain;  // 16

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p *= 2.03;
    a *= 0.5;
  }
  return v;
}

vec3 mesh(vec2 uv, float t) {
  vec2 pa = vec2(0.2 + 0.15 * sin(t * 0.7), 0.15 + 0.1 * cos(t * 0.5));
  vec2 pb = vec2(0.85 + 0.1 * cos(t * 0.6), 0.3 + 0.15 * sin(t * 0.4));
  vec2 pc = vec2(0.25 + 0.15 * cos(t * 0.45), 0.85 + 0.08 * sin(t * 0.8));
  vec2 pd = vec2(0.8 + 0.1 * sin(t * 0.55), 0.8 + 0.1 * cos(t * 0.65));
  // Inverse-distance weights give the soft "mesh" blend.
  float wa = 1.0 / (0.02 + dot(uv - pa, uv - pa));
  float wb = 1.0 / (0.02 + dot(uv - pb, uv - pb));
  float wc = 1.0 / (0.02 + dot(uv - pc, uv - pc));
  float wd = 1.0 / (0.02 + dot(uv - pd, uv - pd));
  return (uA * wa + uB * wb + uC * wc + uD * wd) / (wa + wb + wc + wd);
}

vec3 aurora(vec2 uv, float t) {
  vec3 col = uD;
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float y = 0.25 + 0.18 * fi + 0.06 * sin(uv.x * 5.0 + t * (0.4 + 0.1 * fi) + fi * 2.0)
              + 0.08 * (fbm(vec2(uv.x * 2.0 + t * 0.1, fi)) - 0.5);
    float band = exp(-pow((uv.y - y) * 9.0, 2.0)) * (0.6 + 0.4 * fbm(vec2(uv.x * 6.0, t * 0.2 + fi)));
    vec3 c = i == 0 ? uA : (i == 1 ? uB : uC);
    col = mix(col, c, clamp(band, 0.0, 1.0) * 0.85);
  }
  // A few stars in the dark parts.
  float star = step(0.997, hash(floor(uv * uSize / 2.0)));
  return col + star * 0.6 * (1.0 - length(col - uD));
}

vec3 paper(vec2 uv) {
  float fibre = fbm(uv * vec2(18.0, 60.0)) * 0.06 + fbm(uv * 4.0) * 0.05;
  vec3 col = uA * (0.95 + fibre);
  float v = distance(uv, vec2(0.5));
  return col * (1.0 - 0.18 * smoothstep(0.3, 0.9, v));
}

vec3 halftone(vec2 frag, vec2 uv) {
  float cell = max(6.0, uSize.x / 70.0);
  vec2 g = frag / cell;
  // Rotated screen, like print.
  mat2 r = mat2(0.866, -0.5, 0.5, 0.866);
  vec2 q = r * g;
  vec2 c = fract(q) - 0.5;
  float tone = uv.y * 0.85 + 0.1 * sin(uv.x * 3.0);
  float radius = 0.5 * sqrt(clamp(tone, 0.0, 1.0));
  float dotMask = 1.0 - smoothstep(radius - 0.06, radius + 0.06, length(c));
  vec3 ink = mix(uA, uB, uv.y);
  return mix(uC, ink, dotMask);
}

vec3 grid(vec2 uv, float t) {
  vec3 sky = mix(uA, uB, smoothstep(0.0, 0.62, uv.y));
  float horizon = 0.62;
  if (uv.y < horizon) {
    float sun = smoothstep(0.2, 0.18, distance(uv, vec2(0.5, 0.42)));
    float stripes = step(0.5, fract(uv.y * 40.0)) * step(0.32, uv.y);
    return mix(sky, uC, sun * (1.0 - stripes * 0.8) * 0.9);
  }
  // Floor in perspective: z grows towards the horizon.
  float depth = (uv.y - horizon) / (1.0 - horizon);
  float z = 1.0 / max(depth, 0.01);
  float x = (uv.x - 0.5) * z;
  float lines = max(
      1.0 - smoothstep(0.0, 0.06 * z * 0.2 + 0.02, abs(fract(x * 2.0) - 0.5) * 2.0 - 0.9),
      1.0 - smoothstep(0.0, 0.08, abs(fract(z * 0.6 - t * 0.5) - 0.5) * 2.0 - 0.9));
  vec3 floorCol = mix(uB, uD, depth);
  return mix(floorCol, uC, clamp(lines, 0.0, 1.0) * (0.35 + 0.65 * depth));
}

vec3 sunburst(vec2 uv, float t) {
  vec2 p = (uv - vec2(0.5, 0.45)) * vec2(uSize.x / uSize.y, 1.0);
  float a = atan(p.y, p.x) + t * 0.05;
  float rays = step(0.0, sin(a * 18.0));
  vec3 col = mix(uA, uB, rays * 0.65);
  float glow = exp(-length(p) * 4.0);
  return mix(col, uC, glow * 0.9);
}

vec3 holo(vec2 uv, float t) {
  float n = fbm(uv * 3.0 + vec2(t * 0.05, -t * 0.04));
  float phase = uv.x * 1.6 + uv.y * 1.1 + n * 1.8 + t * 0.08;
  vec3 film = 0.5 + 0.5 * cos(6.2832 * (phase + vec3(0.0, 0.33, 0.67)));
  film = mix(film, vec3(1.0), 0.35);
  return mix(film, uA, 0.3);
}

vec3 filmLeak(vec2 uv, float t) {
  vec3 col = uD;
  float leak1 = exp(-pow(distance(uv, vec2(-0.05, 0.2 + 0.05 * sin(t * 0.3))) * 2.2, 2.0));
  float leak2 = exp(-pow(distance(uv, vec2(1.05, 0.75 + 0.05 * cos(t * 0.25))) * 2.0, 2.0));
  col = mix(col, uA, clamp(leak1 * 1.2, 0.0, 1.0));
  col = mix(col, uB, clamp(leak2 * 1.1, 0.0, 1.0));
  float dust = step(0.9985, hash(floor(uv * uSize / 1.5) + floor(t * 6.0)));
  return col + dust * 0.5;
}

vec3 checker(vec2 uv) {
  vec2 q = uv * vec2(6.0, 6.0 * uSize.y / uSize.x);
  float c = mod(floor(q.x) + floor(q.y), 2.0);
  vec3 col = mix(uA, uB, c);
  return mix(col, uC, 0.25 * uv.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float t = uTime;
  int style = int(uStyle + 0.5);
  vec3 col;
  if (style == 0) col = mesh(uv, t);
  else if (style == 1) col = aurora(uv, t);
  else if (style == 2) col = paper(uv);
  else if (style == 3) col = halftone(frag, uv);
  else if (style == 4) col = grid(uv, t);
  else if (style == 5) col = sunburst(uv, t);
  else if (style == 6) col = holo(uv, t);
  else if (style == 7) col = filmLeak(uv, t);
  else if (style == 9) col = checker(uv);
  else col = mix(uA, uB, clamp(uv.x * 0.4 + uv.y * 0.6, 0.0, 1.0));
  col += (hash(frag + fract(t) * 37.0) - 0.5) * uGrain * 0.12;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
