import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/gemini_service.dart';
import '../services/landmark_service.dart';
import '../services/tts_service.dart';
import '../theme.dart';
import '../widgets/onboarding_hint.dart';
import '../widgets/pose_painter.dart';
import '../widgets/result_card.dart';
import '../widgets/sign_history.dart';
import '../widgets/status_pill.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.cameras});
  final List<CameraDescription> cameras;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  late CameraDescription _camera;
  bool _initFailed = false;
  String? _initError;

  final GeminiService _gemini = GeminiService();
  final TtsService _tts = TtsService();
  final LandmarkService _landmarks = LandmarkService();

  LandmarkFrame? _frame;
  SignPrediction? _prediction;
  bool _calling = false;
  bool _ttsOn = true;
  bool _autoCapture = true;
  bool _showHint = true;

  final List<String> _history = [];
  String? _lastAddedSign;

  static const _captureInterval = Duration(milliseconds: 1400);
  DateTime _lastCapture = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _camera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!kIsWeb) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _initFailed = true;
          _initError = 'Camera permission denied';
        });
        return;
      }
    }
    await _tts.init();
    await _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final controller = CameraController(
        _camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: kIsWeb
            ? ImageFormatGroup.jpeg
            : (defaultTargetPlatform == TargetPlatform.android
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888),
      );
      await controller.initialize();
      // Image streaming + ML Kit pose are mobile-only. On web we drive
      // recognition from a periodic timer instead.
      if (!kIsWeb) {
        await controller.startImageStream(_onCameraImage);
      } else {
        _startWebCaptureTimer();
      }
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      setState(() {
        _initFailed = true;
        _initError = '$e';
      });
    }
  }

  Timer? _webTimer;

  void _startWebCaptureTimer() {
    _webTimer?.cancel();
    _webTimer = Timer.periodic(_captureInterval, (_) {
      if (!_autoCapture) return;
      if (_calling) return;
      _captureAndRecognize();
    });
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    final next = widget.cameras.firstWhere(
      (c) => c.lensDirection != _camera.lensDirection,
      orElse: () => _camera,
    );
    if (next.name == _camera.name) return;

    final old = _controller;
    setState(() => _controller = null);
    _webTimer?.cancel();
    if (!kIsWeb) {
      try {
        await old?.stopImageStream();
      } catch (_) {}
    }
    await old?.dispose();
    _camera = next;
    await _startCamera();
  }

  Future<void> _onCameraImage(CameraImage image) async {
    final f = await _landmarks.detect(image, _camera);
    if (f != null && mounted) setState(() => _frame = f);

    if (!_autoCapture) return;
    final now = DateTime.now();
    if (_calling || now.difference(_lastCapture) < _captureInterval) return;
    _lastCapture = now;
    _captureAndRecognize();
  }

  Future<void> _captureAndRecognize() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_calling) return;
    _calling = true;
    if (mounted) setState(() {});

    try {
      if (!kIsWeb) {
        try {
          await controller.stopImageStream();
        } catch (_) {}
      }
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();

      final pred = await _gemini.recognize(bytes);
      if (!mounted) return;
      setState(() => _prediction = pred);
      _maybeAppendHistory(pred);

      if (_ttsOn && pred.confidence >= 0.55 && pred.gloss.isNotEmpty) {
        await _tts.speak(pred.gloss);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _prediction = SignPrediction.unknown('capture failed: $e'));
      }
    } finally {
      _calling = false;
      if (!kIsWeb) {
        try {
          await _controller?.startImageStream(_onCameraImage);
        } catch (_) {}
      }
      if (mounted) setState(() {});
    }
  }

  void _maybeAppendHistory(SignPrediction p) {
    final label = p.gloss.isNotEmpty ? p.gloss : p.sign;
    if (p.sign == '—' || p.sign == 'NONE' || p.confidence < 0.4) return;
    if (label == _lastAddedSign) return;
    _lastAddedSign = label;
    _history.insert(0, label);
    if (_history.length > 8) _history.removeLast();
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StatefulBuilder(builder: (context, setSheet) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Auto-recognize',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Continuously send frames to Gemini',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  value: _autoCapture,
                  activeThumbColor: AppColors.accent,
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _autoCapture = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Speak recognized sign',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Uses on-device TTS',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  value: _ttsOn,
                  activeThumbColor: AppColors.accent,
                  onChanged: (v) {
                    setSheet(() {});
                    setState(() => _ttsOn = v);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.cameraswitch_rounded,
                      color: AppColors.accent),
                  title: const Text('Switch camera',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _camera.lensDirection == CameraLensDirection.front
                        ? 'Front-facing'
                        : 'Rear-facing',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () {
                    Navigator.pop(context);
                    _switchCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger),
                  title: const Text('Clear history',
                      style: TextStyle(color: Colors.white)),
                  onTap: () {
                    setState(() {
                      _history.clear();
                      _lastAddedSign = null;
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _webTimer?.cancel();
      if (!kIsWeb) {
        try {
          await c.stopImageStream();
        } catch (_) {}
      }
      await c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      await _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webTimer?.cancel();
    _controller?.dispose();
    if (!kIsWeb) {
      _landmarks.dispose();
    }
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                gradient: AppColors.brand,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sign_language_rounded,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text('SLRS · Gemini'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _initFailed
          ? _errorView()
          : controller == null
              ? const _LoadingView()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.55),
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.65),
                              ],
                              stops: const [0.0, 0.25, 0.55, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_frame != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: PosePainter(
                              poses: _frame!.poses,
                              imageSize: _frame!.imageSize,
                              rotation: _frame!.rotation,
                              cameraLensDirection: _camera.lensDirection,
                            ),
                          ),
                        ),
                      ),
                    SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 64, left: 16, right: 16),
                            child: Row(
                              children: [
                                StatusPill(busy: _calling, online: !_initFailed),
                                const Spacer(),
                                if (!_autoCapture)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'MANUAL',
                                      style: TextStyle(
                                        color: AppColors.warn,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SignHistory(items: _history),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: ResultCard(
                              prediction: _prediction,
                              busy: _calling,
                              ttsOn: _ttsOn,
                              onToggleTts: () => setState(() => _ttsOn = !_ttsOn),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_autoCapture)
                      Positioned(
                        right: 20,
                        bottom: 140,
                        child: _GlowFab(
                          onPressed: _calling ? null : _captureAndRecognize,
                          busy: _calling,
                        ),
                      ),
                    if (_showHint && controller.value.isInitialized)
                      OnboardingHint(onDismiss: () => setState(() => _showHint = false)),
                  ],
                ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 56),
            const SizedBox(height: 14),
            Text(
              _initError ?? 'Unable to start camera',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.bg,
              ),
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowFab extends StatelessWidget {
  const _GlowFab({required this.onPressed, required this.busy});
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.55),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: FloatingActionButton.large(
        onPressed: onPressed,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        child: busy
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.bg),
                ),
              )
            : const Icon(Icons.camera_alt_rounded, size: 30),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.accent),
          SizedBox(height: 18),
          Text('Starting camera…', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
