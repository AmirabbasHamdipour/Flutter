// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:dio/dio.dart' as dio;
import 'package:path_provider/path_provider.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:animations/animations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// -----------------------------------------------------------------------------
// Environment & Constants
// -----------------------------------------------------------------------------
const String baseUrl = 'https://tweeter.runflare.run'; // base URL without trailing slash

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------
class User {
  final int id;
  final String username;
  final String? bio;
  final String? profileImage;
  final bool isBlue;
  final DateTime createdAt;
  final int postsCount;
  final int bookmarksCount;

  User({
    required this.id,
    required this.username,
    this.bio,
    this.profileImage,
    required this.isBlue,
    required this.createdAt,
    required this.postsCount,
    required this.bookmarksCount,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      bio: json['bio'] as String?,
      profileImage: json['profile_image'] as String?,
      isBlue: (json['is_blue'] as int) == 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      postsCount: json['posts_count'] as int? ?? 0,
      bookmarksCount: json['bookmarks_count'] as int? ?? 0,
    );
  }
}

class Post {
  final int id;
  final int userId;
  final String? caption;
  final String mediaType; // 'image', 'video', 'audio', 'file', 'text'
  final String? mediaPath;
  final String? thumbnailPath;
  final DateTime createdAt;
  // Joined fields
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  int likesCount;
  int commentsCount;
  bool likedByUser;
  bool bookmarkedByUser;

  Post({
    required this.id,
    required this.userId,
    this.caption,
    required this.mediaType,
    this.mediaPath,
    this.thumbnailPath,
    required this.createdAt,
    required this.username,
    this.userProfileImage,
    required this.userIsBlue,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.likedByUser = false,
    this.bookmarkedByUser = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      caption: json['caption'] as String?,
      mediaType: json['media_type'] as String,
      mediaPath: json['media_path'] as String?,
      thumbnailPath: json['thumbnail_path'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      username: json['username'] as String,
      userProfileImage: json['profile_image'] as String?,
      userIsBlue: (json['is_blue'] as int) == 1,
      likesCount: json['likes_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      likedByUser: json['liked_by_user'] ?? false,
      bookmarkedByUser: json['bookmarked_by_user'] ?? false,
    );
  }
}

class Comment {
  final int id;
  final int postId;
  final int userId;
  final int? parentId;
  final String content;
  final DateTime createdAt;
  // Joined fields
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  int likesCount;
  bool likedByUser;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    this.parentId,
    required this.content,
    required this.createdAt,
    required this.username,
    this.userProfileImage,
    required this.userIsBlue,
    this.likesCount = 0,
    this.likedByUser = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as int,
      postId: json['post_id'] as int,
      userId: json['user_id'] as int,
      parentId: json['parent_id'] as int?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      username: json['username'] as String,
      userProfileImage: json['profile_image'] as String?,
      userIsBlue: (json['is_blue'] as int) == 1,
      likesCount: json['likes_count'] ?? 0,
      likedByUser: json['liked_by_user'] ?? false,
    );
  }
}

class DirectMessage {
  final int id;
  final int senderId;
  final int receiverId;
  final String? content;
  final String? mediaType;
  final String? mediaPath;
  final DateTime createdAt;
  final String senderUsername;
  final String? senderProfileImage;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.content,
    this.mediaType,
    this.mediaPath,
    required this.createdAt,
    required this.senderUsername,
    this.senderProfileImage,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    return DirectMessage(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int,
      content: json['content'] as String?,
      mediaType: json['media_type'] as String?,
      mediaPath: json['media_path'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderUsername: json['sender_username'] as String,
      senderProfileImage: json['sender_profile_image'] as String?,
    );
  }
}

class GroupMessage {
  final int id;
  final int senderId;
  final String? content;
  final String? mediaType;
  final String? mediaPath;
  final DateTime createdAt;
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;

