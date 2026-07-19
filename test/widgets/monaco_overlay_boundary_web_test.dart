import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('does not read the overlay size before first layout', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = errors.add;

    try {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: _SkipChildLayout(
            child: MonacoOverlayBoundary(
              child: SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(
        errors,
        isEmpty,
        reason:
            'Overlay sync must tolerate an unlaid-out RenderBox:\n'
            '${errors.map((error) => error.exceptionAsString()).join('\n')}',
      );
    } finally {
      FlutterError.onError = previousErrorHandler;
    }
  }, skip: !kIsWeb);
}

class _SkipChildLayout extends SingleChildRenderObjectWidget {
  const _SkipChildLayout({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSkipChildLayout();
  }
}

class _RenderSkipChildLayout extends RenderProxyBox {
  @override
  void performLayout() {
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}
}
