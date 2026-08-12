import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceSearchDialog extends StatefulWidget {
  const VoiceSearchDialog({super.key});

  @override
  State<VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<VoiceSearchDialog> with SingleTickerProviderStateMixin {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  String _recognizedWords = "";
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initSpeech();
  }

  void _initSpeech() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted && _isListening) {
            _stopListening();
          }
        }
      },
      onError: (errorNotification) {
        if (mounted) _stopListening();
      },
    );
    if (available && mounted) {
      _startListening();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not available')),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startListening() async {
    setState(() => _isListening = true);
    await _speechToText.listen(
      onResult: (result) {
        setState(() {
          _recognizedWords = result.recognizedWords;
        });
        if (result.finalResult && mounted) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.pop(context, _recognizedWords);
          });
        }
      },
      listenMode: ListenMode.search,
    );
  }

  void _stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
      if (mounted && _recognizedWords.isNotEmpty) {
        Navigator.pop(context, _recognizedWords);
      } else if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speechToText.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Listening...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            _recognizedWords.isEmpty ? 'Say something like "Tomato"' : _recognizedWords,
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _stopListening,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening ? 1.0 + (_pulseController.value * 0.2) : 1.0,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _isListening ? const Color(0xFFE53935) : const Color(0xFF164431),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? const Color(0xFFE53935) : const Color(0xFF164431)).withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: _pulseController.value * 10,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.mic_rounded, color: Colors.white, size: 40),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
