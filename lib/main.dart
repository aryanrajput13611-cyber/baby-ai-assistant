import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

// 1. Overlay Entry Point (Screen Glow + Floating Mic Bar)
@pragma("vm:entry-point")
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayAssistantUI(),
  ));
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: BabyControlScreen(),
  ));
}

// 2. Main App Screen for Permissions & Activation
class BabyControlScreen extends StatefulWidget {
  const BabyControlScreen({super.key});

  @override
  State<BabyControlScreen> createState() => _BabyControlScreenState();
}

class _BabyControlScreenState extends State<BabyControlScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _status = "Baby Assistant Not Started";

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
  }

  Future<void> _requestAllPermissions() async {
    await Permission.microphone.request();
    bool overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (!overlayGranted) {
      await FlutterOverlayWindow.requestPermission();
    }
    _initWakeWordListener();
  }

  void _initWakeWordListener() async {
    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          _restartListening();
        }
      },
      onError: (val) => _restartListening(),
    );

    if (available) {
      _startListeningWakeWord();
    }
  }

  void _startListeningWakeWord() {
    setState(() => _isListening = true);
    _speech.listen(
      onResult: (val) {
        String heard = val.recognizedWords.toLowerCase();
        if (heard.contains("baby")) {
          _speech.stop();
          _triggerAssistantOverlay();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
    );
  }

  void _restartListening() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _startListeningWakeWord();
    });
  }

  Future<void> _triggerAssistantOverlay() async {
    bool isActive = await FlutterOverlayWindow.isActive();
    if (!isActive) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: false,
        overlayTitle: "Baby AI Active",
        overlayContent: "Listening...",
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: WindowSize.fullCover,
        width: WindowSize.fullCover,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Baby AI Assistant"),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.graphic_eq, color: Colors.greenAccent, size: 80),
            const SizedBox(height: 20),
            Text(
              _status,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => _triggerAssistantOverlay(),
              child: const Text("Test Overlay Glow & Mic"),
            ),
          ],
        ),
      ),
    );
  }
}

// 3. Floating Overlay UI (Side Edge Glow + Floating Mic Pill)
class OverlayAssistantUI extends StatefulWidget {
  const OverlayAssistantUI({super.key});

  @override
  State<OverlayAssistantUI> createState() => _OverlayAssistantUIState();
}

class _OverlayAssistantUIState extends State<OverlayAssistantUI>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _recognizedText = "बोलिए, मैं सुन रही हूँ...";
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initTTS();
    _listenUserVoice();
  }

  void _initTTS() async {
    await _tts.setLanguage("hi-IN");
    await _tts.setPitch(1.0);
  }

  void _listenUserVoice() async {
    bool available = await _speech.initialize();
    if (available) {
      _speech.listen(
        onResult: (result) {
          setState(() {
            _recognizedText = result.recognizedWords;
          });
          if (result.finalResult) {
            _askBabyAI(result.recognizedWords);
          }
        },
      );
    }
  }

  Future<void> _askBabyAI(String prompt) async {
    if (_isProcessing || prompt.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _recognizedText = "सोच रही हूँ...";
    });

    // Gemini API Request (Add your Gemini API Key here)
    const apiKey = "YOUR_GEMINI_API_KEY";
    final url = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {
                  "text":
                      "You are Baby, a personal AI voice assistant. Give very short, sweet, single-sentence replies in Hindi: $prompt"
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String reply = data['candidates'][0]['content']['parts'][0]['text'];
        setState(() => _recognizedText = reply);
        await _tts.speak(reply);
      } else {
        setState(() => _recognizedText = "API में कुछ समस्या आई");
      }
    } catch (e) {
      setState(() => _recognizedText = "इंटरनेट कनेक्शन जांचें");
    } finally {
      setState(() => _isProcessing = false);
      Future.delayed(const Duration(seconds: 4), () {
        FlutterOverlayWindow.closeOverlay();
      });
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Screen Side Edge Lighting Glow Effect
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.4 + (_glowController.value * 0.6)),
                    width: 6.0,
                  ),
                ),
              );
            },
          ),

          // Bottom Floating Overlay Pill
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 28, left: 16, right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withOpacity(0.95),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => FlutterOverlayWindow.closeOverlay(),
                  ),
                  Expanded(
                    child: Text(
                      _recognizedText,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.greenAccent,
                    ),
                    child: const Icon(Icons.mic, color: Colors.black, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