  GroupMessage({
    required this.id,
    required this.senderId,
    this.content,
    this.mediaType,
    this.mediaPath,
    required this.createdAt,
    required this.username,
    this.userProfileImage,
    required this.userIsBlue,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      content: json['content'] as String?,
      mediaType: json['media_type'] as String?,
      mediaPath: json['media_path'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      username: json['username'] as String,
      userProfileImage: json['profile_image'] as String?,
      userIsBlue: (json['is_blue'] as int) == 1,
    );
  }
}

// -----------------------------------------------------------------------------
// API Service
// -----------------------------------------------------------------------------
class ApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
  ));

  ApiService() {
    _dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
  }

  // Auth
  Future<Map<String, dynamic>> register(String username, String password, String bio, File? profileImage) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/register'));
    request.fields['username'] = username;
    request.fields['password'] = password;
    request.fields['bio'] = bio;
    if (profileImage != null) {
      request.files.add(await http.MultipartFile.fromPath('profile_image', profileImage.path));
    }
    var response = await request.send();
    var respStr = await response.stream.bytesToString();
    if (response.statusCode == 201) {
      return jsonDecode(respStr);
    } else {
      throw Exception(jsonDecode(respStr)['error'] ?? 'Registration failed');
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post('/login', data: {'username': username, 'password': password});
    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception(response.data['error'] ?? 'Login failed');
    }
  }

  Future<User> getProfile(int userId) async {
    final response = await _dio.get('/profile/$userId');
    if (response.statusCode == 200) {
      return User.fromJson(response.data);
    } else {
      throw Exception(response.data['error'] ?? 'Failed to load profile');
    }
  }

  Future<void> updateProfile(int userId, String? bio, File? profileImage) async {
    var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/profile/$userId'));
    request.fields['user_id'] = userId.toString();
    if (bio != null) request.fields['bio'] = bio;
    if (profileImage != null) {
      request.files.add(await http.MultipartFile.fromPath('profile_image', profileImage.path));
    }
    var response = await request.send();
    if (response.statusCode != 200) {
      var respStr = await response.stream.bytesToString();
      throw Exception(jsonDecode(respStr)['error'] ?? 'Update failed');
    }
  }

  // Posts
  Future<List<Post>> getPosts({int page = 1, int perPage = 10}) async {
    final response = await _dio.get('/posts', queryParameters: {'page': page, 'per_page': perPage});
    if (response.statusCode == 200) {
      List<dynamic> data = response.data;
      return data.map((e) => Post.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load posts');
    }
  }

  Future<Map<String, dynamic>> fetchPost(int postId, {int? userId}) async {
    final response = await _dio.get('/post/$postId', queryParameters: userId != null ? {'user_id': userId} : {});
    if (response.statusCode == 200) {
      return response.data;
    } else {
      throw Exception(response.data['error'] ?? 'Failed to load post');
    }
  }

  Future<Map<String, dynamic>> uploadPost(int userId, String caption, File? media, {ProgressCallback? onProgress}) async {
    String fileName = media?.path.split('/').last ?? '';
    String mediaType = _getMediaType(fileName);
    FormData formData = FormData.fromMap({
      'user_id': userId,
      'caption': caption,
      if (media != null) 'media': await MultipartFile.fromFile(media.path, filename: fileName),
    });
    final response = await _dio.post('/upload', data: formData, onSendProgress: onProgress);
    if (response.statusCode == 201) {
      return response.data;
    } else {
      throw Exception(response.data['error'] ?? 'Upload failed');
    }
  }

  Future<void> updatePost(int postId, int userId, String newCaption) async {
    final response = await _dio.put('/post/$postId', data: {'user_id': userId, 'caption': newCaption});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Update failed');
    }
  }

  Future<void> deletePost(int postId, int userId) async {
    final response = await _dio.delete('/post/$postId', queryParameters: {'user_id': userId});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Delete failed');
    }
  }

  String _getMediaType(String filename) {
    var ext = filename.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) return 'image';
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'ogg'].contains(ext)) return 'audio';
    return 'file';
  }

  // Likes
  Future<Map<String, dynamic>> toggleLike(int postId, int userId) async {
    final response = await _dio.post('/like', data: {'post_id': postId, 'user_id': userId});
    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data;
    } else {
      throw Exception('Failed to toggle like');
    }
  }

  // Bookmarks
  Future<Map<String, dynamic>> toggleBookmark(int postId, int userId) async {
    final response = await _dio.post('/bookmark', data: {'post_id': postId, 'user_id': userId});
    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data;
    } else {
      throw Exception('Failed to toggle bookmark');
    }
  }

  Future<List<Post>> getBookmarks(int userId) async {
    final response = await _dio.get('/bookmarks/$userId');
    if (response.statusCode == 200) {
      List<dynamic> data = response.data;
      return data.map((e) => Post.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load bookmarks');
    }
  }

  // Comments
  Future<Map<String, dynamic>> addComment(int postId, int userId, String content, {int? parentId}) async {
    final response = await _dio.post('/comment', data: {
      'post_id': postId,
      'user_id': userId,
      'content': content,
      if (parentId != null) 'parent_id': parentId,
    });
    if (response.statusCode == 201) {
      return response.data;
    } else {
      throw Exception(response.data['error'] ?? 'Failed to add comment');
    }
  }

  Future<void> updateComment(int commentId, int userId, String newContent) async {
    final response = await _dio.put('/comment/$commentId', data: {'user_id': userId, 'content': newContent});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Update failed');
    }
  }

  Future<void> deleteComment(int commentId, int userId) async {
    final response = await _dio.delete('/comment/$commentId', queryParameters: {'user_id': userId});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Delete failed');
    }
  }

  Future<Map<String, dynamic>> toggleCommentLike(int commentId, int userId) async {
    final response = await _dio.post('/comment/$commentId/like', data: {'user_id': userId});
    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data;
    } else {
      throw Exception('Failed to toggle comment like');
    }
  }

  // Direct Messages
  Future<Map<String, dynamic>> sendDirectMessage(int senderId, int receiverId, String content, File? media) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/direct/send'));
    request.fields['sender_id'] = senderId.toString();
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = content;
    if (media != null) {
      request.files.add(await http.MultipartFile.fromPath('media', media.path));
    }
    var response = await request.send();
    var respStr = await response.stream.bytesToString();
    if (response.statusCode == 201) {
      return jsonDecode(respStr);
    } else {
      throw Exception(jsonDecode(respStr)['error'] ?? 'Failed to send message');
    }
  }

  Future<List<DirectMessage>> getDirectMessages(int userId, int otherId, {int page = 1, int perPage = 20}) async {
    final response = await _dio.get('/direct/messages/$userId', queryParameters: {
      'other_id': otherId,
      'page': page,
      'per_page': perPage,
    });
    if (response.statusCode == 200) {
      List<dynamic> data = response.data;
      return data.map((e) => DirectMessage.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load messages');
    }
  }

  // Group Messages
  Future<Map<String, dynamic>> sendGroupMessage(int senderId, String content, File? media) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/group/send'));
    request.fields['sender_id'] = senderId.toString();
    request.fields['content'] = content;
    if (media != null) {
      request.files.add(await http.MultipartFile.fromPath('media', media.path));
    }
    var response = await request.send();
    var respStr = await response.stream.bytesToString();
    if (response.statusCode == 201) {
      return jsonDecode(respStr);
    } else {
      throw Exception(jsonDecode(respStr)['error'] ?? 'Failed to send group message');
    }
  }

  Future<List<GroupMessage>> getGroupMessages({int page = 1, int perPage = 20}) async {
    final response = await _dio.get('/group/messages', queryParameters: {'page': page, 'per_page': perPage});
    if (response.statusCode == 200) {
      List<dynamic> data = response.data;
      return data.map((e) => GroupMessage.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load group messages');
    }
  }
}

