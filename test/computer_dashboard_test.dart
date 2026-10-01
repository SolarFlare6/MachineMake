import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/models/dcp_models.dart';
import 'package:machmake2/screens/computer/computer_dashboard_screen.dart';
import 'package:machmake2/screens/computer/computer_mapping_tab.dart';
import 'package:machmake2/services/device_manager.dart';

void main() {
  testWidgets('ComputerDashboardScreen switches to Mapping tab and interacts with actions', (WidgetTester tester) async {
    final testPc = DeviceItem(
      id: 'pc-1',
      name: 'Workstation PC',
      profile: 'pc',
      deviceType: 'Desktop Computer',
      availableTransports: ['wifi'],
      selectedTransport: 'wifi',
      iconKey: 'rpi',
      ipAddress: '192.168.1.150',
      port: 8765,
      isConnected: true,
      isPaired: true,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;

    await tester.pumpWidget(
      MaterialApp(
        home: ComputerDashboardScreen(
          device: testPc,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify initial tab (System / Telemetry)
    expect(find.text('Workstation PC'), findsOneWidget);
    expect(find.text('System Telemetry'), findsOneWidget);
    expect(find.text('System Operations'), findsOneWidget);
    expect(find.text('Open SSH Terminal'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Mapping'), findsOneWidget);

    // 2. Switch to Mapping Tab
    await tester.tap(find.text('Mapping'));
    await tester.pumpAndSettle();

    expect(find.byType(ComputerMappingTab), findsOneWidget);
    expect(find.text('Input & Device Mapping'), findsOneWidget);

    // Default action should be Mouse
    expect(find.text('VIRTUAL TRACKPAD'), findsOneWidget);
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);

    // Tap Left Click button
    await tester.tap(find.text('Left Click'));
    await tester.pumpAndSettle();

    // 3. Switch to Keyboard action
    await tester.tap(find.text('Keyboard'));
    await tester.pumpAndSettle();

    expect(find.text('Type on Remote Host'), findsOneWidget);
    expect(find.text('Quick Keystrokes & Shortcuts'), findsOneWidget);
    expect(find.text('Ctrl + C'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);

    // Enter text and tap Send
    await tester.enterText(find.byType(TextField), 'Hello MachineMake');
    await tester.tap(find.text('Send Text to Device'));
    await tester.pumpAndSettle();

    // 4. Switch to Lock PC action
    await tester.tap(find.text('Lock PC'));
    await tester.pumpAndSettle();

    expect(find.text('Lock Remote Device'), findsOneWidget);
    expect(find.text('LOCK DEVICE NOW'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('Linux'), findsOneWidget);
    expect(find.text('macOS'), findsOneWidget);

    // Tap Linux OS radio
    await tester.tap(find.text('Linux'));
    await tester.pumpAndSettle();

    // Tap Lock Device Now button
    await tester.tap(find.text('LOCK DEVICE NOW'));
    await tester.pumpAndSettle();

    // 5. Switch to Media action
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();

    expect(find.text('Media & Music Control'), findsOneWidget);
    expect(find.text('Host Volume Control'), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);

    // Tap play button
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    // 6. Switch back to System tab
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(find.text('System Telemetry'), findsOneWidget);

    // Clear any active SnackBars and timers cleanly
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
    await tester.pumpAndSettle();

    // Dispose DeviceManager singleton timer so test invariants pass
    DeviceManager().dispose();
  });
}
