import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gal/gal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:photo_view/photo_view.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:animations/animations.dart';

// ----------------------------------------------------------------------------
// Configuration
// ----------------------------------------------------------------------------
const String baseUrl = 'https://tweeter.runflare.run';

// ----------------------------------------------------------------------------
// Models
// ----------------------------------------------------------------------------
class User {
  final int id;
  final String username;
  final String? bio;
  final String? profileImage;
  final bool isBlue;
  final DateTime createdAt;
  int postsCount;
  int bookmarksCount;

  User({
    required this.id,
    required this.username,
    this.bio,
    this.profileImage,
    required this.isBlue,
    required this.createdAt,
    this.postsCount = 0,
    this.bookmarksCount = 0,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      bio: json['bio'],
      profileImage: json['profile_image'],
      isBlue: json['is_blue'] == 1,
      createdAt: DateTime.parse(json['created_at']),
      postsCount: json['posts_count'] ?? 0,
      bookmarksCount: json['bookmarks_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'bio': bio,
        'profile_image': profileImage,
        'is_blue': isBlue ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };
}

class Post {
  final int id;
  final int userId;
  final String caption;
  final String mediaType; // 'image', 'video', 'audio', 'file', 'text'
  final String? mediaPath;
  final String? thumbnailPath;
  final DateTime createdAt;
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  int likesCount;
  int commentsCount;
  bool likedByUser;
  bool bookmarkedByUser;
  List<Comment>? comments; // used in detail

  Post({
    required this.id,
    required this.userId,
    required this.caption,
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
    this.comments,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      userId: json['user_id'],
      caption: json['caption'] ?? '',
      mediaType: json['media_type'],
      mediaPath: json['media_path'],
      thumbnailPath: json['thumbnail_path'],
      createdAt: DateTime.parse(json['created_at']),
      username: json['username'],
      userProfileImage: json['profile_image'],
      userIsBlue: json['is_blue'] == 1,
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
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  int likesCount;
  bool likedByUser;
  List<Comment>? replies; // we'll build tree

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
    this.replies,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      postId: json['post_id'],
      userId: json['user_id'],
      parentId: json['parent_id'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
      username: json['username'],
      userProfileImage: json['profile_image'],
      userIsBlue: json['is_blue'] == 1,
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
      id: json['id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      content: json['content'],
      mediaType: json['media_type'],
      mediaPath: json['media_path'],
      createdAt: DateTime.parse(json['created_at']),
      senderUsername: json['sender_username'],
      senderProfileImage: json['sender_profile_image'],
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
      id: json['id'],
      senderId: json['sender_id'],
      content: json['content'],
      mediaType: json['media_type'],
      mediaPath: json['media_path'],
      createdAt: DateTime.parse(json['created_at']),
      username: json['username'],
      userProfileImage: json['profile_image'],
      userIsBlue: json['is_blue'] == 1,
    );
  }
}

// ----------------------------------------------------------------------------
// API Service
// ----------------------------------------------------------------------------
class ApiService {
  final Dio _dio = Dio(BaseOptions(baseUrl: baseUrl));
  final String? userId;

  ApiService({this.userId}) {
    _dio.interceptors.add(LogInterceptor(responseBody: true));
  }

  // Helper to add userId to form data or query params
  Future<Map<String, dynamic>> _addUserId(Map<String, dynamic> data) async {
    if (userId != null) {
      data['user_id'] = userId;
    } else {
      // try to get from prefs
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getInt('user_id');
      if (storedId != null) data['user_id'] = storedId;
    }
    return data;
  }

  // Auth
  Future<Map<String, dynamic>> register(
      String username, String password, String bio, File? profileImage) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/register'));
    request.fields['username'] = username;
    request.fields['password'] = password;
    request.fields['bio'] = bio;
    if (profileImage != null) {
      request.files.add(await http.MultipartFile.fromPath('profile_image', profileImage.path));
    }
    var response = await request.send();
    var responseBody = await response.stream.bytesToString();
    if (response.statusCode == 201) {
      return jsonDecode(responseBody);
    } else {
      throw Exception(responseBody);
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(response.body);
    }
  }

  Future<User> getProfile(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/profile/$userId'));
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception(response.body);
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
      throw Exception(await response.stream.bytesToString());
    }
  }

  // Posts
  Future<List<Post>> getPosts({int page = 1, int perPage = 10}) async {
    final response = await http.get(Uri.parse('$baseUrl/posts?page=$page&per_page=$perPage'));
    if (response.statusCode == 200) {
      List list = jsonDecode(response.body);
      return list.map((e) => Post.fromJson(e)).toList();
    } else {
      throw Exception(response.body);
    }
  }

  Future<Post> getPost(int postId, {int? userId}) async {
    final uri = userId != null
        ? Uri.parse('$baseUrl/post/$postId?user_id=$userId')
        : Uri.parse('$baseUrl/post/$postId');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      Map<String, dynamic> json = jsonDecode(response.body);
      // parse comments
      if (json['comments'] != null) {
        List commentsJson = json['comments'];
        List<Comment> comments = commentsJson.map((c) => Comment.fromJson(c)).toList();
        // build reply tree
        Map<int, Comment> commentMap = {};
        List<Comment> topComments = [];
        for (var c in comments) {
          c.replies = [];
          commentMap[c.id] = c;
          if (c.parentId == null) {
            topComments.add(c);
          } else {
            commentMap[c.parentId]?.replies?.add(c);
          }
        }
        json['comments'] = topComments;
      }
      return Post.fromJson(json);
    } else {
      throw Exception(response.body);
    }
  }

  Future<Post> uploadPost({
    required int userId,
    required String caption,
    File? media,
    void Function(int, int)? onProgress, // sent, total
  }) async {
    var uri = Uri.parse('$baseUrl/upload');
    var request = http.MultipartRequest('POST', uri);
    request.fields['user_id'] = userId.toString();
    request.fields['caption'] = caption;
    if (media != null) {
      var multipartFile = await http.MultipartFile.fromPath('media', media.path);
      request.files.add(multipartFile);
    }
    // Progress is not directly supported by http.MultipartRequest; we use Dio for progress elsewhere.
    var response = await request.send();
    if (response.statusCode == 201) {
      var responseBody = await response.stream.bytesToString();
      var json = jsonDecode(responseBody);
      // We need to fetch the actual post? The response only contains message and post_id.
      // We'll fetch the post separately.
      return await getPost(json['post_id'], userId: userId);
    } else {
      throw Exception(await response.stream.bytesToString());
    }
  }

  Future<void> deletePost(int postId, int userId) async {
    final response = await http.delete(Uri.parse('$baseUrl/post/$postId?user_id=$userId'));
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }

  Future<void> updatePost(int postId, int userId, String newCaption) async {
    final response = await http.put(
      Uri.parse('$baseUrl/post/$postId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'caption': newCaption}),
    );
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }

  // Likes
  Future<bool> toggleLike(int postId, int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/like'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'post_id': postId, 'user_id': userId}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      Map<String, dynamic> json = jsonDecode(response.body);
      return json['liked'];
    } else {
      throw Exception(response.body);
    }
  }

  // Bookmarks
  Future<bool> toggleBookmark(int postId, int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/bookmark'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'post_id': postId, 'user_id': userId}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      Map<String, dynamic> json = jsonDecode(response.body);
      return json['bookmarked'];
    } else {
      throw Exception(response.body);
    }
  }

