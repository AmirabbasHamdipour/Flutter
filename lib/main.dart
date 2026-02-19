// main.dart
// A complete Flutter client for the Tweeter Flask server.
// Uses Riverpod for state management, Dio for HTTP, and various packages for media.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

// ---------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------
const String baseUrl = 'https://tweeter.runflare.run';

// ---------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------
class User {
  final int id;
  final String username;
  final String bio;
  final String? profileImage;
  final bool isBlue;
  final DateTime createdAt;
  final int postsCount;
  final int bookmarksCount;

  User({
    required this.id,
    required this.username,
    required this.bio,
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
      bio: json['bio'] ?? '',
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
  // joined fields
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  // computed
  final int likesCount;
  final int commentsCount;
  final bool likedByUser;
  final bool bookmarkedByUser;

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
    required this.likesCount,
    required this.commentsCount,
    required this.likedByUser,
    required this.bookmarkedByUser,
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
  // user info
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  // likes
  final int likesCount;
  final bool likedByUser;
  // replies (filled client-side)
  List<Comment> replies;

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
    required this.likesCount,
    required this.likedByUser,
    List<Comment>? replies,
  }) : replies = replies ?? [];

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
  final String content;
  final String? mediaType;
  final String? mediaPath;
  final DateTime createdAt;
  final String senderUsername;
  final String? senderProfileImage;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
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
      content: json['content'] ?? '',
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
  final String content;
  final String? mediaType;
  final String? mediaPath;
  final DateTime createdAt;
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.content,
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
      content: json['content'] ?? '',
      mediaType: json['media_type'],
      mediaPath: json['media_path'],
      createdAt: DateTime.parse(json['created_at']),
      username: json['username'],
      userProfileImage: json['profile_image'],
      userIsBlue: json['is_blue'] == 1,
    );
  }
}

// ---------------------------------------------------------------------
// API Client & Services
// ---------------------------------------------------------------------
class ApiClient {
  final Dio _dio = Dio(BaseOptions(baseUrl: baseUrl));