// -----------------------------------------------------------------------------
// Providers
// -----------------------------------------------------------------------------
class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final SharedPreferences _prefs;

  User? _currentUser;
  int? _userId;
  String? _username;

  User? get currentUser => _currentUser;
  int? get userId => _userId;
  String? get username => _username;

  AuthProvider(this._prefs) {
    _loadSavedUser();
  }

  Future<void> _loadSavedUser() async {
    _userId = _prefs.getInt('user_id');
    _username = _prefs.getString('username');
    if (_userId != null) {
      try {
        _currentUser = await _apiService.getProfile(_userId!);
      } catch (e) {
        logout();
      }
    }
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    try {
      final data = await _apiService.login(username, password);
      int userId = data['user_id'];
      await _prefs.setInt('user_id', userId);
      await _prefs.setString('username', username);
      _userId = userId;
      _username = username;
      _currentUser = await _apiService.getProfile(userId);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> register(String username, String password, String bio, File? profileImage) async {
    try {
      final data = await _apiService.register(username, password, bio, profileImage);
      int userId = data['user_id'];
      await _prefs.setInt('user_id', userId);
      await _prefs.setString('username', username);
      _userId = userId;
      _username = username;
      _currentUser = await _apiService.getProfile(userId);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    await _prefs.remove('user_id');
    await _prefs.remove('username');
    _userId = null;
    _username = null;
    _currentUser = null;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (_userId != null) {
      _currentUser = await _apiService.getProfile(_userId!);
      notifyListeners();
    }
  }

  Future<void> updateProfile(String? bio, File? profileImage) async {
    if (_userId != null) {
      await _apiService.updateProfile(_userId!, bio, profileImage);
      await refreshProfile();
    }
  }
}

class ThemeProvider extends ChangeNotifier {
  final SharedPreferences _prefs;
  static const String _key = 'isDarkMode';
  bool _isDarkMode;

  ThemeProvider(this._prefs) : _isDarkMode = _prefs.getBool(_key) ?? false;

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _prefs.setBool(_key, _isDarkMode);
    notifyListeners();
  }
}

class PostProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<Post> _posts = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;

  List<Post> get posts => _posts;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> loadPosts({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _posts.clear();
    }
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      final newPosts = await _apiService.getPosts(page: _currentPage);
      if (newPosts.isEmpty) {
        _hasMore = false;
      } else {
        _posts.addAll(newPosts);
        _currentPage++;
      }
    } catch (e) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggleLike(int postId, int userId) async {
    try {
      final result = await _apiService.toggleLike(postId, userId);
      final index = _posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        _posts[index].likedByUser = result['liked'] ?? false;
        _posts[index].likesCount += (result['liked'] ? 1 : -1);
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> toggleBookmark(int postId, int userId) async {
    try {
      final result = await _apiService.toggleBookmark(postId, userId);
      final index = _posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        _posts[index].bookmarkedByUser = result['bookmarked'] ?? false;
        notifyListeners();
      }
    } catch (e) {}
  }

  void updatePostInList(Post updatedPost) {
    final index = _posts.indexWhere((p) => p.id == updatedPost.id);
    if (index != -1) {
      _posts[index] = updatedPost;
      notifyListeners();
    }
  }

  void removePost(int postId) {
    _posts.removeWhere((p) => p.id == postId);
    notifyListeners();
  }
}

class CommentProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<Comment> _comments = [];
  Post? _post;

  List<Comment> get comments => _comments;
  Post? get post => _post;

  Future<void> loadComments(int postId, {int? userId}) async {
    try {
      final data = await _apiService.fetchPost(postId, userId: userId);
      _post = Post.fromJson(data);
      final List<dynamic> commentsJson = data['comments'] ?? [];
      _comments = commentsJson.map((c) => Comment.fromJson(c)).toList();
      notifyListeners();
    } catch (e) {}
  }

  Future<void> addComment(int postId, int userId, String content, {int? parentId}) async {
    try {
      await _apiService.addComment(postId, userId, content, parentId: parentId);
      await loadComments(postId, userId: userId);
    } catch (e) {}
  }

  Future<void> toggleLike(int commentId, int userId) async {
    try {
      final result = await _apiService.toggleCommentLike(commentId, userId);
      final index = _comments.indexWhere((c) => c.id == commentId);
      if (index != -1) {
        _comments[index].likedByUser = result['liked'] ?? false;
        _comments[index].likesCount += (result['liked'] ? 1 : -1);
        notifyListeners();
      }
    } catch (e) {}
  }
}

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  List<DirectMessage> _messages = [];
  List<GroupMessage> _groupMessages = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;

  List<DirectMessage> get messages => _messages;
  List<GroupMessage> get groupMessages => _groupMessages;

  Future<void> loadDirectMessages(int userId, int otherId, {bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _messages.clear();
    }
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      final newMessages = await _apiService.getDirectMessages(userId, otherId, page: _currentPage);
      if (newMessages.isEmpty) {
        _hasMore = false;
      } else {
        _messages.addAll(newMessages);
        _currentPage++;
      }
    } catch (e) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendDirectMessage(int senderId, int receiverId, String content, File? media) async {
    try {
      await _apiService.sendDirectMessage(senderId, receiverId, content, media);
      await loadDirectMessages(senderId, receiverId, refresh: true);
    } catch (e) {}
  }

  Future<void> loadGroupMessages({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _groupMessages.clear();
    }
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      final newMessages = await _apiService.getGroupMessages(page: _currentPage);
      if (newMessages.isEmpty) {
        _hasMore = false;
      } else {
        _groupMessages.addAll(newMessages);
        _currentPage++;
      }
    } catch (e) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendGroupMessage(int senderId, String content, File? media) async {
    try {
      await _apiService.sendGroupMessage(senderId, content, media);
      await loadGroupMessages(refresh: true);
    } catch (e) {}
  }
}

