import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:permission_handler/permission_handler.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MaterialApp(home: PesoAuthApp()));
}

class PesoAuthApp extends StatefulWidget {
  const PesoAuthApp({super.key});

  @override
  State<PesoAuthApp> createState() => _PesoAuthAppState();
}

class _PesoAuthAppState extends State<PesoAuthApp> {
  late CameraController controller;
  late FlutterVision vision;
  bool isLoaded = false;
  bool isProcessing = false;
  File? capturedImage;
  List<Map<String, dynamic>> yoloResults = [];
  bool isFlashOn = false;

  // --- 1. THE DICTIONARY: Human Friendly Names ---
  final Map<String, String> friendlyNames = {
    'security_thread': 'Security Thread',
    'optically_variable_device': 'Hologram',
    'see_through_mark': 'See-Through Text',
    'concealed_value': 'Hidden Value',
    'serial_number': 'Serial Number',
    'value': 'Denomination',
    'watermark': 'Watermark',
    'portrait': 'Portrait',
  };

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    await Permission.camera.request();
    
    // FIX 1: Switch back to HIGH (16:9). 
    // Since we are not streaming AI, this won't crash your Honor X9a memory.
    // 16:9 is much closer to your 20:9 screen than Medium (4:3).
    controller = CameraController(
      cameras[0], 
      ResolutionPreset.high, 
      enableAudio: false,
    );
    
    await controller.initialize();
    await controller.setFocusMode(FocusMode.auto); 

    vision = FlutterVision();
    await vision.loadYoloModel(
      labels: 'assets/labels.txt',
      modelPath: 'assets/peso_model.tflite',
      modelVersion: "yolov8",
      quantization: false, 
      numThreads: 2,
      useGpu: false,
    );

