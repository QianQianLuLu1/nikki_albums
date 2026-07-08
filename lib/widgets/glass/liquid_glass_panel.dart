// LiquidGlassPanel — 液态玻璃效果可复用组件（A 方案）。
//
// 三层叠加，逐层可独立降级：
//   1. 磨砂模糊（frosted）  : BackdropFilter + ImageFilter.blur
//   2. 镜面高光/边缘光（specular）: 纯 Flutter 绘制（顶部线性渐变高光 + 1px 半透明白内描边）
//   3. 可控背景折射（refraction）: 仅当玻璃压在「自有/已知背景」上才启用。把该背景渲染成
//      ui.Image 作为 sampler 喂给自定义位移着色器（liquid_glass_shader.frag）。
//
// 折射层严格套用 image_fragment.frag 的 Flutter FragmentShader GLSL 方言与 Dart 端
// setFloat / setImageSampler 调用顺序。若 enableRefraction 为 true 但 backgroundSampler
// 为 null，安全降级为仅磨砂 + 高光，不抛未捕获异常。
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 可复用的「液态玻璃」面板。
///
/// 仅建议用于小面积、有明确意图的外立面（如相册顶栏），避免铺满大块内容造成毛玻璃滥用。
class LiquidGlassPanel extends StatefulWidget {
  /// 创建液态玻璃面板。
  const LiquidGlassPanel({
    required this.child,
    this.blurSigma = 10,
    this.enableSpecular = true,
    this.enableRefraction = false,
    this.backgroundSampler,
    this.shaderAsset = 'assets/shaders/liquid_glass_shader.frag',
    this.radius = const BorderRadius.all(Radius.circular(16)),
    super.key,
  });

  /// 玻璃面板背后的内容（会先被磨砂模糊处理）。
  final Widget child;

  /// 磨砂模糊强度（同时作用于 x/y 轴）。
  final double blurSigma;

  /// 是否绘制镜面高光 + 玻璃边缘光。
  final bool enableSpecular;

  /// 是否启用可控背景折射。仅当 [backgroundSampler] 非 null 时才有意义。
  final bool enableRefraction;

  /// 自有/已知背景图，作为折射着色器的采样源。
  /// [enableRefraction] 为 true 时必传；为 null 时安全降级。
  final ui.Image? backgroundSampler;

  /// 折射着色器资源路径（需已在 pubspec.yaml 的 flutter.shaders 注册）。
  final String shaderAsset;

  /// 玻璃面板的圆角。
  final BorderRadiusGeometry radius;

  @override
  State<LiquidGlassPanel> createState() => _LiquidGlassPanelState();
}