  Future<Response> get(String path, {Map<String, dynamic>? query}) async {
    try {
      return await _dio.get(path, queryParameters: query);
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> post(String path, {dynamic data, bool isForm = false}) async {
    try {
      return await _dio.post(path, data: data, options: Options(contentType: isForm ? Headers.formUrlEncodedContentType : Headers.jsonContentType));
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> put(String path, {dynamic data, bool isForm = false}) async {
    try {
      return await _dio.put(path, data: data, options: Options(contentType: isForm ? Headers.formUrlEncodedContentType : Headers.jsonContentType));
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> delete(String path, {Map<String, dynamic>? query}) async {
    try {
      return await _dio.delete(path, queryParameters: query);
    } on DioError catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioError e) {
    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map && data.containsKey('error')) {
        return data['error'];
      }
      return 'Server error: ${e.response!.statusCode}';
    }
    return 'Network error: ${e.message}';
  }
}

// Auth & User API
class AuthApi {
  final ApiClient _client = ApiClient();

  Future<int> register(String username, String password, String bio, File? profileImage) async {
    final form = FormData.fromMap({
      'username': username,
      'password': password,
      'bio': bio,
      if (profileImage != null) 'profile_image': await MultipartFile.fromFile(profileImage.path),
    });
    final res = await _client.post('/register', data: form, isForm: true);
    return res.data['user_id'];
  }

  Future<int> login(String username, String password) async {
    final res = await _client.post('/login', data: {'username': username, 'password': password});
    return res.data['user_id'];
  }

  Future<User> getProfile(int userId) async {
    final res = await _client.get('/profile/$userId');
    return User.fromJson(res.data);
  }

  Future<void> updateProfile(int userId, String bio, File? profileImage) async {
    final form = FormData.fromMap({
      'user_id': userId.toString(),
      'bio': bio,
      if (profileImage != null) 'profile_image': await MultipartFile.fromFile(profileImage.path),
    });
    await _client.put('/profile/$userId', data: form, isForm: true);
  }

  Future<void> giveBlue(String username) async {
    await _client.post('/give_blue/$username');
  }
}

// Post API
class PostApi {
  final ApiClient _client = ApiClient();

  Future<int> createPost(int userId, String caption, File? media) async {
    final form = FormData.fromMap({
      'user_id': userId.toString(),
      'caption': caption,
      if (media != null) 'media': await MultipartFile.fromFile(media.path),
    });
    final res = await _client.post('/upload', data: form, isForm: true);
    return res.data['post_id'];
  }

  Future<List<Post>> getPosts({int page = 1, int perPage = 10}) async {
    final res = await _client.get('/posts', query: {'page': page, 'per_page': perPage});
    return (res.data as List).map((e) => Post.fromJson(e)).toList();
  }

  Future<Map<String, dynamic>> getPost(int postId, {int? userId}) async {
    final res = await _client.get('/post/$postId', query: userId != null ? {'user_id': userId} : null);
    return res.data;
  }

  Future<void> updatePost(int postId, int userId, String caption) async {
    await _client.put('/post/$postId', data: {'user_id': userId, 'caption': caption});
  }

  Future<void> deletePost(int postId, int userId) async {
    await _client.delete('/post/$postId', query: {'user_id': userId});
  }
}

// Comment API
class CommentApi {
  final ApiClient _client = ApiClient();

  Future<int> addComment(int postId, int userId, String content, {int? parentId}) async {
    final res = await _client.post('/comment', data: {
      'post_id': postId,
      'user_id': userId,
      'content': content,
      if (parentId != null) 'parent_id': parentId,
    });
    return res.data['comment_id'];
  }

  Future<void> updateComment(int commentId, int userId, String content) async {
    await _client.put('/comment/$commentId', data: {'user_id': userId, 'content': content});
  }

  Future<void> deleteComment(int commentId, int userId) async {
    await _client.delete('/comment/$commentId', query: {'user_id': userId});
  }

  Future<Map<String, dynamic>> toggleLikeComment(int commentId, int userId) async {
    final res = await _client.post('/comment/$commentId/like', data: {'user_id': userId});
    return res.data;
  }
}

// Like API for posts
class LikeApi {
  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>> toggleLike(int postId, int userId) async {
    final res = await _client.post('/like', data: {'post_id': postId, 'user_id': userId});
    return res.data;
  }
}

// Bookmark API
class BookmarkApi {
  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>> toggleBookmark(int postId, int userId) async {
    final res = await _client.post('/bookmark', data: {'post_id': postId, 'user_id': userId});
    return res.data;
  }

  Future<List<Post>> getBookmarks(int userId) async {
    final res = await _client.get('/bookmarks/$userId');
    return (res.data as List).map((e) => Post.fromJson(e)).toList();
  }
}

// Direct Message API
class DirectMessageApi {
  final ApiClient _client = ApiClient();

  Future<int> sendMessage(int senderId, int receiverId, String content, File? media) async {
    final form = FormData.fromMap({
      'sender_id': senderId.toString(),
      'receiver_id': receiverId.toString(),
      'content': content,
      if (media != null) 'media': await MultipartFile.fromFile(media.path),
    });
    final res = await _client.post('/direct/send', data: form, isForm: true);
    return res.data['message_id'];
  }

  Future<List<DirectMessage>> getMessages(int userId, int otherId, {int page = 1, int perPage = 20}) async {
    final res = await _client.get('/direct/messages/$userId', query: {'other_id': otherId, 'page': page, 'per_page': perPage});
    return (res.data as List).map((e) => DirectMessage.fromJson(e)).toList();
  }
}

// Group Message API
class GroupMessageApi {
  final ApiClient _client = ApiClient();

  Future<int> sendMessage(int senderId, String content, File? media) async {
    final form = FormData.fromMap({
      'sender_id': senderId.toString(),
      'content': content,
      if (media != null) 'media': await MultipartFile.fromFile(media.path),
    });
    final res = await _client.post('/group/send', data: form, isForm: true);
    return res.data['message_id'];
  }

  Future<List<GroupMessage>> getMessages({int page = 1, int perPage = 20}) async {
    final res = await _client.get('/group/messages', query: {'page': page, 'per_page': perPage});
    return (res.data as List).map((e) => GroupMessage.fromJson(e)).toList();
  }
}

// ---------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final authApiProvider = Provider<AuthApi>((ref) => AuthApi());
final postApiProvider = Provider<PostApi>((ref) => PostApi());
final commentApiProvider = Provider<CommentApi>((ref) => CommentApi());
final likeApiProvider = Provider<LikeApi>((ref) => LikeApi());
final bookmarkApiProvider = Provider<BookmarkApi>((ref) => BookmarkApi());
final directMessageApiProvider = Provider<DirectMessageApi>((ref) => DirectMessageApi());
final groupMessageApiProvider = Provider<GroupMessageApi>((ref) => GroupMessageApi());

// Current user ID
final currentUserIdProvider = StateProvider<int?>((ref) => null);

// Current user profile
final currentUserProvider = FutureProvider<User>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) throw Exception('Not logged in');
  final api = ref.watch(authApiProvider);
  return api.getProfile(userId);
});

// Feed posts with pagination
final feedProvider = StateNotifierProvider<FeedNotifier, AsyncValue<List<Post>>>((ref) {
  return FeedNotifier(ref.read(postApiProvider), ref.read(currentUserIdProvider));
});

class FeedNotifier extends StateNotifier<AsyncValue<List<Post>>> {
  final PostApi _api;
  final int? _currentUserId;
  int _page = 1;
  bool _hasMore = true;

