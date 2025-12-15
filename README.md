# 🎙️ Speakbot - Real-time AI Voice Agent

A Flutter-based voice assistant application that enables real-time voice conversations with an AI bot using WebSocket communication. Features a beautiful dark-themed interface with animated gradient visualizations.

![Flutter](https://img.shields.io/badge/Flutter-3.0+-blue.svg)
![Dart](https://img.shields.io/badge/Dart-3.0+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## 📋 Table of Contents

- [Features](#features)
- [Architecture Overview](#architecture-overview)
- [Frontend Implementation](#frontend-implementation)
- [Backend Communication](#backend-communication)
- [Setup & Installation](#setup--installation)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

## ✨ Features

- 🎤 **Real-time Voice Recording** - Press and hold to record audio
- 🔊 **Streaming Audio Playback** - Receive and play AI responses in real-time
- 🌈 **Animated UI** - Beautiful gradient animations and dark mode interface
- ⚡ **WebSocket Communication** - Low-latency bidirectional communication
- 🎧 **Audio Buffering** - Smart buffering system for smooth playback
- 🔒 **JWT Authentication** - Secure token-based authentication
- ⏸️ **Interrupt Capability** - Stop AI mid-speech for natural conversations

## 📱 Frontend Implementation

### Technology Stack

- **Framework**: Flutter 3.0+
- **Language**: Dart 3.0+
- **Key Packages**:
  - `web_socket_channel`: WebSocket communication
  - `record`: Audio recording (PCM16 format)
  - `just_audio`: High-quality audio playback
  - `permission_handler`: Microphone permissions

### Core Components

#### 1. **Audio Recording System**

```dart

RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 24000,
  numChannels: 2,
)
```

**How it works:**
- User presses and holds the microphone button
- Audio is captured in chunks and buffered in memory
- On release, the entire audio buffer is Base64-encoded
- Sent as a single payload to the backend via WebSocket
- Automatic 30-second limit to prevent memory overflow

#### 2. **Audio Playback System**

```dart
// Converts raw PCM to WAV format with proper headers
_addWavHeader(pcmData, sampleRate: 16000)
```

**How it works:**
- Receives raw PCM audio chunks from backend
- Buffers minimum 3 chunks before playback (reduces stuttering)
- Adds WAV headers for compatibility with `just_audio`
- Writes to temporary files for playback
- Automatically cleans up temp files after playback

#### 3. **WebSocket Communication**

**Connection Flow:**
```
1. Connect to wss://your-backend-url/api/v1/voice
2. Send auth message with JWT token
3. Wait for auth_success response
4. Ready to send/receive audio
```

#### 4. **UI Components**

- **AnimatedGradientCircle**: Custom-painted rotating gradient with 3 layers
- **Microphone Button**: Gradient purple-to-blue styling
- **Status Display**: Real-time status updates and transcripts
- **Dark Theme**: Sleek dark mode interface (Color: `#1a1a1a`)

### State Management

The app uses a simple setState-based approach with these key states:
- `_isConnected`: WebSocket connection status
- `_isRecording`: Currently recording audio
- `_isPlaying`: Currently playing AI response
- `_status`: User-facing status message

## 🔌 Backend Communication

### WebSocket Protocol

#### Message Format
All messages are JSON-encoded with a `type` field:

#### **1. Authentication**

**Client → Server:**
```json
{
  "type": "auth",
  "token": "eyJhbGc...",
  "session_id": "uuid-v4"
}
```

**Server → Client:**
```json
{
  "type": "auth_success"
}
```

#### **2. Audio Transmission**

**Client → Server:**
```json
{
  "type": "audio",
  "audio": "base64-encoded-pcm-data"
}
```

**Client → Server (end of speech):**
```json
{
  "type": "commit"
}
```

#### **3. Audio Reception**

**Server → Client:**
```json
{
  "type": "speech_started"
}
```

**Server → Client (streaming audio chunks):**
```json
{
  "type": "audio",
  "data": "base64-encoded-pcm-data"
}
```

**Server → Client:**
```json
{
  "type": "speech_ended"
}
```

#### **4. Transcripts**

**Server → Client (user speech):**
```json
{
  "type": "user_transcript",
  "transcript": "Hello, how are you?"
}
```

**Server → Client (AI response):**
```json
{
  "type": "assistant_transcript",
  "transcript": "I'm doing well, thank you!"
}
```

#### **5. Interruption**

**Client → Server:**
```json
{
  "type": "interrupt"
}
```

### Backend Requirements

The backend should:

1. **Accept WebSocket connections** at `/api/v1/voice`
2. **Authenticate** using JWT tokens
3. **Process audio** in PCM16 format (24kHz from client, 16kHz to client)
4. **Stream responses** in chunks for real-time playback
5. **Handle interrupts** gracefully
6. **Support STT** (Speech-to-Text) for transcription
7. **Support TTS** (Text-to-Speech) for responses

### Expected Audio Formats

| Direction | Format | Sample Rate | Channels | Encoding |
|-----------|--------|-------------|----------|----------|
| Client → Server | PCM16 | 24kHz | 2 (Stereo) | Base64 |
| Server → Client | PCM16 | 16kHz | 1 (Mono) | Base64 |

## 🚀 Setup & Installation

### Prerequisites

- Flutter SDK 3.0 or higher
- Dart SDK 3.0 or higher
- Android Studio / Xcode (for mobile development)
- A running backend server with WebSocket support

### Installation Steps

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/speakbot.git
   cd speakbot
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure backend URL:**
   
   Open `lib/main.dart` and update these constants:
   ```dart
   static const String _wsUrl = 'wss://your-backend-url/api/v1/voice';
   static const String _token = 'your-jwt-token';
   static const String _sessionId = 'your-session-id';
   ```

4. **Run the app:**
   ```bash
   # For Android
   flutter run

   # For iOS
   flutter run -d ios

   # For Web (limited audio support)
   flutter run -d chrome
   ```

### Permissions

#### Android (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

#### iOS (`ios/Runner/Info.plist`):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice chat</string>
```

## 🔧 How It Works

### Complete Flow Diagram

```
User Press & Hold Mic
        │
        ▼
  Start Recording
  (PCM16, 24kHz)
        │
        ▼
   Buffer Audio
   (in memory)
        │
        ▼
User Releases Mic
        │
        ▼
  Base64 Encode
        │
        ▼
Send via WebSocket
  {"type": "audio"}
  {"type": "commit"}
        │
        ▼
Backend Processing
 (STT → AI → TTS)
        │
        ▼
Receive PCM Chunks
  {"type": "audio"}
        │
        ▼
  Buffer 3+ Chunks
        │
        ▼
  Add WAV Header
        │
        ▼
Write to Temp File
        │
        ▼
Play Audio with
  just_audio
        │
        ▼
  Clean Up File
        │
        ▼
Wait for Next Chunk
   or Complete
```

### Key Implementation Details

#### Audio Buffering Strategy

The app uses a smart buffering system to ensure smooth playback:

1. **Minimum Buffer**: 3 chunks before starting playback
2. **Timeout Buffer**: 500ms timeout to flush partial buffers
3. **Queue System**: Chunks are queued and played sequentially
4. **Automatic Cleanup**: Temp files are deleted after playback

```dart
if (_rawPcmChunks.length >= _minBufferChunks) {
  _bufferTimer?.cancel();
  _flushAudioBuffer(); // Play immediately
}
```

#### Memory Management

- Audio buffer is cleared after sending
- Temp files are automatically deleted
- WebSocket resources are properly disposed
- Animation controllers are cleaned up

#### Error Handling

- Connection failures trigger reconnection UI
- Audio errors are logged but don't crash the app
- Permission denials show user-friendly messages
- Invalid audio chunks are skipped gracefully

## ⚙️ Configuration

### Adjustable Parameters

```dart
// Recording
static const int MAX_RECORDING_SECONDS = 30;
const RecordConfig(sampleRate: 24000, numChannels: 2);

// Playback
static const int MIN_BUFFER_CHUNKS = 3;
static const int BUFFER_TIMEOUT_MS = 500;
static const int PLAYBACK_SAMPLE_RATE = 16000;

// Animation
const Duration(milliseconds: 1000); // Pulse animation
const Duration(seconds: 4); // Gradient rotation
```

### Backend Configuration

Update these in your backend:
- JWT token expiration time
- Session timeout duration
- Audio chunk size
- STT/TTS model selection

## 🐛 Troubleshooting

### Common Issues

#### 1. **No Audio Playback**
- Check sample rate mismatch (backend should send 16kHz)
- Verify Base64 decoding is correct
- Ensure temp directory has write permissions

#### 2. **Choppy Audio**
- Increase `MIN_BUFFER_CHUNKS` to 5-7
- Check network latency
- Verify backend is sending consistent chunk sizes

#### 3. **WebSocket Connection Fails**
- Verify URL format (must start with `wss://`)
- Check JWT token validity
- Ensure backend CORS settings allow connections

#### 4. **Recording Not Working**
- Check microphone permissions
- Verify device has microphone
- Test with `flutter run -v` for detailed logs

### Debug Mode

Enable detailed logging:
```dart
void _log(String msg) {
  debugPrint("[$timestamp] $msg"); // Already implemented
}
```

## 📊 Performance Considerations

- **Memory**: ~2-5MB per 30s recording
- **Network**: ~24KB/s upload, ~16KB/s download
- **CPU**: Minimal, mostly I/O bound
- **Battery**: Moderate usage during active recording

## 🔐 Security Notes

- JWT tokens should be stored securely (use flutter_secure_storage)
- Use WSS (not WS) in production
- Implement token refresh mechanism
- Sanitize all user inputs on backend

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📧 Contact

For questions or support, please open an issue on GitHub.

---

**Built with ❤️ using Flutter**