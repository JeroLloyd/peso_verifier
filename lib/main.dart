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

  final Map<String, String> friendlyNames = {
    // Specific Bills
    '1000_pearl': '1000 Peso (Pearl)',
    '1000_pearl_watermark': 'Watermark (1000)',
    '500_big_parrot': '500 Peso (Parrot)',
    '500_parrot_watermark': 'Watermark (500)',
    '200_tarsier': '200 Peso (Tarsier)',
    '200_tarsier_watermark': 'Watermark (200)',
    '100_whale': '100 Peso (Whale)',
    '100_whale_watermark': 'Watermark (100)',
    '50_maliputo': '50 Peso (Maliputo)',
    '50_maliputo_watermark': 'Watermark (50)',
    '20_civet': '20 Peso (Civet)',
    '20_civet_watermark': 'Watermark (20)',
    
    // Coins
    '20_New_Front': '20 Peso Coin', '20_New_Back': '20 Peso Coin',
    '10_New_Front': '10 Peso Coin', '10_New_Back': '10 Peso Coin',
    '5_New_Front': '5 Peso Coin',   '5_New_Back': '5 Peso Coin',
    '1_New_Front': '1 Peso Coin',   '1_New_Back': '1 Peso Coin',
    '25Cent_New_Front': '25¢ Coin', '25Cent_New_Back': '25¢ Coin',
    
    // Security Features
    'security_thread': 'Security Thread',
    'optically_variable_device': 'Hologram (OVD)',
    'clear_window': 'Clear Window',
    'concealed_value': 'Hidden Value',
    'see_through_mark': 'See-Through Text',
    'serial_number': 'Serial Number',
    'portrait': 'Portrait (Face)',
    'value': 'Value Label',
    'eagle': 'Eagle Crest',
    'sampaguita': 'Sampaguita',
  };

  @override
  void initState() {
    super.initState();
    initApp();
  }

  Future<void> initApp() async {
    await Permission.camera.request();
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
        confThreshold: 0.10, // Keep lenient to find features
        classThreshold: 0.10,
      );

      _generateAnalysisReport(result, imageFile);

    } catch (e) {
      print("❌ Error: $e");
      setState(() {
        isProcessing = false;
      });
    }
  }

  // --- NEW NEUTRAL REPORT LOGIC ---
  void _generateAnalysisReport(List<Map<String, dynamic>> results, File image) {
    String detectedDenomination = "Unknown";
    bool isCoin = false;

    // 1. Identify Target
    for (var res in results) {
      if (res['box'][4] < 0.10) continue; 
      String tag = res['tag'];

      if (tag.contains('1000_')) detectedDenomination = "1000 Peso";
      else if (tag.contains('500_')) detectedDenomination = "500 Peso";
      else if (tag.contains('200_')) detectedDenomination = "200 Peso";
      else if (tag.contains('100_')) detectedDenomination = "100 Peso";
      else if (tag.contains('50_')) detectedDenomination = "50 Peso";
      else if (tag.contains('20_') && !tag.contains('Coin')) detectedDenomination = "20 Peso";

      if (tag.contains('Coin') || tag.contains('New_') || tag.contains('Old_') || tag.contains('25Cent')) {
        isCoin = true;
        detectedDenomination = "Coin";
      }
    }

    // 2. Prepare Data (No "Verdict", just stats)
    String title = "ANALYSIS COMPLETE";
    Color headerColor = Colors.blue[800]!;
    IconData headerIcon = Icons.analytics_outlined;
    String subTitle = detectedDenomination == "Unknown" ? "Target Unknown" : "Target: $detectedDenomination";

    setState(() {
      capturedImage = image;
      yoloResults = results;
      isProcessing = false;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildReportCard(title, headerColor, headerIcon, results, subTitle),
    );
  }

  Widget _buildReportCard(String title, Color color, IconData icon, List<Map<String, dynamic>> results, String subTitle) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75, 
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
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue[200]!)),
            child: Text(subTitle, style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          
          const SizedBox(height: 10),
          Icon(icon, color: color, size: 50),
          const SizedBox(height: 5),
          Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          
          const SizedBox(height: 15),
          
          // --- THE DISCLAIMER BOX ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber[300]!)
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber[900], size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Percentages indicate AI confidence in recognizing the visual feature. High percentages are NOT a guarantee of authenticity. Always verify manually.",
                    style: TextStyle(color: Colors.amber[900], fontSize: 12, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft, child: Text("DETECTED FEATURES:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 10),

          Expanded(
            child: results.isEmpty 
            ? Center(child: Text("No identifying features detected.", style: TextStyle(color: Colors.grey[400])))
            : ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final rawTag = results[index]['tag'];
                  final confidenceRaw = results[index]['box'][4];
                  final confidence = (confidenceRaw * 100).toStringAsFixed(0);
                  final displayName = friendlyNames[rawTag] ?? rawTag.replaceAll('_', ' ').toUpperCase();
                  
                  // Neutral Coloring
                  bool isHighVal = confidenceRaw > 0.85;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87), overflow: TextOverflow.ellipsis),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isHighVal ? Colors.green[100] : Colors.blue[100],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text("$confidence%", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isHighVal ? Colors.green[800] : Colors.blue[800])),
                        ),
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
    if (Navigator.canPop(context)) Navigator.pop(context); 
    setState(() { capturedImage = null; yoloResults = []; });
  }

  void toggleFlash() async {
    if (controller.value.isInitialized) {
      if (isFlashOn) await controller.setFlashMode(FlashMode.off);
      else await controller.setFlashMode(FlashMode.torch);
      setState(() { isFlashOn = !isFlashOn; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isLoaded) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));

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
          if (capturedImage == null)
            Transform.scale(scale: scale, child: Center(child: CameraPreview(controller)))
          else
            Image.file(capturedImage!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),

          if (capturedImage != null) ...displayCleanBoxes(yoloResults),

          if (capturedImage == null)
            Positioned(top: 50, right: 20, child: FloatingActionButton(heroTag: "flash", backgroundColor: isFlashOn ? Colors.yellow : Colors.white, onPressed: toggleFlash, mini: true, child: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off, color: Colors.black))),

          if (capturedImage == null && !isProcessing)
            Positioned(bottom: 40, left: 0, right: 0, child: Center(child: GestureDetector(onTap: captureAndScan, child: Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey[300]!, width: 5), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)]), child: Icon(Icons.camera_alt_rounded, size: 40, color: Colors.grey[800]))))),

          if (isProcessing) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Colors.white))),

          if (capturedImage != null)
            Positioned(bottom: 40, left: 20, right: 20, child: ElevatedButton.icon(onPressed: resetCamera, icon: const Icon(Icons.refresh, color: Colors.white), label: const Text("SCAN AGAIN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), elevation: 10))),
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
      String displayName = friendlyNames[rawTag] ?? rawTag.replaceAll('_', ' ').toUpperCase();
      double confidenceVal = box[4];
      String confidenceStr = (confidenceVal * 100).toStringAsFixed(0);
      
      bool isValid = confidenceVal >= 0.30;
      Color boxColor = isValid ? Colors.blue : Colors.grey;

      double left = (box[0] * scale) - offsetX;
      double top = (box[1] * scale) - offsetY;
      double width = (box[2] - box[0]) * scale;
      double height = (box[3] - box[1]) * scale;

      return Positioned(left: left, top: top, width: width, height: height, child: Stack(clipBehavior: Clip.none, children: [
        Container(decoration: BoxDecoration(border: Border.all(color: boxColor, width: 2.5), borderRadius: BorderRadius.circular(6))),
        Positioned(top: -18, left: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]), child: Text("$displayName $confidenceStr%", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
      ]));
    }).toList();
  }

  @override
  void dispose() {
    controller.dispose();
    vision.closeYoloModel();
    super.dispose();
  }
}