  FeedNotifier(this._api, this._currentUserId) : super(const AsyncValue.loading()) {
    loadMore();
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    try {
      final newPosts = await _api.getPosts(page: _page, perPage: 10);
      if (newPosts.isEmpty) {
        _hasMore = false;
      } else {
        _page++;
        state = AsyncValue.data([...state.value ?? [], ...newPosts]);
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void refresh() {
    _page = 1;
    _hasMore = true;
    state = const AsyncValue.loading();
    loadMore();
  }
}

// Bookmarks
final bookmarksProvider = FutureProvider<List<Post>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) throw Exception('Not logged in');
  final api = ref.watch(bookmarkApiProvider);
  return api.getBookmarks(userId);
});

// Group messages with pagination
final groupMessagesProvider = StateNotifierProvider<GroupMessagesNotifier, AsyncValue<List<GroupMessage>>>((ref) {
  return GroupMessagesNotifier(ref.read(groupMessageApiProvider));
});

class GroupMessagesNotifier extends StateNotifier<AsyncValue<List<GroupMessage>>> {
  final GroupMessageApi _api;
  int _page = 1;
  bool _hasMore = true;

  GroupMessagesNotifier(this._api) : super(const AsyncValue.loading()) {
    loadMore();
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    try {
      final newMessages = await _api.getMessages(page: _page, perPage: 20);
      if (newMessages.isEmpty) {
        _hasMore = false;
      } else {
        _page++;
        // prepend for reverse order (oldest first)
        state = AsyncValue.data([...newMessages.reversed, ...state.value ?? []]);
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void addMessage(GroupMessage message) {
    state = AsyncValue.data([message, ...state.value ?? []]);
  }
}

// Direct chat messages
final directMessagesProvider = FutureProvider.family<List<DirectMessage>, int>((ref, otherId) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) throw Exception('Not logged in');
  final api = ref.watch(directMessageApiProvider);
  return api.getMessages(userId, otherId, page: 1, perPage: 50); // load all for simplicity
});

// ---------------------------------------------------------------------
// Utility Functions
// ---------------------------------------------------------------------
Future<File?> pickImage() async {
  final picker = ImagePicker();
  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
  return image != null ? File(image.path) : null;
}

Future<File?> pickFile() async {
  final result = await FilePicker.platform.pickFiles();
  if (result != null) {
    return File(result.files.single.path!);
  }
  return null;
}

String getMediaUrl(String? path) {
  if (path == null) return '';
  return '$baseUrl/static/$path';
}

Widget buildThumbnail(String? thumbnailPath, String mediaType) {
  if (thumbnailPath == null) return const SizedBox();
  final url = getMediaUrl(thumbnailPath);
  if (mediaType == 'image') {
    return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover);
  } else if (mediaType == 'video') {
    return Stack(
      alignment: Alignment.center,
      children: [
        CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
        const Icon(Icons.play_circle_fill, color: Colors.white, size: 50),
      ],
    );
  }
  return const SizedBox();
}

void showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ---------------------------------------------------------------------
// Screens
// ---------------------------------------------------------------------

// Splash Screen
class SplashScreen extends ConsumerStatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId != null) {
      ref.read(currentUserIdProvider.notifier).state = userId;
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// Login Screen
class LoginScreen extends ConsumerStatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = ref.read(authApiProvider);
      final userId = await api.login(_usernameController.text, _passwordController.text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_id', userId);
      ref.read(currentUserIdProvider.notifier).state = userId;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      showSnackBar(context, e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(controller: _usernameController, decoration: InputDecoration(labelText: 'Username'), validator: (v) => v!.isEmpty ? 'Required' : null),
              TextFormField(controller: _passwordController, decoration: InputDecoration(labelText: 'Password'), obscureText: true, validator: (v) => v!.isEmpty ? 'Required' : null),
              SizedBox(height: 20),
              _isLoading ? CircularProgressIndicator() : ElevatedButton(onPressed: _login, child: Text('Login')),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: Text('Create account')),
            ],
          ),
        ),
      ),
    );
  }
}

