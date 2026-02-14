import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

// ------------------- Constants -------------------
const String baseUrl = 'https://tweeter.runflare.run';
const int postsPerPage = 10;

// ------------------- Models ----------------------
class User {
  final int id;
  final String username;
  final String bio;
  final String? profileImage;
  final bool isBlue;

  User({
    required this.id,
    required this.username,
    this.bio = '',
    this.profileImage,
    this.isBlue = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['user_id'] ?? 0,
      username: json['username'] ?? '',
      bio: json['bio'] ?? '',
      profileImage: json['profile_image'],
      isBlue: json['is_blue'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'bio': bio,
    'profile_image': profileImage,
    'is_blue': isBlue ? 1 : 0,
  };
}

class Post {
  final int id;
  final int userId;
  final String caption;
  final String mediaType; // image, video, audio, file
  final String mediaPath;
  final String? thumbnailPath;
  final DateTime createdAt;
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  int likesCount;
  int commentsCount;
  bool likedByUser;
  bool bookmarkedByUser;
  List<Comment>? comments; // for detail view

  Post({
    required this.id,
    required this.userId,
    required this.caption,
    required this.mediaType,
    required this.mediaPath,
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
      comments: json['comments'] != null
          ? (json['comments'] as List).map((c) => Comment.fromJson(c)).toList()
          : null,
    );
  }
}

class Comment {
  final int id;
  final int postId;
  final int userId;
  final String content;
  final DateTime createdAt;
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.username,
    this.userProfileImage,
    required this.userIsBlue,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      postId: json['post_id'],
      userId: json['user_id'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
      username: json['username'],
      userProfileImage: json['profile_image'],
      userIsBlue: json['is_blue'] == 1,
    );
  }
}

// ------------------- API Service -----------------
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
  ));

  // Register
  Future<User> register(String username, String bio, File? profileImage) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/register'));
    request.fields['username'] = username;
    if (bio.isNotEmpty) request.fields['bio'] = bio;
    if (profileImage != null) {
      request.files.add(await http.MultipartFile.fromPath('profile_image', profileImage.path));
    }
    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return User(id: data['user_id'], username: username, bio: bio);
    } else {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Registration failed');
    }
  }

  // Upload post
  Future<int> uploadPost(int userId, String caption, File mediaFile) async {
    String filename = mediaFile.path.split('/').last;
    String mediaType = _getMediaType(filename);
    String url = '$baseUrl/upload';
    var request = http.MultipartRequest('POST', Uri.parse(url));
    request.fields['user_id'] = userId.toString();
    request.fields['caption'] = caption;
    request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 201) {
      return jsonDecode(response.body)['post_id'];
    } else {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Upload failed');
    }
  }

  String _getMediaType(String filename) {
    var ext = filename.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) return 'image';
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'ogg'].contains(ext)) return 'audio';
    return 'file';
  }

  // Get posts with pagination
  Future<List<Post>> getPosts({int page = 1, int? currentUserId}) async {
    var uri = Uri.parse('$baseUrl/posts').replace(queryParameters: {
      'page': page.toString(),
      'per_page': postsPerPage.toString(),
    });
    var response = await _dio.getUri(uri);
    if (response.statusCode == 200) {
      List<dynamic> data = response.data;
      return data.map((json) => Post.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load posts');
    }
  }

  // Get single post with comments and user flags
  Future<Post> getPost(int postId, {int? currentUserId}) async {
    var uri = Uri.parse('$baseUrl/post/$postId');
    if (currentUserId != null) {
      uri = uri.replace(queryParameters: {'user_id': currentUserId.toString()});
    }
    var response = await _dio.getUri(uri);
    if (response.statusCode == 200) {
      return Post.fromJson(response.data);
    } else {
      throw Exception('Post not found');
    }
  }

  // Update post caption
  Future<void> updatePost(int postId, int userId, String newCaption) async {
    var response = await _dio.put('$baseUrl/post/$postId',
        data: {'user_id': userId, 'caption': newCaption});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Update failed');
    }
  }

  // Delete post
  Future<void> deletePost(int postId, int userId) async {
    var response = await _dio.delete('$baseUrl/post/$postId',
        queryParameters: {'user_id': userId});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Delete failed');
    }
  }

  // Add comment
  Future<int> addComment(int postId, int userId, String content) async {
    var response = await _dio.post('$baseUrl/comment',
        data: {'post_id': postId, 'user_id': userId, 'content': content});
    if (response.statusCode == 201) {
      return response.data['comment_id'];
    } else {
      throw Exception(response.data['error'] ?? 'Failed to add comment');
    }
  }

  // Update comment
  Future<void> updateComment(int commentId, int userId, String newContent) async {
    var response = await _dio.put('$baseUrl/comment/$commentId',
        data: {'user_id': userId, 'content': newContent});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Update failed');
    }
  }

  // Delete comment
  Future<void> deleteComment(int commentId, int userId) async {
    var response = await _dio.delete('$baseUrl/comment/$commentId',
        queryParameters: {'user_id': userId});
    if (response.statusCode != 200) {
      throw Exception(response.data['error'] ?? 'Delete failed');
    }
  }

  // Toggle like
  Future<bool> toggleLike(int postId, int userId) async {
    var response = await _dio.post('$baseUrl/like',
        data: {'post_id': postId, 'user_id': userId});
    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['liked'];
    } else {
      throw Exception('Failed to toggle like');
    }
  }

  // Toggle bookmark
  Future<bool> toggleBookmark(int postId, int userId) async {
    var response = await _dio.post('$baseUrl/bookmark',
        data: {'post_id': postId, 'user_id': userId});
    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['bookmarked'];
    } else {
      throw Exception('Failed to toggle bookmark');
    }
  }

  // Get bookmarks
  Future<List<Post>> getBookmarks(int userId) async {
    var response = await _dio.get('$baseUrl/bookmarks/$userId');
    if (response.statusCode == 200) {
      List<dynamic> data = response.data;
      return data.map((json) => Post.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load bookmarks');
    }
  }

  // Download file
  Future<void> downloadFile(String url, String filename) async {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      throw Exception('Storage permission denied');
    }
    Directory? dir = await getExternalStorageDirectory();
    String savePath = '${dir?.path}/$filename';
    await _dio.download(url, savePath);
    OpenFile.open(savePath);
  }
}