  Future<List<Post>> getBookmarks(int userId) async {
    final response = await http.get(Uri.parse('$baseUrl/bookmarks/$userId'));
    if (response.statusCode == 200) {
      List list = jsonDecode(response.body);
      return list.map((e) => Post.fromJson(e)).toList();
    } else {
      throw Exception(response.body);
    }
  }

  // Comments
  Future<Comment> addComment(int postId, int userId, String content, {int? parentId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/comment'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'post_id': postId,
        'user_id': userId,
        'content': content,
        'parent_id': parentId,
      }),
    );
    if (response.statusCode == 201) {
      Map<String, dynamic> json = jsonDecode(response.body);
      // We need to fetch the full comment? The response only contains comment_id.
      // For simplicity, we'll return a dummy comment; caller should refresh.
      return Comment(
        id: json['comment_id'],
        postId: postId,
        userId: userId,
        content: content,
        parentId: parentId,
        createdAt: DateTime.now(),
        username: '', // will be filled on refresh
        userIsBlue: false,
      );
    } else {
      throw Exception(response.body);
    }
  }

  Future<void> updateComment(int commentId, int userId, String newContent) async {
    final response = await http.put(
      Uri.parse('$baseUrl/comment/$commentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'content': newContent}),
    );
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }

  Future<void> deleteComment(int commentId, int userId) async {
    final response = await http.delete(Uri.parse('$baseUrl/comment/$commentId?user_id=$userId'));
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
  }

  Future<bool> toggleCommentLike(int commentId, int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/comment/$commentId/like'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      Map<String, dynamic> json = jsonDecode(response.body);
      return json['liked'];
    } else {
      throw Exception(response.body);
    }
  }

  // Direct Messages
  Future<void> sendDirectMessage({
    required int senderId,
    required int receiverId,
    String content = '',
    File? media,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/direct/send'));
    request.fields['sender_id'] = senderId.toString();
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = content;
    if (media != null) {
      request.files.add(await http.MultipartFile.fromPath('media', media.path));
    }
    var response = await request.send();
    if (response.statusCode != 201) {
      throw Exception(await response.stream.bytesToString());
    }
  }

  Future<List<DirectMessage>> getDirectMessages(int userId, int otherId, {int page = 1, int perPage = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/direct/messages/$userId?other_id=$otherId&page=$page&per_page=$perPage'),
    );
    if (response.statusCode == 200) {
      List list = jsonDecode(response.body);
      return list.map((e) => DirectMessage.fromJson(e)).toList();
    } else {
      throw Exception(response.body);
    }
  }

  // Group Messages
  Future<void> sendGroupMessage({
    required int senderId,
    String content = '',
    File? media,
  }) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/group/send'));
    request.fields['sender_id'] = senderId.toString();
    request.fields['content'] = content;
    if (media != null) {
      request.files.add(await http.MultipartFile.fromPath('media', media.path));
    }
    var response = await request.send();
    if (response.statusCode != 201) {
      throw Exception(await response.stream.bytesToString());
    }
  }

  Future<List<GroupMessage>> getGroupMessages({int page = 1, int perPage = 20}) async {
    final response = await http.get(Uri.parse('$baseUrl/group/messages?page=$page&per_page=$perPage'));
    if (response.statusCode == 200) {
      List list = jsonDecode(response.body);
      return list.map((e) => GroupMessage.fromJson(e)).toList();
    } else {
      throw Exception(response.body);
    }
  }
}

