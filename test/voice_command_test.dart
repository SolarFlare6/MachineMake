import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/services/voice_command_service.dart';

void main() {
  group('VoiceCommandService parser tests', () {
    test('parses stand and sit commands', () {
      final stand1 = VoiceCommandService.parse('stand');
      expect(stand1?.toolName, 'stand');
      expect(stand1?.parameters, isEmpty);

      final stand2 = VoiceCommandService.parse('stand up please');
      expect(stand2?.toolName, 'stand');

      final sit1 = VoiceCommandService.parse('sit down');
      expect(sit1?.toolName, 'sit');
      expect(sit1?.parameters, isEmpty);

      final stop = VoiceCommandService.parse('stop');
      expect(stop?.toolName, 'stand');
    });

    test('parses directional walking commands with distance', () {
      final fwd = VoiceCommandService.parse('walk forward');
      expect(fwd?.toolName, 'walk');
      expect(fwd?.parameters['direction'], 'forward');
      expect(fwd?.parameters['distance'], 1.0);

      final fwdDist = VoiceCommandService.parse('walk forward 2.5 meters');
      expect(fwdDist?.toolName, 'walk');
      expect(fwdDist?.parameters['direction'], 'forward');
      expect(fwdDist?.parameters['distance'], 2.5);

      final back = VoiceCommandService.parse('go backward 0.5');
      expect(back?.toolName, 'walk');
      expect(back?.parameters['direction'], 'backward');
      expect(back?.parameters['distance'], 0.5);

      final left = VoiceCommandService.parse('step left');
      expect(left?.toolName, 'walk');
      expect(left?.parameters['direction'], 'left');
      expect(left?.parameters['distance'], 1.0);

      final right = VoiceCommandService.parse('strafe right 1.5');
      expect(right?.toolName, 'walk');
      expect(right?.parameters['direction'], 'right');
      expect(right?.parameters['distance'], 1.5);
    });

    test('parses turn commands with angle', () {
      final turnLeft = VoiceCommandService.parse('turn left');
      expect(turnLeft?.toolName, 'turn');
      expect(turnLeft?.parameters['direction'], 'left');
      expect(turnLeft?.parameters['angle'], 45.0);

      final turnRight = VoiceCommandService.parse('turn right 90 degrees');
      expect(turnRight?.toolName, 'turn');
      expect(turnRight?.parameters['direction'], 'right');
      expect(turnRight?.parameters['angle'], 90.0);
    });

    test('parses LED commands', () {
      final ledOn = VoiceCommandService.parse('turn on the light');
      expect(ledOn?.toolName, 'set_led');
      expect(ledOn?.parameters['on'], true);

      final ledOff = VoiceCommandService.parse('turn off led');
      expect(ledOff?.toolName, 'set_led');
      expect(ledOff?.parameters['on'], false);
    });

    test('parses sensor and camera commands', () {
      final imu = VoiceCommandService.parse('get orientation');
      expect(imu?.toolName, 'get_orientation');

      final pic = VoiceCommandService.parse('take a picture');
      expect(pic?.toolName, 'take_picture');
    });

    test('matches dynamic available tools', () {
      final custom = VoiceCommandService.parse(
        'can you run calibrate servos',
        availableTools: ['calibrate_servos', 'dance'],
      );
      expect(custom?.toolName, 'calibrate_servos');
    });

    test('returns null for gibberish', () {
      final nullCmd = VoiceCommandService.parse('what is the weather today in Paris');
      expect(nullCmd, isNull);
    });
  });
}
