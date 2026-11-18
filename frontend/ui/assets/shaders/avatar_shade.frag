// Phlio avatar shading: gives the flat avatar parts (face, hair, clothes)
// a soft 2.5D, toon-lit look. Each part is filled with this shader; the
// part's bounding box stands in for a rounded 3D surface, so the normal is
// taken from an ellipsoid fitted to the box and lit by a key light from the
// upper left, quantised into soft toon bands, with a rim light and (for
// hair) an anisotropic sheen band.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uRect;    // 0-3  part bounds (x, y, w, h) in canvas pixels
uniform vec3 uColor;   // 4-6  base colour (0-1)
uniform float uKind;   // 7    0 skin, 1 hair, 2 cloth, 3 flat (no shading)
uniform float uTime;   // 8    seconds (sheen drift)
uniform vec3 uRim;     // 9-11 rim light colour

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = (frag - uRect.xy) / max(uRect.zw, vec2(1.0));
  vec2 p = uv * 2.0 - 1.0;                  // -1..1 across the part
  float r2 = dot(p * vec2(0.92, 0.95), p * vec2(0.92, 0.95));
  vec3 n = normalize(vec3(p.x * 0.85, p.y * 0.85, sqrt(max(0.06, 1.0 - min(r2, 0.94)))));
  vec3 light = normalize(vec3(-0.45, -0.6, 0.75));
  float diff = max(dot(n, light), 0.0);
  int kind = int(uKind + 0.5);

  vec3 base = uColor;
  vec3 col;
  if (kind == 3) {
    col = base;
  } else {
    // Soft toon bands: shadow / mid / lit.
    float band = smoothstep(0.18, 0.30, diff) * 0.55 + smoothstep(0.62, 0.74, diff) * 0.45;
    vec3 shadow = base * vec3(0.70, 0.66, 0.76);          // cool shadow
    vec3 lit = min(base * 1.12 + vec3(0.03, 0.025, 0.0), vec3(1.0));
    col = mix(shadow, lit, band);
    // Subsurface warmth on skin, near the edges.
    if (kind == 0) col += vec3(0.06, 0.015, 0.0) * smoothstep(0.4, 0.95, r2);
    // Rim light on the shadow side.
    float rim = pow(1.0 - n.z, 2.6) * smoothstep(0.0, 0.6, p.x + 0.2);
    col = mix(col, uRim, clamp(rim * 0.55, 0.0, 0.55));
    if (kind == 1) {
      // Hair sheen: a bright band that drifts slowly.
      float y = uv.y + 0.03 * sin(uTime * 0.8 + uv.x * 6.0);
      float sheen = exp(-pow((y - 0.32) * 9.0, 2.0)) * (0.5 + 0.5 * n.z);
      col += vec3(0.22) * sheen;
    }
    if (kind == 2) {
      // Fabric: faint vertical weave.
      col *= 0.97 + 0.03 * sin(frag.x * 1.7);
    }
  }
  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
