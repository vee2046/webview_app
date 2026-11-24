import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kmlab_toolbox/ui/widgets/edge_back.dart';

void main() {
  Widget wrap(EdgeBackGesture child) => MaterialApp(
        home: Scaffold(body: child),
      );

  testWidgets('只有从左边缘往右滑才触发返回', (WidgetTester tester) async {
    var fired = 0;
    await tester.pumpWidget(wrap(EdgeBackGesture(
      onBack: () => fired++,
      child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
    )));

    // 从页面中间往右滑 → 不该触发
    await tester.dragFrom(const Offset(200, 300), const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(fired, 0, reason: '不是从左边缘起手的，不算返回手势');

    // 从左边缘往右滑足够距离 → 触发
    await tester.dragFrom(const Offset(8, 300), const Offset(140, 0));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('从左边缘往右滑得不够远不触发', (WidgetTester tester) async {
    var fired = 0;
    await tester.pumpWidget(wrap(EdgeBackGesture(
      onBack: () => fired++,
      child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
    )));

    await tester.dragFrom(const Offset(8, 300), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(fired, 0, reason: '位移没到阈值，不算一次返回');
  });

  testWidgets('往左滑不算返回', (WidgetTester tester) async {
    var fired = 0;
    await tester.pumpWidget(wrap(EdgeBackGesture(
      onBack: () => fired++,
      child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
    )));

    await tester.dragFrom(const Offset(8, 300), const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(fired, 0);
  });

  testWidgets('子内容照常收到事件（纵向滚动不被吞掉）',
      (WidgetTester tester) async {
    var fired = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EdgeBackGesture(
          onBack: () => fired++,
          child: ListView.builder(
            itemCount: 50,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ),
      ),
    ));

    await tester.dragFrom(const Offset(160, 500), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(fired, 0, reason: '纵向滑动不该触发返回手势');
    expect(find.text('row 4'), findsOneWidget, reason: '列表应该滚动了');
  });
}
