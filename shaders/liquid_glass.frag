// 液态玻璃背景着色器：圆角矩形边缘的透镜折射 + 轻微模糊 + 饱和度增强。
//
// 作为 BackdropFilter 的 ImageFilter.shader 使用（仅 Impeller）。
// 片元坐标与 uRect 都是全局物理像素；uSize 与第一个 sampler 由引擎填入。
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // 引擎填入：背景纹理尺寸
uniform vec4 uRect;     // 玻璃形状：left, top, width, height
uniform vec4 uLens;     // 圆角半径, 折射带宽度, 最大位移, 模糊半径
uniform float uSaturation;

uniform sampler2D uTexture;

out vec4 fragColor;

float sdRoundRect(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec4 sampleAt(vec2 coord) {
  vec2 uv = coord / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 halfSize = uRect.zw * 0.5;
  vec2 p = frag - (uRect.xy + halfSize);
  float radius = min(uLens.x, min(halfSize.x, halfSize.y));
  float inside = -sdRoundRect(p, halfSize, radius);

  // 边缘带内沿法线向形状内部取样：越靠近边缘位移越大（圆形透镜曲线），
  // 看起来像玻璃边缘把后面的内容弯折、放大。
  vec2 offset = vec2(0.0);
  float band = uLens.y;
  if (uLens.z > 0.0 && inside > 0.0 && inside < band) {
    vec2 e = vec2(1.0, 0.0);
    vec2 grad = vec2(
      sdRoundRect(p + e.xy, halfSize, radius) - sdRoundRect(p - e.xy, halfSize, radius),
      sdRoundRect(p + e.yx, halfSize, radius) - sdRoundRect(p - e.yx, halfSize, radius)
    );
    float len = length(grad);
    if (len > 0.0001) {
      float t = 1.0 - inside / band;
      float m = 1.0 - sqrt(max(1.0 - t * t, 0.0));
      offset = -grad / len * m * uLens.z;
    }
  }

  vec2 c = frag + offset;
  float b = uLens.w;
  vec4 color;
  if (b > 0.0) {
    // 13 点盘形模糊，半径很小（约 2dp），足够把细节柔化又保留轮廓。
    float h = b * 0.5;
    float d = b * 0.866;
    color = sampleAt(c) * 0.16;
    color += (sampleAt(c + vec2(h, 0.0)) + sampleAt(c - vec2(h, 0.0)) +
              sampleAt(c + vec2(0.0, h)) + sampleAt(c - vec2(0.0, h))) * 0.09;
    color += (sampleAt(c + vec2(b, 0.0)) + sampleAt(c - vec2(b, 0.0)) +
              sampleAt(c + vec2(0.0, b)) + sampleAt(c - vec2(0.0, b))) * 0.06;
    color += (sampleAt(c + vec2(d, d)) + sampleAt(c - vec2(d, d)) +
              sampleAt(c + vec2(d, -d)) + sampleAt(c - vec2(d, -d))) * 0.06;
  } else {
    color = sampleAt(c);
  }

  float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
  color.rgb = clamp(mix(vec3(luma * color.a), color.rgb, uSaturation), 0.0, 1.0);
  fragColor = color;
}
