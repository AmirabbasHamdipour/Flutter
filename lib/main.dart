// ignore_for_file: unused_element, unused_field, depend_on_referenced_packages, unnecessary_null_comparison

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';
import 'package:http_parser/http_parser.dart';
import 'package:get_it/get_it.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

final getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');

  // Create providers
  final authProvider = AuthProvider();
  final chatProvider = ChatProvider();
  final messageProvider = MessageProvider();
  final connectivityService = ConnectivityService();

  // Register in GetIt
  getIt.registerSingleton<AuthProvider>(authProvider);
  getIt.registerSingleton<ChatProvider>(chatProvider);
  getIt.registerSingleton<MessageProvider>(messageProvider);
  getIt.registerSingleton<ConnectivityService>(connectivityService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: chatProvider),
        ChangeNotifierProvider.value(value: messageProvider),
        ChangeNotifierProvider.value(value: connectivityService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پیام‌رسان',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Vazir', // در صورت وجود فونت فارسی
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fa', 'IR')],
      locale: const Locale('fa', 'IR'),
      home: const SplashScreen(),
      routes: {
        '/login': (ctx) => const LoginPage(),
        '/register': (ctx) => const RegisterPage(),
        '/home': (ctx) => const HomePage(),
        '/chat': (ctx) => const ChatPage(),
        '/profile': (ctx) => const ProfilePage(),
        '/chat-info': (ctx) => const ChatInfoPage(),
        '/search': (ctx) => const SearchPage(),
      },
    );
  }
}

// -------------------- Constants --------------------
const baseUrl = 'https://tweeter.runflare.run';
const apiUrl = '$baseUrl';
const socketUrl = baseUrl;

// -------------------- Models --------------------
class User {
  final int id;
  final String username;
  final String? firstName;
  final String? lastName;
  final String? bio;
  final String? avatar;
  bool isOnline;
  DateTime? lastSeen;
  final String? phone;

  User({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
    this.bio,
    this.avatar,
    this.isOnline = false,
    this.lastSeen,
    this.phone,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      bio: json['bio'],
      avatar: json['avatar'],
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
      phone: json['phone'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'bio': bio,
        'avatar': avatar,
        'is_online': isOnline,
        'last_seen': lastSeen?.toIso8601String(),
        'phone': phone,
      };

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    if (firstName != null) return firstName!;
    return username;
  }
}

class Chat {
  final int id;
  final String type;
  String? title;
  String? description;
  String? avatar;
  final int createdBy;
  final DateTime createdAt;
  final List<User> participants;
  Message? lastMessage;
  bool isArchived;
  User? otherUser;

  Chat({
    required this.id,
    required this.type,
    this.title,
    this.description,
    this.avatar,
    required this.createdBy,
    required this.createdAt,
    required this.participants,
    this.lastMessage,
    this.isArchived = false,
    this.otherUser,
  });

  factory Chat.fromJson(Map<String, dynamic> json, {int? currentUserId}) {
    var participants = (json['participants'] as List)
        .map((p) => User.fromJson(p))
        .toList();
    User? otherUser;
    if (json['type'] == 'private' && participants.length == 2 && currentUserId != null) {
      otherUser = participants.firstWhere((p) => p.id != currentUserId);
    }
    return Chat(
      id: json['id'],
      type: json['type'],
      title: json['title'],
      description: json['description'],
      avatar: json['avatar'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      participants: participants,
      lastMessage: json['last_message'] != null ? Message.fromJson(json['last_message']) : null,
      isArchived: json['is_archived'] ?? false,
      otherUser: otherUser,
    );
  }

  String get displayTitle {
    if (type == 'private' && otherUser != null) {
      return otherUser!.displayName;
    }
    return title ?? 'ناشناس';
  }
}

class Message {
  final int id;
  final int chatId;
  final User sender;
  final int? replyToId;
  final String? text;
  final String? media;
  final String? mediaType;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isDeleted;
  final int? forwardFrom;
  final bool pinned;
  final List<Reaction> reactions;
  final List<int> readBy;

  Message({
    required this.id,
    required this.chatId,
    required this.sender,
    this.replyToId,
    this.text,
    this.media,
    this.mediaType,
    required this.createdAt,
    this.editedAt,
    this.isDeleted = false,
    this.forwardFrom,
    this.pinned = false,
    this.reactions = const [],
    this.readBy = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      chatId: json['chat_id'],
      sender: User.fromJson(json['sender']),
      replyToId: json['reply_to'],
      text: json['text'],
      media: json['media'],
      mediaType: json['media_type'],
      createdAt: DateTime.parse(json['created_at']),
      editedAt: json['edited_at'] != null ? DateTime.parse(json['edited_at']) : null,
      isDeleted: json['is_deleted'] ?? false,
      forwardFrom: json['forward_from'],
      pinned: json['pinned'] ?? false,
      reactions: (json['reactions'] as List?)?.map((r) => Reaction.fromJson(r)).toList() ?? [],
      readBy: (json['read_by'] as List?)?.cast<int>().toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_id': chatId,
        'sender': sender.toJson(),
        'reply_to': replyToId,
        'text': text,
        'media': media,
        'media_type': mediaType,
        'created_at': createdAt.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
        'is_deleted': isDeleted,
        'forward_from': forwardFrom,
        'pinned': pinned,
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'read_by': readBy,
      };
}

class Reaction {
  final int userId;
  final String emoji;
  final DateTime createdAt;

  Reaction({required this.userId, required this.emoji, required this.createdAt});

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      userId: json['user_id'],
      emoji: json['emoji'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'emoji': emoji,
        'created_at': createdAt.toIso8601String(),
      };
}

// -------------------- Connectivity Service --------------------
class ConnectivityService extends ChangeNotifier {
  bool _isConnected = true;
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<ConnectivityResult> _subscription;

  bool get isConnected => _isConnected;

