import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum MicPermissionState { granted, denied, permanentlyDenied }

/// Wraps native audio recording for the Recitation Screen.
///
/// Records mono WAV audio at 16kHz, which is the minimum sample rate needed
/// for future speech-to-text processing (Phase 2+). Files are saved locally,
/// named by Surah/Ayah/timestamp, so recordings persist across app sessions
/// entirely offline.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _recordingStartedAt;
  String? _currentPath;

  Future<MicPermissionState> checkPermission() async {
    final hasPermission = await _recorder.hasPermission();
    if (hasPermission) return MicPermissionState.granted;
    return MicPermissionState.denied;
  }

  Future<String> _buildFilePath(int surah, int ayah) async {
    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${dir.path}/recordings');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${recordingsDir.path}/s${surah}_a${ayah}_$timestamp.wav';
  }

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> start(int surah, int ayah) async {
    final path = await _buildFilePath(surah, ayah);
    _currentPath = path;
    _recordingStartedAt = DateTime.now();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  /// Stops recording and returns the saved file path, duration, and file size,
  /// or null if nothing was recorded (e.g. stopped before starting).
  Future<RecordingResult?> stop() async {
    final path = await _recorder.stop();
    if (path == null || _recordingStartedAt == null) return null;
    final duration = DateTime.now().difference(_recordingStartedAt!);
    final file = File(path);
    final sizeBytes = await file.exists() ? await file.length() : 0;
    _recordingStartedAt = null;
    final result = RecordingResult(
      filePath: path,
      duration: duration,
      sizeBytes: sizeBytes,
    );
    _currentPath = null;
    return result;
  }

  /// Called if the app is backgrounded or interrupted mid-recording, so the
  /// partial recording is saved safely instead of lost or crashing.
  Future<RecordingResult?> stopSafelyIfRecording() async {
    if (await _recorder.isRecording()) {
      return stop();
    }
    return null;
  }

  void dispose() {
    _recorder.dispose();
  }
}

class RecordingResult {
  final String filePath;
  final Duration duration;
  final int sizeBytes;

  RecordingResult({
    required this.filePath,
    required this.duration,
    required this.sizeBytes,
  });

  String get formattedDuration {
    final seconds = duration.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }

  String get formattedSize {
    final kb = sizeBytes / 1024;
    return '${kb.toStringAsFixed(0)} KB';
  }
}