// ----------------------------------------------------------------------------
// Providers
// ----------------------------------------------------------------------------
class UserProvider extends ChangeNotifier {
  User? _currentUser;
  int? _userId;
  String? _username;

  User? get currentUser => _currentUser;
  int? get userId => _userId;
  String? get username => _username;

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('user_id');
    _username = prefs.getString('username');
    if (_userId != null) {
      try {
        _currentUser = await ApiService().getProfile(_userId!);
      } catch (e) {
        // maybe token expired? clear
        await logout();
      }
    }
    notifyListeners();
  }

  Future<void> login(int userId, String username) async {
    _userId = userId;
    _username = username;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
    await prefs.setString('username', username);
    _currentUser = await ApiService().getProfile(userId);
    notifyListeners();
  }

  Future<void> logout() async {
    _userId = null;
    _username = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('username');
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (_userId != null) {
      _currentUser = await ApiService().getProfile(_userId!);
      notifyListeners();
    }
  }
}

class ThemeProvider extends ChangeNotifier {
  bool _isDark = false;
  bool get isDark => _isDark;

  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  void toggleTheme() {
    _isDark = !_isDark;
    notifyListeners();
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool('isDark') ?? false;
    notifyListeners();
  }

  Future<void> saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', _isDark);
  }
}

