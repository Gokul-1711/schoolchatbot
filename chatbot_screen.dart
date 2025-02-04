import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:animate_do/animate_do.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use 10.0.2.2 for Android emulator
  // Use localhost for iOS simulator
  // Use your computer's IP address for physical devices
  static const String baseUrl = 'http://10.1.0.26:5000/api/chat';
  final client = http.Client();

  Future<Map<String, dynamic>> sendMessage(String message) async {
    try {
      final response = await client.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'message': message,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('Connection timed out. Please check your internet connection.');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  Future<void> setUserData(Map userData) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/user'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(userData),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Failed to set user data: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('Connection timed out. Please check your internet connection.');
    } catch (e) {
      throw Exception('Error setting user data: $e');
    }
  }

  Future<String> uploadFile(File file) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      var streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['file_path'];
      } else {
        throw Exception('Failed to upload: ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('Connection timed out. Please check your internet connection.');
    } catch (e) {
      throw Exception('Error: $e');
    }
  }
}

Future<void> loadAndSetCurriculum() async {
  try {
    String jsonString = await rootBundle.loadString('assets/data/chatbot.json');
    Map<String, dynamic> curriculumData = json.decode(jsonString);

    var baseUrl;
    final response = await http.post(
      Uri.parse('$baseUrl/curriculum/set'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(curriculumData),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      print('Failed to set curriculum data: ${response.statusCode}');
    }
  } catch (e) {
    print('Error loading curriculum data: $e');
  }
}

// Rest of your existing code remains the same, including:
// - MessageType enum
// - ChatMessage class
// - ChatbotPage class
// - _ChatbotPageState class
// - MessageInput class
// - ScaleAnimation class

// The only changes needed are in the API calls and error handling as shown above
enum MessageType {
  text,
  image,
  file,
  curriculum
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool animate;
  final MessageType messageType;
  final String? filePath;

  const ChatMessage({
    Key? key,
    required this.text,
    required this.isUser,
    this.animate = false,
    this.messageType = MessageType.text,
    this.filePath,
  }) : super(key: key);

  Widget _buildMessageContent() {
    final TextStyle messageStyle = GoogleFonts.poppins(
      color: isUser ? Colors.white : Colors.black87,
      fontSize: 15,
    );

    if (messageType == MessageType.text && text.contains('•')) {
      final lines = text.split('\n');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          if (line.trim().startsWith('•')) {
            return Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 4.0),
              child: Text(line.trim(), style: messageStyle),
            );
          }
          return Text(line, style: messageStyle);
        }).toList(),
      );
    }

    switch (messageType) {
      case MessageType.text:
        return Text(text, style: messageStyle);
      case MessageType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (filePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(filePath!),
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              text,
              style: GoogleFonts.poppins(
                color: isUser ? Colors.white : Colors.black87,
                fontSize: 12,
              ),
            ),
          ],
        );
      case MessageType.file:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file,
              color: isUser ? Colors.white : Colors.black87,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text, style: messageStyle),
            ),
          ],
        );
      case MessageType.curriculum:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: text.split('\n').map((line) {
            return Padding(
              padding: EdgeInsets.only(
                left: line.trim().startsWith('•') ? 8.0 : 0,
                top: 4.0,
              ),
              child: Text(line, style: messageStyle),
            );
          }).toList(),
        );
    }
  }

  Widget _buildAvatar() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isUser
              ? [Colors.grey.shade200, Colors.grey.shade300]
              : [_ChatbotPageState.primaryColor, _ChatbotPageState.accentColor],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isUser ? Colors.grey : _ChatbotPageState.primaryColor)
                .withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        isUser ? Icons.person : Icons.ac_unit_sharp,
        color: isUser ? Colors.grey.shade700 : Colors.white,
        size: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget messageWidget = Container(
      margin: EdgeInsets.only(
        top: 8.0,
        bottom: 8.0,
        left: isUser ? 60.0 : 16.0,
        right: isUser ? 16.0 : 60.0,
      ),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isUser
                      ? [
                    _ChatbotPageState.primaryColor,
                    _ChatbotPageState.primaryColor.withOpacity(0.8),
                  ]
                      : [
                    Colors.white,
                    Colors.white.withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 5),
                  bottomRight: Radius.circular(isUser ? 5 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isUser
                        ? _ChatbotPageState.primaryColor.withOpacity(0.2)
                        : Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _buildMessageContent(),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser) _buildAvatar(),
        ],
      ),
    );

    if (animate) {
      return FadeInUp(
        duration: const Duration(milliseconds: 500),
        child: messageWidget,
      );
    }
    return messageWidget;
  }
}

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({Key? key}) : super(key: key);

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  late SharedPreferences _prefs;
  bool _isTyping = false;
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color accentColor = Color(0xFF4B47B1);
  static const Color backgroundColor = Color(0xFFF8F9FF);

  @override
  void initState() {
    super.initState();
    loadAndSetCurriculum();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadUserDataAndInitialize();
  }

  Future<void> _loadUserDataAndInitialize() async {
    try {
      String? userId = _prefs.getString('currentUser');
      if (userId == null) {
        _addInitialMessage();
        return;
      }

      DatabaseEvent event = await _database.child('users').child(userId).once();
      if (event.snapshot.value == null) {
        _addInitialMessage();
        return;
      }

      Map userData = event.snapshot.value as Map;
      await _apiService.setUserData(userData);

      setState(() {
        _messages.insert(
          0,
          ChatMessage(
            text: "Hello ${userData['name']}! I'm your AI Tutor for class ${userData['standard']} - ${userData['stream']}. How can I help you today?\n\n"
                "You can ask me about:\n"
                "• Your current curriculum and subjects\n"
                "• Chapter information for any subject\n"
                "• Any educational questions",
            isUser: false,
            animate: true,
          ),
        );
      });
    } catch (e) {
      print('Error loading user data: $e');
      _addInitialMessage();
    }
  }
  void _addInitialMessage() {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: "Hello! I'm your AI Tutor. You can ask me about:\n\n"
              "• Available standards and subjects\n"
              "• Chapter information for any subject\n"
              "• Any educational questions\n\n"
              "For example, try asking 'What standards are available?' or 'Show me chapters for 10th standard Mathematics'",
          isUser: false,
          animate: true,
        ),
      );
    });
  }

  void _handleMessageSent(String message) async {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: message,
          isUser: true,
          animate: true,
        ),
      );
      _isTyping = true;
    });

    try {
      final response = await _apiService.sendMessage(message);

      setState(() {
        _isTyping = false;
        _messages.insert(
          0,
          ChatMessage(
            text: response['response'],
            isUser: false,
            messageType: _getMessageType(response['type']),
            animate: true,
          ),
        );
      });
    } catch (e) {
      setState(() {
        _isTyping = false;
        _messages.insert(
          0,
          ChatMessage(
            text: 'Error: Failed to get response. Please try again.',
            isUser: false,
            animate: true,
          ),
        );
      });
    }
  }

  MessageType _getMessageType(String? type) {
    switch (type) {
      case 'curriculum':
        return MessageType.curriculum;
      case 'file':
        return MessageType.file;
      case 'image':
        return MessageType.image;
      default:
        return MessageType.text;
    }
  }

  void _handleFileUploaded(File file) async {
    try {
      final filePath = await _apiService.uploadFile(file);
      setState(() {
        _messages.insert(
          0,
          ChatMessage(
            text: 'File uploaded: ${file.path.split('/').last}',
            isUser: true,
            messageType: MessageType.file,
            filePath: filePath,
            animate: true,
          ),
        );
      });
    } catch (e) {
      print('Error uploading file: $e');
    }
  }

  void _handleImageCaptured(File image) {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: 'Image captured',
          isUser: true,
          messageType: MessageType.image,
          filePath: image.path,
          animate: true,
        ),
      );
    });
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Clear Chat',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to clear all messages?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _messages.clear();
                  _addInitialMessage();
                });
                Navigator.pop(context);
              },
              child: Text(
                'Clear',
                style: GoogleFonts.poppins(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              elevation: 0,
              backgroundColor: Colors.white.withOpacity(0.6),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [primaryColor, accentColor],
                      ),
                    ),
                    child: const Icon(
                      Icons.ac_unit_sharp,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'AI Tutor',
                    style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete, color: primaryColor),
                  onPressed: _clearChat,
                  tooltip: 'Clear Chat',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildTypingIndicator() {
    return FadeInUp(
      duration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, accentColor],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.ac_unit_sharp,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: List.generate(
                  3,
                      (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    child: ScaleAnimation(
                      duration: Duration(milliseconds: 600),
                      delay: Duration(milliseconds: index * 200),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isTyping && index == 0) {
                  return _buildTypingIndicator();
                }
                return _messages[_isTyping ? index - 1 : index];
              },
            ),
          ),
          MessageInput(
            onMessageSent: _handleMessageSent,
            onFileUploaded: _handleFileUploaded,
            onImageCaptured: _handleImageCaptured,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class MessageInput extends StatefulWidget {
  final Function(String) onMessageSent;
  final Function(File) onFileUploaded;
  final Function(File) onImageCaptured;

  const MessageInput({
    Key? key,
    required this.onMessageSent,
    required this.onFileUploaded,
    required this.onImageCaptured,
  }) : super(key: key);

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _isComposing = false;

  void _handleSubmitted(String text) {
    if (text.trim().isEmpty) return;
    widget.onMessageSent(text);
    _controller.clear();
    setState(() {
      _isComposing = false;
    });
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        widget.onFileUploaded(file);
      }
    } catch (e) {
      print('Error picking file: $e');
    }
  }

  Future<void> _captureImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);

      if (image != null) {
        widget.onImageCaptured(File(image.path));
      }
    } catch (e) {
      print('Error capturing image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: _pickFile,
                color: _ChatbotPageState.primaryColor,
              ),
              IconButton(
                icon: const Icon(Icons.camera_alt),
                onPressed: _captureImage,
                color: _ChatbotPageState.primaryColor,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: (text) {
                    setState(() {
                      _isComposing = text.isNotEmpty;
                    });
                  },
                  onSubmitted: _handleSubmitted,
                  decoration: InputDecoration(
                    hintText: 'Ask me anything...',
                    hintStyle: GoogleFonts.poppins(
                      color: Colors.grey[400],
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isComposing
                      ? () => _handleSubmitted(_controller.text)
                      : null,
                  color: _isComposing
                      ? _ChatbotPageState.primaryColor
                      : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class ScaleAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;

  const ScaleAnimation({
    Key? key,
    required this.child,
    required this.duration,
    required this.delay,
  }) : super(key: key);

  @override
  State<ScaleAnimation> createState() => _ScaleAnimationState();
}

class _ScaleAnimationState extends State<ScaleAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
