// Phlio profile & chat effects: an animated overlay drawn over the
// background colour / wallpaper (transparent where there is no effect).
//
// uEffect:
//   1 sparkles   glints that twinkle and drift upward
//   2 snow       three layers of falling flakes with sway
//   3 aurora     soft ribbons of light across the top
//   4 stars      a twinkling star field with the odd shooting star
//   5 bokeh      large soft out-of-focus circles drifting
//   6 fireflies  glowing points wandering with a slow pulse
//   7 hearts     little hearts floating up with a sway
//   8 confetti   tumbling coloured paper falling
//   9 rain       light diagonal rain streaks
//  10 petals     blossom petals drifting down and spinning
//  11 bubbles    soap bubbles rising, with a rim and a highlight
//  12 galaxy     a slow swirling nebula with a few stars
//  13 matrix     falling columns of glowing code glyphs
//  14 glitch     scanlines, flickering blocks and RGB-split bars
// uColor tints the effect; uIntensity (0.1-1) scales density/brightness.
// Output is premultiplied alpha.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;       // 0-1
uniform float uTime;      // 2
uniform float uEffect;    // 3
uniform vec3 uColor;      // 4-6
uniform float uIntensity; // 7

out vec4 fragColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

vec2 hash2(vec2 p) {
  float n = hash(p);
  return vec2(n, hash(p + n + 17.17));
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p *= 2.02;
    a *= 0.5;
  }
  return v;
}

// A four-pointed glint at distance d (in cells) with rotation-free arms.
float glint(vec2 d, float size) {
  float core = size / (length(d) + 0.0001);
  float arms = size * 0.35 / (abs(d.x * d.y) * 40.0 + 0.02);
  return clamp(core * 0.06 + arms * 0.015, 0.0, 1.5) * smoothstep(0.5, 0.0, length(d));
}

vec4 sparkles(vec2 uv, float aspect, float t) {
  float a = 0.0;
  for (int layer = 0; layer < 2; layer++) {
    float scale = 7.0 + float(layer) * 5.0;
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y += t * (0.25 + 0.15 * float(layer));  // drift upward
    vec2 cell = floor(p);
    vec2 r = hash2(cell + float(layer) * 31.0);
    if (r.x > 0.35 + 0.5 * (1.0 - uIntensity)) {
      vec2 center = cell + 0.2 + 0.6 * hash2(cell * 1.7);
      float tw = pow(0.5 + 0.5 * sin(t * (1.5 + 2.5 * r.y) + r.x * 40.0), 6.0);
      a += glint(p - center, 0.6 + 0.6 * r.y) * tw;
    }
  }
  a = clamp(a, 0.0, 1.0);
  vec3 col = mix(uColor, vec3(1.0), 0.45 * a);
  return vec4(col * a, a);
}

vec4 snow(vec2 uv, float aspect, float t) {
  float a = 0.0;
  for (int layer = 0; layer < 3; layer++) {
    float fl = float(layer);
    float scale = 6.0 + fl * 6.0;
    float speed = 0.12 + 0.06 * (2.0 - fl);
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y -= t * speed * scale;                 // falling
    p.x += sin(p.y * 0.35 + t * 0.8 + fl) * 0.35;  // sway
    vec2 cell = floor(p);
    vec2 r = hash2(cell + fl * 13.0);
    if (r.x < 0.25 + 0.6 * uIntensity) {
      vec2 center = cell + 0.15 + 0.7 * hash2(cell + 3.1);
      float radius = (0.06 + 0.1 * r.y) * (1.2 - fl * 0.25);
      float d = length(p - center);
      a += smoothstep(radius, radius * 0.25, d) * (0.95 - fl * 0.2);
    }
  }
  a = clamp(a, 0.0, 1.0);
  vec3 col = mix(vec3(1.0), uColor, 0.25);
  return vec4(col * a, a);
}

