import 'dart:io';

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TtsStudioApp());
}

class TtsStudioApp extends StatelessWidget {
  const TtsStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native TTS Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const TtsHomePage(),
    );
  }
}

class AccentPreset {
  const AccentPreset({
    required this.label,
    required this.locale,
    required this.region,
  });

  final String label;
  final String locale;
  final String region;
}

class TtsHomePage extends StatefulWidget {
  const TtsHomePage({super.key});

  @override
  State<TtsHomePage> createState() => _TtsHomePageState();
}

class _TtsHomePageState extends State<TtsHomePage> {
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _textController = TextEditingController(
    text:
        'Hello! This is a natural, on-device text-to-speech demo. You can export this as WAV or MP3.',
  );

  static const List<AccentPreset> _presets = [
    AccentPreset(label: '🇳🇬 Nigeria', locale: 'en-NG', region: 'Nigerian English'),
    AccentPreset(label: '🇺🇸 US', locale: 'en-US', region: 'American English'),
    AccentPreset(label: '🇬🇧 UK', locale: 'en-GB', region: 'British English'),
    AccentPreset(label: '🇿🇦 South Africa', locale: 'en-ZA', region: 'South African English'),
    AccentPreset(label: '🇨🇳 Chinese', locale: 'zh-CN', region: 'Mandarin Chinese'),
  ];

