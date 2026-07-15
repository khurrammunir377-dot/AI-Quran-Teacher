import 'dart:async';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../models/quran_models.dart';
import '../services/audio_recorder_service.dart';
import '../services/db_helper.dart';
import '../services/quran_repository.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

class RecitationScreen extends StatefulWidget {
  final int surahNumber;
  final int initialAyah;

  const RecitationScreen({
    super.key,
    required this.surahNumber,
    required this.initialAyah,
  });

  @override
  State<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends State<RecitationScreen>
    with WidgetsBindingObserver {
  late List<AyahInfo> _ayahs;
  late int _currentIndex;

  final AudioRecorderService _recorderService = AudioRecorderService();
  final ap.AudioPlayer _player = ap.AudioPlayer();

  bool _isRecording = false;
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  RecordingResult? _lastRecording;
  String _fontSizeName = 'medium';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ayahs = QuranRepository.instance.ayahsForSurah(widget.surahNumber);
    _currentIndex = _ayahs.indexWhere((a) => a.ayah == widget.initialAyah);
    if (_currentIndex < 0) _currentIndex = 0;
    _loadFontSize();
    _saveSession();
  }

  Future<void> _loadFontSize() async {
    final size = await SettingsService.instance.getFontSize();
    if (mounted) setState(() => _fontSizeName = size.name);
  }

  Future<void> _saveSession() async {
    final ayah = _ayahs[_currentIndex];
    await SettingsService.instance.setLastSession(ayah.surah, ayah.ayah);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Save any in-progress recording safely instead of losing it or crashing.
      _recorderService.stopSafelyIfRecording();
    }
  }

  AyahInfo get _currentAyah => _ayahs[_currentIndex];

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final permissionState = await _checkMicPermission();
    if (permissionState != MicPermissionState.granted) {
      _handleDeniedPermission(permissionState);
      return;
    }

    await _recorderService.start(_currentAyah.surah, _currentAyah.ayah);
    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
      _lastRecording = null;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _elapsed += const Duration(milliseconds: 200));
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final result = await _recorderService.stop();
    setState(() {
      _isRecording = false;
      _lastRecording = result;
    });
    if (result != null) {
      await DbHelper.instance.saveRecording(
        surah: _currentAyah.surah,
        ayah: _currentAyah.ayah,
        filePath: result.filePath,
        durationMs: result.duration.inMilliseconds,
        sizeBytes: result.sizeBytes,
      );
    }
  }

  Future<MicPermissionState> _checkMicPermission() async {
    final status = await ph.Permission.microphone.status;
    if (status.isGranted) return MicPermissionState.granted;
    if (status.isPermanentlyDenied) return MicPermissionState.permanentlyDenied;

    final result = await ph.Permission.microphone.request();
    if (result.isGranted) return MicPermissionState.granted;
    if (result.isPermanentlyDenied) return MicPermissionState.permanentlyDenied;
    return MicPermissionState.denied;
  }

  void _handleDeniedPermission(MicPermissionState state) {
    if (!mounted) return;
    if (state == MicPermissionState.permanentlyDenied) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Microphone Access Needed'),
          content: const Text(
            'Hifz Companion needs microphone access to record your recitation. '
            'Please enable it in your phone\'s app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ph.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required to record.'),
        ),
      );
    }
  }

  Future<void> _playLastRecording() async {
    if (_lastRecording == null) return;
    await _player.play(ap.DeviceFileSource(_lastRecording!.filePath));
  }

  void _reRecord() {
    setState(() {
      _lastRecording = null;
      _elapsed = Duration.zero;
    });
  }

  void _goToAyah(int delta) {
    final newIndex = _currentIndex + delta;
    if (newIndex < 0 || newIndex >= _ayahs.length) return;
    setState(() {
      _currentIndex = newIndex;
      _lastRecording = null;
      _elapsed = Duration.zero;
    });
    _saveSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _recorderService.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surahInfo = QuranRepository.instance.surahByNumber(widget.surahNumber);
    final fontSize = arabicFontSizeValue(_fontSizeName);

    return Scaffold(
      appBar: AppBar(title: Text(surahInfo.nameTransliteration)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      _currentAyah.text,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontSize: fontSize, height: 1.8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${surahInfo.nameTransliteration} · Ayah ${_currentAyah.ayah} '
                      'of ${surahInfo.totalVerses}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            _buildVerseNav(),
            _buildRecordingControls(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildVerseNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: _currentIndex > 0 ? () => _goToAyah(-1) : null,
            tooltip: 'Previous verse',
          ),
          Text('Verse ${_currentIndex + 1} / ${_ayahs.length}'),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed:
                _currentIndex < _ayahs.length - 1 ? () => _goToAyah(1) : null,
            tooltip: 'Next verse',
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Column(
      children: [
        Text(
          _isRecording
              ? 'Recording... ${_elapsed.inSeconds}s'
              : (_lastRecording != null
                  ? 'Saved: ${_lastRecording!.formattedDuration}, '
                      '${_lastRecording!.formattedSize}'
                  : 'Tap to record'),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _toggleRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isRecording ? Icons.stop : Icons.mic,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_lastRecording != null && !_isRecording)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _playLastRecording,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play Back'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _reRecord,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-record'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _currentIndex < _ayahs.length - 1
                    ? () => _goToAyah(1)
                    : null,
                icon: const Icon(Icons.check),
                label: const Text('Next Verse'),
              ),
            ],
          ),
      ],
    );
  }
}
