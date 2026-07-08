// assets/shaders/liquid_glass_shader.frag
// 液态玻璃折射着色器（A 方案 - 可控背景折射）。
//
// 严格套用 image_fragment.frag 的 Flutter FragmentShader GLSL 方言：
//   - precision 块
//   - #include <flutter/runtime_effect.glsl>
//   - out vec4 fragColor;
//   - uniform 声明顺序与 Dart 端 setFloat / setImageSampler 完全对应
//   - 使用 FlutterFragCoord()（逻辑画布坐标）与 texture()
//
// 功能：对传入的 backgroundSampler 按程序化高度场（中心高斯穹顶 + 轻微正弦涟漪）做 UV
// 位移，得到「内容被弯曲」的液态折射，并叠加极轻微色散（r/g/b 用微小不同偏移）。

#ifdef GL_ES
  precision mediump float;
#else
  precision highp float;
#endif

#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

// 与 Dart 端 setFloat / setImageSampler 调用顺序一致：
// 1) vec2 offset  (面板在画布中的逻辑像素原点)
uniform vec2 offset;
// 2) vec2 size    (面板逻辑像素尺寸)
uniform vec2 size;
// 3) sampler2D backgroundSampler (纹理单元 0)
uniform sampler2D backgroundSampler;
// 4) float u_strength  折射强度（uv 位移幅度）
uniform float u_strength;
// 5) float u_dispersion 色散强度（r/g/b 采样水平偏移）
uniform float u_dispersion;

// 程序化高度场：中心高斯穹顶 + 轻微正弦涟漪（由穹顶调制，使边缘保持平静）。
float heightField(vec2 uv) {
  vec2 p = uv - vec2(0.5);
  float r2 = dot(p, p);                 // 中心为 0，四角约 0.5
  float dome = exp(-r2 * 5.0);          // 中心穹顶，边缘趋于 0
  float ripple = 0.07 * sin(uv.x * 14.0 + uv.y * 8.0);
  return dome + ripple * dome;
}

// 高度场梯度（有限差分），用于计算折射位移方向（沿梯度弯曲采样坐标）。
vec2 heightGradient(vec2 uv) {
  float e = 0.002;
  float hc = heightField(uv);
  float hx = heightField(uv + vec2(e, 0.0));
  float hy = heightField(uv + vec2(0.0, e));
  return vec2(hx - hc, hy - hc) / e;
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - offset) / size;

  // 折射位移：沿高度场梯度方向弯曲采样坐标，模拟液态透镜。
  vec2 disp = heightGradient(uv) * u_strength;
  vec2 sampleUv = uv + disp;

  // 极轻微色散：r/g/b 使用微小不同的水平偏移，得到更通透的玻璃质感。
  float d = u_dispersion;
  float rC = texture(backgroundSampler, sampleUv + vec2(d, 0.0)).r;
  float gC = texture(backgroundSampler, sampleUv).g;
  float bC = texture(backgroundSampler, sampleUv - vec2(d, 0.0)).b;

  fragColor = vec4(rC, gC, bC, 1.0);
}
