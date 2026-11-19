// Story effects — lens, distortion and camera-motion effects.
//
// Everything here moves pixels: lens curves (fisheye, barrel…), mirrors
// and kaleidoscopes, waves, swirls, glitches, blurs, and the photo
// versions of Camera & motion effects (superzoom, strobe, split screen,
// contact sheets…). Ids match lib/shared/media/story_fx_catalog.dart.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;   // 0-1
uniform float uTime;  // 2
uniform float uFx;    // 3
uniform float uAmount; // 4
uniform vec2 uCenter; // 5-6 focus point (0-1)

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

vec4 raw(vec2 uv) { return texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0))); }

vec3 tap(vec2 uv) {
  vec4 s = raw(uv);
  return s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
}

// Mirror-repeat so distortions never smear the edge pixels.
vec2 fold(vec2 uv) { return 1.0 - abs(1.0 - mod(uv, 2.0)); }

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 hue(float h) { return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); }

// Disc blur of radius r (px), 16 taps on a spiral.
vec3 disc(vec2 uv, float r) {
  vec3 s = tap(uv);
  for (int i = 1; i < 16; i++) {
    float f = float(i);
    float a = f * 2.39996;
    s += tap(uv + vec2(cos(a), sin(a)) * sqrt(f / 15.0) * r / uSize);
  }
  return s / 16.0;
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
  vec2 ctr = uCenter;
  vec2 p = uv - ctr;
  p.x *= aspect;
  float r = length(p);
  float ang = atan(p.y, p.x);
  vec4 src = raw(uv);
  vec3 c = src.a > 0.0 ? src.rgb / src.a : vec3(0.0);
  float alpha = src.a;

  if (fx == 1) { // fisheye
    float f = mix(1.0, 0.45 + 1.9 * r * r, k);
    vec2 q = ctr + p * f / vec2(aspect, 1.0);
    c = tap(q) * (1.0 - k * smoothstep(0.62, 0.72, r));
  } else if (fx == 2) { // wide angle: stretch the edges
    vec2 q = ctr + p * (1.0 - 0.28 * k * (1.0 - r * r)) / vec2(aspect, 1.0);
    c = tap(q);
  } else if (fx == 3 || fx == 4) { // barrel / pincushion
    float s = fx == 3 ? -0.35 : 0.35;
    vec2 q = ctr + p * (1.0 + s * k * r * r) / vec2(aspect, 1.0);
    c = (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) ? vec3(0.0) : tap(q);
  } else if (fx == 5) { // kaleidoscope: 6 mirrored slices
    float n = 6.0;
    float seg = 2.0 * PI / n;
    float a = mod(ang + t * 0.15 * k, seg);
    a = abs(a - seg * 0.5);
    vec2 q = ctr + vec2(cos(a), sin(a)) * r / vec2(aspect, 1.0);
    c = mix(c, tap(fold(q)), k);
  } else if (fx == 6) { // mirror: left half reflected
    vec2 q = vec2(uv.x < 0.5 ? uv.x : 1.0 - uv.x, uv.y);
    c = mix(c, tap(q), k);
  } else if (fx == 7) { // infinity mirror: nested shrinking frames
    vec2 q = uv - 0.5;
    float m = max(abs(q.x), abs(q.y)) * 2.0;
    float level = floor(-log2(max(m, 0.001)) / log2(1.0 / 0.82));
    vec2 inner = q / pow(0.82, level) + 0.5;
    c = tap(inner) * (1.0 - 0.07 * level * k);
    c = mix(tap(uv), c, k);
  } else if (fx == 8) { // infinite zoom: endless magnification
    float z = fract(t * 0.18);
    float scale = pow(2.0, z);
    vec2 q = (uv - 0.5) / scale + 0.5;
    vec2 q2 = (uv - 0.5) / (scale * 0.5) + 0.5; // the next loop's frame, so the cycle is seamless
    c = mix(tap(q), tap(q2), smoothstep(0.75, 1.0, z));
    c = mix(tap(uv), c, k);
  } else if (fx == 9) { // tunnel
    float d = 0.25 / max(r, 0.02) + t * 0.3;
    vec2 q = vec2(ang / (2.0 * PI) + 0.5, fract(d));
    vec3 tun = tap(fold(q * vec2(2.0, 1.0))) * smoothstep(0.0, 0.35, r);
    c = mix(c, tun, k);
  } else if (fx == 10 || fx == 24) { // wave / wavy
    float amp = (fx == 10 ? 0.02 : 0.012) * k;
    vec2 q = uv + vec2(sin(uv.y * 14.0 + t * 2.4), cos(uv.x * 11.0 + t * 1.8) * (fx == 24 ? 1.0 : 0.3)) * amp;
    c = tap(fold(q));
  } else if (fx == 11) { // ripple: rings from the centre
    float w = sin(r * 60.0 - t * 6.0) * 0.012 * k * smoothstep(0.9, 0.0, r);
    c = tap(fold(uv + normalize(p + 1e-5) / vec2(aspect, 1.0) * w));
  } else if (fx == 12) { // swirl
    float a = ang + k * 3.2 * smoothstep(0.55, 0.0, r) * (1.0 + 0.15 * sin(t));
    c = tap(fold(ctr + vec2(cos(a), sin(a)) * r / vec2(aspect, 1.0)));
  } else if (fx == 13 || fx == 14) { // bulge / pinch
    float rad = 0.42;
    float f = fx == 14 ? pow(smoothstep(0.0, rad, r), 0.6 + 0.4 * (1.0 - k)) : pow(smoothstep(0.0, rad, r), 1.0 + 1.2 * k);
    f = r < rad ? f * rad / max(r, 1e-4) : 1.0;
    c = tap(ctr + p * f / vec2(aspect, 1.0));
  } else if (fx == 15) { // melt: pixels drip downwards
    float drip = noise(vec2(uv.x * 18.0, 0.0)) * 0.6 + noise(vec2(uv.x * 60.0, 1.0)) * 0.4;
    float pull = k * (0.12 + 0.08 * sin(t * 0.8)) * drip * smoothstep(0.1, 0.9, uv.y);
    c = tap(vec2(uv.x + sin(uv.y * 20.0 + t) * 0.004 * k, uv.y - pull));
  } else if (fx == 16) { // glass: fluted panes refracting
    float cols = 14.0;
    float x = fract(uv.x * cols);
    vec2 q = vec2(uv.x + sin(x * PI * 2.0) * 0.025 * k, uv.y + sin(uv.x * cols * PI * 2.0) * 0.003 * k);
    c = tap(q) * (1.0 - 0.08 * k * smoothstep(0.85, 1.0, x)) + vec3(0.1) * k * pow(max(0.0, 1.0 - abs(x - 0.3) * 4.0), 3.0);
  } else if (fx == 17) { // RGB split
    vec2 d = vec2(0.012, 0.004) * k;
    c = vec3(tap(uv + d).r, c.g, tap(uv - d).b);
  } else if (fx == 18) { // chromatic pulse
    float pulse = 0.5 + 0.5 * sin(t * 4.0);
    vec2 d = (uv - 0.5) * 0.03 * k * pulse;
    c = vec3(tap(uv + d).r, tap(uv).g, tap(uv - d).b);
  } else if (fx == 19) { // pixel sort: bright pixels stream downwards
    // Each column smears a run of pixels downwards; only mid tones sort.
    float col = floor(frag.x / 2.0);
    float len = floor(hash(vec2(col, 3.0)) * 24.0 * k) + 1.0;
    vec3 sum = c;
    float n = 1.0;
    for (int i = 1; i < 24; i++) {
      if (float(i) < len) {
        vec3 s = tap(uv - vec2(0.0, float(i) * 3.0 / uSize.y));
        float ls = luma(s);
        if (ls > 0.25 && ls < 0.9) {
          sum += s;
          n += 1.0;
        }
      }
    }
    float lc = luma(c);
    c = mix(c, sum / n, step(0.25, lc) * step(lc, 0.9));
  } else if (fx == 20) { // glitch: jumping slices, blocks, channel split
    float band = floor(uv.y * 30.0);
    float trig = step(0.8, hash(vec2(band, floor(t * 10.0))));
    float shift = (hash(vec2(band, floor(t * 14.0))) - 0.5) * 0.14 * trig * k;
    vec2 g = vec2(uv.x + shift, uv.y);
    c = vec3(tap(g + vec2(0.008 * k, 0.0)).r, tap(g).g, tap(g - vec2(0.008 * k, 0.0)).b);
    vec2 block = floor(frag / 24.0);
    if (hash(block + floor(t * 6.0)) > 1.0 - 0.04 * k) c = c.gbr;
  } else if (fx == 21) { // liquid: flowing noise warp
    vec2 w = vec2(noise(uv * 4.0 + t * 0.35), noise(uv * 4.0 + 7.3 - t * 0.3)) - 0.5;
    c = tap(fold(uv + w * 0.07 * k));
  } else if (fx == 22) { // prism: three tinted ghosts
    vec2 d = vec2(0.035, 0.0) * k;
    vec3 a = tap(uv - d) * vec3(1.0, 0.25, 0.25);
    vec3 b = tap(uv) * vec3(0.25, 1.0, 0.25);
    vec3 e = tap(uv + d) * vec3(0.25, 0.25, 1.0);
    c = mix(c, (a + b + e) / 1.5, k);
  } else if (fx == 23 || fx == 30) { // zoom blur / superzoom
    float strength = fx == 23 ? 0.12 * k : 0.2 * k * smoothstep(0.0, 0.25, fract(t * 0.6)) * (1.0 - smoothstep(0.6, 1.0, fract(t * 0.6)));
    float zoom = fx == 30 ? 1.0 + 0.6 * k * smoothstep(0.0, 0.4, fract(t * 0.6)) : 1.0;
    vec2 base = ctr + (uv - ctr) / zoom;
    vec3 s = vec3(0.0);
    for (int i = 0; i < 16; i++) {
      float f = float(i) / 15.0;
      s += tap(ctr + (base - ctr) * (1.0 - strength * f));
    }
    c = s / 16.0;
  } else if (fx == 25) { // moiré interference
    float m = sin((frag.x + frag.y) * 0.9) * sin(r * 160.0 - t * 2.0);
    c = mix(c, c * (0.75 + 0.5 * vec3(0.5 + 0.5 * m)), k);
    c += hue(fract(m * 0.3 + t * 0.05)) * 0.08 * k;
  } else if (fx == 27) { // motion blur: sideways streak
    vec3 s = vec3(0.0);
    for (int i = 0; i < 16; i++) s += tap(uv + vec2((float(i) / 15.0 - 0.5) * 0.06 * k, 0.0));
    c = s / 16.0;
  } else if (fx == 28) { // camera shake
    vec2 j = vec2(noise(vec2(t * 9.0, 0.0)) - 0.5, noise(vec2(0.0, t * 8.0)) - 0.5) * 0.04 * k;
    c = tap((uv - 0.5) * 0.96 + 0.5 + j);
  } else if (fx == 29) { // strobe
    float on = step(0.5, fract(t * 6.0));
    c = mix(c, on > 0.5 ? min(c * 1.8 + 0.15, 1.0) : c * 0.25, k);
  } else if (fx == 31) { // dolly zoom: centre holds, background stretches
    float z = 0.5 + 0.5 * sin(t * 1.2);
    float f = mix(1.0, 1.0 - 0.35 * z * k, smoothstep(0.08, 0.7, r));
    c = tap(ctr + p * f / vec2(aspect, 1.0));
  } else if (fx == 32) { // split screen (2 x 2)
    vec2 q = fract(uv * 2.0);
    c = mix(c, tap((q - 0.5) * 0.9 + 0.5), k);
  } else if (fx == 33 || fx == 34) { // contact sheet (3 x 4) / five frames
    vec2 n = fx == 33 ? vec2(3.0, 4.0) : vec2(1.0, 5.0);
    vec2 cell = floor(uv * n);
    vec2 q = fract(uv * n);
    float idx = cell.x + cell.y * n.x;
    float zoom = 1.0 + 0.08 * hash(cell);
    vec2 jitter = (vec2(hash(cell + 1.3), hash(cell + 7.1)) - 0.5) * 0.08;
    // Each cell shows the photo cropped to the cell's shape (no stretching).
    vec2 m = fx == 33
        ? vec2(0.5 + (q.x - 0.5) * 0.75, q.y)
        : vec2(q.x, 0.5 + (q.y - 0.5) * 0.2 + (idx - 2.0) * 0.12);
    vec3 frame = tap((m - 0.5) / zoom + 0.5 + jitter);
    float border = step(0.04, q.x) * step(q.x, 0.96) * step(0.04, q.y) * step(q.y, 0.96);
    c = mix(c, mix(vec3(0.08), frame, border), k);
  } else if (fx == 35) { // shuffle: tiles swapped around
    vec2 n = vec2(3.0, 4.0);
    vec2 cell = floor(uv * n);
    float pick = floor(hash(cell + floor(t * 0.7)) * 12.0);
    vec2 other = vec2(mod(pick, 3.0), floor(pick / 3.0));
    c = mix(c, tap((other + fract(uv * n)) / n), k);
  } else if (fx == 36 || fx == 37) { // clone / ghost trail: fading copies
    vec3 s = c;
    float wsum = 1.0;
    for (int i = 1; i < 6; i++) {
      float f = float(i);
      vec2 off = fx == 36 ? vec2(f * 0.07, 0.0) * k : vec2(sin(t * 2.0 + f * 0.5), cos(t * 1.7 + f * 0.5)) * 0.02 * f * k;
      float w = fx == 36 ? 0.55 / f : 0.6 / f;
      s += tap(uv - off) * w;
      wsum += w;
    }
    c = s / wsum;
  } else if (fx == 38 || fx == 39) { // cinematic blur / tilt-shift
    float focus = fx == 38 ? smoothstep(0.18, 0.6, r) : smoothstep(0.08, 0.35, abs(uv.y - ctr.y));
    c = mix(c, disc(uv, 14.0 * k * focus), focus);
    if (fx == 39) c = mix(vec3(luma(c)), c, 1.0 + 0.35 * k);
  }

  fragColor = vec4(clamp(c, 0.0, 1.0) * alpha, alpha);
}