  ConnectivityService() {
    _initConnectivity();
    _subscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
    } catch (e) {
      print('خطا در بررسی اتصال: $e');
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    _isConnected = result != ConnectivityResult.none;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// -------------------- API Service --------------------
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Dio? _dio;
  String? _token;
  static const int maxRetries = 3;

  void _ensureDio() {
    if (_dio == null) {
      _dio = Dio(BaseOptions(
        baseUrl: apiUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));
      (_dio!.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
          (client) {
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      };
      _dio!.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          return handler.next(options);
        },
        onError: (DioError e, handler) async {
          if (e.response?.statusCode == 401) {
            getIt<AuthProvider>().logout();
          }
          // تلاش مجدد برای خطاهای شبکه
          if (e.type == DioErrorType.connectionError || e.type == DioErrorType.receiveTimeout) {
            final connectivity = getIt<ConnectivityService>();
            if (!connectivity.isConnected) {
              // اگر اینترنت قطع است، خطا را نمایش بده
              return handler.next(e);
            }
            // تلاش مجدد تا maxRetries
            final retryCount = e.requestOptions.extra['retryCount'] ?? 0;
            if (retryCount < maxRetries) {
              e.requestOptions.extra['retryCount'] = retryCount + 1;
              await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
              try {
                final response = await _dio!.fetch(e.requestOptions);
                handler.resolve(response);
                return;
              } catch (e) {
                // ادامه
              }
            }
          }
          return handler.next(e);
        },
      ));
      _dio!.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
      ));
    }
  }

  void init({String? token}) {
    _token = token;
    _dio = Dio(BaseOptions(
      baseUrl: apiUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    (_dio!.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
        (client) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return client;
    };
    _dio!.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (DioError e, handler) async {
        if (e.response?.statusCode == 401) {
          getIt<AuthProvider>().logout();
        }
        if (e.type == DioErrorType.connectionError || e.type == DioErrorType.receiveTimeout) {
          final connectivity = getIt<ConnectivityService>();
          if (!connectivity.isConnected) {
            return handler.next(e);
          }
          final retryCount = e.requestOptions.extra['retryCount'] ?? 0;
          if (retryCount < maxRetries) {
            e.requestOptions.extra['retryCount'] = retryCount + 1;
            await Future.delayed(Duration(seconds: 2 * (retryCount + 1)));
            try {
              final response = await _dio!.fetch(e.requestOptions);
              handler.resolve(response);
              return;
            } catch (e) {
              // ادامه
            }
          }
        }
        return handler.next(e);
      },
    ));
    _dio!.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ));
  }

  Future<Response> post(String path, {dynamic data}) async {
    _ensureDio();
    try {
      return await _dio!.post(path, data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    _ensureDio();
    try {
      return await _dio!.get(path, queryParameters: queryParameters);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> put(String path, {dynamic data}) async {
    _ensureDio();
    try {
      return await _dio!.put(path, data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> delete(String path) async {
    _ensureDio();
    try {
      return await _dio!.delete(path);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> uploadFile(String path, String field, File file,
      {Map<String, dynamic>? data, String? method = 'POST', ProgressCallback? onSendProgress}) async {
    _ensureDio();
    String fileName = file.path.split('/').last;
    // فشرده‌سازی تصویر اگر فایل تصویری باشد
    File? compressedFile;
    if (file.path.toLowerCase().endsWith('.jpg') || file.path.toLowerCase().endsWith('.jpeg') || file.path.toLowerCase().endsWith('.png')) {
      compressedFile = await _compressImage(file);
    }
    final fileToUpload = compressedFile ?? file;
    FormData formData = FormData.fromMap({
      ...?data,
      field: await MultipartFile.fromFile(fileToUpload.path, filename: fileName),
    });
    return await _dio!.post(path, data: formData, onSendProgress: onSendProgress);
  }

  Future<File> _compressImage(File file) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imageBytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);
      if (image != null) {
        // کاهش کیفیت و اندازه
        img.Image resized = img.copyResize(image, width: 1024); // حداکثر عرض 1024
        final compressedBytes = img.encodeJpg(resized, quality: 75);
        final compressedFile = File(targetPath)..writeAsBytesSync(compressedBytes);
        return compressedFile;
      }
    } catch (e) {
      print('خطا در فشرده‌سازی: $e');
    }
    return file;
  }
}

// -------------------- Socket Service --------------------
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _currentToken;
  Timer? _reconnectTimer;

  void connect(String token) {
    _currentToken = token;
    if (_isConnected) return;
    _socket = IO.io(socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'query': {'token': token},
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 2000,
    });
    _socket?.onConnect((_) {
      print('Socket connected');
      _isConnected = true;
      _reconnectTimer?.cancel();
    });
    _socket?.onDisconnect((_) {
      print('Socket disconnected');
      _isConnected = false;
      _attemptReconnect();
    });
    _socket?.onError((err) {
      print('Socket error: $err');
      _isConnected = false;
    });
    _socket?.onReconnect((_) {
      print('Socket reconnected');
      _isConnected = true;
    });
  }

  void _attemptReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected && _currentToken != null) {
        connect(_currentToken!);
      }
    });
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket?.close();
    _isConnected = false;
  }

  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  void off(String event) {
    _socket?.off(event);
  }

  void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  bool get isConnected => _isConnected;
}

// -------------------- Providers --------------------
class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  String? _token;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _token != null && _currentUser != null;

  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.post('/login', data: {
        'username': username,
        'password': password,
      });
      final data = response.data;
      _token = data['token'];
      _currentUser = User.fromJson(data['user']);
      await _saveToken(_token!);
      _api.init(token: _token);
      _socket.connect(_token!);
      _setupSocketListeners();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> register(Map<String, dynamic> userData) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _api.post('/register', data: userData);
      bool loginSuccess = await login(userData['username'], userData['password']);
      if (loginSuccess) {
        return {'success': true};
      } else {
        return {'success': false, 'error': 'ورود پس از ثبت‌نام ناموفق بود'};
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      if (e is DioError) {
        if (e.response != null) {
          String serverError = e.response?.data['error'] ?? 'خطای ناشناخته سرور';
          return {
            'success': false,
            'error': serverError,
            'statusCode': e.response?.statusCode
          };
        } else {
          return {'success': false, 'error': 'خطای شبکه: ${e.message}'};
        }
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;
    _socket.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _api.init();
    notifyListeners();
  }

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    if (_token != null) {
      _api.init(token: _token);
      _socket.connect(_token!);
      _setupSocketListeners();
      await _fetchCurrentUser();
    }
    notifyListeners();
  }

  Future<void> _fetchCurrentUser() async {}

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  void _setupSocketListeners() {
    _socket.on('new_message', (data) {
      getIt<MessageProvider>().addMessage(data);
    });
    _socket.on('message_updated', (data) {
      getIt<MessageProvider>().updateMessage(data);
    });
    _socket.on('message_deleted', (data) {
      getIt<MessageProvider>().deleteMessage(data['chat_id'], data['message_id']);
    });
    _socket.on('reaction_updated', (data) {
      getIt<MessageProvider>().updateReactions(data['chat_id'], data['message_id'], data['reactions']);
    });
    _socket.on('read_receipt', (data) {
      getIt<MessageProvider>().markRead(data['chat_id'], data['message_id'], data['user_id']);
    });
    _socket.on('typing', (data) {
      getIt<ChatProvider>().setTyping(data['chat_id'], data['user_id'], data['is_typing']);
    });
    _socket.on('user_status', (data) {
      getIt<ChatProvider>().updateUserStatus(data['user_id'], data['is_online']);
    });
    _socket.on('new_chat', (data) {
      getIt<ChatProvider>().addChat(data);
    });
    _socket.on('chat_updated', (data) {
      getIt<ChatProvider>().updateChat(data);
    });
    _socket.on('participant_added', (data) {
      getIt<ChatProvider>().updateChat(data['chat']);
    });
    _socket.on('participant_removed', (data) {
      getIt<ChatProvider>().updateChat(data['chat']);
    });
    _socket.on('removed_from_chat', (data) {
      getIt<ChatProvider>().removeChat(data['chat_id']);
    });
    _socket.on('chat_archived', (data) {
      getIt<ChatProvider>().archiveChat(data['chat_id']);
    });
    _socket.on('message_pinned', (data) {
      getIt<MessageProvider>().updateMessage(data['message']);
    });
    _socket.on('message_unpinned', (data) {
      getIt<MessageProvider>().unpinMessage(data['chat_id'], data['message_id']);
    });
  }
}

