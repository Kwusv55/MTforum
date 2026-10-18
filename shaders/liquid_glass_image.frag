// 液态玻璃（壁纸采样版）：页面卡片的整块玻璃底，一次绘制完成。
//
// 背景：与 liquid_glass.frag 相同的边缘折射 + 轻微模糊 + 饱和度，但不读屏幕，
// 而是从预先画好的「壁纸 + 遮罩」图里取样（卡片背后只有静止的壁纸）。
// 其上依次叠：玻璃底色渐变、镜面反光（柔光混合）、内侧辉光。
// 这些原本由 CustomPainter 画：辉光用 MaskFilter.blur、反光用 softLight，
// 每张卡片每帧都要离屏模糊、读回像素，是页面滑动掉帧的主要来源。
//
// 作为普通画笔着色器使用（仅 Impeller）。片元坐标是画布局部坐标（逻辑像素），
// 其余长度也都是逻辑像素。
#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;       // 壁纸图尺寸（像素）
uniform vec4 uRect;       // 折射形状（画布坐标）：left, top, width, height
uniform vec4 uLens;       // 圆角半径, 折射带宽度, 最大位移, 模糊半径
uniform float uSaturation;
uniform vec3 uMap;        // 画布坐标 → 壁纸坐标的平移 xy，以及壁纸图每逻辑像素的像素数
uniform vec4 uBox;        // 卡片本身（画布坐标）
uniform vec3 uTintColor;  // 玻璃底色
uniform vec2 uTintAlpha;  // 底色不透明度：顶部, 底部
uniform vec2 uSpecular;   // 左上、右下两片反光的强度（0 = 不画）
uniform float uGlow;      // 内侧辉光强度

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

// 标准正态分布函数的近似。
float phi(float x) {
  return 1.0 / (1.0 + exp(-1.5976 * x - 0.07056 * x * x * x));
}

// 柔光混合，源色为纯白时的结果（W3C soft-light）。
vec3 softLightWhite(vec3 b) {
  vec3 d = mix(sqrt(b), ((16.0 * b - 12.0) * b + 4.0) * b, step(b, vec3(0.25)));
  return d;
}

// 椭圆径向渐变：中心 1，边缘 0。
float ellipse(vec2 p, vec2 center, vec2 radius) {
  return max(1.0 - length((p - center) / radius), 0.0);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;

  // ---- 背景：边缘透镜折射 ----
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
  vec3 rgb = clamp(mix(vec3(luma), color.rgb, uSaturation), 0.0, 1.0);

  // ---- 玻璃底色：自上而下的线性渐变 ----
  vec2 local = frag - uBox.xy;
  float w = uBox.z;
  float hh = uBox.w;
  float tint = mix(uTintAlpha.x, uTintAlpha.y, clamp(local.y / hh, 0.0, 1.0));
  rgb = mix(rgb, uTintColor, tint);

  // ---- 镜面反光：左上一大片、右下一小片，按胶囊高度设计，高卡片不放大 ----
  float sh = min(hh, 120.0);
  if (uSpecular.x > 0.0) {
    float a = ellipse(local, vec2(w * 0.18, -sh * 0.10), vec2(w * 0.54, sh * 0.405));
    rgb = mix(rgb, softLightWhite(rgb), a * uSpecular.x);
  }
  if (uSpecular.y > 0.0) {
    float a = ellipse(local, vec2(w, hh + sh * 0.2), vec2(w * 0.45, sh * 0.40));
    rgb = mix(rgb, softLightWhite(rgb), a * uSpecular.y);
  }

  // ---- 内侧辉光：等同于沿边缘 12 宽的白色描边做 σ=6 高斯模糊后裁掉外半圈 ----
  if (uGlow > 0.0) {
    vec2 boxHalf = uBox.zw * 0.5;
    float boxRadius = min(uLens.x, min(boxHalf.x, boxHalf.y));
    float dist = -sdRoundRect(local - boxHalf, boxHalf, boxRadius);
    float g = phi((6.0 - dist) / 6.0) - phi((-6.0 - dist) / 6.0);
    rgb = mix(rgb, vec3(1.0), clamp(g, 0.0, 1.0) * uGlow);
  }

  fragColor = vec4(rgb, 1.0);
}
