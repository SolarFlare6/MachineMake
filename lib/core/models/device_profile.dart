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
    if (clean.contains('pico') ||
        clean.contains('rp2040') ||
        clean.contains('rp2350') ||
        clean.contains('microcontroller') ||
        clean.contains('mcu') ||
        clean.contains('esp32') ||
        clean.contains('esp8266') ||
        clean.contains('stm32') ||
        clean.contains('arduino')) {
      return DeviceProfile.microcontroller;
    }
    if (clean.contains('quadruped') || clean.contains('spot') || clean.contains('dog')) {
      return DeviceProfile.quadruped;
    }
    if (clean.contains('robot') || clean.contains('arm') || clean.contains('rover')) {
      return DeviceProfile.robot;
    }
    if (clean.contains('computer') ||
        clean.contains('raspberry') ||
        clean.contains('rpi') ||
        clean.contains('pc') ||
        clean.contains('desktop') ||
        clean.contains('workstation') ||
        clean.contains('laptop') ||
        clean.contains('macos') ||
        clean.contains('mac') ||
        clean.contains('windows') ||
        clean.contains('linux') ||
        clean.contains('sbc')) {
      return DeviceProfile.computer;
    }
    return DeviceProfile.generic;
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
  bool get isComputer => this == DeviceProfile.computer;
  bool get isGenericOrMcu => this == DeviceProfile.generic || this == DeviceProfile.microcontroller;
}
