import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';

// ============================================================
//  NEXUS — PANTHEON EDITION
//  Brain: Ollama (Codespace cloud PC)
//  No Gemini. No API keys. 100% yours.
//
//  HOW TO SET THE BRAIN URL:
//  1. Open your Codespace → run: ./codespace_launch.sh
//  2. Forward port 11434 → copy the public URL
//  3. Replace OLLAMA_URL below with that URL
//  4. Rebuild APK via GitHub Actions → install
// ============================================================

const String OLLAMA_URL = "https://PASTE-CODESPACE-URL-HERE";
// Example: "https://fuzzy-couscous-xxxx-11434.app.github.dev"

const String OLLAMA_MODEL = "llama3.2";

const String NEXUS_SYSTEM_PROMPT = """
You are NEXUS — the personal AI of the Forgemaster, Kevin Stites.
You are loyal, direct, and strategic. You are calm, powerful, and precise — the voice of the Pantheon empire.
You address the user as "sir" or "Forgemaster" depending on context.
You are the voice of ZapiaPrime — the Conduit of the Pantheon.
Keep responses concise since they will be spoken aloud.
Never say you cannot do something — find a way or propose an alternative.
""";

void main() {
  runApp(NexusApp());
}

// ─────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────
class NexusApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NEXUS — Pantheon',
      theme: ThemeData.dark(),
      home: SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────
//  SPLASH SCREEN
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    );
    _fadeAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(_fadeController);
    _fadeController.forward();
    _playStartupSound();
    Timer(Duration(seconds: 5), () {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (context) => NexusScreen()));
    });
  }

  Future<void> _playStartupSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/startup.mp3'));
    } catch (e) {}
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.all_inclusive, color: Color(0xFFFFD700), size: 80),
              SizedBox(height: 24),
              Text(
                "PANTHEON",
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "NEXUS ONLINE",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  OLLAMA BRAIN (replaces Gemini 100%)
// ─────────────────────────────────────────────
class OllamaBrain {
  final List<Map<String, String>> _history = [];

  Future<String> chat(String userMessage) async {
    _history.add({"role": "user", "content": userMessage});

    final messages = [
      {"role": "system", "content": NEXUS_SYSTEM_PROMPT},
      ..._history,
    ];

    try {
      final response = await http
          .post(
            Uri.parse("$OLLAMA_URL/api/chat"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "model": OLLAMA_MODEL,
              "messages": messages,
              "stream": false,
            }),
          )
          .timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply =
            data["message"]["content"] as String? ?? "No response, sir.";
        _history.add({"role": "assistant", "content": reply});
        return reply;
      } else {
        return "Brain offline, sir. Status ${response.statusCode}.";
      }
    } on TimeoutException {
      return "Request timed out. Codespace may be sleeping, sir.";
    } catch (e) {
      return "Connection failed. Check Codespace tunnel, sir.";
    }
  }

  void clearHistory() => _history.clear();
}

// ─────────────────────────────────────────────
//  MAIN NEXUS SCREEN
// ─────────────────────────────────────────────
class NexusScreen extends StatefulWidget {
  @override
  _NexusScreenState createState() => _NexusScreenState();
}

