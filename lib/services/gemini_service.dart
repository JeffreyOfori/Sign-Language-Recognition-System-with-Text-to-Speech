import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class SignPrediction {
  SignPrediction({
    required this.sign,
    required this.confidence,
    required this.gloss,
    required this.note,
  });

  final String sign;
  final double confidence;
  final String gloss;
  final String note;

  factory SignPrediction.unknown(String reason) => SignPrediction(
        sign: '—',
        confidence: 0,
        gloss: '',
        note: reason,
      );
}

class GeminiService {
  GeminiService() {
    _apiKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
    final primary = dotenv.env['OPENROUTER_MODEL'] ?? 'google/gemma-4-31b-it:free';
    final fallbacks = (dotenv.env['OPENROUTER_FALLBACKS'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    _models = [primary, ...fallbacks];
    if (_apiKey.isEmpty) {
      throw StateError(
        'OPENROUTER_API_KEY missing — set it in the .env file before running.',
      );
    }
  }

  late final String _apiKey;
  late final List<String> _models;

  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  static const _systemPrompt = '''
You are an expert in Ghanaian Sign Language (GSL) and American Sign Language (ASL) fingerspelling.
The image shows a single human hand (or two hands) making a sign in front of a camera.
Identify the most likely sign being shown.

GSL/ASL signs to consider include (but are not limited to):
- Greetings: HELLO, GOODBYE, GOOD MORNING, THANK YOU, PLEASE, SORRY
- Responses: YES, NO, OK, MAYBE
- People: I/ME, YOU, FAMILY, FRIEND, MOTHER, FATHER
- Needs: HELP, WATER, FOOD, BATHROOM, DOCTOR, PAIN
- Numbers: ZERO through NINE
- ASL alphabet: A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z

Return ONLY a JSON object with this shape (no markdown, no prose):
{
  "sign": "<uppercase label, e.g. HELLO or LETTER_A>",
  "confidence": <float 0.0-1.0>,
  "gloss": "<plain-English meaning, e.g. 'Hello' or 'Letter A'>",
  "note": "<short reasoning, <= 12 words>"
}

If no clear hand sign is visible, return:
{ "sign": "NONE", "confidence": 0.0, "gloss": "", "note": "no clear sign" }
''';

  Future<SignPrediction> recognize(Uint8List jpegBytes) async {
    final base64Image = base64Encode(jpegBytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';
    String lastError = 'no models configured';

    for (final model in _models) {
      try {
        final body = jsonEncode({
          'model': model,
          'temperature': 0.1,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': _systemPrompt},
                {
                  'type': 'image_url',
                  'image_url': {'url': dataUrl},
                },
              ],
            },
          ],
        });

        final resp = await http.post(
          Uri.parse(_endpoint),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://slrs-gemini.local',
            'X-Title': 'SLRS Gemini',
          },
          body: body,
        );

        if (resp.statusCode == 429 || resp.statusCode == 503) {
          lastError = 'http ${resp.statusCode} on $model';
          continue; // try next fallback model
        }
        if (resp.statusCode != 200) {
          return SignPrediction.unknown(
              'http ${resp.statusCode}: ${_short(resp.body)}');
        }

        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final choices = decoded['choices'] as List?;
        final message = choices?.firstOrNull as Map<String, dynamic>?;
        final content = message?['message']?['content']?.toString().trim() ?? '';
        if (content.isEmpty) {
          lastError = 'empty content from $model';
          continue;
        }

        final cleaned = _stripFences(content);
        final Map<String, dynamic> j = jsonDecode(cleaned);
        return SignPrediction(
          sign: (j['sign'] ?? '—').toString(),
          confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
          gloss: (j['gloss'] ?? '').toString(),
          note: (j['note'] ?? '').toString(),
        );
      } catch (e) {
        lastError = 'error on $model: $e';
      }
    }
    return SignPrediction.unknown(lastError);
  }

  String _stripFences(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    return t.trim();
  }

  String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}