// ------------------- Providers -------------------
class AuthProvider extends ChangeNotifier {
  User? _currentUser;
  User? get currentUser => _currentUser;

  AuthProvider() {
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    String? userJson = prefs.getString('user');
    if (userJson != null) {
      _currentUser = User.fromJson(jsonDecode(userJson));
      notifyListeners();
    }
  }

  Future<void> register(String username, String bio, File? profileImage) async {
    try {
      User user = await ApiService().register(username, bio, profileImage);
      _currentUser = user;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(user.toJson()));
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
    notifyListeners();
  }
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    int? index = prefs.getInt('themeMode');
    if (index != null) {
      _themeMode = ThemeMode.values[index];
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }
}

class PostsProvider extends ChangeNotifier {
  List<Post> _posts = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;

  List<Post> get posts => _posts;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Future<void> loadPosts({int? userId, bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _posts = [];
    }
    if (!_hasMore || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      List<Post> newPosts = await ApiService().getPosts(page: _currentPage, currentUserId: userId);
      if (newPosts.isEmpty) {
        _hasMore = false;
      } else {
        _posts.addAll(newPosts);
        _currentPage++;
      }
    } catch (e) {
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updatePostInFeed(Post updatedPost) {
    int index = _posts.indexWhere((p) => p.id == updatedPost.id);
    if (index != -1) {
      _posts[index] = updatedPost;
      notifyListeners();
    }
  }

  void removePostFromFeed(int postId) {
    _posts.removeWhere((p) => p.id == postId);
    notifyListeners();
  }
}

class BookmarksProvider extends ChangeNotifier {
  List<Post> _bookmarks = [];
  bool _isLoading = false;
  List<Post> get bookmarks => _bookmarks;

  Future<void> loadBookmarks(int userId) async {
    _isLoading = true;
    notifyListeners();
    try {
      _bookmarks = await ApiService().getBookmarks(userId);
    } catch (e) {
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggleBookmarkInList(int postId) {
    // If bookmark removed, remove from list
    _bookmarks.removeWhere((p) => p.id == postId);
    notifyListeners();
  }
}

// ------------------- Main App --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PostsProvider()),
        ChangeNotifierProvider(create: (_) => BookmarksProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Tweeter',
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(useMaterial3: true).copyWith(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
              appBarTheme: AppBarTheme(centerTitle: true),
            ),
            darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
            ),
            themeMode: themeProvider.themeMode,
            home: SplashScreen(),
          );
        },
      ),
    );
  }
}