// Register Screen
class RegisterScreen extends ConsumerStatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bioController = TextEditingController();
  File? _profileImage;
  bool _isLoading = false;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = ref.read(authApiProvider);
      await api.register(_usernameController.text, _passwordController.text, _bioController.text, _profileImage);
      showSnackBar(context, 'Registration successful. Please login.');
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      showSnackBar(context, e.toString());
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
              TextFormField(controller: _usernameController, decoration: InputDecoration(labelText: 'Username'), validator: (v) => v!.isEmpty ? 'Required' : null),
              TextFormField(controller: _passwordController, decoration: InputDecoration(labelText: 'Password'), obscureText: true, validator: (v) => v!.isEmpty ? 'Required' : null),
              TextFormField(controller: _bioController, decoration: InputDecoration(labelText: 'Bio'), maxLines: 3),
              SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      final file = await pickImage();
                      setState(() => _profileImage = file);
                    },
                    child: Text('Pick Profile Image'),
                  ),
                  if (_profileImage != null) Text(' Image selected'),
                ],
              ),
              SizedBox(height: 20),
              _isLoading ? CircularProgressIndicator() : ElevatedButton(onPressed: _register, child: Text('Register')),
            ],
          ),
        ),
      ),
    );
  }
}

// Home Screen with Bottom Navigation
class HomeScreen extends ConsumerStatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    FeedScreen(),
    BookmarksScreen(),
    GroupChatScreen(),
    ProfileScreen(isOwn: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Bookmarks'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Group'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.pushNamed(context, '/create_post'),
              child: Icon(Icons.add),
            )
          : null,
    );
  }
}

// Feed Screen
class FeedScreen extends ConsumerStatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(feedProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Feed')),
      body: feedState.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (posts) {
          return RefreshIndicator(
            onRefresh: () async => ref.read(feedProvider.notifier).refresh(),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: posts.length + 1,
              itemBuilder: (ctx, i) {
                if (i < posts.length) {
                  return PostCard(post: posts[i]);
                } else {
                  return Center(child: CircularProgressIndicator());
                }
              },
            ),
          );
        },
      ),
    );
  }
}

// Post Card Widget
class PostCard extends ConsumerWidget {
  final Post post;
  const PostCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    return Card(
      margin: EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: post.userProfileImage != null
                  ? CachedNetworkImageProvider(getMediaUrl(post.userProfileImage))
                  : null,
              child: post.userProfileImage == null ? Text(post.username[0]) : null,
            ),
            title: Row(
              children: [
                Text(post.username),
                if (post.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 16),
              ],
            ),
            trailing: IconButton(
              icon: Icon(post.bookmarkedByUser ? Icons.bookmark : Icons.bookmark_border),
              onPressed: userId == null ? null : () async {
                try {
                  await ref.read(bookmarkApiProvider).toggleBookmark(post.id, userId);
                  ref.refresh(feedProvider);
                } catch (e) {
                  showSnackBar(context, e.toString());
                }
              },
            ),
          ),
          if (post.caption.isNotEmpty) Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(post.caption),
          ),
          if (post.mediaType != 'text') ...[
            SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/post/${post.id}', arguments: post.id),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: buildThumbnail(post.thumbnailPath, post.mediaType),
              ),
            ),
          ],
          Row(
            children: [
              IconButton(
                icon: Icon(post.likedByUser ? Icons.favorite : Icons.favorite_border, color: post.likedByUser ? Colors.red : null),
                onPressed: userId == null ? null : () async {
                  try {
                    await ref.read(likeApiProvider).toggleLike(post.id, userId);
                    ref.refresh(feedProvider);
                  } catch (e) {
                    showSnackBar(context, e.toString());
                  }
                },
              ),
              Text('${post.likesCount}'),
              IconButton(
                icon: Icon(Icons.comment),
                onPressed: () => Navigator.pushNamed(context, '/post/${post.id}', arguments: post.id),
              ),
              Text('${post.commentsCount}'),
            ],
          ),
        ],
      ),
    );
  }
}