// -----------------------------------------------------------------------------
// Main App & Themes
// -----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  const MyApp({Key? key, required this.prefs}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(prefs)),
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
        ChangeNotifierProvider(create: (_) => PostProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Tweeter Client',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            theme: ThemeData(
              brightness: Brightness.light,
              primarySwatch: Colors.blue,
              fontFamily: GoogleFonts.poppins().fontFamily,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              primarySwatch: Colors.blue,
              fontFamily: GoogleFonts.poppins().fontFamily,
            ),
            home: Consumer<AuthProvider>(
              builder: (context, auth, _) {
                if (auth.userId != null) {
                  return MainScreen();
                }
                return LoginScreen();
              },
            ),
            routes: {
              '/login': (_) => LoginScreen(),
              '/main': (_) => MainScreen(),
            },
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Login & Register Screens
// -----------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: Duration(milliseconds: 300));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        if (_isLogin) {
          await auth.login(_usernameController.text, _passwordController.text);
        } else {
          // For simplicity, we only implement login; registration can be added similarly
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please use login')));
          setState(() => _isLoading = false);
          return;
        }
        Navigator.pushReplacementNamed(context, '/main');
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade300, Colors.purple.shade300],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tweeter', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold)),
                      SizedBox(height: 20),
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person)),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock)),
                        obscureText: true,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      SizedBox(height: 24),
                      if (_isLoading)
                        CircularProgressIndicator()
                      else
                        Column(
                          children: [
                            ElevatedButton(
                              onPressed: _submit,
                              style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
                              child: Text(_isLogin ? 'Login' : 'Register'),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                  _animationController.forward(from: 0);
                                });
                              },
                              child: Text(_isLogin ? 'Need an account? Register' : 'Already have an account? Login'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Main Screen with Bottom Navigation Bar
// -----------------------------------------------------------------------------
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final pages = [
    FeedPage(),
    ExplorePage(),
    ProfilePage(),
    ChatsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UploadPostPage()),
        ),
        child: Icon(Icons.add),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Feed Page
