import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class CountryPreset {
  const CountryPreset({
    required this.label,
    required this.code,
    required this.accents,
  });

  final String label;
  final String code;
  final List<AccentPreset> accents;
}

class _TtsHomePageState extends State<TtsHomePage> {
  static const String _defaultAccentKey = 'default_accent_by_country';

  final FlutterTts _tts = FlutterTts();
  final TextEditingController _textController = TextEditingController(
    text:
        'Hello! This is a natural, on-device text-to-speech demo. You can export this as WAV.',
  );

  static const List<CountryPreset> _countries = [
    CountryPreset(
      label: '🇳🇬 Nigeria',
      code: 'NG',
      accents: [
        AccentPreset(label: 'Nigerian English', locale: 'en-NG', region: 'Nigerian English'),
      ],
    ),
    CountryPreset(
      label: '🇬🇭 Ghana',
      code: 'GH',
      accents: [
        AccentPreset(label: 'Ghanaian English', locale: 'en-GH', region: 'Ghanaian English'),
      ],
    ),
    CountryPreset(
      label: '🇺🇸 US',
      code: 'US',
      accents: [
        AccentPreset(label: 'American English', locale: 'en-US', region: 'American English'),
      ],
    ),
    CountryPreset(
      label: '🇬🇧 UK',
      code: 'GB',
      accents: [
        AccentPreset(label: 'British English', locale: 'en-GB', region: 'British English'),
      ],
    ),
    CountryPreset(
      label: '🇿🇦 South Africa',
      code: 'ZA',
      accents: [
        AccentPreset(
          label: 'South African English',
          locale: 'en-ZA',
          region: 'South African English',
        ),
      ],
    ),
    CountryPreset(
      label: '🇨🇳 Chinese',
      code: 'CN',
      accents: [
        AccentPreset(label: 'Mandarin Chinese', locale: 'zh-CN', region: 'Mandarin Chinese'),
      ],
    ),
  ];

  Map<String, String> _defaultAccentByCountry = <String, String>{};
  List<Map<String, String>> _voicesForLocale = const [];
  String _selectedCountryCode = _countries.first.code;
  String _selectedLocale = _countries.first.accents.first.locale;
  String _selectedGender = 'Any';
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
    await _loadSavedDefaults();
    await _tts.setSharedInstance(true);
    await _tts.awaitSpeakCompletion(true);
    await _tts.awaitSynthCompletion(true);
    await _tts.setSpeechRate(_speechRate);
    await _tts.setPitch(_pitch);

    final country = _countryByCode(_selectedCountryCode);
    final savedLocale = _defaultAccentByCountry[_selectedCountryCode];
    final initialLocale = country.accents
        .map((a) => a.locale)
        .contains(savedLocale)
        ? savedLocale!
        : country.accents.first.locale;

