// Phlio avatar post-process (ImageFilter over the rendered 3D figure):
// smooths the polygon edges (the triangles are drawn without
// anti-aliasing), adds a soft ink outline around the silhouette like a
// cel-shaded game character, a faint inner edge line and a little extra
// saturation. Sampler 0 is the rendered figure (premultiplied alpha).
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;     // 0-1 pixels
uniform float uWidth;   // 2   outline width in pixels
uniform vec3 uInk;      // 3-5 outline colour
uniform float uOutline; // 6   outline strength 0-1

uniform sampler2D uTexture;

out vec4 fragColor;

vec4 tap(vec2 uv) { return texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0))); }

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec2 px = 1.0 / uSize;
  vec4 c = tap(uv);

  // Edge-aware smoothing (cheap FXAA-like): blend toward the neighbours
  // where the colour changes sharply.
  vec4 n = tap(uv + vec2(0.0, -px.y));
  vec4 s = tap(uv + vec2(0.0, px.y));
  vec4 e = tap(uv + vec2(px.x, 0.0));
  vec4 w = tap(uv + vec2(-px.x, 0.0));
  vec4 avg = (n + s + e + w) * 0.25;
  float lumC = dot(c.rgb, vec3(0.299, 0.587, 0.114));
  float lumA = dot(avg.rgb, vec3(0.299, 0.587, 0.114));
  float edge = clamp(abs(lumC - lumA) * 4.0 + abs(c.a - avg.a) * 2.0, 0.0, 1.0);
  c = mix(c, (c + avg) * 0.5, edge * 0.6);

  // Silhouette outline: the strongest alpha within uWidth pixels.
  float reach = 0.0;
  for (int i = 0; i < 12; i++) {
    float a = 6.2831853 * float(i) / 12.0;
    vec2 o = vec2(cos(a), sin(a)) * uWidth * px;
    reach = max(reach, tap(uv + o).a);
  }
  float outline = clamp(reach - c.a, 0.0, 1.0) * uOutline;

  // Inner edge: slightly darker just inside the silhouette.
  float inner = clamp(c.a - min(min(n.a, s.a), min(e.a, w.a)), 0.0, 1.0);
  c.rgb *= 1.0 - inner * 0.25;

  // A touch more saturation.
  float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
  c.rgb = mix(vec3(l) * c.a, c.rgb, 1.12);

  vec4 ink = vec4(uInk * outline, outline);
  fragColor = c + ink * (1.0 - c.a);
}