class ChatProvider extends ChangeNotifier {
  List<Chat> _chats = [];
  Map<String, bool> _typingUsers = {};
  final ApiService _api = ApiService();

  List<Chat> get chats => _chats;

  Future<void> loadChats() async {
    try {
      final response = await _api.get('/chats');
      final List data = response.data;
      _chats = data.map((c) => Chat.fromJson(c, currentUserId: getIt<AuthProvider>().currentUser?.id)).toList();
      notifyListeners();
    } catch (e) {
      print('load chats error: $e');
    }
  }

  void addChat(dynamic chatJson) {
    final chat = Chat.fromJson(chatJson, currentUserId: getIt<AuthProvider>().currentUser?.id);
    _chats.insert(0, chat);
    notifyListeners();
  }

  void updateChat(dynamic chatJson) {
    final updated = Chat.fromJson(chatJson, currentUserId: getIt<AuthProvider>().currentUser?.id);
    final index = _chats.indexWhere((c) => c.id == updated.id);
    if (index != -1) {
      _chats[index] = updated;
      notifyListeners();
    }
  }

  void removeChat(int chatId) {
    _chats.removeWhere((c) => c.id == chatId);
    notifyListeners();
  }

  void archiveChat(int chatId) {
    final chat = _chats.firstWhere((c) => c.id == chatId);
    chat.isArchived = true;
    notifyListeners();
  }

  void updateUserStatus(int userId, bool isOnline) {
    for (var chat in _chats) {
      for (var user in chat.participants) {
        if (user.id == userId) {
          user.isOnline = isOnline;
        }
      }
      if (chat.otherUser?.id == userId) {
        chat.otherUser?.isOnline = isOnline;
      }
    }
    notifyListeners();
  }

  void setTyping(int chatId, int userId, bool isTyping) {
    final key = '$chatId-$userId';
    if (isTyping) {
      _typingUsers[key] = true;
    } else {
      _typingUsers.remove(key);
    }
    notifyListeners();
  }

  bool isTyping(int chatId, int userId) {
    return _typingUsers['$chatId-$userId'] == true;
  }

  void sendTyping(int chatId, bool isTyping) {
    SocketService().emit('typing', {
      'chat_id': chatId,
      'is_typing': isTyping,
    });
  }

  Future<Chat?> createPrivateChat(int userId) async {
    try {
      final response = await _api.post('/chats', data: {
        'type': 'private',
        'participant_ids': [userId],
      });
      final chat = Chat.fromJson(response.data, currentUserId: getIt<AuthProvider>().currentUser?.id);
      if (!_chats.any((c) => c.id == chat.id)) {
        _chats.insert(0, chat);
        notifyListeners();
      }
      return chat;
    } catch (e) {
      return null;
    }
  }

