#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize;
uniform float uProgress;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float band = 1.0 - smoothstep(0.0, 0.20, abs(uv.x + uv.y * 0.2 - (uProgress * 1.6 - 0.2)));
  float alpha = band * sin(uProgress * 3.14159265) * 0.10;
  fragColor = vec4(vec3(alpha), alpha);
}
