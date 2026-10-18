// 液态玻璃（壁纸采样版）：效果与 liquid_glass.frag 相同，但不读屏幕背景，
// 而是从预先画好的「壁纸 + 遮罩」图里取样。
//
// 页面卡片背后只有静止的壁纸，所以直接采样这张图就等于采样背景，
// 省掉每张卡片每帧一次的背景读取。作为普通画笔着色器使用（仅 Impeller）。
// 片元坐标是画布局部坐标（逻辑像素），uRect / uLens 也都是逻辑像素。
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // 壁纸图尺寸（像素）
uniform vec4 uRect;     // 玻璃形状（画布坐标）：left, top, width, height
uniform vec4 uLens;     // 圆角半径, 折射带宽度, 最大位移, 模糊半径
uniform float uSaturation;
uniform vec3 uMap;      // 画布坐标 → 壁纸坐标的平移 xy，以及壁纸图每逻辑像素的像素数

uniform sampler2D uTexture;

out vec4 fragColor;

float sdRoundRect(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec4 sampleAt(vec2 coord) {
  vec2 uv = (coord + uMap.xy) * uMap.z / uSize;
  return texture(uTexture, clamp(uv, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 halfSize = uRect.zw * 0.5;
  vec2 p = frag - (uRect.xy + halfSize);
  float radius = min(uLens.x, min(halfSize.x, halfSize.y));
  float inside = -sdRoundRect(p, halfSize, radius);

  vec2 offset = vec2(0.0);
  float band = uLens.y;
  if (uLens.z > 0.0 && inside > 0.0 && inside < band) {
    vec2 e = vec2(0.5, 0.0);
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