  Future<Chat?> createGroup(String title, List<int> participantIds) async {
    try {
      final response = await _api.post('/chats', data: {
        'type': 'group',
        'title': title,
        'participant_ids': participantIds,
      });
      final chat = Chat.fromJson(response.data, currentUserId: getIt<AuthProvider>().currentUser?.id);
      _chats.insert(0, chat);
      notifyListeners();
      return chat;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateChatInfo(int chatId, {String? title, String? description}) async {
    try {
      final data = <String, dynamic>{};
      if (title != null) data['title'] = title;
      if (description != null) data['description'] = description;
      await _api.put('/chats/$chatId', data: data);
    } catch (e) {}
  }

  Future<void> addParticipant(int chatId, int userId) async {
    try {
      await _api.post('/chats/$chatId/participants', data: {'user_id': userId});
    } catch (e) {}
  }

  Future<void> removeParticipant(int chatId, int userId) async {
    try {
      await _api.delete('/chats/$chatId/participants/$userId');
    } catch (e) {}
  }

  Future<void> archiveChatManually(int chatId) async {
    try {
      await _api.post('/chats/$chatId/archive');
    } catch (e) {}
  }
}

class MessageProvider extends ChangeNotifier {
  final Map<int, List<Message>> _messages = {};
  final Map<int, bool> _loading = {};
  final ApiService _api = ApiService();

  List<Message>? getMessages(int chatId) => _messages[chatId];

  bool isLoading(int chatId) => _loading[chatId] ?? false;

  Future<void> loadMessages(int chatId, {int limit = 50, int offset = 0}) async {
    if (offset == 0) {
      _messages[chatId] = [];
    }
    _loading[chatId] = true;
    notifyListeners();
    try {
      final response = await _api.get('/chats/$chatId/messages',
          queryParameters: {'limit': limit, 'offset': offset});
      final List data = response.data;
      final newMessages = data.map((m) => Message.fromJson(m)).toList();
      if (offset == 0) {
        _messages[chatId] = newMessages;
      } else {
        _messages[chatId]?.addAll(newMessages);
      }
      _messages[chatId]?.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _loading[chatId] = false;
      notifyListeners();
    } catch (e) {
      _loading[chatId] = false;
      notifyListeners();
    }
  }

  void addMessage(dynamic messageJson) {
    final msg = Message.fromJson(messageJson);
    if (_messages.containsKey(msg.chatId)) {
      _messages[msg.chatId]!.insert(0, msg);
      _messages[msg.chatId]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  void updateMessage(dynamic messageJson) {
    final msg = Message.fromJson(messageJson);
    if (_messages.containsKey(msg.chatId)) {
      final index = _messages[msg.chatId]!.indexWhere((m) => m.id == msg.id);
      if (index != -1) {
        _messages[msg.chatId]![index] = msg;
        notifyListeners();
      }
    }
  }

  void deleteMessage(int chatId, int messageId) {
    if (_messages.containsKey(chatId)) {
      _messages[chatId]!.removeWhere((m) => m.id == messageId);
      notifyListeners();
    }
  }

  void updateReactions(int chatId, int messageId, List<dynamic> reactionsJson) {
    if (_messages.containsKey(chatId)) {
      final msgIndex = _messages[chatId]!.indexWhere((m) => m.id == messageId);
      if (msgIndex != -1) {
        final reactions = reactionsJson.map((r) => Reaction.fromJson(r)).toList();
        final oldMsg = _messages[chatId]![msgIndex];
        final newMsg = Message(
          id: oldMsg.id,
          chatId: oldMsg.chatId,
          sender: oldMsg.sender,
          replyToId: oldMsg.replyToId,
          text: oldMsg.text,
          media: oldMsg.media,
          mediaType: oldMsg.mediaType,
          createdAt: oldMsg.createdAt,
          editedAt: oldMsg.editedAt,
          isDeleted: oldMsg.isDeleted,
          forwardFrom: oldMsg.forwardFrom,
          pinned: oldMsg.pinned,
          reactions: reactions,
          readBy: oldMsg.readBy,
        );
        _messages[chatId]![msgIndex] = newMsg;
        notifyListeners();
      }
    }
  }

  void markRead(int chatId, int messageId, int userId) {
    if (_messages.containsKey(chatId)) {
      final msgIndex = _messages[chatId]!.indexWhere((m) => m.id == messageId);
      if (msgIndex != -1) {
        final msg = _messages[chatId]![msgIndex];
        if (!msg.readBy.contains(userId)) {
          final newReadBy = List<int>.from(msg.readBy)..add(userId);
          final newMsg = Message(
            id: msg.id,
            chatId: msg.chatId,
            sender: msg.sender,
            replyToId: msg.replyToId,
            text: msg.text,
            media: msg.media,
            mediaType: msg.mediaType,
            createdAt: msg.createdAt,
            editedAt: msg.editedAt,
            isDeleted: msg.isDeleted,
            forwardFrom: msg.forwardFrom,
            pinned: msg.pinned,
            reactions: msg.reactions,
            readBy: newReadBy,
          );
          _messages[chatId]![msgIndex] = newMsg;
          notifyListeners();
        }
      }
    }
  }

  void unpinMessage(int chatId, int messageId) {
    if (_messages.containsKey(chatId)) {
      for (var msg in _messages[chatId]!) {
        if (msg.pinned && msg.id == messageId) {
          final newMsg = Message(
            id: msg.id,
            chatId: msg.chatId,
            sender: msg.sender,
            replyToId: msg.replyToId,
            text: msg.text,
            media: msg.media,
            mediaType: msg.mediaType,
            createdAt: msg.createdAt,
            editedAt: msg.editedAt,
            isDeleted: msg.isDeleted,
            forwardFrom: msg.forwardFrom,
            pinned: false,
            reactions: msg.reactions,
            readBy: msg.readBy,
          );
          final index = _messages[chatId]!.indexOf(msg);
          _messages[chatId]![index] = newMsg;
          notifyListeners();
          break;
        }
      }
    }
  }

  Future<Message?> sendMessage(int chatId, String text, {int? replyTo, File? mediaFile, ProgressCallback? onSendProgress}) async {
    try {
      final uri = '/chats/$chatId/messages';
      if (mediaFile != null) {
        final response = await _api.uploadFile(uri, 'media', mediaFile,
            data: {'text': text, 'reply_to': replyTo}, onSendProgress: onSendProgress);
        final msg = Message.fromJson(response.data);
        addMessage(response.data);
        return msg;
      } else {
        final response = await _api.post(uri, data: {
          'text': text,
          'reply_to': replyTo,
        });
        final msg = Message.fromJson(response.data);
        addMessage(response.data);
        return msg;
      }
    } catch (e) {
      return null;
    }
  }

  Future<void> editMessage(int messageId, String newText) async {
    try {
      await _api.put('/messages/$messageId', data: {'text': newText});
    } catch (e) {}
  }

  Future<void> deleteMessageApi(int messageId) async {
    try {
      await _api.delete('/messages/$messageId');
    } catch (e) {}
  }

  Future<void> addReaction(int messageId, String emoji) async {
    try {
      await _api.post('/messages/$messageId/reactions', data: {'emoji': emoji});
    } catch (e) {}
  }

  Future<void> removeReaction(int messageId) async {
    try {
      await _api.delete('/messages/$messageId/reactions');
    } catch (e) {}
  }

  Future<void> markReadApi(int messageId) async {
    try {
      await _api.post('/messages/$messageId/read');
    } catch (e) {}
  }

  Future<void> forwardMessage(int messageId, List<int> chatIds) async {
    try {
      await _api.post('/messages/$messageId/forward', data: {'chat_ids': chatIds});
    } catch (e) {}
  }

  Future<void> pinMessage(int chatId, int messageId) async {
    try {
      await _api.post('/chats/$chatId/pin/$messageId');
    } catch (e) {}
  }

  Future<void> unpinMessageApi(int chatId) async {
    try {
      await _api.post('/chats/$chatId/unpin');
    } catch (e) {}
  }
}

// -------------------- Splash Screen --------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await getIt<AuthProvider>().loadToken();
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      final auth = getIt<AuthProvider>();
      if (auth.isLoggedIn) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: const Center(
          child: Icon(Icons.chat, size: 80, color: Colors.blue),
        ),
      ),
    );
  }
}