// Post Detail Screen
class PostDetailScreen extends ConsumerStatefulWidget {
  final int postId;
  const PostDetailScreen({required this.postId});

  @override
  _PostDetailScreenState createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  late Future<Map<String, dynamic>> _postFuture;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _postFuture = ref.read(postApiProvider).getPost(widget.postId, userId: ref.read(currentUserIdProvider));
  }

  void _refreshPost() {
    setState(() {
      _postFuture = ref.read(postApiProvider).getPost(widget.postId, userId: ref.read(currentUserIdProvider));
    });
  }

  Future<void> _addComment({int? parentId}) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    try {
      await ref.read(commentApiProvider).addComment(widget.postId, userId, content, parentId: parentId);
      _commentController.clear();
      _refreshPost();
    } catch (e) {
      showSnackBar(context, e.toString());
    }
  }

  List<Comment> _buildCommentTree(List<Comment> flat) {
    final map = <int, Comment>{};
    final roots = <Comment>[];
    for (var c in flat) {
      map[c.id] = c;
    }
    for (var c in flat) {
      if (c.parentId != null && map.containsKey(c.parentId)) {
        map[c.parentId]!.replies.add(c);
      } else {
        roots.add(c);
      }
    }
    return roots;
  }

  Widget _buildCommentTile(Comment comment) {
    return Padding(
      padding: EdgeInsets.only(left: comment.parentId != null ? 32 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: comment.userProfileImage != null ? CachedNetworkImageProvider(getMediaUrl(comment.userProfileImage)) : null,
              child: comment.userProfileImage == null ? Text(comment.username[0]) : null,
            ),
            title: Row(
              children: [
                Text(comment.username),
                if (comment.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 16),
              ],
            ),
            subtitle: Text(comment.content),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(comment.likedByUser ? Icons.favorite : Icons.favorite_border, size: 16),
                  onPressed: () async {
                    final userId = ref.read(currentUserIdProvider);
                    if (userId == null) return;
                    try {
                      await ref.read(commentApiProvider).toggleLikeComment(comment.id, userId);
                      _refreshPost();
                    } catch (e) {
                      showSnackBar(context, e.toString());
                    }
                  },
                ),
                Text('${comment.likesCount}'),
                IconButton(
                  icon: Icon(Icons.reply, size: 16),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text('Reply to ${comment.username}'),
                        content: TextField(controller: _commentController, autofocus: true),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
                          TextButton(
                            onPressed: () {
                              _addComment(parentId: comment.id);
                              Navigator.pop(context);
                            },
                            child: Text('Reply'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          ...comment.replies.map(_buildCommentTile).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Post')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _postFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          final post = Post.fromJson(data);
          final comments = (data['comments'] as List).map((e) => Comment.fromJson(e)).toList();
          final commentTree = _buildCommentTree(comments);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    PostCard(post: post),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    ...commentTree.map(_buildCommentTile).toList(),
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
                        decoration: InputDecoration(hintText: 'Add a comment...'),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send),
                      onPressed: () => _addComment(),
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

// Create Post Screen
class CreatePostScreen extends ConsumerStatefulWidget {
  @override
  _CreatePostScreenState createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _captionController = TextEditingController();
  File? _media;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Create Post')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _captionController, decoration: InputDecoration(labelText: 'Caption'), maxLines: 3),
            SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final file = await pickImage();
                    setState(() => _media = file);
                  },
                  child: Text('Pick Image'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    final file = await pickFile();
                    setState(() => _media = file);
                  },
                  child: Text('Pick File'),
                ),
              ],
            ),
            if (_media != null) Text('Selected: ${_media!.path.split('/').last}'),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: () async {
                      if (userId == null) return;
                      setState(() => _isLoading = true);
                      try {
                        await ref.read(postApiProvider).createPost(userId, _captionController.text, _media);
                        Navigator.pop(context);
                      } catch (e) {
                        showSnackBar(context, e.toString());
                      } finally {
                        setState(() => _isLoading = false);
                      }
                    },
                    child: Text('Post'),
                  ),
          ],
        ),
      ),
    );
  }
}

