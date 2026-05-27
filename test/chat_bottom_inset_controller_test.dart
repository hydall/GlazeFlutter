import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/features/chat/chat_bottom_inset_controller.dart';
import 'package:glaze_flutter/features/chat/chat_drawer_controller.dart';

class _Harness extends StatefulWidget {
  const _Harness({required this.onCreate});

  final void Function(ChatDrawerController controller) onCreate;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with SingleTickerProviderStateMixin {
  late final ChatDrawerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChatDrawerController(
      vsync: this,
      readKeyboardHeight: () async => 0,
      persistKeyboardHeight: (_) async {},
    );
    widget.onCreate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('computeInsets uses keyboard height and input bar height', (
    tester,
  ) async {
    late ChatDrawerController drawerCtrl;
    await tester.pumpWidget(
      MaterialApp(
        home: _Harness(onCreate: (controller) => drawerCtrl = controller),
      ),
    );

    final bottomPanelInset = ChatBottomInsetController.computeInsets(
      keyboardHeight: 300,
      safeBottom: 24,
      drawerCtrl: drawerCtrl,
    );

    expect(bottomPanelInset, greaterThanOrEqualTo(300));
  });
}
