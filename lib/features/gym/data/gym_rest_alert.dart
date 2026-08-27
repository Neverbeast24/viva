import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Rest-timer alarm: generated beep plus vibration / haptics.
///
/// Lives under `gym/data/` because it is a device helper, not a widget.
class GymRestAlert {
  static final AudioPlayer _player = AudioPlayer();
  static bool _armed = false;

  static Future<void> unlock() async {
    if (_armed) return;
    _armed = true;
    try {
      await _player.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.mixWithOthers},
          ),
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      );
      await _player.setVolume(1);
    } catch (_) {
      // Device audio session is best-effort.
    }
  }

  static Future<void> fire() async {
    await unlock();
    unawaited(_playBeep());
    await _buzz();
  }

  static Future<void> tick() async {
    await HapticFeedback.selectionClick();
  }

  static Future<void> _playBeep() async {
    try {
      await _player.stop();
      await _player.play(BytesSource(_beepWav(), mimeType: 'audio/wav'));
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> _buzz() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        await Vibration.vibrate(pattern: [0, 180, 70, 180, 70, 240, 80, 320]);
        return;
      }
    } catch (_) {
      // Fall through to haptics.
    }
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
  }
}

Uint8List _beepWav() {
  const sampleRate = 22050;
  final tones = <(double, double)>[
    (880, 0.18),
    (0, 0.06),
    (1174, 0.22),
    (0, 0.08),
    (988, 0.28),
  ];
  var total = 0;
  for (final tone in tones) {
    total += (sampleRate * tone.$2).round();
  }
  final samples = Int16List(total);
  var offset = 0;
  for (final tone in tones) {
    final n = (sampleRate * tone.$2).round();
    final freq = tone.$1;
    for (var i = 0; i < n; i++) {
      final env = i < 200 ? i / 200 : i > n - 200 ? max(0, (n - i) / 200) : 1.0;
      final v = freq == 0 ? 0.0 : sin(2 * pi * freq * i / sampleRate) * env * 0.42;
      samples[offset + i] = (v * 32767).round().clamp(-32767, 32767);
    }
    offset += n;
  }
  final byteCount = samples.length * 2;
  final header = ByteData(44);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + byteCount, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, byteCount, Endian.little);
  final out = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(samples.buffer.asUint8List());
  return out.takeBytes();
}
