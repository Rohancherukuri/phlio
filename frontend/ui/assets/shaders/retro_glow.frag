// Phlio Stream · Music: animated "retro glow" backdrop for the player.
// Three drifting colour fields from the album art (or the Phlio palette),
// soft film grain and faint scanlines, breathing with playback.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1
uniform float uTime;    // 2
uniform vec3 uA;        // 3-5
uniform vec3 uB;        // 6-8
uniform vec3 uC;        // 9-11
uniform float uEnergy;  // 12  0 paused .. 1 playing
uniform float uBase;    // 13  0 black base, 1 white base

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(443.897, 441.423));
  p += dot(p, p.yx + 19.19);
  return fract((p.x + p.y) * p.x);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float aspect = uSize.x / uSize.y;
  vec2 p = vec2(uv.x * aspect, uv.y);
  float t = uTime * (0.12 + 0.25 * uEnergy);

  vec2 c1 = vec2(aspect * (0.25 + 0.20 * sin(t * 1.3)), 0.25 + 0.15 * cos(t * 1.1));
  vec2 c2 = vec2(aspect * (0.80 + 0.15 * cos(t * 0.9)), 0.55 + 0.20 * sin(t * 0.7));
  vec2 c3 = vec2(aspect * (0.40 + 0.25 * sin(t * 0.6 + 2.0)), 0.90 + 0.10 * cos(t * 1.4));

  float w1 = exp(-3.2 * dot(p - c1, p - c1));
  float w2 = exp(-2.6 * dot(p - c2, p - c2));
  float w3 = exp(-3.0 * dot(p - c3, p - c3));

  vec3 base = mix(vec3(0.03, 0.04, 0.07), vec3(0.97, 0.97, 0.99), uBase);
  float glow = mix(0.85, 0.55, uBase) * (0.75 + 0.25 * uEnergy);
  vec3 col = base;
  col = mix(col, uA, clamp(w1 * glow, 0.0, 1.0));
  col = mix(col, uB, clamp(w2 * glow, 0.0, 1.0));
  col = mix(col, uC, clamp(w3 * glow * 0.8, 0.0, 1.0));

  // Retro texture: grain + faint scanlines + vignette.
  col += (hash(frag + fract(uTime) * 61.0) - 0.5) * 0.045;
  col *= 1.0 - 0.035 * step(0.5, fract(frag.y * 0.5)) * (1.0 - uBase);
  float v = distance(uv, vec2(0.5));
  col *= 1.0 - mix(0.45, 0.12, uBase) * smoothstep(0.35, 0.95, v);

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
