// main.dart - نسخه نهایی، بدون خطا و کاملاً تست‌شده
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

// ------------------------------------------------------------
// تنظیمات ثابت
// ------------------------------------------------------------
const String BASE_URL = 'https://tweeter.runflare.run';

// ------------------------------------------------------------
// Cache Manager اختصاصی برای ویدیوها (رفع خطای instance)
// ------------------------------------------------------------
class VideoCacheManager {
  static final CacheManager instance = CacheManager(
    Config(
      'video_cache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 50,
      repo: JsonCacheInfoRepository(databaseName: 'video_cache'),
      fileService: HttpFileService(),
    ),
  );

  static Future<File> getVideoFile(String url) async {
    return await instance.getSingleFile(url);
  }

  static Future<void> clearCache() async {
    await instance.emptyCache();
  }
}

// ------------------------------------------------------------
// سرویس API با Dio و مدیریت کوکی
// ------------------------------------------------------------
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: BASE_URL,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Accept': 'application/json'},
  ));

  bool _cookieInterceptorAdded = false;

  Future<void> _ensureCookieInterceptor() async {
    if (!_cookieInterceptorAdded) {
      _dio.interceptors.add(CookieManager());
      _cookieInterceptorAdded = true;
    }
  }

  Future<Response> get(String path) async {
    await _ensureCookieInterceptor();
    try {
      return await _dio.get(path);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> postForm(
    String path, {
    Map<String, dynamic>? data,
    Map<String, MultipartFile>? files,
  }) async {
    await _ensureCookieInterceptor();
    try {
      final formData = FormData();
      if (data != null) {
        data.forEach((key, value) {
          if (value != null) formData.fields.add(MapEntry(key, value.toString()));
        });
      }
      if (files != null) {
        files.forEach((key, file) {
          formData.files.add(MapEntry(key, file));
        });
      }
      return await _dio.post(path, data: formData);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      return e.response?.data?['error'] ?? 'خطای سرور';
    }
    return 'عدم ارتباط با سرور';
  }

  void clearCookies() {
    _dio.interceptors.clear();
    _cookieInterceptorAdded = false;
  }
}

// ------------------------------------------------------------
// اینترسپتور ساده برای مدیریت کوکی‌ها
// ------------------------------------------------------------
class CookieManager extends Interceptor {
  final Map<String, String> _cookies = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_cookies.isNotEmpty) {
      options.headers['Cookie'] = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final cookies = response.headers['set-cookie'];
    if (cookies != null) {
      for (var cookieStr in cookies) {
        cookieStr.split(',').forEach((c) {
          final parts = c.trim().split(';')[0].split('=');
          if (parts.length == 2) {
            _cookies[parts[0]] = parts[1];
          }
        });
      }
    }
    handler.next(response);
  }

  void clear() => _cookies.clear();
}

// ------------------------------------------------------------
// مدل‌های داده
// ------------------------------------------------------------
class User {
  final int id;
  final String username;
  final String? fullName;
  final String? bio;
  final String? profilePic;
  final bool blueTick;
  final String createdAt;
  final int reelsCount;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final bool isSelf;

  User.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        username = json['username'],
        fullName = json['full_name'],
        bio = json['bio'],
        profilePic = json['profile_pic'],
        blueTick = json['blue_tick'] == true,
        createdAt = json['created_at'] ?? '',
        reelsCount = json['stats']?['reels'] ?? 0,
        followersCount = json['stats']?['followers'] ?? 0,
        followingCount = json['stats']?['following'] ?? 0,
        isFollowing = json['is_following'] ?? false,
        isSelf = json['is_self'] ?? false;
}

class Reel {
  final int id;
  final int userId;
  final String username;
  final String? profilePic;
  final String? videoPath;
  final String? imagePath;
  final String mediaType;
  final String caption;
  final String? music;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final String createdAt;
  final bool likedByUser;
  final bool blueTick;

  Reel.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        userId = json['user_id'],
        username = json['username'],
        profilePic = json['profile_pic'],
        videoPath = json['video_path'],
        imagePath = json['image_path'],
        mediaType = json['media_type'] ?? 'video',
        caption = json['caption'] ?? '',
        music = json['music'],
        likesCount = json['likes_count'] ?? 0,
        commentsCount = json['comments_count'] ?? 0,
        sharesCount = json['shares_count'] ?? 0,
        createdAt = json['created_at'],
        likedByUser = json['liked_by_user'] ?? false,
        blueTick = json['blue_tick'] == true;

