// Phlio "Hacker" theme backdrop (original artwork, drawn procedurally):
// a black screen with halftone sonar rings pulsing out from the centre,
// a dithered halftone wash in the accent colour, CRT scanlines, a slow
// rolling scan bar and the odd horizontal glitch slice with an RGB split.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1
uniform float uTime;    // 2
uniform vec3 uAccent;   // 3-5
uniform float uGlitch;  // 6  (0-1)

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

// Halftone: a dot grid whose dot size follows `level` (0-1).
float halftone(vec2 frag, float level, float cell) {
  vec2 g = mod(frag, cell) - cell * 0.5;
  float r = cell * 0.5 * sqrt(clamp(level, 0.0, 1.0)) * 1.15;
  return smoothstep(r + 0.8, r - 0.8, length(g));
}

// Grey halftone of rings and paper-like blobs (r), and the accent
// halftone of a torn diagonal strip (g).
vec2 scene(vec2 frag, float t) {
  vec2 uv = frag / uSize;
  vec2 c = vec2((uv.x - 0.5) * uSize.x / uSize.y, uv.y - 0.42);
  float d = length(c);
  // Sonar rings: bands moving outward, broken up by noise.
  float rings = 0.5 + 0.5 * sin(d * 30.0 - t * 1.4);
  rings = smoothstep(0.4, 0.95, rings) * smoothstep(1.3, 0.12, d);
  rings *= 0.45 + 0.55 * noise(vec2(atan(c.y, c.x) * 3.0, d * 5.0 - t * 0.15));
  // Collage blobs drifting slowly.
  float blobs = smoothstep(0.52, 0.8, noise(uv * vec2(2.6, 1.6) + vec2(t * 0.02, -t * 0.015)));
  float grey = max(rings * 0.9, blobs * 0.55);
  // A torn diagonal strip with ragged edges.
  float k = uv.x * 0.55 + uv.y;
  float edge = (noise(vec2(uv.x * 40.0, 3.0)) - 0.5) * 0.035 + (noise(vec2(uv.x * 9.0, 8.0)) - 0.5) * 0.05;
  float strip = smoothstep(0.0, 0.004, k - 1.02 - edge) * smoothstep(0.0, 0.004, 1.22 + edge - k);
  float accent = strip * (0.4 + 0.3 * noise(uv * 5.0 + t * 0.05));
  return vec2(halftone(frag, grey * (1.0 - strip), 6.0),
              halftone(frag + 3.0, accent, 5.0));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float t = uTime;

  // Glitch slices: a few horizontal bands shift sideways now and then.
  float row = floor(frag.y / 18.0);
  float burst = step(0.82, hash(vec2(floor(t * 3.0), 7.0))) * uGlitch;
  float slice = step(0.88, hash(vec2(row, floor(t * 12.0)))) * burst;
  float shift = (hash(vec2(row, floor(t * 20.0))) - 0.5) * 60.0 * slice;

  vec2 r = scene(frag + vec2(shift + 2.5 * slice, 0.0), t);
  vec2 g = scene(frag + vec2(shift, 0.0), t);
  vec2 b = scene(frag + vec2(shift - 2.5 * slice, 0.0), t);

  vec3 paper = vec3(0.78, 0.8, 0.82);
  vec3 col = vec3(r.x, g.x, b.x) * mix(paper, uAccent, 0.18) * 0.62
           + vec3(r.y, g.y, b.y) * uAccent * 0.75;

  // CRT scanlines and a slow rolling bright bar.
  col *= 0.82 + 0.18 * step(0.5, fract(frag.y / 3.0));
  float bar = fract(frag.y / uSize.y - t * 0.08);
  col += uAccent * 0.06 * smoothstep(0.06, 0.0, abs(bar - 0.5));
  // Static noise and vignette.
  col += (hash(frag + fract(t) * 91.0) - 0.5) * 0.05;
  vec2 uv = frag / uSize;
  col *= smoothstep(1.15, 0.35, length(uv - 0.5) * 1.2);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