// ------------------- Splash Screen ----------------
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  _navigate() async {
    await Future.delayed(Duration(seconds: 2));
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.currentUser != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RegisterScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Lottie.asset(
          'assets/splash.json', // You need to add a lottie file or use a placeholder
          width: 200,
          height: 200,
        ),
      ),
    );
  }
}

// ------------------- Register Screen --------------
class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
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
      await Provider.of<AuthProvider>(context, listen: false)
          .register(_usernameController.text.trim(), _bioController.text.trim(), _profileImage);
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainScreen()));
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
                  backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                  child: _profileImage == null ? Icon(Icons.camera_alt, size: 40) : null,
                ),
              ),
              SizedBox(height: 20),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: InputDecoration(labelText: 'Bio (optional)', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _register,
                child: _isLoading ? CircularProgressIndicator() : Text('Register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------- Main Screen (Bottom Navigation) ----
class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    FeedScreen(),
    UploadScreen(),
    BookmarksScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Upload'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Bookmarks'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

// ------------------- Feed Screen ------------------
class FeedScreen extends StatefulWidget {
  @override
  _FeedScreenState createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PostsProvider>(context, listen: false).loadPosts(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      Provider.of<PostsProvider>(context, listen: false).loadPosts();
    }
  }

  Future<void> _refresh() async {
    await Provider.of<PostsProvider>(context, listen: false).loadPosts(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Feed'), actions: [
        IconButton(icon: Icon(Icons.refresh), onPressed: _refresh),
      ]),
      body: Consumer<PostsProvider>(
        builder: (context, provider, _) {
          if (provider.posts.isEmpty && provider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: provider.posts.length + (provider.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == provider.posts.length) {
                  return Center(child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  ));
                }
                final post = provider.posts[index];
                return PostCard(post: post, currentUserId: auth.currentUser?.id);
              },
            ),
          );
        },
      ),
    );
  }
}

// ------------------- Post Card Widget ------------
class PostCard extends StatefulWidget {
  final Post post;
  final int? currentUserId;

  PostCard({required this.post, required this.currentUserId});