// ----------------------------------------------------------------------------
// Main App
// ----------------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.storage.request();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()..loadUser()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..loadTheme()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Tweeter',
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: themeProvider.themeMode,
            home: Consumer<UserProvider>(
              builder: (context, userProvider, _) {
                if (userProvider.userId == null) {
                  return LoginScreen();
                }
                return MainScreen();
              },
            ),
            routes: {
              '/login': (_) => LoginScreen(),
              '/register': (_) => RegisterScreen(),
            },
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Login & Register Screens
// ----------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: Duration(milliseconds: 800));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final res = await api.login(_usernameController.text, _passwordController.text);
      final userId = res['user_id'];
      await context.read<UserProvider>().login(userId, _usernameController.text);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: EdgeInsets.all(24),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Welcome Back', style: Theme.of(context).textTheme.headlineMedium),
                      SizedBox(height: 24),
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(labelText: 'Username'),
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(labelText: 'Password'),
                        obscureText: true,
                        validator: (v) => v!.isEmpty ? 'Required' : null,
                      ),
                      SizedBox(height: 24),
                      if (_isLoading) CircularProgressIndicator(),
                      if (!_isLoading)
                        ElevatedButton(
                          onPressed: _login,
                          child: Text('Login'),
                          style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 45)),
                        ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/register');
                        },
                        child: Text('Create new account'),
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

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bioController = TextEditingController();
  File? _profileImage;
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _profileImage = File(picked.path));
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.register(
        _usernameController.text,
        _passwordController.text,
        _bioController.text,
        _profileImage,
      );
      // Auto login
      final loginRes = await api.login(_usernameController.text, _passwordController.text);
      final userId = loginRes['user_id'];
      await context.read<UserProvider>().login(userId, _usernameController.text);
      Navigator.pop(context); // go back to main
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Register')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 50,
                  backgroundImage: _profileImage != null
                      ? FileImage(_profileImage!)
                      : null,
                  child: _profileImage == null ? Icon(Icons.camera_alt, size: 50) : null,
                ),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Username'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: InputDecoration(labelText: 'Bio'),
                maxLines: 3,
              ),
              SizedBox(height: 24),
              if (_isLoading) CircularProgressIndicator(),
              if (!_isLoading)
                ElevatedButton(
                  onPressed: _register,
                  child: Text('Register'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Main Screen (with bottom navigation)
// ----------------------------------------------------------------------------
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _screens = [
    HomeFeedScreen(),
    BookmarksScreen(),
    DirectMessagesListScreen(),
    GroupChatScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Bookmarks'),
          BottomNavigationBarItem(icon: Icon(Icons.mail), label: 'DMs'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Group'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Home Feed Screen
// ----------------------------------------------------------------------------
class HomeFeedScreen extends StatefulWidget {
  @override
  _HomeFeedScreenState createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final List<Post> _posts = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchPosts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPosts() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService(userId: context.read<UserProvider>().userId?.toString());
      final newPosts = await api.getPosts(page: _page);
      if (newPosts.isEmpty) _hasMore = false;
      setState(() {
        _posts.addAll(newPosts);
        _page++;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchPosts();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _posts.clear();
      _page = 1;
      _hasMore = true;
    });
    await _fetchPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CreatePostScreen()),
              ).then((_) => _refresh());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _posts.length + (_isLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _posts.length) {
              return Center(child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ));
            }
            return PostCard(post: _posts[index]);
          },
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Post Card Widget
// ----------------------------------------------------------------------------
class PostCard extends StatefulWidget {
  final Post post;

  const PostCard({Key? key, required this.post}) : super(key: key);

  @override
  _PostCardState createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post _post;
  bool _isLiked = false;
  bool _isBookmarked = false;
  int _likesCount = 0;
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _isLiked = widget.post.likedByUser;
    _isBookmarked = widget.post.bookmarkedByUser;
    _likesCount = widget.post.likesCount;
  }

  Future<void> _toggleLike() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
    try {
      final liked = await _api.toggleLike(_post.id, userId);
      // if server state differs, we could revert, but assume success
    } catch (e) {
      // revert
      setState(() {
        _isLiked = !_isLiked;
        _likesCount += _isLiked ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _toggleBookmark() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    setState(() => _isBookmarked = !_isBookmarked);
    try {
      await _api.toggleBookmark(_post.id, userId);
    } catch (e) {
      setState(() => _isBookmarked = !_isBookmarked);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openPost() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: _post.id),
      ),
    ).then((_) {
      // refresh if needed
    });
  }

  Future<void> _downloadMedia() async {
    if (_post.mediaPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No media to download')));
      return;
    }

    try {
      // Request permission if needed
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }

      final url = '$baseUrl/${_post.mediaPath}';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_post.mediaPath!.split('/').last}');
      await Dio().download(url, file.path);

      if (_post.mediaType == 'image') {
        await Gal.putImage(file.path);
      } else if (_post.mediaType == 'video') {
        await Gal.putVideo(file.path);
      } else {
        // For audio/files, you can use share or another method
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File downloaded to ${file.path}')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to gallery')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: _openPost,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: _post.userProfileImage != null
                    ? CachedNetworkImageProvider('$baseUrl/${_post.userProfileImage}')
                    : null,
                child: _post.userProfileImage == null ? Icon(Icons.person) : null,
              ),
              title: Row(
                children: [
                  Text(_post.username),
                  if (_post.userIsBlue)
                    Icon(Icons.verified, color: Colors.blue, size: 16),
                ],
              ),
              subtitle: Text(DateFormat.yMMMd().add_jm().format(_post.createdAt)),
            ),
            if (_post.caption.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(_post.caption),
              ),
            if (_post.mediaType != 'text' && _post.thumbnailPath != null)
              Padding(
                padding: EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: '$baseUrl/${_post.thumbnailPath}',
                    placeholder: (_, __) => Container(height: 200, color: Colors.grey[300]),
                    errorWidget: (_, __, ___) => Container(height: 200, color: Colors.grey[300], child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, color: _isLiked ? Colors.red : null),
                  onPressed: _toggleLike,
                ),
                Text('$_likesCount'),
                IconButton(
                  icon: Icon(Icons.comment),
                  onPressed: _openPost,
                ),
                Text('${_post.commentsCount}'),
                IconButton(
                  icon: Icon(_isBookmarked ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: _toggleBookmark,
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.download),
                  onPressed: _downloadMedia,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Create Post Screen with Media Editing
// ----------------------------------------------------------------------------
class CreatePostScreen extends StatefulWidget {
  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _captionController = TextEditingController();
  File? _mediaFile;
  String? _mediaType; // 'image', 'video'
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickMedia() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.image),
            title: Text('Image'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await _picker.pickImage(source: ImageSource.gallery);
              if (picked != null) {
                _editImage(File(picked.path));
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.video_library),
            title: Text('Video'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await _picker.pickVideo(source: ImageSource.gallery);
              if (picked != null) {
                _editVideo(File(picked.path));
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.insert_drive_file),
            title: Text('File (document, audio)'),
            onTap: () async {
              Navigator.pop(context);
              final result = await FilePicker.platform.pickFiles();
              if (result != null) {
                setState(() {
                  _mediaFile = File(result.files.single.path!);
                  _mediaType = 'file'; // or audio based on extension
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editImage(File imageFile) async {
  final cropped = await ImageCropper().cropImage(
    sourcePath: imageFile.path,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Crop Image',
        toolbarColor: Colors.blue,
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
      _mediaFile = File(cropped.path);
      _mediaType = 'image';
    });
  }
}

  Future<void> _editVideo(File videoFile) async {
    // For simplicity, we skip video trimming to avoid ffmpeg dependency issues.
    setState(() {
      _mediaFile = videoFile;
      _mediaType = 'video';
    });
  }

  Future<void> _upload() async {
    if (_captionController.text.isEmpty && _mediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add something')));
      return;
    }
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      // Use Dio for progress
      final dio = Dio();
      final formData = FormData.fromMap({
        'user_id': userId,
        'caption': _captionController.text,
        if (_mediaFile != null)
          'media': await MultipartFile.fromFile(_mediaFile!.path, filename: _mediaFile!.path.split('/').last),
      });
      await dio.post(
        '$baseUrl/upload',
        data: formData,
        onSendProgress: (sent, total) {
          setState(() {
            _uploadProgress = sent / total;
          });
        },
      );
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Post'),
        actions: [
          if (!_isUploading)
            TextButton(
              onPressed: _upload,
              child: Text('Post'),
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _captionController,
              decoration: InputDecoration(labelText: 'Caption'),
              maxLines: 3,
            ),
            SizedBox(height: 16),
            if (_mediaFile != null)
              Stack(
                alignment: Alignment.center,
                children: [
                  if (_mediaType == 'image')
                    Image.file(_mediaFile!, height: 200, fit: BoxFit.cover),
                  if (_mediaType == 'video')
                    Container(height: 200, child: Center(child: Text('Video selected'))),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => setState(() {
                        _mediaFile = null;
                        _mediaType = null;
                      }),
                    ),
                  ),
                ],
              ),
            if (_mediaFile == null)
              ElevatedButton.icon(
                onPressed: _pickMedia,
                icon: Icon(Icons.attach_file),
                label: Text('Add media'),
              ),
            if (_isUploading)
              LinearProgressIndicator(value: _uploadProgress),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Post Detail Screen
// ----------------------------------------------------------------------------
class PostDetailScreen extends StatefulWidget {
  final int postId;

  const PostDetailScreen({Key? key, required this.postId}) : super(key: key);

  @override
  _PostDetailScreenState createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Future<Post> _postFuture;
  final TextEditingController _commentController = TextEditingController();
  int? _replyingTo; // comment id for reply

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final userId = context.read<UserProvider>().userId;
    setState(() {
      _postFuture = ApiService().getPost(widget.postId, userId: userId);
    });
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    try {
      await ApiService().addComment(
        widget.postId,
        userId,
        _commentController.text,
        parentId: _replyingTo,
      );
      _commentController.clear();
      setState(() => _replyingTo = null);
      _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Post')),
      body: FutureBuilder<Post>(
        future: _postFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final post = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    PostCard(post: post),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Comments', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    if (post.comments != null)
                      ...post.comments!.map((c) => CommentTile(
                        comment: c,
                        onReply: (cid) {
                          setState(() => _replyingTo = cid);
                        },
                        onRefresh: _refresh,
                      )),
                  ],
                ),
              ),
              if (_replyingTo != null)
                Container(
                  color: Colors.grey[200],
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Text('Replying...'),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => setState(() => _replyingTo = null),
                      ),
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
                          hintText: 'Add a comment...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send),
                      onPressed: _addComment,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Comment Tile
// ----------------------------------------------------------------------------
class CommentTile extends StatefulWidget {
  final Comment comment;
  final Function(int) onReply;
  final VoidCallback onRefresh;

  const CommentTile({Key? key, required this.comment, required this.onReply, required this.onRefresh});

  @override
  _CommentTileState createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  late Comment _comment;
  bool _isLiked = false;
  int _likesCount = 0;

  @override
  void initState() {
    super.initState();
    _comment = widget.comment;
    _isLiked = _comment.likedByUser;
    _likesCount = _comment.likesCount;
  }

  Future<void> _toggleLike() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
    });
    try {
      await ApiService().toggleCommentLike(_comment.id, userId);
    } catch (e) {
      setState(() {
        _isLiked = !_isLiked;
        _likesCount += _isLiked ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: _comment.parentId != null ? 32.0 : 8.0, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: _comment.userProfileImage != null
                  ? CachedNetworkImageProvider('$baseUrl/${_comment.userProfileImage}')
                  : null,
              child: _comment.userProfileImage == null ? Icon(Icons.person) : null,
            ),
            title: Row(
              children: [
                Text(_comment.username),
                if (_comment.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 16),
              ],
            ),
            subtitle: Text(_comment.content),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, size: 16),
                  onPressed: _toggleLike,
                ),
                Text('$_likesCount'),
                IconButton(
                  icon: Icon(Icons.reply, size: 16),
                  onPressed: () => widget.onReply(_comment.id),
                ),
              ],
            ),
          ),
          if (_comment.replies != null)
            ..._comment.replies!.map((reply) => CommentTile(
              comment: reply,
              onReply: widget.onReply,
              onRefresh: widget.onRefresh,
            )),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Bookmarks Screen
// ----------------------------------------------------------------------------
class BookmarksScreen extends StatefulWidget {
  @override
  _BookmarksScreenState createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Post> _bookmarks = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchBookmarks();
  }

  Future<void> _fetchBookmarks() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    setState(() => _isLoading = true);
    try {
      final posts = await ApiService().getBookmarks(userId);
      setState(() => _bookmarks = posts);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Bookmarks')),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _bookmarks.length,
              itemBuilder: (_, i) => PostCard(post: _bookmarks[i]),
            ),
    );
  }
}

