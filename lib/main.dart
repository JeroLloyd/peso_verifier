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
  bool isProcessing = false; // Loading state
  File? capturedImage;       // Stores the photo you take
  List<Map<String, dynamic>> yoloResults = [];
  bool isFlashOn = false;

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    await Permission.camera.request();
    
    // Medium (480p) is best: Good aspect ratio (4:3), good detail, fast processing.
    controller = CameraController(
      cameras[0], 
      ResolutionPreset.medium, 
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
      // 1. Capture the High-Quality Photo
      final XFile photo = await controller.takePicture();
      File imageFile = File(photo.path);

      // 2. Load bytes for AI
      final imageBytes = await imageFile.readAsBytes();
      final decodedImage = await decodeImageFromList(imageBytes);

      // 3. Run AI on the static image
      final result = await vision.yoloOnImage(
        bytesList: imageBytes,
        imageHeight: decodedImage.height,
        imageWidth: decodedImage.width,
        iouThreshold: 0.4,
        confThreshold: 0.20, // 20% Confidence
        classThreshold: 0.20,
      );

      print("✅ CAPTURE SCANNED: $result");

      setState(() {
        capturedImage = imageFile; // Show the frozen image
        yoloResults = result;      // Draw boxes on it
        isProcessing = false;
      });

      if (result.isEmpty) {
        _showNoDetectionDialog();
      }

    } catch (e) {
      print("❌ Error: $e");
      setState(() {
        isProcessing = false;
      });
    }
  }

  void resetCamera() {
    setState(() {
      capturedImage = null; // Go back to live camera
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

  void _showNoDetectionDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("No security features detected. Try getting closer or adding light."),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isLoaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      body: Stack(
        children: [
          // 1. SHOW CAMERA OR CAPTURED IMAGE
          if (capturedImage == null)
            CameraPreview(controller)
          else
            Image.file(capturedImage!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),

          // 2. SHOW BOXES (Only appears after capture)
          if (capturedImage != null)
             ...displayBoxes(yoloResults),

          // 3. FLASHLIGHT BUTTON (Only in Camera Mode)
          if (capturedImage == null)
            Positioned(
              top: 50,
              right: 20,
              child: FloatingActionButton(
                heroTag: "flash",
                backgroundColor: isFlashOn ? Colors.yellow : Colors.grey,
                onPressed: toggleFlash,
                child: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.black),
              ),
            ),

          // 4. CAPTURE / RESET BUTTONS
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : capturedImage == null
                      ? GestureDetector(
                          onTap: captureAndScan,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey, width: 4),
                            ),
                            child: const Icon(Icons.camera_alt, size: 40, color: Colors.black),
                          ),
                        )
                      : FloatingActionButton.extended(
                          onPressed: resetCamera,
                          label: const Text("Scan Again"),
                          icon: const Icon(Icons.refresh),
                          backgroundColor: Colors.blue,
                        ),
            ),
          )
        ],
      ),
    );
  }

  List<Widget> displayBoxes(List<Map<String, dynamic>> results) {
    if (results.isEmpty || capturedImage == null) return [];
    
    // Simple scaling is usually enough for Image.file as it fills the screen
    final Size size = MediaQuery.of(context).size;
    
    // We assume the image fills the screen (BoxFit.cover)
    // NOTE: If detection boxes are slightly off, we might need to adjust this math
    // based on the specific aspect ratio of the photo vs the screen.
    // For now, this is the standard "Cover" scaling.
    
    // We need the image size to calculate scale
    // Since we decode it in the function, we might want to store it, 
    // but for simplicity we can estimate using the screen size if aspect ratios match (Medium preset helps this).
    
    // For exact precision, we normally calculate based on the decoded image size
    // For this snippet, we will rely on relative positions if your model returns normalized 0-1.
    // IF your model returns pixels (0-640), we calculate factors:
    
    // Assuming 640x640 model output or similar pixel coordinates:
    // We need the ACTUAL image size from the camera.
    double imageW = controller.value.previewSize!.height; // Swapped for Portrait
    double imageH = controller.value.previewSize!.width;
    
    double factorX = size.width / imageW;
    double factorY = size.height / imageH;

    return results.map((result) {
      final box = result["box"];
      String tag = result['tag'];
      
      return Positioned(
        left: box[0] * factorX,
        top: box[1] * factorY,
        width: (box[2] - box[0]) * factorX,
        height: (box[3] - box[1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.greenAccent, width: 3.0),
            color: Colors.greenAccent.withOpacity(0.2), // Light fill
          ),
          child: Text(
            "$tag ${(result['box'][4] * 100).toStringAsFixed(0)}%",
            style: const TextStyle(
              backgroundColor: Colors.green,
              color: Colors.white,
              fontSize: 12.0,
            ),
          ),
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