vec4 aurora(vec2 uv, float aspect, float t) {
  float a = 0.0;
  vec3 col = vec3(0.0);
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float y = 0.18 + fi * 0.09 + 0.06 * sin(uv.x * 3.0 + t * 0.3 + fi * 2.0)
              + 0.08 * (fbm(vec2(uv.x * 2.5 + t * 0.06 + fi, t * 0.05)) - 0.5);
    float dy = (uv.y - y) / (0.035 + 0.03 * fi);
    float band = exp(-dy * dy);  // no pow() on a negative base
    // Vertical "curtain" streaks.
    float streak = 0.55 + 0.45 * fbm(vec2(uv.x * 22.0 + fi * 5.0, t * 0.25));
    float s = band * streak;
    vec3 tint = i == 0 ? uColor : (i == 1 ? mix(uColor, vec3(0.4, 1.0, 0.8), 0.6)
                                          : mix(uColor, vec3(0.7, 0.5, 1.0), 0.6));
    col += tint * s;
    a += s;
  }
  a = clamp(a * (0.45 + 0.55 * uIntensity), 0.0, 0.85);
  col = col / max(a, 0.001) * a;
  return vec4(clamp(col * (0.45 + 0.55 * uIntensity), 0.0, 1.0), a);
}

vec4 stars(vec2 uv, float aspect, float t) {
  vec2 p = vec2(uv.x * aspect, uv.y) * 38.0;
  vec2 cell = floor(p);
  vec2 r = hash2(cell);
  float a = 0.0;
  if (r.x > 0.86 - 0.12 * uIntensity) {
    vec2 center = cell + 0.25 + 0.5 * hash2(cell + 9.0);
    float tw = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(t * (0.8 + 2.0 * r.y) + r.x * 60.0), 3.0);
    a += smoothstep(0.12 + 0.1 * r.y, 0.0, length(p - center)) * tw;
  }
  // A shooting star every ~6 s along a random diagonal.
  float cycle = floor(t / 6.0);
  float k = fract(t / 6.0);
  vec2 s0 = vec2(0.15 + 0.7 * hash(vec2(cycle, 1.0)), 0.05 + 0.3 * hash(vec2(cycle, 2.0)));
  vec2 dir = normalize(vec2(1.0, 0.45));
  vec2 head = s0 + dir * k * 0.9;
  vec2 q = vec2((uv.x - head.x) * aspect, uv.y - head.y);
  float along = dot(q, dir);
  float across = abs(dot(q, vec2(-dir.y, dir.x)));
  float trail = smoothstep(0.0025, 0.0, across) * smoothstep(-0.22, 0.0, along) * step(along, 0.0);
  a += trail * smoothstep(0.0, 0.1, k) * smoothstep(0.55, 0.3, k);
  a = clamp(a, 0.0, 1.0);
  vec3 col = mix(vec3(1.0), uColor, 0.35);
  return vec4(col * a, a);
}

vec4 bokeh(vec2 uv, float aspect, float t) {
  float a = 0.0;
  vec3 col = vec3(0.0);
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    float scale = 2.6 + fl * 2.0;
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p += vec2(t * 0.05 * (1.0 + fl), -t * 0.035);
    vec2 cell = floor(p);
    vec2 r = hash2(cell + fl * 7.0);
    if (r.x < 0.3 + 0.55 * uIntensity) {
      vec2 center = cell + 0.25 + 0.5 * hash2(cell + 4.0) + 0.12 * vec2(sin(t * 0.4 + r.y * 6.0), cos(t * 0.3 + r.x * 6.0));
      float radius = 0.18 + 0.2 * r.y;
      float d = length(p - center);
      float disk = smoothstep(radius, radius * 0.82, d);
      float rim = smoothstep(radius * 0.7, radius, d) * disk;
      float s = (disk * 0.16 + rim * 0.12) * (0.7 + 0.3 * sin(t * 0.6 + r.x * 9.0));
      col += mix(uColor, vec3(1.0, 0.85, 0.95), r.y * 0.5) * s;
      a += s;
    }
  }
  a = clamp(a, 0.0, 0.6);
  return vec4(clamp(col, 0.0, 1.0), a);
}

