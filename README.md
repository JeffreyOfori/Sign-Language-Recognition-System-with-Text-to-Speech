# SLRS · Gemini

Real-time Sign Language Recognition System (Group 13D project) — Flutter Android app
that pipes a live camera feed through Google's **Gemini Vision API** to recognise
Ghanaian / American sign language gestures, with on-device pose landmarks for
visual feedback and TTS for spoken output.

## Architecture

```
Camera frames ──▶ ML Kit Pose Detector  ──▶  Landmark overlay (CustomPaint)
            └──▶ JPEG every ~1.4s  ──▶  Gemini 2.0 Flash ──▶ JSON {sign, confidence, gloss}
                                                       └──▶ Result card + flutter_tts
```

## Setup

1. **Get an OpenRouter API key** from <https://openrouter.ai/settings/keys>. OpenRouter
   gives you Gemini (and other models) behind one unified endpoint and includes a
   free tier on `google/gemma-4-31b-it:free`.
2. Paste it into `.env`:

   ```env
   OPENROUTER_API_KEY=sk-or-v1-...your_key...
   OPENROUTER_MODEL=google/gemma-4-31b-it:free
   ```

3. Fetch packages:

   ```powershell
   flutter pub get
   ```

4. Accept Android licenses (one-time):

   ```powershell
   flutter doctor --android-licenses
   ```

## Run

Plug in an Android phone with USB debugging on, or start an emulator that exposes a
camera (`-camera-back webcam0`), then:

```powershell
flutter devices
flutter run -d <device-id>
```

Build a shareable APK:

```powershell
flutter build apk --release
# output: build\app\outputs\flutter-apk\app-release.apk
```

## How it works

- **`lib/main.dart`** — bootstraps cameras + `.env`.
- **`lib/screens/home_screen.dart`** — owns the camera controller, throttles capture
  to one Gemini call per ~1.4s, paints landmarks on each frame.
- **`lib/services/gemini_service.dart`** — sends the JPEG + GSL/ASL system prompt;
  parses the JSON response into a `SignPrediction`.
- **`lib/services/landmark_service.dart`** — wraps `google_mlkit_pose_detection`.
- **`lib/services/tts_service.dart`** — `flutter_tts` wrapper; only speaks when
  confidence ≥ 0.55.
- **`lib/widgets/pose_painter.dart`** — `CustomPainter` that draws shoulder→wrist→
  fingertip skeleton over the camera preview.

## Toggles in the app

- ↻ (top-right) — switch between auto-recognize and manual "Recognize" button.
- 🔊 (result card) — mute / unmute spoken output.

## Notes / limits

- Gemini's GSL coverage is weaker than ASL; the prompt biases toward common signs
  shared between the two systems. Add more few-shot examples in
  `gemini_service.dart` if you have reference images of specific GSL signs.
- Pose detection uses upper-body landmarks (shoulders → wrists → thumb/index/pinky).
  It is **not** a true hand-skeleton model — it's a visual cue for the demo.
- Frames are sent over the network. Don't show sensitive content on camera.

## Project context

This implements the proposal in `SLRS1.pptx` (Group 13D, UEW), substituting the
proposed CNN+LSTM pipeline with the Gemini Vision API for faster iteration and no
local training step. The hand-landmark overlay still appears in the demo as
required by the methodology.