// -----------------------------------------------------------------------------
class FeedPage extends StatefulWidget {
  @override
  _FeedPageState createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PostProvider>(context, listen: false).loadPosts(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      Provider.of<PostProvider>(context, listen: false).loadPosts();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final postProvider = Provider.of<PostProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    return RefreshIndicator(
      onRefresh: () async => postProvider.loadPosts(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: postProvider.posts.length + (postProvider.hasMore ? 1 : 0),
        itemBuilder: (ctx, index) {
          if (index == postProvider.posts.length) {
            return Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
          }
          final post = postProvider.posts[index];
          return PostCard(post: post, userId: auth.userId!);
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Post Card Widget
// -----------------------------------------------------------------------------
class PostCard extends StatelessWidget {
  final Post post;
  final int userId;

  const PostCard({Key? key, required this.post, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PostDetailPage(postId: post.id)),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: post.userProfileImage != null
                    ? CachedNetworkImageProvider('$baseUrl/${post.userProfileImage}')
                    : null,
                child: post.userProfileImage == null ? Icon(Icons.person) : null,
              ),
              title: Row(
                children: [
                  Text(post.username),
                  if (post.userIsBlue)
                    Icon(Icons.verified, color: Colors.blue, size: 16),
                ],
              ),
              subtitle: Text(DateFormat.yMMMd().add_jm().format(post.createdAt)),
            ),
            if (post.caption != null && post.caption!.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(post.caption!),
              ),
            if (post.mediaType == 'image' && post.mediaPath != null)
              Container(
                height: 200,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: '$baseUrl/${post.mediaPath}',
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Center(child: CircularProgressIndicator()),
                  errorWidget: (_, __, ___) => Icon(Icons.broken_image),
                ),
              ),
            if (post.mediaType == 'video' && post.thumbnailPath != null)
              Container(
                height: 200,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CachedNetworkImage(
                      imageUrl: '$baseUrl/${post.thumbnailPath}',
                      fit: BoxFit.cover,
                    ),
                    Icon(Icons.play_circle_filled, size: 50, color: Colors.white),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(post.likedByUser ? Icons.favorite : Icons.favorite_border, color: post.likedByUser ? Colors.red : null),
                    onPressed: () => Provider.of<PostProvider>(context, listen: false).toggleLike(post.id, userId),
                  ),
                  Text('${post.likesCount}'),
                  SizedBox(width: 16),
                  IconButton(
                    icon: Icon(Icons.comment),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailPage(postId: post.id))),
                  ),
                  Text('${post.commentsCount}'),
                  Spacer(),
                  IconButton(
                    icon: Icon(post.bookmarkedByUser ? Icons.bookmark : Icons.bookmark_border),
                    onPressed: () => Provider.of<PostProvider>(context, listen: false).toggleBookmark(post.id, userId),
                  ),
                  IconButton(
                    icon: Icon(Icons.share),
                    onPressed: () => _sharePost(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sharePost(BuildContext context) {
    // share post link or content
  }
}

// -----------------------------------------------------------------------------
// Post Detail Page
// -----------------------------------------------------------------------------
class PostDetailPage extends StatefulWidget {
  final int postId;
  const PostDetailPage({Key? key, required this.postId}) : super(key: key);

  @override
  _PostDetailPageState createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _commentController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = Provider.of<AuthProvider>(context, listen: false).userId;
      Provider.of<CommentProvider>(context, listen: false).loadComments(widget.postId, userId: userId);
    });
  }