vec4 fireflies(vec2 uv, float aspect, float t) {
  float a = 0.0;
  vec2 p = vec2(uv.x * aspect, uv.y) * 5.0;
  vec2 base = floor(p);
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 cell = base + vec2(float(x), float(y));
      vec2 r = hash2(cell);
      if (r.x <= 0.75 - 0.5 * uIntensity) {
      vec2 wander = vec2(sin(t * (0.3 + r.x * 0.4) + r.y * 6.28), cos(t * (0.25 + r.y * 0.4) + r.x * 6.28));
      vec2 center = cell + 0.5 + 0.38 * wander;
      float pulse = 0.3 + 0.7 * pow(0.5 + 0.5 * sin(t * (1.2 + r.y) + r.x * 30.0), 2.0);
      float d = length(p - center);
      a += (smoothstep(0.06, 0.0, d) + 0.35 * exp(-d * d * 60.0)) * pulse;
      }
    }
  }
  a = clamp(a, 0.0, 1.0);
  vec3 col = mix(uColor, vec3(1.0, 1.0, 0.85), 0.35 * a);
  return vec4(col * a, a);
}

float dot2(vec2 v) { return dot(v, v); }

// Signed distance to a heart (Inigo Quilez), point-up at the bottom.
float sdHeart(vec2 p) {
  p.x = abs(p.x);
  if (p.y + p.x > 1.0) return sqrt(dot2(p - vec2(0.25, 0.75))) - 0.3535534;
  return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

mat2 rot(float a) {
  float c = cos(a), s = sin(a);
  return mat2(c, -s, s, c);
}

vec4 hearts(vec2 uv, float aspect, float t) {
  float a = 0.0;
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    float scale = 5.0 + fl * 3.0;
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y += t * (0.35 + 0.2 * fl);
    vec2 cell = floor(p);
    vec2 r = hash2(cell + fl * 11.0);
    if (r.x < 0.2 + 0.45 * uIntensity) {
      vec2 center = cell + 0.5 + vec2(0.25 * sin(t * 1.3 + r.y * 6.0), 0.0);
      vec2 q = (p - center) / (0.22 + 0.12 * r.y);
      q.y = -q.y + 0.55;  // flip: screen y grows down
      float d = sdHeart(q);
      a += smoothstep(0.08, -0.04, d) * (0.65 + 0.35 * sin(t * 2.0 + r.x * 9.0));
    }
  }
  a = clamp(a, 0.0, 1.0);
  vec3 col = mix(vec3(1.0, 0.42, 0.65), uColor, 0.45);
  return vec4(col * a, a * 0.9);
}

vec4 confetti(vec2 uv, float aspect, float t) {
  vec3 col = vec3(0.0);
  float a = 0.0;
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    float scale = 7.0 + fl * 4.0;
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y -= t * (0.9 + 0.4 * fl);
    vec2 cell = floor(p);
    vec2 r = hash2(cell + fl * 5.0);
    if (r.x < 0.25 + 0.5 * uIntensity) {
      vec2 center = cell + 0.5 + 0.3 * vec2(sin(t + r.y * 6.0), 0.0);
      vec2 q = rot(t * (1.5 + 2.0 * r.y) + r.x * 6.28) * (p - center);
      q.x /= max(0.15, abs(cos(t * 3.0 + r.x * 12.0)));  // flip as it tumbles
      float box = step(abs(q.x), 0.16) * step(abs(q.y), 0.08);
      float k = fract(r.y * 7.0);
      vec3 c = k < 0.2 ? vec3(1.0, 0.71, 0.56) : k < 0.4 ? vec3(0.55, 0.47, 1.0)
             : k < 0.6 ? vec3(0.41, 0.84, 0.8) : k < 0.8 ? vec3(0.9, 0.58, 0.84) : uColor;
      col += c * box;
      a += box;
    }
  }
  a = clamp(a, 0.0, 1.0);
  return vec4(clamp(col, 0.0, 1.0) * a, a);
}