// -------------------- Login Page --------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      final auth = getIt<AuthProvider>();
      bool success = await auth.login(_usernameController.text, _passwordController.text);
      if (success && mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ورود ناموفق بود')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthProvider>();
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 80, color: Colors.blue),
                  const SizedBox(height: 20),
                  const Text('به پیام‌رسان خوش آمدید', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'نام کاربری',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (v) => v!.isEmpty ? 'اجباری' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'رمز عبور',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (v) => v!.isEmpty ? 'اجباری' : null,
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: Colors.blue,
                            ),
                            child: auth.isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('ورود', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('حساب کاربری ندارید؟'),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/register'),
                        child: const Text('ثبت‌نام', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- Register Page --------------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _register() async {
    if (_formKey.currentState!.validate()) {
      final auth = getIt<AuthProvider>();
      Map<String, dynamic> data = {
        'username': _usernameController.text,
        'password': _passwordController.text,
        'first_name': _firstNameController.text,
        'last_name': _lastNameController.text,
        'phone': _phoneController.text,
        'bio': _bioController.text,
      };
      final result = await auth.register(data);
      if (result != null && result['success'] == true) {
        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      } else {
        String errorMsg = result?['error'] ?? 'ثبت‌نام ناموفق بود';
        final statusCode = result?['statusCode'];
        if (statusCode != null) {
          errorMsg += ' (کد خطا: $statusCode)';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'باشه',
                onPressed: () {},
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت‌نام')),
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(Icons.person_add, size: 60, color: Colors.green),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _usernameController,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'نام کاربری *',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (v) => v!.isEmpty ? 'اجباری' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'رمز عبور *',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (v) => v!.isEmpty ? 'اجباری' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscurePassword,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'تکرار رمز عبور *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (v) {
                      if (v!.isEmpty) return 'اجباری';
                      if (v != _passwordController.text) return 'رمز عبور مطابقت ندارد';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      labelText: 'نام',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      labelText: 'نام خانوادگی',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'شماره تلفن',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bioController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'درباره من',
                      prefixIcon: const Icon(Icons.info),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: Colors.green,
                      ),
                      child: auth.isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('ثبت‌نام', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('قبلاً ثبت‌نام کرده‌اید؟'),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text('ورود', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- Home Page --------------------
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final chatProvider = getIt<ChatProvider>();
    await chatProvider.loadChats();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthProvider>();
    final chatProvider = getIt<ChatProvider>();
    final connectivity = getIt<ConnectivityService>();

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('پیام‌رسان'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          if (!connectivity.isConnected)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.signal_wifi_off, color: Colors.red),
            ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.pushNamed(context, '/search'),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(auth.currentUser?.displayName ?? ''),
              accountEmail: Text(auth.currentUser?.username ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundImage: auth.currentUser?.avatar != null
                    ? CachedNetworkImageProvider(auth.currentUser!.avatar!)
                    : null,
                child: auth.currentUser?.avatar == null ? const Icon(Icons.person) : null,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('پروفایل'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/profile');
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive),
              title: const Text('آرشیو'),
              onTap: () {
                Navigator.pop(context);
                // TODO: show archived chats
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('تنظیمات'),
              onTap: () {
                Navigator.pop(context);
                // TODO: settings page
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('خروج'),
              onTap: () async {
                Navigator.pop(context);
                await auth.logout();
                if (mounted) Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          ChatsTab(),
          GroupsTab(),
          ProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'گفتگوها'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'گروه‌ها'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'پروفایل'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex == 0 || _selectedIndex == 1
          ? FloatingActionButton(
              onPressed: _selectedIndex == 0 ? _showNewChatDialog : _showNewGroupDialog,
              child: const Icon(Icons.edit),
            )
          : null,
    );
  }

  void _showNewChatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('گفتگوی جدید'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<User>>(
            future: _fetchUsers(),
            builder: (ctx, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = snapshot.data!.where((u) => u.id != getIt<AuthProvider>().currentUser?.id).toList();
              return ListView.builder(
                shrinkWrap: true,
                itemCount: users.length,
                itemBuilder: (ctx, i) {
                  final user = users[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user.avatar != null ? CachedNetworkImageProvider(user.avatar!) : null,
                      child: user.avatar == null ? Text(user.username[0].toUpperCase()) : null,
                    ),
                    title: Text(user.displayName),
                    subtitle: Text(user.username),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final chatProvider = getIt<ChatProvider>();
                      final chat = await chatProvider.createPrivateChat(user.id);
                      if (chat != null && mounted) {
                        Navigator.pushNamed(context, '/chat', arguments: chat);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<List<User>> _fetchUsers() async {
    try {
      final response = await ApiService().get('/users');
      final List data = response.data;
      return data.map((u) => User.fromJson(u)).toList();
    } catch (e) {
      return [];
    }
  }

  void _showNewGroupDialog() {
    final TextEditingController titleController = TextEditingController();
    List<User> selectedUsers = [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('گروه جدید'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'نام گروه'),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<User>>(
                  future: _fetchUsers(),
                  builder: (ctx, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final users = snapshot.data!.where((u) => u.id != getIt<AuthProvider>().currentUser?.id).toList();
                    return StatefulBuilder(
                      builder: (ctx, setState) => ListView.builder(
                        shrinkWrap: true,
                        itemCount: users.length,
                        itemBuilder: (ctx, i) {
                          final user = users[i];
                          final isSelected = selectedUsers.contains(user);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  selectedUsers.add(user);
                                } else {
                                  selectedUsers.remove(user);
                                }
                              });
                            },
                            title: Text(user.displayName),
                            secondary: CircleAvatar(
                              backgroundImage: user.avatar != null ? CachedNetworkImageProvider(user.avatar!) : null,
                              child: user.avatar == null ? Text(user.username[0].toUpperCase()) : null,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('لغو'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty && selectedUsers.isNotEmpty) {
                Navigator.pop(ctx);
                final chatProvider = getIt<ChatProvider>();
                final chat = await chatProvider.createGroup(
                  titleController.text,
                  selectedUsers.map((u) => u.id).toList(),
                );
                if (chat != null && mounted) {
                  Navigator.pushNamed(context, '/chat', arguments: chat);
                }
              }
            },
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );
  }
}

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = getIt<ChatProvider>();
    return RefreshIndicator(
      onRefresh: () => chatProvider.loadChats(),
      child: ListView.builder(
        itemCount: chatProvider.chats.length,
        itemBuilder: (ctx, i) {
          final chat = chatProvider.chats[i];
          if (chat.type == 'group' || chat.type == 'channel') return const SizedBox.shrink();
          return ChatTile(chat: chat);
        },
      ),
    );
  }
}

class GroupsTab extends StatelessWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = getIt<ChatProvider>();
    return RefreshIndicator(
      onRefresh: () => chatProvider.loadChats(),
      child: ListView.builder(
        itemCount: chatProvider.chats.length,
        itemBuilder: (ctx, i) {
          final chat = chatProvider.chats[i];
          if (chat.type != 'group' && chat.type != 'channel') return const SizedBox.shrink();
          return ChatTile(chat: chat);
        },
      ),
    );
  }
}

class ChatTile extends StatelessWidget {
  final Chat chat;
  const ChatTile({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthProvider>();
    return InkWell(
      onTap: () {
        Navigator.pushNamed(context, '/chat', arguments: chat);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: chat.avatar != null
                      ? CachedNetworkImageProvider(chat.avatar!)
                      : (chat.type == 'private' && chat.otherUser?.avatar != null
                          ? CachedNetworkImageProvider(chat.otherUser!.avatar!)
                          : null),
                  child: (chat.avatar == null && (chat.type != 'private' || chat.otherUser?.avatar == null))
                      ? Icon(chat.type == 'private' ? Icons.person : Icons.group, size: 28)
                      : null,
                ),
                if (chat.type == 'private' && chat.otherUser != null && chat.otherUser!.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.displayTitle,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  if (chat.lastMessage != null)
                    Text(
                      chat.lastMessage!.text ?? (chat.lastMessage!.mediaType != null ? '📷 رسانه' : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (chat.lastMessage != null)
                  Text(
                    DateFormat('HH:mm').format(chat.lastMessage!.createdAt),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                const SizedBox(height: 4),
                if (chat.lastMessage != null && !(chat.lastMessage!.readBy.contains(auth.currentUser?.id)))
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: user.avatar != null ? CachedNetworkImageProvider(user.avatar!) : null,
                child: user.avatar == null ? const Icon(Icons.person, size: 50) : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  backgroundColor: Colors.blue,
                  radius: 16,
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                    onPressed: () {
                      // Change avatar
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(user.displayName),
            subtitle: Text('@${user.username}'),
          ),
        ),
        if (user.phone != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone),
              title: Text(user.phone!),
            ),
          ),
        if (user.bio != null && user.bio!.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.info),
              title: Text(user.bio!),
            ),
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            Navigator.pushNamed(context, '/profile');
          },
          style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('ویرایش پروفایل'),
        ),
      ],
    );
  }
}

// -------------------- Chat Page --------------------
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late Chat chat;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;
  File? _selectedMedia;
  String? _mediaPreviewPath;
  int? _replyToId;
  Timer? _typingTimer;
  bool _isTyping = false;
  double _sendProgress = 0.0;
  bool _showProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    chat = ModalRoute.of(context)!.settings.arguments as Chat;
    getIt<MessageProvider>().loadMessages(chat.id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // reconnect handled by socket service
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _selectedMedia == null) return;
    setState(() {
      _isSending = true;
      _showProgress = _selectedMedia != null;
      _sendProgress = 0.0;
    });
    final msgProvider = getIt<MessageProvider>();
    await msgProvider.sendMessage(
      chat.id,
      _messageController.text,
      replyTo: _replyToId,
      mediaFile: _selectedMedia,
      onSendProgress: (count, total) {
        setState(() {
          _sendProgress = count / total;
        });
      },
    );
    _messageController.clear();
    setState(() {
      _selectedMedia = null;
      _mediaPreviewPath = null;
      _replyToId = null;
      _isSending = false;
      _showProgress = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleTyping(String text) {
    if (!_isTyping && text.isNotEmpty) {
      _isTyping = true;
      getIt<ChatProvider>().sendTyping(chat.id, true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        getIt<ChatProvider>().sendTyping(chat.id, false);
      }
    });
  }

  Future<void> _pickMedia() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('دوربین'),
              onTap: () => Navigator.pop(ctx, {'source': 'camera'}),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('گالری'),
              onTap: () => Navigator.pop(ctx, {'source': 'gallery'}),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('ویدیو'),
              onTap: () => Navigator.pop(ctx, {'source': 'video'}),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('فایل'),
              onTap: () => Navigator.pop(ctx, {'source': 'file'}),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final picker = ImagePicker();
    File? file;
    if (result['source'] == 'camera') {
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked != null) file = File(picked.path);
    } else if (result['source'] == 'gallery') {
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) file = File(picked.path);
    } else if (result['source'] == 'video') {
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked != null) file = File(picked.path);
    } else if (result['source'] == 'file') {
      final picked = await FilePicker.platform.pickFiles();
      if (picked != null) file = File(picked.files.single.path!);
    }
    if (file != null) {
      setState(() {
        _selectedMedia = file;
        _mediaPreviewPath = file.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthProvider>();
    final msgProvider = getIt<MessageProvider>();
    final messages = msgProvider.getMessages(chat.id) ?? [];
    final chatProvider = getIt<ChatProvider>();
    final typingUsers = chat.participants
        .where((u) => u.id != auth.currentUser?.id && chatProvider.isTyping(chat.id, u.id))
        .map((u) => u.displayName)
        .toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: InkWell(
          onTap: () {
            Navigator.pushNamed(context, '/chat-info', arguments: chat);
          },
          child: Row(
            children: [
              Hero(
                tag: 'chat_avatar_${chat.id}',
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: chat.avatar != null
                      ? CachedNetworkImageProvider(chat.avatar!)
                      : (chat.type == 'private' && chat.otherUser?.avatar != null
                          ? CachedNetworkImageProvider(chat.otherUser!.avatar!)
                          : null),
                  child: (chat.avatar == null && (chat.type != 'private' || chat.otherUser?.avatar == null))
                      ? Icon(chat.type == 'private' ? Icons.person : Icons.group, size: 18)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.displayTitle,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    if (typingUsers.isNotEmpty)
                      Text(
                        '${typingUsers.join(', ')} در حال تایپ...',
                        style: const TextStyle(fontSize: 10, color: Colors.green),
                      )
                    else if (chat.type == 'private' && chat.otherUser != null)
                      Text(
                        chat.otherUser!.isOnline ? 'آنلاین' : 'آخرین بازدید ${_formatLastSeen(chat.otherUser!.lastSeen)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              Navigator.pushNamed(context, '/chat-info', arguments: chat);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgProvider.isLoading(chat.id) && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      return ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = messages[i];
                          final isMe = msg.sender.id == auth.currentUser?.id;
                          return MessageBubble(
                            message: msg,
                            isMe: isMe,
                            chat: chat,
                            onReply: () {
                              setState(() {
                                _replyToId = msg.id;
                              });
                            },
                            onReact: (emoji) {
                              if (msg.reactions.any((r) => r.userId == auth.currentUser?.id)) {
                                msgProvider.removeReaction(msg.id);
                              } else {
                                msgProvider.addReaction(msg.id, emoji);
                              }
                            },
                            onDelete: () {
                              msgProvider.deleteMessageApi(msg.id);
                            },
                            onEdit: (newText) {
                              msgProvider.editMessage(msg.id, newText);
                            },
                            onForward: () {
                              _showForwardDialog(msg);
                            },
                            onPin: () {
                              if (msg.pinned) {
                                msgProvider.unpinMessageApi(chat.id);
                              } else {
                                msgProvider.pinMessage(chat.id, msg.id);
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
          if (_replyToId != null)
            Container(
              color: Colors.grey[100],
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'در حال پاسخ...',
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _replyToId = null),
                  ),
                ],
              ),
            ),
          if (_selectedMedia != null)
            Container(
              height: 70,
              color: Colors.grey[50],
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Stack(
                    children: [
                      if (_mediaPreviewPath != null)
                        Image.file(File(_mediaPreviewPath!), height: 50, width: 50, fit: BoxFit.cover),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.cancel, size: 16),
                          onPressed: () => setState(() {
                            _selectedMedia = null;
                            _mediaPreviewPath = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_selectedMedia!.path.split('/').last, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          if (_showProgress)
            LinearProgressIndicator(value: _sendProgress, backgroundColor: Colors.grey[200]),
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickMedia,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    onChanged: _handleTyping,
                    decoration: const InputDecoration(
                      hintText: 'پیام...',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                    textDirection: TextDirection.rtl,
                  ),
                ),
                if (_isSending)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendMessage,
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Visibility(
        visible: _scrollController.hasClients && _scrollController.position.pixels > 100,
        child: FloatingActionButton.small(
          onPressed: _scrollToBottom,
          child: const Icon(Icons.arrow_downward),
        ),
      ),
    );
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'به تازگی';
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.inMinutes < 1) return 'هم اکنون';
    if (diff.inHours < 1) return '${diff.inMinutes} دقیقه پیش';
    if (diff.inDays < 1) return '${diff.inHours} ساعت پیش';
    return DateFormat('MMM d').format(lastSeen);
  }

  void _showForwardDialog(Message msg) {
    showDialog(
      context: context,
      builder: (ctx) {
        final chatProvider = getIt<ChatProvider>();
        return AlertDialog(
          title: const Text('ارسال به'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: chatProvider.chats.length,
              itemBuilder: (ctx, i) {
                final chat = chatProvider.chats[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: chat.avatar != null ? CachedNetworkImageProvider(chat.avatar!) : null,
                    child: chat.avatar == null ? const Icon(Icons.chat) : null,
                  ),
                  title: Text(chat.displayTitle),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await getIt<MessageProvider>().forwardMessage(msg.id, [chat.id]);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final Chat chat;
  final VoidCallback onReply;
  final Function(String) onReact;
  final VoidCallback onDelete;
  final Function(String) onEdit;
  final VoidCallback onForward;
  final VoidCallback onPin;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.chat,
    required this.onReply,
    required this.onReact,
    required this.onDelete,
    required this.onEdit,
    required this.onForward,
    required this.onPin,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showReactions = false;

  @override
  Widget build(BuildContext context) {
    final reactions = widget.message.reactions;
    return GestureDetector(
      onLongPress: () => setState(() => _showReactions = !_showReactions),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!widget.isMe)
              CircleAvatar(
                radius: 14,
                backgroundImage: widget.message.sender.avatar != null
                    ? CachedNetworkImageProvider(widget.message.sender.avatar!)
                    : null,
                child: widget.message.sender.avatar == null ? Text(widget.message.sender.username[0]) : null,
              ),
            const SizedBox(width: 4),
            Flexible(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: widget.isMe ? Colors.blue[50] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomLeft: widget.isMe ? const Radius.circular(16) : Radius.zero,
                        bottomRight: widget.isMe ? Radius.zero : const Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.isMe)
                          Text(
                            widget.message.sender.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                          ),
                        if (widget.message.replyToId != null)
                          const Text('پاسخ...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        if (widget.message.media != null)
                          GestureDetector(
                            onTap: () {
                              // Show full media
                            },
                            child: Container(
                              width: 150,
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                image: DecorationImage(
                                  image: CachedNetworkImageProvider(widget.message.media!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        if (widget.message.text != null && widget.message.text!.isNotEmpty)
                          Text(
                            widget.message.text!,
                            style: const TextStyle(fontSize: 14),
                          ),
                        if (widget.message.editedAt != null)
                          const Text(
                            'ویرایش شده',
                            style: TextStyle(fontSize: 9, color: Colors.grey),
                          ),
                        if (reactions.isNotEmpty)
                          Wrap(
                            spacing: 2,
                            children: reactions.map((r) => Text(r.emoji, style: const TextStyle(fontSize: 12))).toList(),
                          ),
                      ],
                    ),
                  ),
                  if (_showReactions)
                    Positioned(
                      top: -30,
                      left: widget.isMe ? null : 0,
                      right: widget.isMe ? 0 : null,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ReactionButton(emoji: '👍', onTap: () { widget.onReact('👍'); setState(() => _showReactions = false); }),
                            _ReactionButton(emoji: '❤️', onTap: () { widget.onReact('❤️'); setState(() => _showReactions = false); }),
                            _ReactionButton(emoji: '😂', onTap: () { widget.onReact('😂'); setState(() => _showReactions = false); }),
                            _ReactionButton(emoji: '😮', onTap: () { widget.onReact('😮'); setState(() => _showReactions = false); }),
                            PopupMenuButton(
                              icon: const Icon(Icons.more_horiz, size: 16),
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'reply', child: Text('پاسخ')),
                                if (widget.isMe) const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                if (widget.isMe) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                const PopupMenuItem(value: 'forward', child: Text('ارسال')),
                                PopupMenuItem(value: 'pin', child: Text(widget.message.pinned ? 'لغو پین' : 'پین')),
                              ],
                              onSelected: (value) {
                                setState(() => _showReactions = false);
                                if (value == 'reply') widget.onReply();
                                if (value == 'edit') _showEditDialog();
                                if (value == 'delete') widget.onDelete();
                                if (value == 'forward') widget.onForward();
                                if (value == 'pin') widget.onPin();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            if (widget.isMe)
              CircleAvatar(
                radius: 14,
                backgroundImage: widget.message.sender.avatar != null
                    ? CachedNetworkImageProvider(widget.message.sender.avatar!)
                    : null,
                child: widget.message.sender.avatar == null ? Text(widget.message.sender.username[0]) : null,
              ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog() {
    final controller = TextEditingController(text: widget.message.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش پیام'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          ElevatedButton(
            onPressed: () {
              widget.onEdit(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;
  const _ReactionButton({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Text(emoji, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

// -------------------- Chat Info Page --------------------
class ChatInfoPage extends StatefulWidget {
  const ChatInfoPage({super.key});

  @override
  State<ChatInfoPage> createState() => _ChatInfoPageState();
}

class _ChatInfoPageState extends State<ChatInfoPage> {
  late Chat chat;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    chat = ModalRoute.of(context)!.settings.arguments as Chat;
    _titleController.text = chat.title ?? '';
    _descController.text = chat.description ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthProvider>();
    final isAdmin = chat.createdBy == auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('اطلاعات گفتگو'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                Hero(
                  tag: 'chat_avatar_${chat.id}',
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: chat.avatar != null
                        ? CachedNetworkImageProvider(chat.avatar!)
                        : (chat.type == 'private' && chat.otherUser?.avatar != null
                            ? CachedNetworkImageProvider(chat.otherUser!.avatar!)
                            : null),
                    child: (chat.avatar == null && (chat.type != 'private' || chat.otherUser?.avatar == null))
                        ? Icon(chat.type == 'private' ? Icons.person : Icons.group, size: 50)
                        : null,
                  ),
                ),
                if (isAdmin && chat.type != 'private')
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.blue,
                      radius: 16,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                        onPressed: () {
                          // Change chat avatar
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (chat.type != 'private')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'نام گروه'),
                      enabled: isAdmin,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descController,
                      decoration: const InputDecoration(labelText: 'توضیحات'),
                      maxLines: 3,
                      enabled: isAdmin,
                    ),
                    if (isAdmin)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ElevatedButton(
                          onPressed: () {
                            getIt<ChatProvider>().updateChatInfo(chat.id, title: _titleController.text, description: _descController.text);
                          },
                          child: const Text('به‌روزرسانی'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'شرکت‌کنندگان (${chat.participants.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ...chat.participants.map((u) => ListTile(
                  leading: CircleAvatar(
                    backgroundImage: u.avatar != null ? CachedNetworkImageProvider(u.avatar!) : null,
                    child: u.avatar == null ? Text(u.username[0]) : null,
                  ),
                  title: Text(u.displayName),
                  subtitle: Text(u.username),
                  trailing: u.id == chat.createdBy ? const Icon(Icons.star, color: Colors.amber) : null,
                  onTap: () {
                    // Show user profile
                  },
                )),
                if (isAdmin && chat.type != 'private')
                  ListTile(
                    leading: const Icon(Icons.person_add),
                    title: const Text('افزودن شرکت‌کننده'),
                    onTap: _addParticipant,
                  ),
              ],
            ),
          ),
          if (chat.type != 'private')
            Card(
              child: ListTile(
                leading: const Icon(Icons.archive),
                title: const Text('بایگانی گفتگو'),
                onTap: () {
                  getIt<ChatProvider>().archiveChatManually(chat.id);
                  Navigator.pop(context);
                },
              ),
            ),
        ],
      ),
    );
  }

  void _addParticipant() async {
    final users = await _fetchUsers();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('افزودن شرکت‌کننده'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final user = users[i];
              if (chat.participants.any((p) => p.id == user.id)) return const SizedBox.shrink();
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: user.avatar != null ? CachedNetworkImageProvider(user.avatar!) : null,
                  child: user.avatar == null ? Text(user.username[0]) : null,
                ),
                title: Text(user.displayName),
                onTap: () {
                  Navigator.pop(ctx);
                  getIt<ChatProvider>().addParticipant(chat.id, user.id);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<List<User>> _fetchUsers() async {
    try {
      final response = await ApiService().get('/users');
      final List data = response.data;
      return data.map((u) => User.fromJson(u)).toList();
    } catch (e) {
      return [];
    }
  }
}

// -------------------- Search Page --------------------
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Message> _results = [];
  bool _isSearching = false;

  void _search() async {
    final query = _searchController.text;
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final response = await ApiService().get('/search/messages', queryParameters: {'q': query});
      final List data = response.data;
      setState(() {
        _results = data.map((m) => Message.fromJson(m)).toList();
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('جستجو'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'جستجوی پیام‌ها...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 20),
            if (_isSearching)
              const Center(child: CircularProgressIndicator())
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (ctx, i) {
                    final msg = _results[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: msg.sender.avatar != null ? CachedNetworkImageProvider(msg.sender.avatar!) : null,
                        child: msg.sender.avatar == null ? Text(msg.sender.username[0]) : null,
                      ),
                      title: Text(msg.text ?? 'رسانه'),
                      subtitle: Text(msg.sender.displayName),
                      onTap: () {
                        // Navigate to chat
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -------------------- Profile Page (Edit) --------------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = getIt<AuthProvider>().currentUser;
    if (user != null) {
      _firstNameController.text = user.firstName ?? '';
      _lastNameController.text = user.lastName ?? '';
      _bioController.text = user.bio ?? '';
      _phoneController.text = user.phone ?? '';
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      final auth = getIt<AuthProvider>();
      final userId = auth.currentUser!.id;
      try {
        await ApiService().put('/users/$userId', data: {
          'first_name': _firstNameController.text,
          'last_name': _lastNameController.text,
          'bio': _bioController.text,
          'phone': _phoneController.text,
        });
        setState(() => _isSaving = false);
        Navigator.pop(context);
      } catch (e) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ویرایش پروفایل'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'نام'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'نام خانوادگی'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'شماره تلفن'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(labelText: 'درباره من'),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}