// Profile Screen (can be own or other)
class ProfileScreen extends ConsumerStatefulWidget {
  final bool isOwn;
  final int? userId; // if not own
  const ProfileScreen({this.isOwn = false, this.userId});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late Future<User> _userFuture;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() {
    final targetId = widget.isOwn ? ref.read(currentUserIdProvider) : widget.userId;
    if (targetId == null) return;
    _userFuture = ref.read(authApiProvider).getProfile(targetId);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          if (widget.isOwn)
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: () => Navigator.pushNamed(context, '/edit_profile'),
            ),
        ],
      ),
      body: FutureBuilder<User>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final user = snapshot.data!;
          return Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: user.profileImage != null ? CachedNetworkImageProvider(getMediaUrl(user.profileImage)) : null,
                  child: user.profileImage == null ? Text(user.username[0], style: TextStyle(fontSize: 40)) : null,
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(user.username, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    if (user.isBlue) Icon(Icons.verified, color: Colors.blue, size: 24),
                  ],
                ),
                Text(user.bio),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat('Posts', user.postsCount),
                    _buildStat('Bookmarks', user.bookmarksCount),
                  ],
                ),
                if (!widget.isOwn && currentUserId != null)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/direct_chat', arguments: user.id);
                    },
                    child: Text('Message'),
                  ),
                if (widget.isOwn)
                  ElevatedButton(
                    onPressed: () {
                      // Admin: give blue to someone
                      _showGiveBlueDialog();
                    },
                    child: Text('Give Blue Tick (Admin)'),
                  ),
              ],
            ),
          );
        },
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

  void _showGiveBlueDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Give Blue Tick'),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: 'Username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(authApiProvider).giveBlue(controller.text);
                showSnackBar(context, 'Blue tick given');
                Navigator.pop(context);
              } catch (e) {
                showSnackBar(context, e.toString());
              }
            },
            child: Text('Give'),
          ),
        ],
      ),
    );
  }
}

// Edit Profile Screen
class EditProfileScreen extends ConsumerStatefulWidget {
  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _bioController = TextEditingController();
  File? _newImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    ref.read(currentUserProvider).whenData((user) => _bioController.text = user.bio);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Edit Profile')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _bioController, decoration: InputDecoration(labelText: 'Bio'), maxLines: 3),
            SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final file = await pickImage();
                    setState(() => _newImage = file);
                  },
                  child: Text('Change Profile Image'),
                ),
                if (_newImage != null) Text(' New image selected'),
              ],
            ),
            SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: () async {
                      if (userId == null) return;
                      setState(() => _isLoading = true);
                      try {
                        await ref.read(authApiProvider).updateProfile(userId, _bioController.text, _newImage);
                        Navigator.pop(context);
                      } catch (e) {
                        showSnackBar(context, e.toString());
                      } finally {
                        setState(() => _isLoading = false);
                      }
                    },
                    child: Text('Save'),
                  ),
          ],
        ),
      ),
    );
  }
}

// Bookmarks Screen
class BookmarksScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarksProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Bookmarks')),
      body: bookmarksAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (posts) {
          if (posts.isEmpty) return Center(child: Text('No bookmarks'));
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (ctx, i) => PostCard(post: posts[i]),
          );
        },
      ),
    );
  }
}

