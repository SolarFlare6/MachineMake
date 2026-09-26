/// Recognized device profiles for UDCF routing.
enum DeviceProfile {
  generic,
  computer,
  microcontroller,
  robot,
  quadruped;

  static DeviceProfile fromString(String? val) {
    if (val == null) return DeviceProfile.generic;
    final clean = val.toLowerCase().trim();
    switch (clean) {
      case 'quadruped':
        return DeviceProfile.quadruped;
      case 'robot':
        return DeviceProfile.robot;
      case 'computer':
      case 'raspberry_pi':
      case 'pc':
      case 'laptop':
        return DeviceProfile.computer;
      case 'microcontroller':
      case 'pico':
      case 'esp32':
      case 'arduino':
        return DeviceProfile.microcontroller;
      default:
        return DeviceProfile.generic;
    }
  }

  String get label {
    switch (this) {
      case DeviceProfile.quadruped:
        return 'Quadruped Robot';
      case DeviceProfile.robot:
        return 'Robot';
      case DeviceProfile.computer:
        return 'Computer / SBC';
      case DeviceProfile.microcontroller:
        return 'Microcontroller';
      case DeviceProfile.generic:
        return 'Generic Device';
    }
  }

  bool get isRobot => this == DeviceProfile.quadruped || this == DeviceProfile.robot;
}
