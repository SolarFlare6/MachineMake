import 'package:flutter/material.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_manifest.dart';
import '../../core/models/device_profile.dart';
import '../../models/dcp_models.dart';
import '../../screens/computer/computer_dashboard_screen.dart';
import '../../screens/generic/generic_device_dashboard_screen.dart';
import '../../screens/microcontroller/microcontroller_dashboard_screen.dart';
import '../../screens/robot/quadruped_dashboard_screen.dart';

/// Routes a device to its specialized profile dashboard screen,
/// or falls back to the generic capability-driven interface.
class ProfileRouter {
  ProfileRouter._();

  static Widget buildProfileUI(
    DeviceItem device, {
    DeviceConnection? conn,
    DeviceManifest? manifest,
  }) {
    final profile = DeviceProfile.fromString(device.profile);

    switch (profile) {
      case DeviceProfile.quadruped:
      case DeviceProfile.robot:
        return QuadrupedDashboardScreen(
          device: device,
          conn: conn,
          manifest: manifest,
        );
      case DeviceProfile.computer:
        return ComputerDashboardScreen(
          device: device,
          conn: conn,
          manifest: manifest,
        );
      case DeviceProfile.microcontroller:
        return MicrocontrollerDashboardScreen(
          device: device,
          conn: conn,
          manifest: manifest,
        );
      case DeviceProfile.generic:
        return GenericDeviceDashboardScreen(
          device: device,
          conn: conn,
          manifest: manifest,
        );
    }
  }

  /// Pushes the appropriate profile UI onto the navigator.
  static Future<void> openDeviceDashboard(
    BuildContext context,
    DeviceItem device, {
    DeviceConnection? conn,
    DeviceManifest? manifest,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => buildProfileUI(
          device,
          conn: conn,
          manifest: manifest,
        ),
      ),
    );
  }
}