// Group Chat Screen
class GroupChatScreen extends ConsumerStatefulWidget {
  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();
  File? _media;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 100) {
      ref.read(groupMessagesProvider.notifier).loadMore();
    }
  }

  Future<void> _sendMessage() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final content = _messageController.text.trim();
    if (content.isEmpty && _media == null) return;
    try {
      final api = ref.read(groupMessageApiProvider);
      final msgId = await api.sendMessage(userId, content, _media);
      // Optimistically add message? We'll refresh later but better to add via notifier
      // For simplicity, we'll just refresh the list after a short delay
      _messageController.clear();
      setState(() => _media = null);
      ref.refresh(groupMessagesProvider);
    } catch (e) {
      showSnackBar(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(groupMessagesProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Group Chat')),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) {
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) {
                    final msg = messages[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: msg.userProfileImage != null ? CachedNetworkImageProvider(getMediaUrl(msg.userProfileImage)) : null,
                        child: msg.userProfileImage == null ? Text(msg.username[0]) : null,
                      ),
                      title: Row(
                        children: [
                          Text(msg.username),
                          if (msg.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 16),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.content.isNotEmpty) Text(msg.content),
                          if (msg.mediaType != null) _buildMediaPreview(msg),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file),
                  onPressed: () async {
                    final file = await pickFile();
                    setState(() => _media = file);
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      suffixIcon: _media != null
                          ? IconButton(
                              icon: Icon(Icons.close),
                              onPressed: () => setState(() => _media = null),
                            )
                          : null,
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

  Widget _buildMediaPreview(GroupMessage msg) {
    if (msg.mediaType == 'image') {
      return Image.network(getMediaUrl(msg.mediaPath), height: 100);
    } else if (msg.mediaType == 'video') {
      return Text('[Video] ${msg.mediaPath}');
    } else if (msg.mediaType == 'audio') {
      return Text('[Audio] ${msg.mediaPath}');
    } else {
      return Text('[File] ${msg.mediaPath}');
    }
  }
}

// Direct Chat Screen (simplified - just list messages and send)
class DirectChatScreen extends ConsumerStatefulWidget {
  final int otherId;
  const DirectChatScreen({required this.otherId});

  @override
  _DirectChatScreenState createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen> {
  final _messageController = TextEditingController();
  File? _media;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    final messagesAsync = ref.watch(directMessagesProvider(widget.otherId));
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) {
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) {
                    final msg = messages[i];
                    final isMe = msg.senderId == userId;
                    return ListTile(
                      leading: isMe ? null : CircleAvatar(
                        backgroundImage: msg.senderProfileImage != null ? CachedNetworkImageProvider(getMediaUrl(msg.senderProfileImage)) : null,
                        child: msg.senderProfileImage == null ? Text(msg.senderUsername[0]) : null,
                      ),
                      title: Text(isMe ? 'Me' : msg.senderUsername),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg.content.isNotEmpty) Text(msg.content),
                          if (msg.mediaType != null) _buildMediaPreview(msg),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.attach_file),
                  onPressed: () async {
                    final file = await pickFile();
                    setState(() => _media = file);
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      suffixIcon: _media != null
                          ? IconButton(
                              icon: Icon(Icons.close),
                              onPressed: () => setState(() => _media = null),
                            )
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () async {
                    if (userId == null) return;
                    final content = _messageController.text;
                    try {
                      await ref.read(directMessageApiProvider).sendMessage(userId, widget.otherId, content, _media);
                      _messageController.clear();
                      setState(() => _media = null);
                      ref.refresh(directMessagesProvider(widget.otherId));
                    } catch (e) {
                      showSnackBar(context, e.toString());
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview(DirectMessage msg) {
    if (msg.mediaType == 'image') {
      return Image.network(getMediaUrl(msg.mediaPath), height: 100);
    } else if (msg.mediaType == 'video') {
      return Text('[Video] ${msg.mediaPath}');
    } else if (msg.mediaType == 'audio') {
      return Text('[Audio] ${msg.mediaPath}');
    } else {
      return Text('[File] ${msg.mediaPath}');
    }
  }
}

// ---------------------------------------------------------------------
// App Router
// ---------------------------------------------------------------------
class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => SplashScreen());
      case '/login':
        return MaterialPageRoute(builder: (_) => LoginScreen());
      case '/register':
        return MaterialPageRoute(builder: (_) => RegisterScreen());
      case '/home':
        return MaterialPageRoute(builder: (_) => HomeScreen());
      case '/create_post':
        return MaterialPageRoute(builder: (_) => CreatePostScreen());
      case '/edit_profile':
        return MaterialPageRoute(builder: (_) => EditProfileScreen());
      case '/post/:id':
        final id = settings.arguments as int;
        return MaterialPageRoute(builder: (_) => PostDetailScreen(postId: id));
      case '/direct_chat':
        final otherId = settings.arguments as int;
        return MaterialPageRoute(builder: (_) => DirectChatScreen(otherId: otherId));
      default:
        return MaterialPageRoute(builder: (_) => Scaffold(body: Center(child: Text('No route defined'))));
    }
  }
}

// ---------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Tweeter Client',
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}