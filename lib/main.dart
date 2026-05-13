import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await dotenv.load(fileName: '.env');
  final cameras = await availableCameras();
  runApp(SlrsApp(cameras: cameras));
}

class SlrsApp extends StatelessWidget {
  const SlrsApp({super.key, required this.cameras});
  final List<CameraDescription> cameras;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SLRS Gemini',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: cameras.isEmpty ? const _NoCamera() : HomeScreen(cameras: cameras),
    );
  }
}

class _NoCamera extends StatelessWidget {
  const _NoCamera();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.no_photography_rounded,
                  color: AppColors.muted, size: 56),
              SizedBox(height: 16),
              Text(
                'No camera detected on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
