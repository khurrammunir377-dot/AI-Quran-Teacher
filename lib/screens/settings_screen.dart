import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ArabicFontSize _fontSize = ArabicFontSize.medium;
  bool _darkMode = false;
  bool _referenceAudio = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final size = await SettingsService.instance.getFontSize();
    final dark = await SettingsService.instance.getDarkMode();
    final refAudio = await SettingsService.instance.getReferenceAudioEnabled();
    if (!mounted) return;
    setState(() {
      _fontSize = size;
      _darkMode = dark;
      _referenceAudio = refAudio;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('Arabic Text Size'),
            subtitle: Text('Applies to the Recitation Screen'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ArabicFontSize>(
              segments: const [
                ButtonSegment(value: ArabicFontSize.small, label: Text('Small')),
                ButtonSegment(value: ArabicFontSize.medium, label: Text('Medium')),
                ButtonSegment(value: ArabicFontSize.large, label: Text('Large')),
              ],
              selected: {_fontSize},
              onSelectionChanged: (selection) async {
                final size = selection.first;
                setState(() => _fontSize = size);
                await SettingsService.instance.setFontSize(size);
              },
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: _darkMode,
            onChanged: (value) async {
              setState(() => _darkMode = value);
              await SettingsService.instance.setDarkMode(value);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Restart the app to apply theme changes'),
                  ),
                );
              }
            },
          ),
          SwitchListTile(
            title: const Text('Reciter Reference Audio'),
            subtitle: const Text('Coming in a future update'),
            value: _referenceAudio,
            onChanged: (value) async {
              setState(() => _referenceAudio = value);
              await SettingsService.instance.setReferenceAudioEnabled(value);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Support This App'),
            subtitle: const Text(
              'Hifz Companion is free for everyone. Support is optional.',
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Support This App'),
                  content: const Text(
                    'This app is, and will always remain, completely free for '
                    'every student. Voluntary support options will be available '
                    'here in a future update, for those who wish to contribute '
                    'as an ongoing charitable act (Sadaqah Jariyah). No feature '
                    'is ever limited based on support.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
