import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/models/dcp_models.dart';
import 'package:machmake2/screens/robot/quadruped_dashboard_screen.dart';

void main() {
  testWidgets('QuadrupedDashboardScreen taps, switches tabs, and tests Sensors Audio & Buzzer accordion', (WidgetTester tester) async {
    final testDevice = DeviceItem(
      id: 'robot-1',
      name: 'Quadruped Bot',
      profile: 'quadruped',
      deviceType: 'robot',
      availableTransports: ['wifi'],
      iconKey: 'quadruped',
      ipAddress: '192.168.1.100',
      port: 8765,
      isConnected: true,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;

    await tester.pumpWidget(
      MaterialApp(
        home: QuadrupedDashboardScreen(
          device: testDevice,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify initial tab (Move)
    expect(find.text('Quadruped Bot'), findsOneWidget);
    expect(find.text('Cam feed & Sim'), findsOneWidget);
    expect(find.text('Robot movement'), findsOneWidget);

    // 2. Toggle "Robot movement" accordion
    await tester.tap(find.text('Robot movement'));
    await tester.pumpAndSettle();

    // 3. Toggle "Servo control" accordion
    await tester.tap(find.text('Servo control'));
    await tester.pumpAndSettle();

    // 4. Switch to Sim tab
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(find.text('3D Sim'), findsOneWidget);

    // 5. Switch to Camera tab
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();

    // 6. Switch to Sensors tab
    await tester.tap(find.text('Sensors'));
    await tester.pumpAndSettle();
    expect(find.text('MPU6050 Accelerometer'), findsOneWidget);
    expect(find.text('MPU6050 Gyroscope'), findsOneWidget);
    // Audio is no longer on Sensors tab
    expect(find.text('Audio & Buzzer'), findsNothing);

    // 7. Switch to Config tab
    await tester.tap(find.text('Config'));
    await tester.pumpAndSettle();
    expect(find.text('Control & Safety'), findsOneWidget);
    expect(find.text('IMU Active Stabilizer'), findsOneWidget);
    expect(find.text('Autonomy Switch'), findsOneWidget);
    // Audio control section is in Config tab
    expect(find.text('Audio control'), findsOneWidget);
    expect(find.text('Tonal Buzzer  —  GPIO 23'), findsOneWidget);
    expect(find.text('Speaker  —  pygame.mixer'), findsOneWidget);

    // 10. Switch back to Move tab
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(find.text('Cam feed & Sim'), findsOneWidget);
  });
}
