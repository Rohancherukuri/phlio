// Phlio avatar stage: the backdrop behind the 3D avatar — a vertical
// gradient, a soft diagonal spotlight beam from above, a lit floor patch
// with a contact shadow and a few low-poly shards scattered around it.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1
uniform float uTime;    // 2
uniform vec3 uTop;      // 3-5
uniform vec3 uBottom;   // 6-8
uniform float uFloor;   // 9   floor line (0-1 of height); < 0 = no floor (close-ups)
uniform vec3 uShadow;   // 10-12

out vec4 fragColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float tri(vec2 p, vec2 a, vec2 b, vec2 c) {
  vec2 e0 = b - a, e1 = c - b, e2 = a - c;
  vec2 v0 = p - a, v1 = p - b, v2 = p - c;
  float s0 = e0.x * v0.y - e0.y * v0.x;
  float s1 = e1.x * v1.y - e1.y * v1.x;
  float s2 = e2.x * v2.y - e2.y * v2.x;
  return (s0 >= 0.0 && s1 >= 0.0 && s2 >= 0.0) || (s0 <= 0.0 && s1 <= 0.0 && s2 <= 0.0) ? 1.0 : 0.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float aspect = uSize.x / uSize.y;
  vec3 col = mix(uTop, uBottom, smoothstep(0.0, 1.0, uv.y));

  // Spotlight beam: a soft wedge from above, leaning slightly.
  vec2 apex = vec2(0.58, -0.25);
  vec2 d = uv - apex;
  float ang = atan(d.x * aspect, d.y);
  float beam = smoothstep(0.34, 0.12, abs(ang + 0.08)) * smoothstep(1.4, 0.2, length(d));
  col = mix(col, vec3(1.0), beam * 0.18 * (0.9 + 0.1 * sin(uTime * 0.7)));

  if (uFloor > 0.0) {
    vec2 f = vec2((uv.x - 0.5) * aspect, (uv.y - uFloor) * 3.2);
    // Lit floor patch.
    col = mix(col, vec3(1.0), smoothstep(0.75, 0.0, length(f * vec2(0.9, 1.0))) * 0.16);
    // Contact shadow (violet), soft at the edge.
    float sh = smoothstep(0.32, 0.05, length(f * vec2(1.0, 1.1)));
    col = mix(col, uShadow, sh * 0.55);
    // A few shards scattered on the floor.
    for (int i = 0; i < 7; i++) {
      float fi = float(i);
      vec2 c = vec2(0.5 + (hash(vec2(fi, 1.0)) - 0.5) * 0.7, uFloor + (hash(vec2(fi, 2.0)) - 0.4) * 0.06);
      float s = 0.008 + 0.01 * hash(vec2(fi, 3.0));
      vec2 p = uv - c;
      p.x *= aspect;
      float r = hash(vec2(fi, 4.0)) * 6.28;
      mat2 m = mat2(cos(r), -sin(r), sin(r), cos(r));
      p = m * p;
      float t = tri(p, vec2(-s, -s * 0.6), vec2(s, -s * 0.4), vec2(0.0, s));
      col = mix(col, uShadow * 0.9, t * 0.8);
    }
  }
  // Gentle vignette.
  vec2 q = uv - 0.5;
  col *= 1.0 - dot(q, q) * 0.35;
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