  List<Map<String, String>> _voicesForLocale = const [];
  String _selectedLocale = _presets.first.locale;
  Map<String, String>? _selectedVoice;
  double _speechRate = 0.55;
  double _pitch = 1.0;
  bool _busy = false;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _configureTts();
  }

  Future<void> _configureTts() async {
    await _tts.setSharedInstance(true);
    await _tts.awaitSpeakCompletion(true);
    await _tts.awaitSynthCompletion(true);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
    await _loadVoicesForLocale(_selectedLocale);
  }

  Future<void> _loadVoicesForLocale(String locale) async {
    final dynamic voices = await _tts.getVoices;
    final parsedVoices = (voices as List<dynamic>)
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (voice) => voice.map(
            (dynamic key, dynamic value) => MapEntry(
              key.toString(),
              value.toString(),
            ),
          ),
        )
        .where((voice) => (voice['locale'] ?? '').toLowerCase() == locale.toLowerCase())
        .map(
          (voice) => {
            'name': voice['name'] ?? 'Default',
            'locale': voice['locale'] ?? locale,
          },
        )
        .toList(growable: false);

    Map<String, String>? chosenVoice;
    if (parsedVoices.isNotEmpty) {
      chosenVoice = parsedVoices.first;
      await _tts.setVoice(chosenVoice);
    }

    await _tts.setLanguage(locale);
    if (!mounted) return;
    setState(() {
      _selectedLocale = locale;
      _voicesForLocale = parsedVoices;
      _selectedVoice = chosenVoice;
      _status = parsedVoices.isEmpty
          ? 'No dedicated voice found for $locale. Engine fallback will be used.'
          : 'Loaded ${parsedVoices.length} voice(s) for $locale';
    });
  }

  Future<void> _speak() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('Enter text first.');
      return;
    }

    await _applyVoiceConfig();
    await _tts.stop();
    await _tts.speak(text);
    if (!mounted) return;
    setState(() => _status = 'Speaking...');
  }

  Future<void> _stop() async {
    await _tts.stop();
    if (!mounted) return;
    setState(() => _status = 'Stopped');
  }

  Future<void> _applyVoiceConfig() async {
    await _tts.setLanguage(_selectedLocale);
    if (_selectedVoice != null) {
      await _tts.setVoice(_selectedVoice!);
    }
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);
  }

  Future<void> _exportWav() async {
    await _exportAudio(asMp3: false);
  }

  Future<void> _exportMp3() async {
    await _exportAudio(asMp3: true);
  }

  Future<void> _exportAudio({required bool asMp3}) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('Cannot export empty text.');
      return;
    }

    setState(() {
      _busy = true;
      _status = asMp3 ? 'Exporting MP3...' : 'Exporting WAV...';
    });

    try {
      await _applyVoiceConfig();
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final wavPath = '${dir.path}/tts_$timestamp.wav';

      await _tts.synthesizeToFile(text, wavPath, true);

      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        throw Exception('TTS engine did not generate WAV file.');
      }

      if (!asMp3) {
        await _shareFile(wavFile);
        setState(() => _status = 'WAV exported: ${wavFile.path}');
        return;
      }

      final mp3Path = '${dir.path}/tts_$timestamp.mp3';
      final session = await FFmpegKit.execute(
        '-y -i "$wavPath" -codec:a libmp3lame -q:a 2 "$mp3Path"',
      );
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        throw Exception('MP3 conversion failed (code: $rc).');
      }

      final mp3File = File(mp3Path);
      if (!await mp3File.exists()) {
        throw Exception('MP3 file not found after conversion.');
      }

      await _shareFile(mp3File);
      setState(() => _status = 'MP3 exported: ${mp3File.path}');
    } catch (e) {
      setState(() => _status = 'Error: $e');
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _shareFile(File file) async {
    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'Generated by Native TTS Studio');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _tts.stop();
    _tts.awaitSpeakCompletion(false);
    _tts.awaitSynthCompletion(false);
    _tts.setSharedInstance(false);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preset = _presets.firstWhere(
      (p) => p.locale == _selectedLocale,
      orElse: () => _presets.first,
    );
    final theme = Theme.of(context);
    final canSelectVoice = _voicesForLocale.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Native TTS Studio'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.secondaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On-device voices • No cloud API required',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Now supports faster speech playback for quick listening and exports.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _textController,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Text to synthesize',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets
                .map(
                  (p) => ChoiceChip(
                    label: Text(p.label),
                    selected: _selectedLocale == p.locale,
                    onSelected: (_) => _loadVoicesForLocale(p.locale),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            'Selected accent: ${preset.region} (${preset.locale})',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String, String>>(
            value: _selectedVoice,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Voice',
            ),
            items: _voicesForLocale
                .map(
                  (voice) => DropdownMenuItem<Map<String, String>>(
                    value: voice,
                    child: Text(voice['name'] ?? 'Unknown voice'),
                  ),
                )
                .toList(),
            onChanged: !canSelectVoice
                ? null
                : (voice) async {
                    setState(() => _selectedVoice = voice);
                    if (voice != null) {
                      await _tts.setVoice(voice);
                    }
                  },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Speed (${_speechRate.toStringAsFixed(2)})',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  _SpeedChip(
                    label: 'Normal',
                    selected: _speechRate == 0.55,
                    onTap: () => setState(() => _speechRate = 0.55),
                  ),
                  _SpeedChip(
                    label: 'Fast',
                    selected: _speechRate == 0.75,
                    onTap: () => setState(() => _speechRate = 0.75),
                  ),
                  _SpeedChip(
                    label: 'Max',
                    selected: _speechRate == 1.0,
                    onTap: () => setState(() => _speechRate = 1.0),
                  ),
                ],
              ),
            ],
          ),
          Slider(
            value: _speechRate,
            min: 0.2,
            max: 1.0,
            onChanged: (v) => setState(() => _speechRate = v),
          ),
          Text('Pitch (${_pitch.toStringAsFixed(2)})', style: theme.textTheme.titleSmall),
          Slider(
            value: _pitch,
            min: 0.6,
            max: 1.4,
            onChanged: (v) => setState(() => _pitch = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _speak,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Preview'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _stop,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _exportWav,
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('Export WAV'),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _exportMp3,
                icon: const Icon(Icons.library_music_outlined),
                label: const Text('Export MP3'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _status,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Tip: For the most natural voices on Samsung devices, keep Google Speech Services up to date and download offline voice packs in Android Settings.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );
  }
}