    setState(() {
      isLoaded = true;
    });
  }

  Future<void> captureAndScan() async {
    if (isProcessing) return;

    setState(() {
      isProcessing = true;
      yoloResults = [];
    });

    try {
      final XFile photo = await controller.takePicture();
      File imageFile = File(photo.path);

      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = await decodeImageFromList(imageBytes);

      final result = await vision.yoloOnImage(
        bytesList: imageBytes,
        imageHeight: decodedImage.height,
        imageWidth: decodedImage.width,
        iouThreshold: 0.4,
        confThreshold: 0.20, 
        classThreshold: 0.20,
      );

      _generateVerdict(result, imageFile);

    } catch (e) {
      print("❌ Error: $e");
      setState(() {
        isProcessing = false;
      });
    }
  }

  void _generateVerdict(List<Map<String, dynamic>> results, File image) {
    final strongFeatures = [
      'security_thread', 
      'optically_variable_device', 
      'see_through_mark', 
      'concealed_value'
    ];

    int strongCount = 0;
    int totalCount = results.length;

    for (var res in results) {
      if (strongFeatures.contains(res['tag'])) {
        strongCount++;
      }
    }

    String verdictTitle;
    Color verdictColor;
    IconData verdictIcon;
    String verdictMsg;

    if (strongCount >= 1) {
      verdictTitle = "LIKELY AUTHENTIC";
      verdictMsg = "Advanced security features detected.";
      verdictColor = Colors.green[700]!;
      verdictIcon = Icons.verified_user_rounded;
    } else if (totalCount >= 3) {
      verdictTitle = "LIKELY AUTHENTIC";
      verdictMsg = "Multiple identifying marks found.";
      verdictColor = Colors.green[700]!;
      verdictIcon = Icons.verified_user_rounded;
    } else if (results.isNotEmpty) {
      verdictTitle = "INCONCLUSIVE";
      verdictMsg = "Some features found, but key security marks missing.";
      verdictColor = Colors.orange[800]!;
      verdictIcon = Icons.help_outline_rounded;
    } else {
      verdictTitle = "NOT DETECTED";
      verdictMsg = "No banknote features identified. Check lighting.";
      verdictColor = Colors.red[700]!;
      verdictIcon = Icons.error_outline_rounded;
    }

    setState(() {
      capturedImage = image;
      yoloResults = results;
      isProcessing = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false, 
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.55, 
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black26)],
        ),
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 15),
            Icon(verdictIcon, color: verdictColor, size: 50),
            const SizedBox(height: 10),
            Text(verdictTitle, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: verdictColor)),
            Text(verdictMsg, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 20),
            
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber[200]!)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber[900]),
                  const SizedBox(width: 8),
                  const Expanded(child: Text("Always manually tilt the bill to verify the shiny thread.", style: TextStyle(fontSize: 11))),
                ],
              ),
            ),
            
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: resetCamera,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
                child: const Text("SCAN ANOTHER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void resetCamera() {
    Navigator.pop(context);
    setState(() {
      capturedImage = null;
      yoloResults = [];
    });
  }

  void toggleFlash() async {
    if (controller.value.isInitialized) {
      if (isFlashOn) {
        await controller.setFlashMode(FlashMode.off);
      } else {
        await controller.setFlashMode(FlashMode.torch);
      }
      setState(() {
        isFlashOn = !isFlashOn;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isLoaded) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));

    // --- FIX 2: Full Screen Scaling Logic ---
    var scale = 1.0;
    if (capturedImage == null && controller.value.isInitialized) {
      final size = MediaQuery.of(context).size;
      // Calculate how much we need to zoom to fill the tall Honor screen
      // Camera is usually 16:9 (1.77 aspect)
      // Your Phone is 20:9 (2.22 aspect)
      // We scale by the difference (approx 1.25x)
      var cameraAspect = controller.value.aspectRatio;
      scale = size.aspectRatio * cameraAspect;
      if (scale < 1) scale = 1 / scale;
    }

    return Scaffold(
      backgroundColor: Colors.black, // Makes borders invisible
      body: Stack(
        fit: StackFit.expand, // Force stack to fill screen
        children: [
          // 1. Scaled Camera Preview
          if (capturedImage == null)
            Transform.scale(
              scale: scale, // <--- THE MAGIC ZOOM
              child: Center(
                child: CameraPreview(controller),
              ),
            )
          else
            Image.file(capturedImage!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),

          // 2. Overlays
          if (capturedImage != null)
             ...displayCleanBoxes(yoloResults),

          // 3. Flash Button
          if (capturedImage == null)
            Positioned(
              top: 50, right: 20,
              child: FloatingActionButton(
                heroTag: "flash",
                backgroundColor: isFlashOn ? Colors.yellow : Colors.white,
                onPressed: toggleFlash,
                mini: true,
                child: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.black),
              ),
            ),

          // 4. Capture Button
          if (capturedImage == null && !isProcessing)
            Positioned(
              bottom: 40, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: captureAndScan,
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[300]!, width: 5),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                    ),
                    child: Icon(Icons.camera_alt_rounded, size: 40, color: Colors.grey[800]),
                  ),
                ),
              ),
            ),

          if (isProcessing)
             Container(
               color: Colors.black54,
               child: const Center(child: CircularProgressIndicator(color: Colors.white)),
             )
        ],
      ),
    );
  }

  List<Widget> displayCleanBoxes(List<Map<String, dynamic>> results) {
    if (results.isEmpty || capturedImage == null) return [];
    
    final Size size = MediaQuery.of(context).size;
    
    // NOTE: When displaying static image with BoxFit.cover, 
    // we assume the image fills the screen.
    // If the image aspect ratio differs slightly, Flutter crops it.
    // Box coordinates might drift slightly at the edges, but this is usually acceptable.
    // For perfect precision, we would calculate the exact crop offset, 
    // but for this UI, simple scaling is sufficient.
    
    // We can just rely on the fact that Image.file(fit: cover) and the screen size match
    // ONLY IF the image was taken in the same orientation.
    // Standard High Res is 16:9, screen is 20:9. 
    // BoxFit.cover crops the top/bottom of the 16:9 image to fit 20:9? 
    // No, 20:9 is TALLER. It zooms the 16:9 image to fill height, cropping sides?
    // Actually, 20:9 is NARROWER. It will zoom to fill Height, cropping Left/Right.
    
    // To match coordinates, we need the "Displayed" size, not just screen size.
    // However, calculating the crop offset is complex.
    // A simplified approach that works 90% of the time:
    
    double imageW = controller.value.previewSize!.height; // Portrait swap
    double imageH = controller.value.previewSize!.width;
    
    double factorX = size.width / imageW;
    double factorY = size.height / imageH;
    
    // For BoxFit.cover logic override:
    // We use the LARGER factor to ensure we scale up to cover
    double scale = factorX > factorY ? factorX : factorY;
    
    // We need to center the image conceptually.
    // Offset to center = (ScaledImageDim - ScreenDim) / 2
    double offsetX = (imageW * scale - size.width) / 2;
    double offsetY = (imageH * scale - size.height) / 2;

    return results.map((result) {
      final box = result["box"];
      String rawTag = result['tag'];
      String displayName = friendlyNames[rawTag] ?? rawTag.toUpperCase();
      
      bool isSecurityFeature = ['security_thread', 'optically_variable_device', 'see_through_mark'].contains(rawTag);
      Color boxColor = isSecurityFeature ? Colors.amber[700]! : Colors.blue[400]!;

      // Apply Scale and subtract Offset to align with BoxFit.cover
      double left = (box[0] * scale) - offsetX;
      double top = (box[1] * scale) - offsetY;
      double width = (box[2] - box[0]) * scale;
      double height = (box[3] - box[1]) * scale;

      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: boxColor, width: 2.5),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            Positioned(
              top: -15, 
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: boxColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  displayName, 
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 10, 
                    fontWeight: FontWeight.bold
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  @override
  void dispose() {
    controller.dispose();
    vision.closeYoloModel();
    super.dispose();
  }
}