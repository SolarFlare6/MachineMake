import 'package:flutter/material.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_capability.dart';
import '../../theme/app_theme.dart';
import 'gpio_pin_grid.dart';
import 'pwm_slider_panel.dart';
import 'camera_control_card.dart';
import 'telemetry_gauge_row.dart';
import 'robotics_joystick_card.dart';
import 'generic_capability_card.dart';

/// Maps a [CapabilityType] to the appropriate control widget.
/// Used by [GenericDeviceDashboardScreen] to auto-generate UI from a device manifest.
class CapabilityWidgetFactory {
  /// Returns the widget best suited for the given capability.
  static Widget buildForCapability(
    DeviceCapability cap,
    DeviceConnection? conn,
  ) {
    switch (cap.type) {
      case CapabilityType.gpio:
        return GpioPinGrid(capability: cap, conn: conn);
      case CapabilityType.pwm:
        return PwmSliderPanel(capability: cap, conn: conn);
      case CapabilityType.camera:
        return CameraControlCard(capability: cap, conn: conn);
      case CapabilityType.telemetry:
        return TelemetryGaugeRow(capability: cap, conn: conn);
      case CapabilityType.robotics:
        return RoboticsJoystickCard(capability: cap, conn: conn);
      default:
        return GenericCapabilityCard(capability: cap);
    }
  }

  /// Returns the icon appropriate for a given capability type.
  static IconData iconFor(CapabilityType type) {
    switch (type) {
      case CapabilityType.gpio:
        return Icons.developer_board;
      case CapabilityType.pwm:
        return Icons.tune;
      case CapabilityType.i2c:
      case CapabilityType.spi:
      case CapabilityType.uart:
        return Icons.cable;
      case CapabilityType.camera:
        return Icons.videocam;
      case CapabilityType.networking:
        return Icons.wifi;
      case CapabilityType.storage:
        return Icons.storage;
      case CapabilityType.audio:
        return Icons.volume_up;
      case CapabilityType.display:
        return Icons.monitor;
      case CapabilityType.aiInference:
        return Icons.psychology;
      case CapabilityType.robotics:
        return Icons.smart_toy;
      case CapabilityType.telemetry:
        return Icons.analytics;
      case CapabilityType.power:
        return Icons.battery_charging_full;
      case CapabilityType.custom:
        return Icons.extension;
    }
  }

  /// Returns a color accent for a capability type.
  static Color colorFor(CapabilityType type) {
    switch (type) {
      case CapabilityType.gpio:
        return AppTheme.primaryOrange;
      case CapabilityType.pwm:
        return Colors.amberAccent;
      case CapabilityType.camera:
        return AppTheme.gpuCyan;
      case CapabilityType.telemetry:
        return AppTheme.ramPink;
      case CapabilityType.robotics:
        return Colors.greenAccent;
      case CapabilityType.networking:
        return Colors.lightBlueAccent;
      case CapabilityType.power:
        return Colors.redAccent;
      case CapabilityType.aiInference:
        return Colors.purpleAccent;
      default:
        return AppTheme.textMuted;
    }
  }
}