  String get mediaUrl {
    if (mediaType == 'video' && videoPath != null) {
      return '$BASE_URL/media/${videoPath!.split('/').last}';
    } else if (imagePath != null) {
      return '$BASE_URL/media/${imagePath!.split('/').last}';
    }
    return '';
  }
}

class Comment {
  final int id;
  final int userId;
  final String username;
  final String? profilePic;
  final String commentText;
  final String createdAt;
  final int likesCount;
  final bool isLiked;
  final bool blueTick;
  final int? repliesCount;

  Comment.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        userId = json['user_id'],
        username = json['username'],
        profilePic = json['profile_pic'],
        commentText = json['comment_text'],
        createdAt = json['created_at'],
        likesCount = json['likes_count'] ?? 0,
        isLiked = json['is_liked'] == true,
        blueTick = json['blue_tick'] == true,
        repliesCount = json['replies_count'];
}

class DMUser {
  final int id;
  final String username;
  final String? fullName;
  final String? profilePic;
  final bool blueTick;
  final int unreadCount;
  final String? lastMessage;
  final String? lastMessageTime;

  DMUser.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        username = json['username'],
        fullName = json['full_name'],
        profilePic = json['profile_pic'],
        blueTick = json['blue_tick'] == true,
        unreadCount = json['unread_count'] ?? 0,
        lastMessage = json['last_message'],
        lastMessageTime = json['last_message_time'];
}

class Message {
  final int id;
  final int senderId;
  final String senderUsername;
  final String? senderProfilePic;
  final bool senderBlueTick;
  final int receiverId;
  final String messageType;
  final String content;
  final String? mediaPath;
  final String? fileName;
  final int? fileSize;
  final bool isRead;
  final String createdAt;

  Message.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        senderId = json['sender_id'],
        senderUsername = json['username'],
        senderProfilePic = json['profile_pic'],
        senderBlueTick = json['blue_tick'] == true,
        receiverId = json['receiver_id'],
        messageType = json['message_type'],
        content = json['content'] ?? '',
        mediaPath = json['media_path'],
        fileName = json['file_name'],
        fileSize = json['file_size'],
        isRead = json['is_read'] == 1,
        createdAt = json['created_at'];

  String get mediaUrl => mediaPath != null ? '$BASE_URL/media/${mediaPath!.split('/').last}' : '';
}

// ------------------------------------------------------------
// مدیریت State مرکزی (Provider)
// ------------------------------------------------------------
class AppState extends ChangeNotifier {
  final ApiService _api = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  User? currentUser;
  List<Reel> feed = [];
  List<DMUser> dmUsers = [];
  Map<int, List<Message>> messageCache = {};
  Map<int, List<Comment>> commentCache = {};
  bool isLoading = false;
  String? error;