  void _addComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() => _isLoading = true);
    await Provider.of<CommentProvider>(context, listen: false).addComment(
      widget.postId,
      auth.userId!,
      _commentController.text.trim(),
    );
    _commentController.clear();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final commentProvider = Provider.of<CommentProvider>(context);
    final post = commentProvider.post;
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Post')),
      body: post == null
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      PostCard(post: post, userId: auth.userId!),
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Comments', style: Theme.of(context).textTheme.titleMedium),
                      ),
                      ...commentProvider.comments.map((c) => CommentTile(comment: c, userId: auth.userId!)),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: 'Write a comment...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _isLoading ? Container(width: 24, height: 24, child: CircularProgressIndicator()) : Icon(Icons.send),
                        onPressed: _addComment,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Comment Tile
// -----------------------------------------------------------------------------
class CommentTile extends StatelessWidget {
  final Comment comment;
  final int userId;

  const CommentTile({Key? key, required this.comment, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: comment.userProfileImage != null
                ? CachedNetworkImageProvider('$baseUrl/${comment.userProfileImage}')
                : null,
            child: comment.userProfileImage == null ? Icon(Icons.person, size: 16) : null,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.username, style: TextStyle(fontWeight: FontWeight.bold)),
                    if (comment.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 14),
                    SizedBox(width: 8),
                    Text(DateFormat.Hm().format(comment.createdAt)),
                  ],
                ),
                Text(comment.content),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: Icon(comment.likedByUser ? Icons.favorite : Icons.favorite_border, size: 16),
                onPressed: () => Provider.of<CommentProvider>(context, listen: false).toggleLike(comment.id, userId),
              ),
              Text('${comment.likesCount}', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Explore Page (placeholder)
// -----------------------------------------------------------------------------
class ExplorePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Explore Page (coming soon)'));
  }
}

// -----------------------------------------------------------------------------
// Profile Page
// -----------------------------------------------------------------------------
class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsPage())),
          ),
        ],
      ),
      body: auth.currentUser == null
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: auth.currentUser!.profileImage != null
                        ? CachedNetworkImageProvider('$baseUrl/${auth.currentUser!.profileImage}')
                        : null,
                    child: auth.currentUser!.profileImage == null ? Icon(Icons.person, size: 50) : null,
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(auth.currentUser!.username, style: Theme.of(context).textTheme.titleLarge),
                      if (auth.currentUser!.isBlue) Icon(Icons.verified, color: Colors.blue),
                    ],
                  ),
                  if (auth.currentUser!.bio != null) Text(auth.currentUser!.bio!),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStat('Posts', auth.currentUser!.postsCount),
                      _buildStat('Bookmarks', auth.currentUser!.bookmarksCount),
                    ],
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _editProfile(context),
                    child: Text('Edit Profile'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStat(String label, int count) {
    return Column(
      children: [
        Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label),
      ],
    );
  }

  void _editProfile(BuildContext context) {
    // show dialog to edit bio and profile image
  }
}