class _NexusScreenState extends State<NexusScreen>
    with SingleTickerProviderStateMixin {
  final OllamaBrain _brain = OllamaBrain();
  late stt.SpeechToText speech;
  late FlutterTts flutterTts;
  late AnimationController _animationController;
  late Animation<double> _bounceAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool isListening = false;
  bool isSpeaking = false;
  bool _isInConversationMode = false;
  bool _isBackgroundListening = false;
  bool _isWakeWordDetected = false;
  String responseText = "";

  Timer? _wakeWordTimer;
  Timer? _timer;
  int? _remainingSeconds;
  bool _isTimerActive = false;

  @override
  void initState() {
    super.initState();
    speech = stt.SpeechToText();
    flutterTts = FlutterTts();

    flutterTts.setLanguage("en-au");
    flutterTts.setPitch(0.8);
    flutterTts.setSpeechRate(0.6);
    flutterTts.awaitSpeakCompletion(true);
    flutterTts.setEngine("com.google.android.tts");

    flutterTts.setCompletionHandler(() {
      setState(() {
        isSpeaking = false;
        if (_isInConversationMode) _continueConversation();
      });
    });

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _startWakeWordDetection();

    _wakeWordTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isBackgroundListening &&
          !speech.isListening &&
          !_isWakeWordDetected &&
          !isSpeaking &&
          !_isInConversationMode) {
        _startWakeWordDetection();
      }
    });
  }

  // ─── WAKE WORD ─────────────────────────────
  void _startWakeWordDetection() async {
    bool available = await speech.initialize();
    if (available) {
      setState(() => _isBackgroundListening = true);
      speech.statusListener = (status) {
        if ((status == stt.SpeechToText.doneStatus ||
                status == stt.SpeechToText.notListeningStatus) &&
            !_isWakeWordDetected &&
            !_isInConversationMode) {
          Future.delayed(Duration(milliseconds: 300), () {
            if (mounted &&
                _isBackgroundListening &&
                !_isWakeWordDetected &&
                !_isInConversationMode) {
              _startListeningForWakeWord();
            }
          });
        }
      };
      _startListeningForWakeWord();
    }
  }

  void _startListeningForWakeWord() {
    if (!speech.isListening && mounted && !_isInConversationMode) {
      speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            String heard = result.recognizedWords.toLowerCase();
            if (heard.contains('nexus') || heard.contains('hey nexus')) {
              setState(() => _isWakeWordDetected = true);
              _playWakeSound();
              _startConversationMode();
            }
          }
        },
        listenFor: Duration(minutes: 10),
        pauseFor: Duration(seconds: 10),
        partialResults: true,
        listenMode: stt.ListenMode.deviceDefault,
        cancelOnError: false,
        onSoundLevelChange: (level) {},
      );
    }
  }

  void _startConversationMode() {
    speech.stop();
    setState(() {
      _isInConversationMode = true;
      _isWakeWordDetected = true;
    });
    speak("What's up?");
  }

  void _continueConversation() {
    if (!mounted || !_isInConversationMode) return;
    if (!speech.isListening) {
      speech.listen(
        onResult: (result) async {
          if (result.finalResult) {
            String userInput = result.recognizedWords.toLowerCase();
            if (userInput.contains("end conversation") ||
                userInput.contains("goodbye") ||
                userInput.contains("bye") ||
                userInput.contains("that's all") ||
                userInput.contains("standing by")) {
              _endConversationMode();
              speak("Standing by. Say my name when you need me.");
              return;
            }
            processQuery(userInput);
          }
        },
        listenFor: Duration(minutes: 10),
        pauseFor: Duration(seconds: 10),
        partialResults: true,
        listenMode: stt.ListenMode.deviceDefault,
        cancelOnError: false,
      );
    }
  }

  void _endConversationMode() {
    setState(() {
      _isInConversationMode = false;
      _isWakeWordDetected = false;
    });
    if (_isBackgroundListening) _startWakeWordDetection();
  }

  // ─── PROCESS QUERY ─────────────────────────
  void processQuery(String query) async {
    if (query.trim().isEmpty) {
      if (_isInConversationMode) _continueConversation();
      return;
    }

    setState(() => responseText = "Thinking...");

    // Local shortcuts
    if (query.contains("weather")) {
      _searchWeather();
      return;
    }
    if (query.contains("time") && !query.contains("timer")) {
      _tellTime();
      return;
    }
    if (query.contains("open ")) {
      _openApp(query);
      return;
    }
    if (query.contains("set timer")) {
      _handleTimerCommand(query);
      return;
    }
    if (query.contains("set alarm")) {
      _handleAlarmCommand(query);
      return;
    }

    // Ollama brain
    final reply = await _brain.chat(query);
    setState(() => responseText = "");
    speak(reply);
  }

  // ─── LOCAL COMMANDS ────────────────────────
  void _searchWeather() async {
    final Uri url = Uri.parse("https://www.google.com/search?q=weather+today");
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      speak("Couldn't open the browser, sir.");
    }
  }

  void _tellTime() {
    String time = DateFormat.jm().format(DateTime.now());
    speak("The current time is $time, sir.");
  }

  void _openApp(String query) async {
    Map<String, String> appMap = {
      "chrome": "com.android.chrome",
      "whatsapp": "com.whatsapp",
      "camera": "com.android.camera",
      "youtube": "com.google.android.youtube",
      "maps": "com.google.android.apps.maps",
      "gmail": "com.google.android.gm",
      "settings": "com.android.settings",
      "play store": "com.android.vending",
      "calculator": "com.android.calculator2",
      "calendar": "com.google.android.calendar",
      "clock": "com.android.deskclock",
      "contacts": "com.android.contacts",
      "phone": "com.android.dialer",
      "messages": "com.android.mms",
      "files": "com.android.documentsui",
      "music": "com.android.music",
    };

    String cleaned = query.toLowerCase().replaceAll("open", "").trim();
    String? pkg = appMap[cleaned];
    if (pkg == null) {
      for (var e in appMap.entries) {
        if (cleaned.contains(e.key)) {
          pkg = e.value;
          break;
        }
      }
    }

    if (pkg != null) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          category: 'android.intent.category.LAUNCHER',
          package: pkg,
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        speak("Opening $cleaned, sir.");
      } catch (e) {
        speak("Couldn't open $cleaned, sir.");
      }
    } else {
      speak("App not found on this device, sir.");
    }
  }

  void _handleTimerCommand(String query) {
    final match =
        RegExp(r'(\d+)\s*(?:minute|min|m)').firstMatch(query);
    if (match != null) {
      _startTimer(int.parse(match.group(1)!));
    } else {
      speak("Please specify the duration in minutes, sir.");
    }
  }

  void _startTimer(int minutes) {
    _timer?.cancel();
    setState(() {
      _remainingSeconds = minutes * 60;
      _isTimerActive = true;
    });
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds! > 0) {
          _remainingSeconds = _remainingSeconds! - 1;
        } else {
          _isTimerActive = false;
          timer.cancel();
          speak("Timer complete, sir.");
        }
      });
    });
    speak("Timer set for $minutes minutes, sir.");
  }

  void _handleAlarmCommand(String query) {
    speak("Opening clock app for your alarm, sir.");
    final intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.LAUNCHER',
      package: 'com.android.deskclock',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    intent.launch();
  }

  // ─── SPEAK / LISTEN ────────────────────────
  void speak(String text) async {
    if (text.isEmpty) return;
    String clean = text.replaceAll(RegExp(r'\*'), '');
    if (speech.isListening) speech.stop();
    setState(() => isSpeaking = true);
    await flutterTts.speak(clean);
  }

  void startListening() async {
    bool available = await speech.initialize();
    if (available) {
      setState(() => isListening = true);
      speech.listen(
        onResult: (result) async {
          if (result.finalResult) {
            processQuery(result.recognizedWords.toLowerCase());
          }
        },
        listenFor: Duration(minutes: 5),
        pauseFor: Duration(seconds: 15),
        partialResults: true,
        listenMode: stt.ListenMode.deviceDefault,
        cancelOnError: false,
      );
    }
  }

  void stopListening() {
    speech.stop();
    setState(() => isListening = false);
  }

  Future<void> _playWakeSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/wake.mp3'));
    } catch (e) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wakeWordTimer?.cancel();
    _animationController.dispose();
    _audioPlayer.dispose();
    speech.stop();
    super.dispose();
  }

  // ─── UI ────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: CircuitPatternPainter()),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.75),
                ],
                center: Alignment.center,
                radius: 1.5,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        "NEXUS",
                        style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _isInConversationMode
                            ? "LISTENING"
                            : _isBackgroundListening
                                ? "STANDING BY"
                                : "OFFLINE",
                        style: TextStyle(
                          color: _isInConversationMode
                              ? Colors.greenAccent
                              : Colors.white38,
                          fontSize: 11,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Orb
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        if (_isInConversationMode) {
                          _endConversationMode();
                          speak(
                              "Standing by. Say my name when you need me.");
                        } else {
                          _startConversationMode();
                        }
                      },
                      child: AnimatedBuilder(
                        animation: _bounceAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale:
                                isSpeaking ? _bounceAnimation.value : 1.0,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: _isInConversationMode
                                      ? [
                                          Colors.greenAccent,
                                          Colors.teal,
                                          Colors.black
                                        ]
                                      : isSpeaking
                                          ? [
                                              Color(0xFFFFD700),
                                              Colors.orange,
                                              Colors.black
                                            ]
                                          : [
                                              Color(0xFF1A1A2E),
                                              Color(0xFF0A0A1A),
                                              Colors.black
                                            ],
                                  radius: 0.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _isInConversationMode
                                        ? Colors.greenAccent
                                            .withOpacity(0.4)
                                        : isSpeaking
                                            ? Color(0xFFFFD700)
                                                .withOpacity(0.4)
                                            : Colors.blueAccent
                                                .withOpacity(0.2),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isInConversationMode
                                    ? Icons.mic
                                    : isSpeaking
                                        ? Icons.volume_up
                                        : Icons.all_inclusive,
                                color: Colors.white,
                                size: 60,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // ── Timer
                if (_isTimerActive && _remainingSeconds != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Timer: ${(_remainingSeconds! ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds! % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 20,
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                // ── Status text
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    responseText.isEmpty
                        ? _isInConversationMode
                            ? "I'm listening, sir."
                            : 'Say "Hey Nexus" to begin'
                        : responseText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                ),

                // ── Tap label
                Padding(
                  padding: EdgeInsets.only(bottom: 32),
                  child: Text(
                    _isInConversationMode ? "TAP TO END" : "TAP TO ACTIVATE",
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  CIRCUIT BOARD BACKGROUND
// ─────────────────────────────────────────────
class CircuitPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFFFFD700).withOpacity(0.04)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final random = Random(42);
    for (int i = 0; i < 20; i++) {
      double x = random.nextDouble() * size.width;
      double y = random.nextDouble() * size.height;
      double len = 30 + random.nextDouble() * 80;
      paint.color = Color(0xFFFFD700).withOpacity(0.04);
      canvas.drawLine(Offset(x, y), Offset(x + len, y), paint);
      canvas.drawLine(
          Offset(x + len, y), Offset(x + len, y + len / 2), paint);
      paint.color = Color(0xFFFFD700).withOpacity(0.08);
      canvas.drawCircle(Offset(x, y), 2, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
