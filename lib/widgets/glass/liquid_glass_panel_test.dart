// LiquidGlassPanel 冒烟测试（结构正确、可编译，需在 Flutter 环境运行）。
//
// 覆盖：
//   - 默认参数 / enableRefraction:false 可构造且不抛异常；
//   - radius / blurSigma 正确透传（ClipRRect 圆角、BackdropFilter 存在）；
//   - enableRefraction:true 但 backgroundSampler:null 时安全降级（不抛未捕获异常）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nikki_albums/widgets/glass/liquid_glass_panel.dart';

void main() {
  group('LiquidGlassPanel', () {
    testWidgets('默认参数可构造且不抛异常', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LiquidGlassPanel(child: Placeholder())),
        ),
      );
      expect(find.byType(LiquidGlassPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('透传 radius 与 blur 层', (WidgetTester tester) async {
      const BorderRadius radius = BorderRadius.all(Radius.circular(24));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassPanel(
              blurSigma: 18,
              radius: radius,
              child: Placeholder(),
            ),
          ),
        ),
      );

      // radius 应被解析后透传到外层 ClipRRect。
      final ClipRRect clip = tester.widget<ClipRRect>(
        find.descendant(
          of: find.byType(LiquidGlassPanel),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(clip.borderRadius, equals(radius));

      // 底层磨砂层（BackdropFilter）必须存在且持有 filter。
      // 注：ImageFilter 的 sigma 值不通过公共 API 暴露，此处仅校验接线正确性。
      final BackdropFilter backdrop = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byType(LiquidGlassPanel),
          matching: find.byType(BackdropFilter),
        ),
      );
      expect(backdrop.filter, isNotNull);
    });

    testWidgets('refraction 开启但 sampler 为 null 时安全降级', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassPanel(
              enableRefraction: true,
              child: Placeholder(),
            ),
          ),
        ),
      );
      expect(find.byType(LiquidGlassPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