  @override
  _PostCardState createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post _post;
  bool _isLiking = false;
  bool _isBookmarking = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  Future<void> _toggleLike() async {
    if (_isLiking || widget.currentUserId == null) return;
    setState(() => _isLiking = true);
    try {
      bool liked = await ApiService().toggleLike(_post.id, widget.currentUserId!);
      setState(() {
        _post.likedByUser = liked;
        _post.likesCount += liked ? 1 : -1;
      });
      // Update in provider if needed
      Provider.of<PostsProvider>(context, listen: false).updatePostInFeed(_post);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLiking = false);
    }
  }

  Future<void> _toggleBookmark() async {
    if (_isBookmarking || widget.currentUserId == null) return;
    setState(() => _isBookmarking = true);
    try {
      bool bookmarked = await ApiService().toggleBookmark(_post.id, widget.currentUserId!);
      setState(() => _post.bookmarkedByUser = bookmarked);
      Provider.of<PostsProvider>(context, listen: false).updatePostInFeed(_post);
      // Also update bookmarks list if needed
      if (!bookmarked) {
        Provider.of<BookmarksProvider>(context, listen: false).toggleBookmarkInList(_post.id);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isBookmarking = false);
    }
  }

  void _openPostDetail() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PostDetailScreen(postId: _post.id, currentUserId: widget.currentUserId),
    )).then((updated) {
      if (updated != null && updated is Post) {
        setState(() => _post = updated);
        Provider.of<PostsProvider>(context, listen: false).updatePostInFeed(updated);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.all(8),
      child: InkWell(
        onTap: _openPostDetail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User header
            ListTile(
              leading: CircleAvatar(
                backgroundImage: _post.userProfileImage != null
                    ? CachedNetworkImageProvider('$baseUrl/${_post.userProfileImage}')
                    : null,
                child: _post.userProfileImage == null ? Icon(Icons.person) : null,
              ),
              title: Row(
                children: [
                  Text(_post.username, style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_post.userIsBlue) SizedBox(width: 4),
                  if (_post.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 16),
                ],
              ),
              subtitle: Text(DateFormat.yMMMd().add_jm().format(_post.createdAt)),
            ),
            // Caption
            if (_post.caption.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(_post.caption),
              ),
            // Media preview
            _buildMediaPreview(),
            // Stats and actions
            Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(_post.likedByUser ? Icons.favorite : Icons.favorite_border,
                        color: _post.likedByUser ? Colors.red : null),
                    onPressed: _toggleLike,
                  ),
                  Text('${_post.likesCount}'),
                  SizedBox(width: 16),
                  IconButton(
                    icon: Icon(Icons.comment),
                    onPressed: _openPostDetail,
                  ),
                  Text('${_post.commentsCount}'),
                  Spacer(),
                  IconButton(
                    icon: Icon(_post.bookmarkedByUser ? Icons.bookmark : Icons.bookmark_border),
                    onPressed: _toggleBookmark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    String fullUrl = '$baseUrl/${_post.mediaPath}';
    String? thumbUrl = _post.thumbnailPath != null ? '$baseUrl/${_post.thumbnailPath}' : null;
    switch (_post.mediaType) {
      case 'image':
        return CachedNetworkImage(
          imageUrl: fullUrl,
          placeholder: (_, __) => Container(height: 200, color: Colors.grey[300]),
          errorWidget: (_, __, ___) => Container(height: 200, color: Colors.grey, child: Icon(Icons.broken_image)),
          fit: BoxFit.cover,
          width: double.infinity,
          height: 200,
        );
      case 'video':
        return Stack(
          alignment: Alignment.center,
          children: [
            if (thumbUrl != null)
              CachedNetworkImage(
                imageUrl: thumbUrl,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            else
              Container(height: 200, color: Colors.black, child: Center(child: Icon(Icons.video_library, size: 50))),
            Icon(Icons.play_circle_fill, size: 50, color: Colors.white70),
          ],
        );
      case 'audio':
        return Container(
          height: 60,
          color: Colors.grey[200],
          child: Row(
            children: [
              SizedBox(width: 16),
              Icon(Icons.audio_file, size: 40),
              SizedBox(width: 8),
              Expanded(child: Text('Audio file', overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      default:
        return Container(
          height: 60,
          color: Colors.grey[200],
          child: Row(
            children: [
              SizedBox(width: 16),
              Icon(Icons.insert_drive_file, size: 40),
              SizedBox(width: 8),
              Expanded(child: Text('File', overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
    }
  }
}

// ------------------- Post Detail Screen ----------
class PostDetailScreen extends StatefulWidget {
  final int postId;
  final int? currentUserId;
  PostDetailScreen({required this.postId, required this.currentUserId});

  @override
  _PostDetailScreenState createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Future<Post> _postFuture;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmittingComment = false;

  @override
  void initState() {
    super.initState();
    _refreshPost();
  }

  void _refreshPost() {
    setState(() {
      _postFuture = ApiService().getPost(widget.postId, currentUserId: widget.currentUserId);
    });
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty || widget.currentUserId == null) return;
    setState(() => _isSubmittingComment = true);
    try {
      await ApiService().addComment(widget.postId, widget.currentUserId!, _commentController.text.trim());
      _commentController.clear();
      _refreshPost();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isSubmittingComment = false);
    }
  }

  Future<void> _editComment(Comment comment) async {
    String? newContent = await showDialog<String>(
      context: context,
      builder: (ctx) {
        TextEditingController controller = TextEditingController(text: comment.content);
        return AlertDialog(
          title: Text('Edit Comment'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text('Save')),
          ],
        );
      },
    );
    if (newContent != null && newContent.isNotEmpty && newContent != comment.content) {
      try {
        await ApiService().updateComment(comment.id, widget.currentUserId!, newContent);
        _refreshPost();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteComment(int commentId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Comment'),
        content: Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiService().deleteComment(commentId, widget.currentUserId!);
        _refreshPost();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
                    // Post card (similar to above but without actions)
                    _buildPostDetails(post),
                    Divider(),
                    // Comments section
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Comments', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    ...post.comments?.map((c) => _buildCommentTile(c, post.userId)).toList() ?? [],
                  ],
                ),
              ),
              // Comment input
              if (widget.currentUserId != null)
                Container(
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
                        icon: _isSubmittingComment ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator()) : Icon(Icons.send),
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

  Widget _buildPostDetails(Post post) {
    // Reuse similar layout as PostCard but without interactive elements (or with limited)
    return Card(
      margin: EdgeInsets.all(8),
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
                Text(post.username, style: TextStyle(fontWeight: FontWeight.bold)),
                if (post.userIsBlue) SizedBox(width: 4),
                if (post.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 16),
              ],
            ),
            subtitle: Text(DateFormat.yMMMd().add_jm().format(post.createdAt)),
          ),
          if (post.caption.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(post.caption),
            ),
          _buildMediaFull(post),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(post.likedByUser ? Icons.favorite : Icons.favorite_border,
                      color: post.likedByUser ? Colors.red : null),
                  onPressed: () async {
                    if (widget.currentUserId == null) return;
                    bool liked = await ApiService().toggleLike(post.id, widget.currentUserId!);
                    setState(() {
                      post.likedByUser = liked;
                      post.likesCount += liked ? 1 : -1;
                    });
                  },
                ),
                Text('${post.likesCount}'),
                SizedBox(width: 16),
                Icon(Icons.comment),
                Text('${post.commentsCount}'),
                Spacer(),
                IconButton(
                  icon: Icon(post.bookmarkedByUser ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: () async {
                    if (widget.currentUserId == null) return;
                    bool bookmarked = await ApiService().toggleBookmark(post.id, widget.currentUserId!);
                    setState(() => post.bookmarkedByUser = bookmarked);
                    if (!bookmarked) {
                      Provider.of<BookmarksProvider>(context, listen: false).toggleBookmarkInList(post.id);
                    }
                  },
                ),
                if (post.userId == widget.currentUserId)
                  PopupMenuButton(
                    icon: Icon(Icons.more_vert),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        child: Text('Edit Caption'),
                        onTap: () async {
                          String? newCaption = await showDialog<String>(
                            context: context,
                            builder: (ctx) {
                              TextEditingController c = TextEditingController(text: post.caption);
                              return AlertDialog(
                                title: Text('Edit Caption'),
                                content: TextField(controller: c, autofocus: true),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text('Save')),
                                ],
                              );
                            },
                          );
                          if (newCaption != null) {
                            await ApiService().updatePost(post.id, widget.currentUserId!, newCaption);
                            _refreshPost();
                          }
                        },
                      ),
                      PopupMenuItem(
                        child: Text('Delete Post'),
                        onTap: () async {
                          bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Delete Post'),
                              content: Text('Are you sure?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete')),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ApiService().deletePost(post.id, widget.currentUserId!);
                            Provider.of<PostsProvider>(context, listen: false).removePostFromFeed(post.id);
                            Navigator.pop(context, true); // signal deletion
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaFull(Post post) {
    String fullUrl = '$baseUrl/${post.mediaPath}';
    if (post.mediaType == 'image') {
      return GestureDetector(
        onTap: () => _showFullScreenImage(fullUrl),
        child: CachedNetworkImage(
          imageUrl: fullUrl,
          placeholder: (_, __) => Container(height: 300, color: Colors.grey[300]),
          errorWidget: (_, __, ___) => Container(height: 300, color: Colors.grey, child: Icon(Icons.broken_image)),
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      );
    } else if (post.mediaType == 'video') {
      return Container(
        height: 300,
        child: Chewie(
          controller: ChewieController(
            videoPlayerController: VideoPlayerController.network(fullUrl),
            autoPlay: false,
            looping: false,
            aspectRatio: 16/9,
          ),
        ),
      );
    } else if (post.mediaType == 'audio') {
      return Container(
        height: 80,
        color: Colors.grey[200],
        child: Row(
          children: [
            SizedBox(width: 16),
            Icon(Icons.audio_file, size: 40),
            Expanded(child: Text('Audio Player')),
            IconButton(
              icon: Icon(Icons.play_arrow),
              onPressed: () {
                // Simple audio play
              },
            ),
          ],
        ),
      );
    } else {
      return Container(
        height: 80,
        color: Colors.grey[200],
        child: Row(
          children: [
            SizedBox(width: 16),
            Icon(Icons.insert_drive_file, size: 40),
            Expanded(child: Text('File: ${post.mediaPath.split('/').last}')),
            IconButton(
              icon: Icon(Icons.download),
              onPressed: () async {
                try {
                  await ApiService().downloadFile(fullUrl, post.mediaPath.split('/').last);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
            ),
          ],
        ),
      );
    }
  }

  void _showFullScreenImage(String url) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: url),
          ),
        ),
      ),
    ));
  }

  Widget _buildCommentTile(Comment comment, int postOwnerId) {
    bool isOwner = comment.userId == widget.currentUserId;
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: comment.userProfileImage != null
            ? CachedNetworkImageProvider('$baseUrl/${comment.userProfileImage}')
            : null,
        child: comment.userProfileImage == null ? Icon(Icons.person) : null,
      ),
      title: Row(
        children: [
          Text(comment.username, style: TextStyle(fontWeight: FontWeight.bold)),
          if (comment.userIsBlue) SizedBox(width: 4),
          if (comment.userIsBlue) Icon(Icons.verified, color: Colors.blue, size: 16),
        ],
      ),
      subtitle: Text(comment.content),
      trailing: isOwner
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: Icon(Icons.edit, size: 18), onPressed: () => _editComment(comment)),
                IconButton(icon: Icon(Icons.delete, size: 18), onPressed: () => _deleteComment(comment.id)),
              ],
            )
          : null,
    );
  }
}