class _LiquidGlassPanelState extends State<LiquidGlassPanel> {
  ui.FragmentProgram? _program;
  bool _programFailed = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadProgram();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool needsRefraction =
        widget.enableRefraction && widget.backgroundSampler != null;
    final bool neededBefore =
        oldWidget.enableRefraction && oldWidget.backgroundSampler != null;
    if (needsRefraction &&
        (!neededBefore || oldWidget.shaderAsset != widget.shaderAsset)) {
      _programFailed = false;
      _program = null;
      _maybeLoadProgram();
    }
  }

  void _maybeLoadProgram() {
    if (widget.enableRefraction && widget.backgroundSampler != null) {
      _loadProgram();
    }
  }

  Future<void> _loadProgram() async {
    try {
      _program = await ui.FragmentProgram.fromAsset(widget.shaderAsset);
      if (mounted) setState(() {});
    } catch (error, stack) {
      _programFailed = true;
      debugPrint(
        '[LiquidGlassPanel] 加载折射着色器 "${widget.shaderAsset}" 失败: '
        '$error\n$stack\n已降级为仅磨砂 + 高光。',
      );
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    // FragmentProgram 不可 dispose；由 CustomPainter 持有的 FragmentShader 会在其
    // paint 结束后自行释放。调用方传入的 backgroundSampler 由调用方负责释放，此处不 dispose。
    super.dispose();
  }

  /// 是否真正绘制折射层：需开启折射、提供 sampler、且着色器已成功加载。
  bool get _showRefraction =>
      widget.enableRefraction &&
      widget.backgroundSampler != null &&
      _program != null &&
      !_programFailed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius resolvedRadius =
        widget.radius.resolve(Directionality.of(context));

    // 本期未加入动效；若后续需要，动效应使用 ease-out/expo 缓动，并受
    // MediaQuery.of(context).disableAnimations 控制（无障碍：关闭动效时禁用动画）。

    final List<Widget> layers = <Widget>[];

    // 第 1 层：底层磨砂模糊（作用于玻璃背后的内容）。
    layers.add(
      Positioned.fill(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
          ),
          child: widget.child,
        ),
      ),
    );

    // 第 3 层（折射，可选）：把自有背景以位移着色器弯曲绘制。
    // 置于高光之下，使镜面高光作为玻璃表面反射处于最上层。
    if (widget.enableRefraction && widget.backgroundSampler == null) {
      // 安全降级：开启了折射但未提供 sampler，不抛异常，仅打警告。
      debugPrint(
        '[LiquidGlassPanel] enableRefraction 为 true 但 backgroundSampler 为 '
        'null，跳过折射，仅使用磨砂 + 高光。',
      );
    } else if (_showRefraction) {
      layers.add(
        Positioned.fill(
          child: _LiquidGlassRefraction(
            program: _program!,
            background: widget.backgroundSampler!,
            radius: resolvedRadius,
          ),
        ),
      );
    }

    // 第 2 层：镜面高光 + 玻璃边缘光（表面反射，置于最上层）。
    if (widget.enableSpecular) {
      layers.add(
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: resolvedRadius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: <Color>[
                  Color.fromRGBO(255, 255, 255, 0.25),
                  Color.fromRGBO(255, 255, 255, 0.0),
                ],
              ),
              border: Border.all(
                color: Color.fromRGBO(255, 255, 255, 0.35),
                width: 1,
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: resolvedRadius,
      child: Stack(children: layers),
    );
  }
}

/// 折射层：用位移着色器把「自有背景」弯曲绘制满面板。
class _LiquidGlassRefraction extends StatelessWidget {
  const _LiquidGlassRefraction({
    required this.program,
    required this.background,
    required this.radius,
  });

  final ui.FragmentProgram program;
  final ui.Image background;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius,
      child: CustomPaint(
        painter: _LiquidGlassRefractionPainter(
          program: program,
          background: background,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 折射层绘制器：构建 FragmentShader，按 image_fragment.frag 的范式写入 uniform，
/// 并把位移后的背景画满面板。
class _LiquidGlassRefractionPainter extends CustomPainter {
  _LiquidGlassRefractionPainter({
    required this.program,
    required this.background,
  });

  final ui.FragmentProgram program;
  final ui.Image background;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.FragmentShader shader = program.fragmentShader();
    try {
      int idx = 0;
      // vec2 offset —— 面板在画布中的逻辑像素原点（此处为 0,0）。
      shader.setFloat(idx++, 0.0);
      shader.setFloat(idx++, 0.0);
      // vec2 size —— 面板逻辑像素尺寸。
      shader.setFloat(idx++, size.width);
      shader.setFloat(idx++, size.height);
      // sampler2D backgroundSampler —— 纹理单元 0。
      shader.setImageSampler(0, background);
      // float u_strength —— 折射强度（uv 位移幅度，约 1.5%）。
      shader.setFloat(idx++, 0.015);
      // float u_dispersion —— 色散强度（r/g/b 采样水平偏移）。
      shader.setFloat(idx++, 0.004);

      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..shader = shader,
      );
    } finally {
      // 释放本次创建的 FragmentShader，避免显存泄漏。
      shader.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassRefractionPainter oldDelegate) =>
      oldDelegate.program != program || oldDelegate.background != background;
}