    await _loadVoicesForLocale(initialLocale);
  }

  Future<void> _loadSavedDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_defaultAccentKey);
    if (raw == null || raw.isEmpty) {
      return;
    }

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      _defaultAccentByCountry = decoded.map(
        (key, value) => MapEntry(key, value.toString()),
      );
    }
  }

  Future<void> _saveDefaultAccent(String countryCode, String locale) async {
    _defaultAccentByCountry[countryCode] = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultAccentKey, jsonEncode(_defaultAccentByCountry));
  }

  CountryPreset _countryByCode(String code) {
    return _countries.firstWhere((country) => country.code == code, orElse: () => _countries.first);
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
            'gender': _normalizeGender(voice),
          },
        )
        .toList(growable: false);

    Map<String, String>? chosenVoice;
    final filteredVoices = _voicesMatchingGender(parsedVoices, _selectedGender);
    if (filteredVoices.isNotEmpty) {
      chosenVoice = filteredVoices.first;
      await _tts.setVoice(chosenVoice);
    } else if (parsedVoices.isNotEmpty) {
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

  String _normalizeGender(Map<String, String> voice) {
    final direct = (voice['gender'] ?? voice['sex'] ?? '').toLowerCase();
    final name = (voice['name'] ?? '').toLowerCase();

    if (direct.contains('female') || name.contains('female') || name.contains('woman')) {
      return 'Female';
    }
    if (direct.contains('male') || name.contains('male') || name.contains('man')) {
      return 'Male';
    }
    return 'Unknown';
  }

  List<Map<String, String>> _voicesMatchingGender(List<Map<String, String>> voices, String gender) {
    if (gender == 'Any') {
      return voices;
    }

    final exact = voices.where((voice) => voice['gender'] == gender).toList(growable: false);
    if (exact.isNotEmpty) {
      return exact;
    }

    return voices.where((voice) => voice['gender'] == 'Unknown').toList(growable: false);
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
    await _exportAudio();
  }

  Future<Directory> _resolveDownloadsDirectory() async {
    final knownDownloads = await getDownloadsDirectory();
    if (knownDownloads != null) {
      return knownDownloads;
    }

    if (Platform.isAndroid) {
      final androidDownloads = Directory('/storage/emulated/0/Download');
      if (await androidDownloads.exists()) {
        return androidDownloads;
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    return appDir;
  }

  Future<void> _exportAudio() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnack('Cannot export empty text.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Exporting WAV...';
    });

    try {
      await _applyVoiceConfig();
      final dir = await _resolveDownloadsDirectory();
      await dir.create(recursive: true);
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final wavPath = '${dir.path}/tts_$timestamp.wav';

      await _tts.synthesizeToFile(text, wavPath, true);

      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        throw Exception('TTS engine did not generate WAV file.');
      }

      await _shareFile(wavFile);
      setState(() => _status = 'WAV saved in Downloads: ${wavFile.path}');
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
    final theme = Theme.of(context);
    final selectedCountry = _countryByCode(_selectedCountryCode);
    final selectedAccent = selectedCountry.accents.firstWhere(
      (accent) => accent.locale == _selectedLocale,
      orElse: () => selectedCountry.accents.first,
    );
    final filteredVoices = _voicesMatchingGender(_voicesForLocale, _selectedGender);
    final canSelectVoice = filteredVoices.isNotEmpty;

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
            children: _countries
                .map(
                  (country) => ChoiceChip(
                    label: Text(country.label),
                    selected: _selectedCountryCode == country.code,
                    onSelected: (_) async {
                      final defaultLocale =
                          _defaultAccentByCountry[country.code] ?? country.accents.first.locale;
                      setState(() => _selectedCountryCode = country.code);
                      await _loadVoicesForLocale(defaultLocale);
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedLocale,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Accent',
            ),
            items: selectedCountry.accents
                .map(
                  (accent) => DropdownMenuItem<String>(
                    value: accent.locale,
                    child: Text(accent.label),
                  ),
                )
                .toList(),
            onChanged: (locale) async {
              if (locale == null) return;
              await _loadVoicesForLocale(locale);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await _saveDefaultAccent(_selectedCountryCode, _selectedLocale);
                _showSnack('Saved default accent for ${selectedCountry.label}.');
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Save as default for this country'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Selected accent: ${selectedAccent.region} (${selectedAccent.locale})',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedGender,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Voice gender',
            ),
            items: const ['Any', 'Male', 'Female']
                .map(
                  (gender) => DropdownMenuItem<String>(
                    value: gender,
                    child: Text(gender),
                  ),
                )
                .toList(),
            onChanged: (gender) async {
              if (gender == null) return;
              final nextVoices = _voicesMatchingGender(_voicesForLocale, gender);
              setState(() {
                _selectedGender = gender;
                _selectedVoice = nextVoices.isNotEmpty ? nextVoices.first : null;
              });
              if (_selectedVoice != null) {
                await _tts.setVoice(_selectedVoice!);
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Map<String, String>>(
            value: _selectedVoice,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Voice',
            ),
            items: filteredVoices
                .map(
                  (voice) => DropdownMenuItem<Map<String, String>>(
                    value: voice,
                    child: Text('${voice['name'] ?? 'Unknown voice'} (${voice['gender'] ?? 'Unknown'})'),
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

class TtsHomePage extends StatefulWidget {
  const TtsHomePage({super.key});

  @override
  State<TtsHomePage> createState() => _TtsHomePageState();
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
