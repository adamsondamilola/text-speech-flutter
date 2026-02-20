import 'package:flutter_test/flutter_test.dart';

import 'package:text_speech_flutter/main.dart';

void main() {
  testWidgets('renders tts studio controls', (WidgetTester tester) async {
    await tester.pumpWidget(const TtsStudioApp());

    expect(find.text('Native TTS Studio'), findsOneWidget);
    expect(find.text('Text to synthesize'), findsOneWidget);
    expect(find.text('Export MP3'), findsOneWidget);
    expect(find.text('Speed (0.55)'), findsOneWidget);
  });
}