// ----------------------------------------------------------------------------
// Direct Messages List Screen (shows conversations)
// ----------------------------------------------------------------------------
// For simplicity, we'll just show a list of users you've chatted with.
// But API doesn't provide that; we'd need to fetch messages and group.
// We'll implement a basic version: a list of other users, and on tap go to chat.
class DirectMessagesListScreen extends StatefulWidget {
  @override
  _DirectMessagesListScreenState createState() => _DirectMessagesListScreenState();
}

class _DirectMessagesListScreenState extends State<DirectMessagesListScreen> {
  List<User> _users = []; // dummy, we need to fetch users from somewhere. For now, just a placeholder.
  // In a real app, you'd have a separate endpoint to get conversations.
  // We'll just show a list of all users (maybe from search) but that's not implemented.
  // Instead, we'll provide a button to start a new conversation by entering user id.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Direct Messages')),
      body: Center(
        child: Text('To start a chat, go to Profile and select a user.\nOr implement user search.'),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () {
          // show dialog to enter other user id
          _startNewChat();
        },
      ),
    );
  }

  void _startNewChat() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Enter user ID'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () {
              final otherId = int.tryParse(controller.text);
              if (otherId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DirectChatScreen(otherUserId: otherId),
                  ),
                );
              }
              Navigator.pop(context);
            },
            child: Text('Start'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Direct Chat Screen
// ----------------------------------------------------------------------------
class DirectChatScreen extends StatefulWidget {
  final int otherUserId;

  const DirectChatScreen({Key? key, required this.otherUserId}) : super(key: key);

  @override
  _DirectChatScreenState createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  List<DirectMessage> _messages = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  File? _mediaFile;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final msgs = await ApiService().getDirectMessages(userId, widget.otherUserId, page: _page);
      if (msgs.isEmpty) _hasMore = false;
      setState(() {
        _messages.insertAll(0, msgs.reversed.toList()); // because newest last? We want oldest first? Actually we'll sort.
        _page++;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    if (_messageController.text.isEmpty && _mediaFile == null) return;
    try {
      await ApiService().sendDirectMessage(
        senderId: userId,
        receiverId: widget.otherUserId,
        content: _messageController.text,
        media: _mediaFile,
      );
      _messageController.clear();
      setState(() => _mediaFile = null);
      // refresh messages
      setState(() {
        _messages.clear();
        _page = 1;
        _hasMore = true;
      });
      _fetchMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _mediaFile = File(result.files.single.path!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat with ${widget.otherUserId}')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              reverse: true, // to show latest at bottom
              itemBuilder: (_, index) {
                if (index == 0 && _isLoading) return Center(child: CircularProgressIndicator());
                final msg = _messages[_messages.length - 1 - index]; // reverse index
                final isMe = msg.senderId == context.read<UserProvider>().userId;
                return MessageBubble(message: msg, isMe: isMe);
              },
            ),
          ),
          if (_mediaFile != null)
            Container(
              color: Colors.grey[200],
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: Text('Media: ${_mediaFile!.path.split('/').last}')),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => setState(() => _mediaFile = null),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file),
                  onPressed: _pickMedia,
                ),
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
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Message Bubble (for direct and group)
// ----------------------------------------------------------------------------
class MessageBubble extends StatelessWidget {
  final dynamic message; // can be DirectMessage or GroupMessage
  final bool isMe;

  const MessageBubble({Key? key, required this.message, required this.isMe}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (!isMe && message is GroupMessage)
            Text((message as GroupMessage).username),
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.content != null && message.content!.isNotEmpty)
                  Text(message.content!),
                if (message.mediaType != null)
                  GestureDetector(
                    onTap: () {
                      // open media
                      final url = '$baseUrl/${message.mediaPath}';
                      // TODO: show full screen
                    },
                    child: Container(
                      width: 150,
                      height: 100,
                      color: Colors.black12,
                      child: Center(child: Text(message.mediaType!)),
                    ),
                  ),
              ],
            ),
          ),
          Text(DateFormat.Hm().format(message.createdAt)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Group Chat Screen
// ----------------------------------------------------------------------------
class GroupChatScreen extends StatefulWidget {
  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  List<GroupMessage> _messages = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  File? _mediaFile;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final msgs = await ApiService().getGroupMessages(page: _page);
      if (msgs.isEmpty) _hasMore = false;
      setState(() {
        _messages.insertAll(0, msgs.reversed.toList());
        _page++;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    if (_messageController.text.isEmpty && _mediaFile == null) return;
    try {
      await ApiService().sendGroupMessage(
        senderId: userId,
        content: _messageController.text,
        media: _mediaFile,
      );
      _messageController.clear();
      setState(() => _mediaFile = null);
      setState(() {
        _messages.clear();
        _page = 1;
        _hasMore = true;
      });
      _fetchMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _mediaFile = File(result.files.single.path!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Group Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              reverse: true,
              itemBuilder: (_, index) {
                if (index == 0 && _isLoading) return Center(child: CircularProgressIndicator());
                final msg = _messages[_messages.length - 1 - index];
                final isMe = msg.senderId == context.read<UserProvider>().userId;
                return MessageBubble(message: msg, isMe: isMe);
              },
            ),
          ),
          if (_mediaFile != null)
            Container(
              color: Colors.grey[200],
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: Text('Media: ${_mediaFile!.path.split('/').last}')),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => setState(() => _mediaFile = null),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file),
                  onPressed: _pickMedia,
                ),
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
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Profile Screen
// ----------------------------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  final TextEditingController _bioController = TextEditingController();
  File? _newProfileImage;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() {
    final user = context.read<UserProvider>().currentUser;
    if (user != null) {
      _bioController.text = user.bio ?? '';
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _newProfileImage = File(picked.path));
    }
  }

  Future<void> _saveProfile() async {
    final userId = context.read<UserProvider>().userId;
    if (userId == null) return;
    try {
      await ApiService().updateProfile(
        userId,
        _bioController.text,
        _newProfileImage,
      );
      await context.read<UserProvider>().refreshProfile();
      setState(() {
        _isEditing = false;
        _newProfileImage = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().currentUser;
    if (user == null) {
      return Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await context.read<UserProvider>().logout();
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: _newProfileImage != null
                      ? FileImage(_newProfileImage!) as ImageProvider
                      : (user.profileImage != null
                          ? CachedNetworkImageProvider('$baseUrl/${user.profileImage}')
                          : null),
                  child: user.profileImage == null && _newProfileImage == null
                      ? Icon(Icons.person, size: 50)
                      : null,
                ),
                if (_isEditing)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: IconButton(
                        icon: Icon(Icons.camera_alt, color: Colors.white),
                        onPressed: _pickImage,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 16),
          if (!_isEditing) ...[
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(user.username, style: Theme.of(context).textTheme.titleLarge),
                  if (user.isBlue) Icon(Icons.verified, color: Colors.blue),
                ],
              ),
            ),
            SizedBox(height: 8),
            Center(child: Text(user.bio ?? 'No bio')),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStat('Posts', user.postsCount),
                _buildStat('Bookmarks', user.bookmarksCount),
              ],
            ),
          ] else ...[
            TextFormField(
              controller: _bioController,
              decoration: InputDecoration(labelText: 'Bio'),
              maxLines: 3,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saveProfile,
              child: Text('Save'),
            ),
          ],
          Divider(),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text('Settings'),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, int count) {
    return Column(
      children: [
        Text(count.toString(), style: Theme.of(context).textTheme.titleLarge),
        Text(label),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Settings Screen
// ----------------------------------------------------------------------------
class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('Dark Mode'),
            value: themeProvider.isDark,
            onChanged: (val) {
              themeProvider.toggleTheme();
              themeProvider.saveTheme();
            },
          ),
          // Add more settings as needed
        ],
      ),
    );
  }
}