// ------------------- Upload Screen ---------------
class UploadScreen extends StatefulWidget {
  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _captionController = TextEditingController();
  File? _selectedFile;
  bool _isUploading = false;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() => _selectedFile = File(result.files.single.path!));
    }
  }

  Future<void> _upload() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Select a file')));
      return;
    }
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.currentUser == null) return;
    setState(() => _isUploading = true);
    try {
      await ApiService().uploadPost(auth.currentUser!.id, _captionController.text, _selectedFile!);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded successfully')));
      _captionController.clear();
      setState(() => _selectedFile = null);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isUploading = false);
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
            TextField(
              controller: _captionController,
              decoration: InputDecoration(labelText: 'Caption', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            SizedBox(height: 20),
            if (_selectedFile != null)
              Container(
                height: 100,
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file, size: 50),
                    SizedBox(width: 8),
                    Expanded(child: Text(_selectedFile!.path.split('/').last)),
                    IconButton(icon: Icon(Icons.close), onPressed: () => setState(() => _selectedFile = null)),
                  ],
                ),
              ),
            ElevatedButton(
              onPressed: _pickFile,
              child: Text('Select File'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isUploading ? null : _upload,
              child: _isUploading ? CircularProgressIndicator() : Text('Upload'),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------- Bookmarks Screen ------------
class BookmarksScreen extends StatefulWidget {
  @override
  _BookmarksScreenState createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.currentUser != null) {
        Provider.of<BookmarksProvider>(context, listen: false).loadBookmarks(auth.currentUser!.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (auth.currentUser == null) {
      return Center(child: Text('Please log in'));
    }
    return Scaffold(
      appBar: AppBar(title: Text('Bookmarks')),
      body: Consumer<BookmarksProvider>(
        builder: (context, provider, _) {
          if (provider.bookmarks.isEmpty && !provider._isLoading) {
            return Center(child: Text('No bookmarks yet'));
          }
          return ListView.builder(
            itemCount: provider.bookmarks.length,
            itemBuilder: (ctx, i) {
              final post = provider.bookmarks[i];
              return PostCard(post: post, currentUserId: auth.currentUser!.id);
            },
          );
        },
      ),
    );
  }
}

// ------------------- Profile Screen --------------
class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // For simplicity, show current user's info and their posts.
  // Could fetch user posts by calling /posts and filtering? But backend doesn't have user-specific endpoint.
  // We'll just show user details and maybe list their posts by filtering locally? Better to implement a /user/<id>/posts endpoint, but not available.
  // Instead we'll just show profile info and provide logout.
  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.currentUser;
    if (user == null) return Center(child: Text('Not logged in'));
    return Scaffold(
      appBar: AppBar(title: Text('Profile'), actions: [
        IconButton(
          icon: Icon(Icons.logout),
          onPressed: () async {
            await auth.logout();
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RegisterScreen()));
          },
        )
      ]),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: user.profileImage != null
                  ? CachedNetworkImageProvider('$baseUrl/${user.profileImage}')
                  : null,
              child: user.profileImage == null ? Icon(Icons.person, size: 50) : null,
            ),
            SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user.username, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                if (user.isBlue) SizedBox(width: 4),
                if (user.isBlue) Icon(Icons.verified, color: Colors.blue, size: 24),
              ],
            ),
            SizedBox(height: 8),
            Text(user.bio.isNotEmpty ? user.bio : 'No bio'),
            SizedBox(height: 32),
            // Could add a list of user's posts here if we had an endpoint.
          ],
        ),
      ),
    );
  }
}

// ------------------- Settings Screen -------------
class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: Text('Theme'),
            subtitle: Text(themeProvider.themeMode.toString().split('.').last),
            trailing: DropdownButton<ThemeMode>(
              value: themeProvider.themeMode,
              onChanged: (mode) {
                if (mode != null) themeProvider.setThemeMode(mode);
              },
              items: ThemeMode.values.map((mode) {
                return DropdownMenuItem(
                  value: mode,
                  child: Text(mode.toString().split('.').last),
                );
              }).toList(),
            ),
          ),
          // Add more settings here
        ],
      ),
    );
  }
}