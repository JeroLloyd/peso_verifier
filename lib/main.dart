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

  // --- 1. THE HUMAN DICTIONARY (Fixes "Computer Naming") ---
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
    // High Res is okay for Capture Mode (Honor X9a support)
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
    // 1. Analyze Features
    final strongFeatures = [
      'security_thread', 'optically_variable_device', 
      'see_through_mark', 'concealed_value'
    ];

    int strongCount = 0;
    int totalCount = results.length;

    for (var res in results) {
      if (strongFeatures.contains(res['tag'])) strongCount++;
    }

    // 2. Decide Verdict
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

    // 3. Show Report Card
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildReportCard(verdictTitle, verdictMsg, verdictColor, verdictIcon, results, strongFeatures),
    ).whenComplete(() {
      // NOTE: We do NOT reset camera here automatically. 
      // We let the user look at the image.
      // They must press the "X" or "Scan Again" button on the screen.
    });
  }

  // Extracted Report Card Widget for cleaner code
  Widget _buildReportCard(String title, String msg, Color color, IconData icon, List results, List strongFeatures) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65, 
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black26)],
      ),
      padding: const EdgeInsets.fromLTRB(25, 15, 25, 25),
      child: Column(
        children: [
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 15),
          Icon(icon, color: color, size: 50),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(msg, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 15),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber[200]!)),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: Colors.amber[900]),
                const SizedBox(width: 8),
                const Expanded(child: Text("Always manually tilt the bill to verify the shiny thread.", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft, child: Text("CONFIDENCE RATINGS:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 10),

          Expanded(
            child: results.isEmpty 
            ? Center(child: Text("No features to rate.", style: TextStyle(color: Colors.grey[400])))
            : ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final rawTag = results[index]['tag'];
                  final confidence = (results[index]['box'][4] * 100).toStringAsFixed(0);
                  
                  // HUMAN NAME CONVERSION
                  final displayName = friendlyNames[rawTag] ?? rawTag.replaceAll('_', ' ').toUpperCase();
                  final isStrong = strongFeatures.contains(rawTag);
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isStrong ? Colors.green[50] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isStrong ? Colors.green[100]! : Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(isStrong ? Icons.verified : Icons.analytics_outlined, size: 18, color: isStrong ? Colors.green[700] : Colors.grey[600]),
                            const SizedBox(width: 10),
                            Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          ],
                        ),
                        Text("$confidence%", style: TextStyle(fontWeight: FontWeight.bold, color: isStrong ? Colors.green[700] : Colors.black87)),
                      ],
                    ),
                  );
                },
              ),
          ),
          const SizedBox(height: 10),
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
    );
  }

  void resetCamera() {
    // If sheet is open, close it. If not, just reset state.
    if (Navigator.canPop(context)) { 
      Navigator.pop(context); 
    }
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

    // Honor X9a Scaling Logic
    var scale = 1.0;
    if (capturedImage == null && controller.value.isInitialized) {
      final size = MediaQuery.of(context).size;
      var cameraAspect = controller.value.aspectRatio;
      scale = size.aspectRatio * cameraAspect;
      if (scale < 1) scale = 1 / scale;
    }

    return Scaffold(
      backgroundColor: Colors.black, 
      body: Stack(
        fit: StackFit.expand, 
        children: [
          // 1. IMAGE/CAMERA LAYER
          if (capturedImage == null)
            Transform.scale(
              scale: scale,
              child: Center(child: CameraPreview(controller)),
            )
          else
            Image.file(capturedImage!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),

          // 2. OVERLAYS (BOXES)
          if (capturedImage != null)
             ...displayCleanBoxes(yoloResults),

          // 3. FLASHLIGHT (Only when camera is live)
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

          // 4. MAIN CAPTURE BUTTON (Bottom Center)
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

          // 5. LOADING SPINNER
          if (isProcessing)
             Container(
               color: Colors.black54,
               child: const Center(child: CircularProgressIndicator(color: Colors.white)),
             ),

          // --- FIX: THE "UNSTUCK" BUTTON ---
          // This button appears ONLY when the image is frozen (capturedImage != null).
          // It ensures you can ALWAYS reset, even if you swiped away the report card.
          if (capturedImage != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: ElevatedButton.icon(
                onPressed: resetCamera,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("SCAN AGAIN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> displayCleanBoxes(List<Map<String, dynamic>> results) {
    if (results.isEmpty || capturedImage == null) return [];
    
    final Size size = MediaQuery.of(context).size;
    double imageW = controller.value.previewSize!.height; 
    double imageH = controller.value.previewSize!.width;
    double factorX = size.width / imageW;
    double factorY = size.height / imageH;
    
    double scale = factorX > factorY ? factorX : factorY;
    double offsetX = (imageW * scale - size.width) / 2;
    double offsetY = (imageH * scale - size.height) / 2;

    return results.map((result) {
      final box = result["box"];
      String rawTag = result['tag'];
      
      // FIX: FORCE HUMAN NAME
      // This line grabs the clean name from our dictionary. 
      // If the tag isn't in the list, it defaults to Uppercase.
      String displayName = friendlyNames[rawTag] ?? rawTag.replaceAll('_', ' ').toUpperCase();
      
      String confidence = (box[4] * 100).toStringAsFixed(0);

      bool isSecurityFeature = ['security_thread', 'optically_variable_device', 'see_through_mark'].contains(rawTag);
      Color boxColor = isSecurityFeature ? Colors.amber[700]! : Colors.blue[400]!;

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
              top: -18, 
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: boxColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Text(
                  "$displayName $confidence%", // HUMAN READABLE LABEL
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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