vec4 rain(vec2 uv, float aspect, float t) {
  float a = 0.0;
  for (int layer = 0; layer < 3; layer++) {
    float fl = float(layer);
    vec2 p = vec2(uv.x * aspect + uv.y * 0.18, uv.y);
    p *= vec2(40.0 + fl * 20.0, 3.0 + fl);
    p.y -= t * (2.6 + fl * 0.8);
    vec2 cell = floor(p);
    vec2 r = hash2(cell + fl * 3.0);
    if (r.x < 0.12 + 0.3 * uIntensity) {
      vec2 f = fract(p);
      float streak = smoothstep(0.5, 0.0, abs(f.x - 0.5) * 6.0) * smoothstep(0.0, 0.4, f.y) * smoothstep(1.0, 0.6, f.y);
      a += streak * (0.5 - fl * 0.12);
    }
  }
  a = clamp(a, 0.0, 0.7);
  vec3 col = mix(vec3(0.85, 0.92, 1.0), uColor, 0.25);
  return vec4(col * a, a);
}

vec4 petals(vec2 uv, float aspect, float t) {
  float a = 0.0;
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    float scale = 5.0 + fl * 3.0;
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y -= t * (0.3 + 0.15 * fl);
    p.x += sin(p.y * 0.7 + t * 0.6) * 0.4;
    vec2 cell = floor(p);
    vec2 r = hash2(cell + fl * 21.0);
    if (r.x < 0.2 + 0.45 * uIntensity) {
      vec2 center = cell + 0.3 + 0.4 * hash2(cell + 2.0);
      vec2 q = rot(t * (0.8 + r.y) + r.x * 6.28) * (p - center);
      q.x *= 1.0 / max(0.3, abs(sin(t * 1.5 + r.y * 9.0)));
      float d = length(q / vec2(0.16, 0.09));
      a += smoothstep(1.0, 0.7, d) * (0.85 - fl * 0.2);
    }
  }
  a = clamp(a, 0.0, 1.0);
  vec3 col = mix(vec3(1.0, 0.76, 0.85), uColor, 0.35);
  return vec4(col * a, a);
}

vec4 bubbles(vec2 uv, float aspect, float t) {
  float a = 0.0;
  for (int layer = 0; layer < 2; layer++) {
    float fl = float(layer);
    float scale = 3.5 + fl * 2.5;
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y += t * (0.25 + 0.15 * fl);
    p.x += sin(p.y * 1.3 + t) * 0.12;
    vec2 cell = floor(p);
    vec2 r = hash2(cell + fl * 17.0);
    if (r.x < 0.25 + 0.5 * uIntensity) {
      vec2 center = cell + 0.3 + 0.4 * hash2(cell + 6.0);
      float radius = 0.12 + 0.18 * r.y;
      float d = length(p - center);
      float rim = smoothstep(radius, radius - 0.02, d) * smoothstep(radius - 0.07, radius - 0.015, d);
      float shine = smoothstep(radius * 0.3, 0.0, length(p - center - vec2(-radius * 0.4, -radius * 0.4)));
      a += rim * 0.6 + shine * 0.7 + smoothstep(radius, 0.0, d) * 0.05;
    }
  }
  a = clamp(a, 0.0, 0.9);
  vec3 col = mix(vec3(0.85, 0.95, 1.0), uColor, 0.3);
  return vec4(col * a, a);
}

vec4 galaxy(vec2 uv, float aspect, float t) {
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.4);
  float r = length(p);
  float ang = atan(p.y, p.x) + t * 0.05 + 2.2 / (r + 0.35);
  vec2 q = vec2(cos(ang), sin(ang)) * r * 3.0;
  float n = fbm(q + vec2(t * 0.03, 0.0));
  float arms = pow(clamp(0.5 + 0.5 * sin(ang * 2.0 + r * 6.0), 0.0, 1.0), 3.0);
  float glow = n * (0.35 + 0.65 * arms) * smoothstep(1.1, 0.0, r);
  vec3 col = mix(uColor, vec3(0.55, 0.47, 1.0), n) * glow * 1.4;
  float a = clamp(glow * (0.5 + 0.5 * uIntensity), 0.0, 0.75);
  vec4 s = stars(uv, aspect, t);
  return vec4(clamp(col * (0.5 + 0.5 * uIntensity) + s.rgb, 0.0, 1.0), clamp(a + s.a, 0.0, 1.0));
}