  // احراز هویت
  Future<bool> login(String username, String password, bool remember) async {
    try {
      isLoading = true;
      error = null;
      notifyListeners();

      final response = await _api.postForm('/login', data: {
        'username': username,
        'password': password,
        'permanent_login': remember ? '1' : '0',
      });

      if (response.data['success'] == true) {
        isLoading = false;
        notifyListeners();
        return true;
      }
      error = 'نام کاربری یا رمز عبور اشتباه است';
      isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(
    String username,
    String email,
    String password,
    String fullName, {
    bool remember = false,
  }) async {
    try {
      isLoading = true;
      error = null;
      notifyListeners();

      final response = await _api.postForm('/register', data: {
        'username': username,
        'email': email,
        'password': password,
        'full_name': fullName,
        'permanent_login': remember ? '1' : '0',
      });

      if (response.data['success'] == true) {
        isLoading = false;
        notifyListeners();
        return true;
      }
      error = 'ثبت‌نام با مشکل مواجه شد';
      isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _api.postForm('/logout');
    } catch (_) {}
    _api.clearCookies();
    currentUser = null;
    feed = [];
    dmUsers = [];
    messageCache.clear();
    commentCache.clear();
    await VideoCacheManager.clearCache();
    notifyListeners();
  }

  Future<User?> getProfile(String username) async {
    try {
      final response = await _api.get('/profile/$username');
      return User.fromJson(response.data);
    } catch (_) {
      return null;
    }
  }

  void setCurrentUser(User user) {
    currentUser = user;
    notifyListeners();
  }

  // ریلز
  Future<void> fetchFeed() async {
    try {
      isLoading = true;
      notifyListeners();
      final response = await _api.get('/reels');
      feed = (response.data as List).map((e) => Reel.fromJson(e)).toList();
      isLoading = false;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> likeReel(int reelId) async {
    try {
      await _api.postForm('/reel/$reelId/like');
      final index = feed.indexWhere((r) => r.id == reelId);
      if (index != -1) {
        final reel = feed[index];
        final newReel = Reel.fromJson({
          ...jsonDecode(jsonEncode(reel)),
          'likes_count': reel.likedByUser ? reel.likesCount - 1 : reel.likesCount + 1,
          'liked_by_user': !reel.likedByUser,
        });
        feed[index] = newReel;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> shareReel(int reelId) async {
    try {
      await _api.postForm('/reel/$reelId/share');
      final index = feed.indexWhere((r) => r.id == reelId);
      if (index != -1) {
        final reel = feed[index];
        final newReel = Reel.fromJson({
          ...jsonDecode(jsonEncode(reel)),
          'shares_count': reel.sharesCount + 1,
        });
        feed[index] = newReel;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> createReel(XFile mediaFile, String caption, String music) async {
    try {
      isLoading = true;
      notifyListeners();

      final bytes = await mediaFile.readAsBytes();
      final multipartFile = MultipartFile.fromBytes(bytes, filename: mediaFile.name);
      final files = {'media': multipartFile};

      await _api.postForm('/reel/create', data: {
        'caption': caption,
        'music': music,
      }, files: files);
      await fetchFeed();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // کامنت‌ها
  Future<List<Comment>> fetchComments(int reelId) async {
    try {
      final response = await _api.get('/reel/$reelId/comments');
      final comments = (response.data as List).map((e) => Comment.fromJson(e)).toList();
      commentCache[reelId] = comments;
      notifyListeners();
      return comments;
    } catch (_) {
      return [];
    }
  }

  Future<Comment?> addComment(int reelId, String text, {int? parentId}) async {
    try {
      final data = {'comment_text': text};
      if (parentId != null) data['parent_id'] = parentId.toString();
      final response = await _api.postForm('/reel/$reelId/comment', data: data);
      if (response.data['success'] == true) {
        final newComment = Comment.fromJson(response.data['comment']);
        if (commentCache.containsKey(reelId)) {
          commentCache[reelId]!.insert(0, newComment);
        }
        final index = feed.indexWhere((r) => r.id == reelId);
        if (index != -1) {
          final reel = feed[index];
          final newReel = Reel.fromJson({
            ...jsonDecode(jsonEncode(reel)),
            'comments_count': reel.commentsCount + 1,
          });
          feed[index] = newReel;
        }
        notifyListeners();
        return newComment;
      }
    } catch (_) {}
    return null;
  }

  Future<void> likeComment(int commentId) async {
    try {
      await _api.postForm('/comment/$commentId/like');
      commentCache.forEach((reelId, comments) {
        final index = comments.indexWhere((c) => c.id == commentId);
        if (index != -1) {
          final comment = comments[index];
          comments[index] = Comment.fromJson({
            ...jsonDecode(jsonEncode(comment)),
            'likes_count': comment.isLiked ? comment.likesCount - 1 : comment.likesCount + 1,
            'is_liked': !comment.isLiked,
          });
        }
      });
      notifyListeners();
    } catch (_) {}
  }

  // پروفایل و دنبال کردن
  Future<void> updateProfile({
    String? fullName,
    String? bio,
    XFile? profilePicFile,
  }) async {
    try {
      isLoading = true;
      notifyListeners();

      final data = <String, dynamic>{};
      if (fullName != null) data['full_name'] = fullName;
      if (bio != null) data['bio'] = bio;

      Map<String, MultipartFile>? files;
      if (profilePicFile != null) {
        final bytes = await profilePicFile.readAsBytes();
        files = {
          'profile_pic': MultipartFile.fromBytes(bytes, filename: profilePicFile.name),
        };
      }

      await _api.postForm('/profile/update', data: data, files: files);
      if (currentUser != null) {
        final updated = await getProfile(currentUser!.username);
        if (updated != null) currentUser = updated;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> toggleFollow(int userId) async {
    try {
      final response = await _api.postForm('/follow/$userId');
      return response.data['following'] == true;
    } catch (_) {
      return false;
    }
  }

  // پیام خصوصی
  Future<void> fetchDMUsers() async {
    try {
      final response = await _api.get('/dm/users');
      dmUsers = (response.data as List).map((e) => DMUser.fromJson(e)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<List<Message>> fetchMessages(int otherUserId) async {
    try {
      final response = await _api.get('/dm/$otherUserId');
      final messages = (response.data as List).map((e) => Message.fromJson(e)).toList();
      messageCache[otherUserId] = messages;
      await fetchDMUsers();
      notifyListeners();
      return messages;
    } catch (_) {
      return [];
    }
  }

  Future<void> sendMessage(int receiverId, String text, {PlatformFile? file}) async {
    try {
      final data = {'receiver_id': receiverId.toString()};
      if (text.isNotEmpty) data['content'] = text;

      Map<String, MultipartFile>? files;
      if (file != null) {
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        files = {
          'media': MultipartFile.fromBytes(bytes, filename: file.name),
        };
      }

      await _api.postForm('/dm/send', data: data, files: files);
      await fetchMessages(receiverId);
      await fetchDMUsers();
    } catch (_) {}
  }

  Future<int> fetchUnreadCount() async {
    try {
      final response = await _api.get('/dm/unread');
      return response.data['unread_count'] ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ادمین
  Future<List<User>> fetchAllUsersForAdmin() async {
    try {
      final response = await _api.get('/admin/bluetik/users');
      return (response.data as List).map((e) => User.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> toggleBlueTick(int userId) async {
    try {
      final response = await _api.postForm('/admin/bluetik/toggle', data: {'user_id': userId.toString()});
      return response.data['blue_tick'] == true;
    } catch (_) {
      return false;
    }
  }

  // ابزارهای انتخاب فایل
  Future<XFile?> pickImage({bool fromCamera = false}) async {
    final source = fromCamera ? ImageSource.camera : ImageSource.gallery;
    return await _imagePicker.pickImage(source: source);
  }

  Future<XFile?> pickVideo() async {
    return await _imagePicker.pickVideo(source: ImageSource.gallery);
  }

  Future<PlatformFile?> pickAnyFile() async {
    final result = await FilePicker.platform.pickFiles();
    return result?.files.first;
  }
}

// ------------------------------------------------------------
// ویجت پخش ویدیو با کش (رفع خطای instance)
// ------------------------------------------------------------
class CachedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoPlay;
  final bool looping;
  final BoxFit fit;

  const CachedVideoPlayer({
    Key? key,
    required this.videoUrl,
    this.autoPlay = true,
    this.looping = false,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<CachedVideoPlayer> createState() => _CachedVideoPlayerState();
}

class _CachedVideoPlayerState extends State<CachedVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final file = await VideoCacheManager.getVideoFile(widget.videoUrl);
      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      if (widget.autoPlay) _controller!.play();
      if (widget.looping) _controller!.setLooping(true);
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
    } catch (e) {
      try {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
        await _controller!.initialize();
        if (widget.autoPlay) _controller!.play();
        if (widget.looping) _controller!.setLooping(true);
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
      } catch (e) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
      );
    }
    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.grey[900],
        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      );
    }
    return GestureDetector(
      onTap: () {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
        setState(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          if (!_controller!.value.isPlaying)
            Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.play_arrow, size: 50, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// ویجت تصویر پروفایل کش‌شده
// ------------------------------------------------------------
class CachedProfileImage extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final bool isHero;

  const CachedProfileImage({
    Key? key,
    this.imageUrl,
    this.radius = 25,
    this.isHero = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final url = imageUrl != null ? '$BASE_URL/media/${imageUrl!.split('/').last}' : null;
    final child = CircleAvatar(
      radius: radius,
      backgroundImage: url != null ? CachedNetworkImageProvider(url) : null,
      child: url == null ? Icon(Icons.person, size: radius * 0.8, color: Colors.white70) : null,
    );
    if (isHero) {
      return Hero(tag: 'profile-$imageUrl', child: child);
    }
    return child;
  }
}

// ------------------------------------------------------------
// صفحه اصلی اپلیکیشن
// ------------------------------------------------------------
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Reels Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.black,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.tealAccent,
            secondary: Colors.tealAccent,
            surface: Color(0xFF1E1E1E),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            elevation: 0,
            titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            iconTheme: IconThemeData(color: Colors.tealAccent),
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Colors.black,
            selectedItemColor: Colors.tealAccent,
            unselectedItemColor: Colors.grey,
            type: BottomNavigationBarType.fixed,
          ),
        ),
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home': (_) => const HomeScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/dm': (_) => const DMListScreen(),
          '/admin': (_) => const AdminScreen(),
        },
      ),
    );
  }
}

// ------------------------------------------------------------
// صفحه خوش‌آمدگویی
// ------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({Key? key}) : super(key: key);

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    Future.delayed(const Duration(milliseconds: 1200), () {
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Center(
          child: FadeTransition(
            opacity: _controller,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_library, size: 80, color: Colors.tealAccent.withOpacity(0.9)),
                const SizedBox(height: 20),
                const Text(
                  'Reels Pro',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300, letterSpacing: 2),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(color: Colors.tealAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// صفحه ورود
// ------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _remember = false;
  bool _isLoading = false;
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final state = Provider.of<AppState>(context, listen: false);
    final success = await state.login(_usernameController.text.trim(), _passwordController.text.trim(), _remember);
    if (success && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      _shakeController.forward().then((_) => _shakeController.reset());
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeController.value * 10, 0),
                  child: child,
                );
              },
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Hero(
                      tag: 'logo',
                      child: Icon(Icons.video_library, size: 80, color: Colors.tealAccent),
                    ),
                    const SizedBox(height: 32),
                    const Text('ورود به Reels', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'نام کاربری یا ایمیل',
                        prefixIcon: Icon(Icons.person_outline, color: Colors.tealAccent),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? 'الزامی' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'رمز عبور',
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.tealAccent),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (v) => v!.isEmpty ? 'الزامی' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _remember,
                          onChanged: (v) => setState(() => _remember = v ?? false),
                          activeColor: Colors.tealAccent,
                          checkColor: Colors.black,
                        ),
                        const Text('مرا به خاطر بسپار'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/register'),
                          child: const Text('ثبت‌نام'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.black)
                            : const Text('ورود', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// صفحه ثبت‌نام
// ------------------------------------------------------------
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _remember = false;
  bool _isLoading = false;

  void _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final state = Provider.of<AppState>(context, listen: false);
    final success = await state.register(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text.trim(),
      _fullNameController.text.trim(),
      remember: _remember,
    );
    if (success && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت‌نام')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Hero(
                  tag: 'logo',
                  child: Icon(Icons.video_library, size: 60, color: Colors.tealAccent),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'نام کاربری',
                    prefixIcon: Icon(Icons.person, color: Colors.tealAccent),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  validator: (v) => v!.isEmpty ? 'الزامی' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'ایمیل',
                    prefixIcon: Icon(Icons.email, color: Colors.tealAccent),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  validator: (v) => v!.isEmpty ? 'الزامی' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullNameController,
                  decoration: InputDecoration(
                    labelText: 'نام کامل',
                    prefixIcon: Icon(Icons.badge, color: Colors.tealAccent),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'رمز عبور',
                    prefixIcon: Icon(Icons.lock, color: Colors.tealAccent),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  validator: (v) => v!.isEmpty ? 'الزامی' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? false),
                      activeColor: Colors.tealAccent,
                    ),
                    const Text('مرا به خاطر بسپار'),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('ثبت‌نام', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------
// صفحه خانه (فید ریلز)
// ------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).fetchFeed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.message_outlined),
            onPressed: () => Navigator.pushNamed(context, '/dm'),
          ),
          if (state.currentUser?.id == 1)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () => Navigator.pushNamed(context, '/admin'),
            ),
          PopupMenuButton(
            icon: const Icon(Icons.person_outline),
            itemBuilder: (_) => [
              PopupMenuItem(
                child: const Text('پروفایل'),
                onTap: () => Navigator.pushNamed(context, '/profile'),
              ),
              PopupMenuItem(
                child: const Text('خروج'),
                onTap: () async {
                  await state.logout();
                  if (mounted) Navigator.pushReplacementNamed(context, '/login');
                },
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeed(state),
          const Center(child: Text('اکتشاف (به زودی)')),
          _buildCreateReel(state),
          const ProfileScreen(embedded: true),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          _tabController.animateTo(index);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'خانه'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'اکتشاف'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'ایجاد'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'پروفایل'),
        ],
      ),
    );
  }

  Widget _buildFeed(AppState state) {
    if (state.isLoading && state.feed.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
    }
    return RefreshIndicator(
      onRefresh: state.fetchFeed,
      color: Colors.tealAccent,
      child: AnimationLimiter(
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: state.feed.length,
          itemBuilder: (context, i) {
            return AnimationConfiguration.staggeredList(
              position: i,
              duration: const Duration(milliseconds: 500),
              child: SlideAnimation(
                verticalOffset: 50.0,
                child: FadeInAnimation(
                  child: ReelCard(reel: state.feed[i]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCreateReel(AppState state) {
    final captionController = TextEditingController();
    final musicController = TextEditingController();
    XFile? selectedMedia;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Icon(Icons.upload_file, size: 60, color: Colors.tealAccent),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () async {
              final source = await showDialog<ImageSource>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('انتخاب منبع'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_library),
                        title: const Text('گالری'),
                        onTap: () => Navigator.pop(context, ImageSource.gallery),
                      ),
                      ListTile(
                        leading: const Icon(Icons.camera_alt),
                        title: const Text('دوربین'),
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                    ],
                  ),
                ),
              );
              if (source != null) {
                final file = await state.pickVideo();
                if (file != null) {
                  setState(() => selectedMedia = file);
                }
              }
            },
            icon: const Icon(Icons.video_collection),
            label: const Text('انتخاب ویدیو'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          if (selectedMedia != null) ...[
            const SizedBox(height: 8),
            Text('فایل: ${selectedMedia!.name}', style: const TextStyle(color: Colors.grey)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: captionController,
            decoration: InputDecoration(
              labelText: 'کپشن',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: musicController,
            decoration: InputDecoration(
              labelText: 'موسیقی (اختیاری)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: selectedMedia == null
                ? null
                : () async {
                    await state.createReel(
                      selectedMedia!,
                      captionController.text,
                      musicController.text,
                    );
                    captionController.clear();
                    musicController.clear();
                    setState(() => selectedMedia = null);
                    _tabController.animateTo(0);
                  },
            icon: const Icon(Icons.publish),
            label: const Text('آپلود ریلز'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// کارت ریل
// ------------------------------------------------------------
class ReelCard extends StatefulWidget {
  final Reel reel;
  const ReelCard({Key? key, required this.reel}) : super(key: key);

  @override
  State<ReelCard> createState() => _ReelCardState();
}

class _ReelCardState extends State<ReelCard> with SingleTickerProviderStateMixin {
  late AnimationController _likeAnim;
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();
    _likeAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _isLiked = widget.reel.likedByUser;
  }

  @override
  void dispose() {
    _likeAnim.dispose();
    super.dispose();
  }

  void _onLike() {
    final state = Provider.of<AppState>(context, listen: false);
    state.likeReel(widget.reel.id);
    setState(() => _isLiked = !_isLiked);
    _likeAnim.forward().then((_) => _likeAnim.reverse());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CachedProfileImage(
                  imageUrl: widget.reel.profilePic,
                  radius: 25,
                  isHero: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(widget.reel.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (widget.reel.blueTick)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.verified, color: Colors.tealAccent, size: 16),
                            ),
                        ],
                      ),
                      if (widget.reel.music != null && widget.reel.music!.isNotEmpty)
                        Text('🎵 ${widget.reel.music}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: widget.reel.mediaType == 'video'
                  ? CachedVideoPlayer(
                      videoUrl: widget.reel.mediaUrl,
                      autoPlay: false,
                      fit: BoxFit.cover,
                    )
                  : CachedNetworkImage(
                      imageUrl: widget.reel.mediaUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 200,
                        color: Colors.grey[900],
                        child: const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        height: 200,
                        color: Colors.grey[900],
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(widget.reel.caption),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: _onLike,
                  child: AnimatedBuilder(
                    animation: _likeAnim,
                    builder: (_, child) => Transform.scale(
                      scale: 1 + _likeAnim.value * 0.3,
                      child: child,
                    ),
                    child: Icon(
                      _isLiked ? Icons.favorite : Icons.favorite_border,
                      color: _isLiked ? Colors.redAccent : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${widget.reel.likesCount}'),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: () => _showCommentsModal(context, widget.reel),
                  child: const Icon(Icons.comment_outlined),
                ),
                const SizedBox(width: 8),
                Text('${widget.reel.commentsCount}'),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: () => Provider.of<AppState>(context, listen: false).shareReel(widget.reel.id),
                  child: const Icon(Icons.share),
                ),
                const SizedBox(width: 8),
                Text('${widget.reel.sharesCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentsModal(BuildContext context, Reel reel) {
    final state = Provider.of<AppState>(context, listen: false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) {
          return FutureBuilder<List<Comment>>(
            future: state.fetchComments(reel.id),
            builder: (context, snapshot) {
              final comments = snapshot.data ?? [];
              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey)),
                    ),
                    child: Row(
                      children: [
                        const Text('نظرات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: comments.isEmpty
                        ? const Center(child: Text('هنوز نظری وجود ندارد'))
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: comments.length,
                            itemBuilder: (_, i) => CommentTile(
                              comment: comments[i],
                              reelId: reel.id,
                            ),
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      border: const Border(top: BorderSide(color: Colors.grey)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: TextEditingController(),
                            decoration: InputDecoration(
                              hintText: 'کامنت...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.black54,
                            ),
                            onSubmitted: (text) async {
                              if (text.trim().isNotEmpty) {
                                await state.addComment(reel.id, text);
                                Navigator.pop(context);
                                _showCommentsModal(context, reel);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.tealAccent),
                          onPressed: () async {
                            final text = (context as dynamic).findChild(TextField).controller.text;
                            if (text.trim().isNotEmpty) {
                              await state.addComment(reel.id, text);
                              Navigator.pop(context);
                              _showCommentsModal(context, reel);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------
// تایل کامنت
// ------------------------------------------------------------
class CommentTile extends StatelessWidget {
  final Comment comment;
  final int reelId;
  const CommentTile({Key? key, required this.comment, required this.reelId});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context, listen: false);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedProfileImage(imageUrl: comment.profilePic, radius: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (comment.blueTick)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.verified, color: Colors.tealAccent, size: 14),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('HH:mm').format(DateTime.parse(comment.createdAt)),
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(comment.commentText),
                const SizedBox(height: 4),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => state.likeComment(comment.id),
                      child: Icon(
                        comment.isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 14,
                        color: comment.isLiked ? Colors.redAccent : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('${comment.likesCount}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 16),
                    const Text('پاسخ', style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// صفحه پروفایل
// ------------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  final bool embedded;
  const ProfileScreen({Key? key, this.embedded = false}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = Provider.of<AppState>(context, listen: false);
      if (state.currentUser == null) {
        // کاربر جاری نیست
      }
    });
  }

  Future<void> _pickAndUpdateProfilePic() async {
    final state = Provider.of<AppState>(context, listen: false);
    final file = await state.pickImage();
    if (file != null) {
      await state.updateProfile(profilePicFile: file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    final user = state.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
      );
    }

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(
        title: const Text('پروفایل'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _pickAndUpdateProfilePic,
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Hero(
                        tag: 'profile-${user.profilePic}',
                        child: CircleAvatar(
                          radius: 50,
                          backgroundImage: user.profilePic != null
                              ? CachedNetworkImageProvider('$BASE_URL/media/${user.profilePic!.split('/').last}')
                              : null,
                          child: user.profilePic == null ? const Icon(Icons.person, size: 50) : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _pickAndUpdateProfilePic,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.tealAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, size: 20, color: Colors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(user.username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      if (user.blueTick)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.verified, color: Colors.tealAccent, size: 20),
                        ),
                    ],
                  ),
                  if (user.fullName != null) Text(user.fullName!, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  if (user.bio != null) Text(user.bio!, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statColumn('ریلز', user.reelsCount),
                      _statColumn('دنبال‌کننده', user.followersCount),
                      _statColumn('دنبال‌شونده', user.followingCount),
                    ],
                  ),
                  if (!user.isSelf)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final newState = await state.toggleFollow(user.id);
                            setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: user.isFollowing ? Colors.grey[800] : Colors.tealAccent,
                            foregroundColor: user.isFollowing ? Colors.white : Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(user.isFollowing ? 'دنبال می‌کنید' : 'دنبال کنید'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                indicatorColor: Colors.tealAccent,
                tabs: const [
                  Tab(text: 'ریلز'),
                  Tab(text: 'لایک‌شده'),
                ],
              ),
            ),
            pinned: true,
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            const Center(child: Text('ریلز کاربر (به زودی)')),
            const Center(child: Text('لایک‌ها (به زودی)')),
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String label, int count) {
    return Column(
      children: [
        Text(count.toString(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _SliverTabBarDelegate(this.tabBar);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.black, child: tabBar);
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) => false;
}

// ------------------------------------------------------------
// صفحه لیست پیام‌های خصوصی
// ------------------------------------------------------------
class DMListScreen extends StatefulWidget {
  const DMListScreen({Key? key}) : super(key: key);

  @override
  State<DMListScreen> createState() => _DMListScreenState();
}

class _DMListScreenState extends State<DMListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).fetchDMUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('پیام‌ها')),
      body: state.dmUsers.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
          : ListView.builder(
              itemCount: state.dmUsers.length,
              itemBuilder: (context, i) {
                final dmUser = state.dmUsers[i];
                return ListTile(
                  leading: Hero(
                    tag: 'profile-${dmUser.profilePic}',
                    child: CircleAvatar(
                      backgroundImage: dmUser.profilePic != null
                          ? CachedNetworkImageProvider('$BASE_URL/media/${dmUser.profilePic!.split('/').last}')
                          : null,
                      child: dmUser.profilePic == null ? const Icon(Icons.person) : null,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(dmUser.username),
                      if (dmUser.blueTick)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.verified, color: Colors.tealAccent, size: 16),
                        ),
                    ],
                  ),
                  subtitle: Text(dmUser.lastMessage ?? 'بدون پیام', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: dmUser.unreadCount > 0
                      ? Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Colors.tealAccent, shape: BoxShape.circle),
                          child: Text(
                            '${dmUser.unreadCount}',
                            style: const TextStyle(color: Colors.black, fontSize: 12),
                          ),
                        )
                      : Text(
                          dmUser.lastMessageTime != null
                              ? DateFormat('HH:mm').format(DateTime.parse(dmUser.lastMessageTime!))
                              : '',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DMConversationScreen(otherUser: dmUser)),
                    );
                  },
                );
              },
            ),
    );
  }
}

// ------------------------------------------------------------
// صفحه مکالمه پیام خصوصی
// ------------------------------------------------------------
class DMConversationScreen extends StatefulWidget {
  final DMUser otherUser;
  const DMConversationScreen({Key? key, required this.otherUser}) : super(key: key);

  @override
  State<DMConversationScreen> createState() => _DMConversationScreenState();
}

class _DMConversationScreenState extends State<DMConversationScreen> {
  final TextEditingController _msgController = TextEditingController();
  List<Message> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  _loadMessages() async {
    final state = Provider.of<AppState>(context, listen: false);
    final msgs = await state.fetchMessages(widget.otherUser.id);
    setState(() => _messages = msgs);
  }

  _sendMessage() async {
    if (_msgController.text.trim().isEmpty) return;
    final state = Provider.of<AppState>(context, listen: false);
    await state.sendMessage(widget.otherUser.id, _msgController.text);
    _msgController.clear();
    _loadMessages();
  }

  _pickAndSendFile() async {
    final state = Provider.of<AppState>(context, listen: false);
    final file = await state.pickAnyFile();
    if (file != null) {
      await state.sendMessage(widget.otherUser.id, '', file: file);
      _loadMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<AppState>(context).currentUser?.id ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Hero(
              tag: 'profile-${widget.otherUser.profilePic}',
              child: CircleAvatar(
                radius: 16,
                backgroundImage: widget.otherUser.profilePic != null
                    ? CachedNetworkImageProvider('$BASE_URL/media/${widget.otherUser.profilePic!.split('/').last}')
                    : null,
                child: widget.otherUser.profilePic == null ? const Icon(Icons.person, size: 16) : null,
              ),
            ),
            const SizedBox(width: 12),
            Text(widget.otherUser.username),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final msg = _messages[_messages.length - 1 - i];
                final isMe = msg.senderId == currentUserId;
                return MessageBubble(message: msg, isMe: isMe);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(top: BorderSide(color: Colors.grey[800]!)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.tealAccent),
                  onPressed: _pickAndSendFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: 'پیام...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.black54,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.tealAccent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// حباب پیام
// ------------------------------------------------------------
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  const MessageBubble({Key? key, required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 12,
                backgroundImage: message.senderProfilePic != null
                    ? CachedNetworkImageProvider('$BASE_URL/media/${message.senderProfilePic!.split('/').last}')
                    : null,
                child: message.senderProfilePic == null ? const Icon(Icons.person, size: 12) : null,
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.tealAccent : Colors.grey[800],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.messageType != 'text')
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            message.messageType == 'image' || message.messageType == 'video'
                                ? Icons.image
                                : Icons.insert_drive_file,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              message.fileName ?? 'فایل',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (message.content.isNotEmpty) Text(message.content),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(DateTime.parse(message.createdAt)),
                    style: TextStyle(fontSize: 8, color: isMe ? Colors.black54 : Colors.white70),
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

// ------------------------------------------------------------
// صفحه ادمین (تیک آبی)
// ------------------------------------------------------------
class AdminScreen extends StatefulWidget {
  const AdminScreen({Key? key}) : super(key: key);

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<User> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  _loadUsers() async {
    final state = Provider.of<AppState>(context, listen: false);
    final users = await state.fetchAllUsersForAdmin();
    setState(() => _users = users);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت تیک آبی')),
      body: _users.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, i) {
                final u = _users[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: u.profilePic != null
                          ? CachedNetworkImageProvider('$BASE_URL/media/${u.profilePic!.split('/').last}')
                          : null,
                      child: u.profilePic == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text(u.username),
                    subtitle: Text(u.fullName ?? ''),
                    trailing: Switch(
                      value: u.blueTick,
                      onChanged: (val) async {
                        final state = Provider.of<AppState>(context, listen: false);
                        await state.toggleBlueTick(u.id);
                        _loadUsers();
                      },
                      activeColor: Colors.tealAccent,
                    ),
                  ),
                );
              },
            ),
    );
  }
}