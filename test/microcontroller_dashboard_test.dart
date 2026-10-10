import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/models/dcp_models.dart';
import 'package:machmake2/screens/microcontroller/microcontroller_dashboard_screen.dart';
import 'package:machmake2/services/device_manager.dart';

void main() {
  testWidgets('MicrocontrollerDashboardScreen renders LED, Temp, ADC, I2C and interacts with GPIO modes', (WidgetTester tester) async {
    final testPico = DeviceItem(
      id: 'pico-test-01',
      name: 'Raspberry Pi Pico W',
      profile: 'microcontroller',
      deviceType: 'Microcontroller',
      availableTransports: ['wifi'],
      selectedTransport: 'wifi',
      iconKey: 'pico',
      ipAddress: '192.168.1.100',
      port: 8765,
      isConnected: true,
      isPaired: true,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;

    await tester.pumpWidget(
      MaterialApp(
        home: MicrocontrollerDashboardScreen(
          device: testPico,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Header and Device Info
    expect(find.text('Raspberry Pi Pico W'), findsOneWidget);
    expect(find.text('Raspberry Pi Pico W Hardware Controller'), findsOneWidget);
    expect(find.text('ws://192.168.1.100:8765/dcp'), findsOneWidget);

    // 2. Verify Built-in LED Card
    expect(find.text('Built-in LED'), findsOneWidget);
    expect(find.text('Flash OK'), findsOneWidget);
    expect(find.text('Alert'), findsOneWidget);

    // 3. Verify Internal Core Temperature Card
    expect(find.text('Core Temp'), findsOneWidget);

    // 4. Verify ADC Section
    expect(find.text('Analog ADC Inputs (GP26 - GP28)'), findsOneWidget);
    expect(find.text('GP26'), findsOneWidget);
    expect(find.text('GP27'), findsOneWidget);
    expect(find.text('GP28'), findsOneWidget);
    expect(find.text('Read All'), findsOneWidget);

    // 5. Verify I2C Bus Section
    expect(find.text('I2C Buses & Connected Peripherals'), findsOneWidget);
    expect(find.text('Scan I2C'), findsOneWidget);

    // 6. Verify GPIO Header Controls & Mode Dropdown
    expect(find.text('User GPIO Header Controls (GP0 - GP22)'), findsOneWidget);
    expect(find.text('GP0'), findsOneWidget);
    expect(find.text('Digital Out'), findsWidgets);

    // 7. Toggle LED Switch
    final switchFinder = find.byType(Switch).first;
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // 8. Test I2C Scan button
    final scanI2cFinder = find.text('Scan I2C');
    await tester.ensureVisible(scanI2cFinder);
    await tester.tap(scanI2cFinder);
    await tester.pump();

    // 9. Test Read All ADC button
    final readAllFinder = find.text('Read All');
    await tester.ensureVisible(readAllFinder);
    await tester.tap(readAllFinder);
    await tester.pump();

    // 10. Clean up SnackBars and DeviceManager timers
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).clearSnackBars();
    await tester.pumpAndSettle();
    DeviceManager().dispose();
  });
}