// -----------------------------------------------------------------------------
// Settings Page
// -----------------------------------------------------------------------------
class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('Dark Mode'),
            value: themeProvider.isDarkMode,
            onChanged: (_) => themeProvider.toggleTheme(),
          ),
          ListTile(
            title: Text('Logout'),
            leading: Icon(Icons.logout),
            onTap: () {
              authProvider.logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Chats Page (Direct & Group)
// -----------------------------------------------------------------------------
class ChatsPage extends StatefulWidget {
  @override
  _ChatsPageState createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chats'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Direct'),
            Tab(text: 'Group'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          DirectChatsList(),
          GroupChatPage(),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Direct Chats List (placeholder)
// -----------------------------------------------------------------------------
class DirectChatsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text('Direct messages list (to be implemented)'));
  }
}

// -----------------------------------------------------------------------------
// Group Chat Page
// -----------------------------------------------------------------------------
class GroupChatPage extends StatefulWidget {
  @override
  _GroupChatPageState createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).loadGroupMessages(refresh: true);
    });
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final chat = Provider.of<ChatProvider>(context, listen: false);
    await chat.sendGroupMessage(auth.userId!, _messageController.text.trim(), null);
    _messageController.clear();
    _scrollController.animateTo(0, duration: Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            controller: _scrollController,
            itemCount: chatProvider.groupMessages.length,
            itemBuilder: (ctx, index) {
              final msg = chatProvider.groupMessages[index];
              final isMe = msg.senderId == auth.userId;
              return Container(
                margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    if (!isMe)
                      CircleAvatar(
                        radius: 16,
                        backgroundImage: msg.userProfileImage != null
                            ? CachedNetworkImageProvider('$baseUrl/${msg.userProfileImage}')
                            : null,
                        child: msg.userProfileImage == null ? Icon(Icons.person, size: 16) : null,
                      ),
                    Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.blue : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Row(
                              children: [
                                Text(msg.username, style: TextStyle(fontWeight: FontWeight.bold)),
                                if (msg.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 14),
                              ],
                            ),
                          if (msg.content != null) Text(msg.content!),
                          if (msg.mediaType != null) Text('[${msg.mediaType}]'),
                          Text(DateFormat.Hm().format(msg.createdAt), style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Upload Post Page
// -----------------------------------------------------------------------------
class UploadPostPage extends StatefulWidget {
  @override
  _UploadPostPageState createState() => _UploadPostPageState();
}

class _UploadPostPageState extends State<UploadPostPage> {
  final _captionController = TextEditingController();
  File? _selectedMedia;
  String? _mediaType;
  double _uploadProgress = 0;
  bool _uploading = false;

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      _selectedMedia = File(pickedFile.path);
      _mediaType = 'image';
      _openEditor();
    } else {
      final video = await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        _selectedMedia = File(video.path);
        _mediaType = 'video';
        _openEditor();
      }
    }
    setState(() {});
  }

  void _openEditor() async {
    if (_mediaType == 'image') {
      CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: _selectedMedia!.path,
        aspectRatioPresets: [
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio3x2,
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9
        ],
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.deepOrange,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop Image',
          ),
        ],
      );
      if (cropped != null) {
        setState(() {
          _selectedMedia = File(cropped.path);
        });
      }
    } else if (_mediaType == 'video') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video editing not fully implemented')));
    }
  }

  Future<void> _upload() async {
    if (_selectedMedia == null) return;
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final api = ApiService();
    try {
      await api.uploadPost(
        auth.userId!,
        _captionController.text,
        _selectedMedia,
        onProgress: (sent, total) {
          setState(() {
            _uploadProgress = sent / total;
          });
        },
      );
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Post uploaded')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Upload Post')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            if (_selectedMedia != null)
              _mediaType == 'image'
                  ? Image.file(_selectedMedia!, height: 200)
                  : Container(height: 200, color: Colors.black, child: Center(child: Text('Video selected'))),
            ElevatedButton(
              onPressed: _pickMedia,
              child: Text('Select Media'),
            ),
            TextField(
              controller: _captionController,
              decoration: InputDecoration(labelText: 'Caption'),
            ),
            SizedBox(height: 20),
            if (_uploading)
              Column(
                children: [
                  LinearProgressIndicator(value: _uploadProgress),
                  Text('${(_uploadProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ElevatedButton(
              onPressed: _uploading ? null : _upload,
              child: Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}