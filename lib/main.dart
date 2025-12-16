import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:voice_agent/widgets/animation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1a1a1a),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1a1a1a),
          elevation: 0,
        ),
      ),
      home: const VoiceChatScreen(),
    );
  }
}

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});
  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with SingleTickerProviderStateMixin {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  final List<Uint8List> _rawPcmChunks = [];
  Timer? _bufferTimer;
  static const int _minBufferChunks = 5;
  static const int _bufferTimeoutMs = 500;

  final _recorder = AudioRecorder();
  bool _isRecording = false;
  StreamSubscription<Uint8List>? _recordSub;
  Uint8List _audioBuffer = Uint8List(0);
  Timer? _forceSendTimer;

  late final AudioPlayer _player;
  final List<Uint8List> _audioQueue = [];
  bool _isPlaying = false;
  bool _isProcessingQueue = false;
  static const int _preBufferChunks = 8;
  bool _hasStartedPlayback = false;

  String _status = 'Tap Connect';
  late AnimationController _pulseController;

  static const String _wsUrl = '{base_url}/api/v1/voice';
  static const String _token = '{access_token}';
  static const String _sessionId = '{_session_id}';

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _log("App started");
    _requestPermission();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _recorder.dispose();
    _player.dispose();
    _pulseController.dispose();
    _recordSub?.cancel();
    _forceSendTimer?.cancel();
    _bufferTimer?.cancel();
    super.dispose();
  }

  void _log(String msg) {
    final t = DateTime.now().toString().substring(11, 23);
    debugPrint("[$t] $msg");
  }

  void _flushAudioBuffer() {
    if (_rawPcmChunks.isEmpty) return;
    final totalLength = _rawPcmChunks.fold<int>(
      0,
      (sum, chunk) => sum + chunk.length,
    );
    final combinedPcm = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in _rawPcmChunks) {
      combinedPcm.setAll(offset, chunk);
      offset += chunk.length;
    }
    _log(
      "Combined ${_rawPcmChunks.length} chunks → ${combinedPcm.length} bytes",
    );
    _rawPcmChunks.clear();
    final wavBytes = _addWavHeader(combinedPcm, sampleRate: 24000);
    _audioQueue.add(wavBytes);
    _log("Queue size: ${_audioQueue.length}");

    // PRE-BUFFERING LOGIC: Wait for initial buffer before starting
    if (!_isProcessingQueue && !_hasStartedPlayback) {
      if (_audioQueue.length >= _preBufferChunks) {
        _log(
          "Pre-buffer complete (${_audioQueue.length} chunks), starting playback",
        );
        _hasStartedPlayback = true;
        _processAudioQueue();
      } else {
        _log(
          "Pre-buffering... (${_audioQueue.length}/$_preBufferChunks chunks)",
        );
      }
    } else if (!_isProcessingQueue && _hasStartedPlayback) {
      // Already started, just continue processing
      _processAudioQueue();
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      _log("Mic permission granted");
      setState(() => _status = 'Ready');
    } else {
      _log("Mic permission denied");
      setState(() => _status = 'Mic denied');
    }
  }

  Uint8List _addWavHeader(Uint8List pcmData, {int sampleRate = 24000}) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;
    final buffer = Uint8List(44 + dataSize);
    final view = ByteData.view(buffer.buffer);
    buffer.setAll(0, 'RIFF'.codeUnits);
    view.setUint32(4, fileSize, Endian.little);
    buffer.setAll(8, 'WAVE'.codeUnits);
    buffer.setAll(12, 'fmt '.codeUnits);
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, numChannels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);
    buffer.setAll(36, 'data'.codeUnits);
    view.setUint32(40, dataSize, Endian.little);
    buffer.setAll(44, pcmData);
    return buffer;
  }

  Future<void> _connect() async {
    if (_isConnected) return;
    _log("Connecting...");
    setState(() => _status = 'Connecting...');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel!.stream.listen(
        _handleMessage,
        onError: (e) => _log("WS Error: $e"),
        onDone: () => _disconnect(),
      );
      _channel!.sink.add(
        jsonEncode({"type": "auth", "token": _token, "session_id": _sessionId}),
      );
      setState(() {
        _isConnected = true;
        _status = 'Authenticating...';
      });
      _log("Auth sent");
    } catch (e) {
      _log("Connect failed: $e");
      setState(() => _status = 'Failed');
    }
  }

  void _handleMessage(dynamic msg) {
    try {
      final data = jsonDecode(msg);
      final type = data['type'] as String?;
      _log("RECV ← $type");
      switch (type) {
        case 'auth_success':
          setState(() => _status = 'Go ahead, I\'m listening');
          _showSnack('Connected!');
          break;
        case 'speech_started':
          _log("Assistant started speaking");
          _hasStartedPlayback = false; // Reset for new response
          setState(() {
            _isPlaying = true;
            _status = 'Assistant speaking...';
          });
          break;
        case 'audio':
          final String? b64 = data['data'];
          if (b64 != null && b64.isNotEmpty) {
            try {
              final rawPcm = base64Decode(b64);
              _log("Received PCM chunk: ${rawPcm.length} bytes");
              _rawPcmChunks.add(rawPcm);

              // Start timer on first chunk
              if (_rawPcmChunks.length == 1) {
                _bufferTimer?.cancel();
                _bufferTimer = Timer(
                  const Duration(milliseconds: _bufferTimeoutMs),
                  () {
                    _flushAudioBuffer();
                  },
                );
              }

              // Flush when we have enough chunks
              if (_rawPcmChunks.length >= _minBufferChunks) {
                _bufferTimer?.cancel();
                _flushAudioBuffer();
              }
            } catch (e) {
              _log("Error decoding audio: $e");
            }
          }
          break;
        case 'speech_ended':
        case 'response_complete':
          _log("Assistant finished - flushing remaining audio");
          _bufferTimer?.cancel();
          if (_rawPcmChunks.isNotEmpty) {
            _flushAudioBuffer();
          }

          // Update status after queue finishes
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _audioQueue.isEmpty && !_isProcessingQueue) {
              setState(() {
                _isPlaying = false;
                _status = 'Go ahead, I\'m listening';
              });
            }
          });
          break;
        case 'user_transcript':
          final text = data['transcript'] ?? '';
          if (text.isNotEmpty) _log("You said: $text");
          break;
        case 'assistant_transcript':
          final text = data['transcript'] ?? '';
          if (text.isNotEmpty) {
            _log("Assistant: $text");
            if (mounted) {
              setState(() => _status = text);
            }
          }
          break;
        case 'error':
          final err = data['error']?['message'] ?? 'Error';
          _log("ERROR: $err");
          _showSnack(err, error: true);
          break;
        default:
          _log("Ignored: $type");
      }
    } catch (e) {
      _log("Parse error: $e");
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    _log("Recording STARTED (buffering up to 30s)");
    _audioBuffer = Uint8List(0);
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    setState(() {
      _isRecording = true;
      _status = 'Recording...';
    });
    _forceSendTimer = Timer(const Duration(seconds: 30), () {
      if (_isRecording) {
        _log("30s limit → auto send");
        _stopRecording();
      }
    });
    _recordSub = stream.listen((chunk) {
      final newBuf = Uint8List(_audioBuffer.length + chunk.length);
      newBuf.setAll(0, _audioBuffer);
      newBuf.setAll(_audioBuffer.length, chunk);
      _audioBuffer = newBuf;
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _forceSendTimer?.cancel();
    await _recordSub?.cancel();
    await _recorder.stop();
    setState(() => _isRecording = false);
    if (_audioBuffer.isEmpty) {
      _log("No audio recorded");
      return;
    }

    final seconds = _audioBuffer.length / (16000 * 2);
    _log(
      "SENDING one chunk: ${_audioBuffer.length} bytes (~${seconds.toStringAsFixed(1)}s)",
    );
    final b64 = base64Encode(_audioBuffer);
    _channel?.sink.add(jsonEncode({"type": "audio", "audio": b64}));
    _channel?.sink.add(jsonEncode({"type": "commit"}));
    _log("SENT audio + commit");
    _audioBuffer = Uint8List(0);
  }

  Future<void> _processAudioQueue() async {
    if (_isProcessingQueue) {
      _log("Already processing queue");
      return;
    }

    _isProcessingQueue = true;
    _isPlaying = true;
    _log("Started queue processor");

    final tempDir = await getTemporaryDirectory();

    while (_audioQueue.isNotEmpty) {
      final wavBytes = _audioQueue.removeAt(0);
      final file = File(
        '${tempDir.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      try {
        await file.writeAsBytes(wavBytes);
        _log(
          "PLAYING: ${wavBytes.length} bytes (${_audioQueue.length} left in queue)",
        );

        await _player.setAudioSource(AudioSource.uri(Uri.file(file.path)));

        await _player.play();

        await _player.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed,
        );

        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        _log("Playback error: $e");
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }

    _isProcessingQueue = false;
    _isPlaying = false;
    _log("Queue processor finished");

    if (mounted) {
      setState(() => _status = 'Go ahead, I\'m listening');
    }
  }

  void _interrupt() {
    _log("Interrupt sent");
    _channel?.sink.add(jsonEncode({"type": "interrupt"}));
    _player.stop();
    _audioQueue.clear();
    _rawPcmChunks.clear();
    _bufferTimer?.cancel();
    _isProcessingQueue = false;
    setState(() {
      _isPlaying = false;
      _status = 'Interrupted';
    });
  }

  void _disconnect() {
    _log("Disconnecting");
    _channel?.sink.close();
    _player.stop();
    _audioQueue.clear();
    _rawPcmChunks.clear();
    _bufferTimer?.cancel();
    _isProcessingQueue = false;
    setState(() {
      _isConnected = false;
      _isRecording = false;
      _isPlaying = false;
      _status = 'Disconnected';
    });
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a1a),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {},
        ),
        title: const Text(
          'Speaking to AI bot',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _status,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 60),

                  if (_isConnected)
                    const AnimatedGradientCircle()
                  else
                    Center(
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[800],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.mic_none,
                            size: 80,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 60),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!_isConnected)
                    ElevatedButton(
                      onPressed: _connect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: EdgeInsets.symmetric(
                          horizontal: MediaQuery.of(context).size.width * 0.35,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Connect',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  if (_isConnected) ...[
                    GestureDetector(
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressEnd: (_) => _stopRecording(),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF667eea).withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isRecording ? Icons.mic : Icons.mic_none,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isPlaying)
                          TextButton.icon(
                            onPressed: _interrupt,
                            icon: const Icon(Icons.stop, color: Colors.orange),
                            label: const Text(
                              'Interrupt',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ),
                        const SizedBox(width: 20),
                        TextButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text(
                            'Disconnect',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