// A blocky 3x5 "glyph" from a cell hash: lit pixels in a tiny grid.
float glyph(vec2 f, float seed) {
  vec2 px = floor(f * vec2(3.0, 5.0));
  if (px.x < 0.0 || px.y < 0.0 || px.x > 2.0 || px.y > 4.0) return 0.0;
  return step(0.45, hash(px + seed * 13.1));
}

vec4 matrix(vec2 uv, float aspect, float t) {
  float cols = 34.0;
  vec2 p = vec2(uv.x * cols, uv.y * cols * 1.6 / aspect);
  float col = floor(p.x);
  float speed = 3.0 + 6.0 * hash(vec2(col, 3.0));
  float head = fract(-t * speed / 40.0 + hash(vec2(col, 9.0))) * 1.3;
  float y = uv.y;
  float trail = smoothstep(0.32 + 0.2 * hash(vec2(col, 5.0)), 0.0, head - y) * step(y, head);
  float lit = step(1.0 - (0.35 + 0.6 * uIntensity), hash(vec2(col, 1.0)));
  vec2 cell = floor(p);
  float seed = hash(cell + floor(t * (2.0 + 6.0 * hash(cell))));
  float g = glyph(fract(p) * vec2(1.25, 1.1) - vec2(0.1, 0.05), seed);
  float a = g * trail * lit;
  float isHead = smoothstep(0.03, 0.0, abs(head - y - 0.01)) * lit;
  vec3 c = mix(uColor, vec3(0.85, 1.0, 0.9), isHead);
  a = clamp(a + isHead * g, 0.0, 1.0);
  return vec4(c * a, a);
}

vec4 glitch(vec2 uv, float aspect, float t) {
  vec2 frag = uv * uSize;
  float a = 0.0;
  vec3 c = vec3(0.0);
  // Scanlines.
  a += 0.06 * step(0.5, fract(frag.y / 3.0));
  // Flickering blocks.
  vec2 block = floor(vec2(uv.x * 9.0, uv.y * 24.0));
  float on = step(0.985 - 0.02 * uIntensity, hash(block + floor(t * 7.0)));
  a += on * 0.55;
  c += on * uColor * 0.55;
  // RGB-split bars sweeping down.
  float bar = fract(uv.y - t * 0.15);
  float band = smoothstep(0.02, 0.0, abs(bar - 0.5));
  c += band * vec3(1.0, 0.1, 0.4) * 0.35 + band * vec3(0.1, 0.9, 1.0) * 0.25;
  a += band * 0.4;
  a = clamp(a, 0.0, 0.8);
  c += vec3(0.06) * step(0.5, fract(frag.y / 3.0));
  return vec4(clamp(c, 0.0, 1.0), a);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float aspect = uSize.x / uSize.y;
  float t = uTime;
  int e = int(uEffect + 0.5);
  vec4 c = vec4(0.0);
  if (e == 1) c = sparkles(uv, aspect, t);
  else if (e == 2) c = snow(uv, aspect, t);
  else if (e == 3) c = aurora(uv, aspect, t);
  else if (e == 4) c = stars(uv, aspect, t);
  else if (e == 5) c = bokeh(uv, aspect, t);
  else if (e == 6) c = fireflies(uv, aspect, t);
  else if (e == 7) c = hearts(uv, aspect, t);
  else if (e == 8) c = confetti(uv, aspect, t);
  else if (e == 9) c = rain(uv, aspect, t);
  else if (e == 10) c = petals(uv, aspect, t);
  else if (e == 11) c = bubbles(uv, aspect, t);
  else if (e == 12) c = galaxy(uv, aspect, t);
  else if (e == 13) c = matrix(uv, aspect, t);
  else if (e == 14) c = glitch(uv, aspect, t);
  fragColor = c;
}
