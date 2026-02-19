// main.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:photo_view/photo_view.dart';

// -------------------- Models --------------------
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
}

class Post {
  final int id;
  final int userId;
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  final String? caption;
  final String mediaType; // text, image, video, audio, file
  final String? mediaPath;
  final String? thumbnailPath;
  final DateTime createdAt;
  int likesCount;
  int commentsCount;
  bool likedByUser;
  bool bookmarkedByUser;
  List<Comment>? comments;

  Post({
    required this.id,
    required this.userId,
    required this.username,
    this.userProfileImage,
    required this.userIsBlue,
    this.caption,
    required this.mediaType,
    this.mediaPath,
    this.thumbnailPath,
    required this.createdAt,
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
      username: json['username'],
      userProfileImage: json['profile_image'],
      userIsBlue: json['is_blue'] == 1,
      caption: json['caption'],
      mediaType: json['media_type'],
      mediaPath: json['media_path'],
      thumbnailPath: json['thumbnail_path'],
      createdAt: DateTime.parse(json['created_at']),
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
  final String username;
  final String? userProfileImage;
  final bool userIsBlue;
  final int? parentId;
  final String content;
  final DateTime createdAt;
  int likesCount;
  bool likedByUser;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.username,
    this.userProfileImage,
    required this.userIsBlue,
    this.parentId,
    required this.content,
    required this.createdAt,
    this.likesCount = 0,
    this.likedByUser = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      postId: json['post_id'],
      userId: json['user_id'],
      username: json['username'],
      userProfileImage: json['profile_image'],
      userIsBlue: json['is_blue'] == 1,
      parentId: json['parent_id'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
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
  final String senderUsername;
  final String? senderProfileImage;
  final bool senderIsBlue;
  final String? content;
  final String? mediaType;
  final String? mediaPath;
  final DateTime createdAt;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    this.senderProfileImage,
    required this.senderIsBlue,
    this.content,
    this.mediaType,
    this.mediaPath,
    required this.createdAt,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'],
      senderId: json['sender_id'],
      senderUsername: json['username'],
      senderProfileImage: json['profile_image'],
      senderIsBlue: json['is_blue'] == 1,
      content: json['content'],
      mediaType: json['media_type'],
      mediaPath: json['media_path'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

// -------------------- API Service --------------------
class ApiService {
  static const String baseUrl = 'https://tweeter.runflare.run';
  static const String staticUrl = 'https://tweeter.runflare.run/static/';

  final http.Client client = http.Client();

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
    var responseData = await http.Response.fromStream(response);
    if (response.statusCode == 201) {
      return jsonDecode(responseData.body);
    } else {
      throw Exception(responseData.body);
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    var response = await client.post(
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
    var response = await client.get(Uri.parse('$baseUrl/profile/$userId'));
    if (response.statusCode == 200) {
      return User.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load profile');
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
      var data = await http.Response.fromStream(response);
      throw Exception(data.body);
    }
  }

  // Posts
  Future<List<Post>> getPosts({int page = 1, int perPage = 10}) async {
    var response = await client.get(Uri.parse('$baseUrl/posts?page=$page&per_page=$perPage'));
    if (response.statusCode == 200) {
      List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => Post.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load posts');
    }
  }

  Future<Post> getPost(int postId, {int? userId}) async {
    var url = '$baseUrl/post/$postId';
    if (userId != null) url += '?user_id=$userId';
    var response = await client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return Post.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load post');
    }
  }

  Future<Map<String, dynamic>> uploadPost(int userId, String caption, File? mediaFile) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
    request.fields['user_id'] = userId.toString();
    request.fields['caption'] = caption;
    if (mediaFile != null) {
      request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
    }
    var response = await request.send();
    var responseData = await http.Response.fromStream(response);
    if (response.statusCode == 201) {
      return jsonDecode(responseData.body);
    } else {
      throw Exception(responseData.body);
    }
  }

  Future<void> updatePost(int postId, int userId, String newCaption) async {
    var response = await client.put(
      Uri.parse('$baseUrl/post/$postId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'caption': newCaption}),
    );
    if (response.statusCode != 200) throw Exception(response.body);
  }

  Future<void> deletePost(int postId, int userId) async {
    var response = await client.delete(Uri.parse('$baseUrl/post/$postId?user_id=$userId'));
    if (response.statusCode != 200) throw Exception(response.body);
  }

  // Likes
  Future<Map<String, dynamic>> toggleLike(int postId, int userId) async {
    var response = await client.post(
      Uri.parse('$baseUrl/like'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'post_id': postId, 'user_id': userId}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(response.body);
    }
  }

  // Bookmarks
  Future<Map<String, dynamic>> toggleBookmark(int postId, int userId) async {
    var response = await client.post(
      Uri.parse('$baseUrl/bookmark'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'post_id': postId, 'user_id': userId}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(response.body);
    }
  }

  Future<List<Post>> getBookmarks(int userId, {int page = 1, int perPage = 10}) async {
    var response = await client.get(Uri.parse('$baseUrl/bookmarks/$userId?page=$page&per_page=$perPage'));
    if (response.statusCode == 200) {
      List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => Post.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load bookmarks');
    }
  }

  // Comments
  Future<Map<String, dynamic>> addComment(int postId, int userId, String content, {int? parentId}) async {
    var response = await client.post(
      Uri.parse('$baseUrl/comment'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'post_id': postId,
        'user_id': userId,
        'content': content,
        if (parentId != null) 'parent_id': parentId,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(response.body);
    }
  }

  Future<void> updateComment(int commentId, int userId, String newContent) async {
    var response = await client.put(
      Uri.parse('$baseUrl/comment/$commentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId, 'content': newContent}),
    );
    if (response.statusCode != 200) throw Exception(response.body);
  }

  Future<void> deleteComment(int commentId, int userId) async {
    var response = await client.delete(Uri.parse('$baseUrl/comment/$commentId?user_id=$userId'));
    if (response.statusCode != 200) throw Exception(response.body);
  }

  Future<Map<String, dynamic>> toggleCommentLike(int commentId, int userId) async {
    var response = await client.post(
      Uri.parse('$baseUrl/comment/$commentId/like'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(response.body);
    }
  }

  // Direct Messages
  Future<Map<String, dynamic>> sendDirectMessage(int senderId, int receiverId, String content, File? mediaFile) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/direct/send'));
    request.fields['sender_id'] = senderId.toString();
    request.fields['receiver_id'] = receiverId.toString();
    request.fields['content'] = content;
    if (mediaFile != null) {
      request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
    }
    var response = await request.send();
    var responseData = await http.Response.fromStream(response);
    if (response.statusCode == 201) {
      return jsonDecode(responseData.body);
    } else {
      throw Exception(responseData.body);
    }
  }

  Future<List<DirectMessage>> getDirectMessages(int userId, int otherId, {int page = 1, int perPage = 20}) async {
    var response = await client.get(Uri.parse('$baseUrl/direct/messages/$userId?other_id=$otherId&page=$page&per_page=$perPage'));
    if (response.statusCode == 200) {
      List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => DirectMessage.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load messages');
    }
  }

  // Group Messages
  Future<Map<String, dynamic>> sendGroupMessage(int senderId, String content, File? mediaFile) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/group/send'));
    request.fields['sender_id'] = senderId.toString();
    request.fields['content'] = content;
    if (mediaFile != null) {
      request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
    }
    var response = await request.send();
    var responseData = await http.Response.fromStream(response);
    if (response.statusCode == 201) {
      return jsonDecode(responseData.body);
    } else {
      throw Exception(responseData.body);
    }
  }

  Future<List<GroupMessage>> getGroupMessages({int page = 1, int perPage = 20}) async {
    var response = await client.get(Uri.parse('$baseUrl/group/messages?page=$page&per_page=$perPage'));
    if (response.statusCode == 200) {
      List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => GroupMessage.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load group messages');
    }
  }

  // Users list
  Future<Map<String, dynamic>> getAllUsers({int page = 1, int perPage = 20, String search = ''}) async {
    var url = '$baseUrl/users?page=$page&per_page=$perPage';
    if (search.isNotEmpty) url += '&search=$search';
    var response = await client.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load users');
    }
  }

  // Blue tick (admin)
  Future<void> giveBlue(String username) async {
    var response = await client.post(Uri.parse('$baseUrl/give_blue/$username'));
    if (response.statusCode != 200) throw Exception(response.body);
  }
}

// -------------------- Providers --------------------
class AuthProvider extends ChangeNotifier {
  int? _currentUserId;
  User? _currentUser;
  final ApiService _api = ApiService();
  final SharedPreferences _prefs;

  AuthProvider(this._prefs) {
    _currentUserId = _prefs.getInt('userId');
    if (_currentUserId != null) {
      loadCurrentUser();
    }
  }

  int? get currentUserId => _currentUserId;
  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUserId != null;

  Future<void> loadCurrentUser() async {
    if (_currentUserId == null) return;
    try {
      _currentUser = await _api.getProfile(_currentUserId!);
      notifyListeners();
    } catch (e) {
      print(e);
    }
  }

  Future<void> login(String username, String password) async {
    var data = await _api.login(username, password);
    int userId = data['user_id'];
    await _prefs.setInt('userId', userId);
    _currentUserId = userId;
    await loadCurrentUser();
  }

  Future<void> register(String username, String password, String bio, File? profileImage) async {
    var data = await _api.register(username, password, bio, profileImage);
    int userId = data['user_id'];
    await _prefs.setInt('userId', userId);
    _currentUserId = userId;
    await loadCurrentUser();
  }

  Future<void> logout() async {
    await _prefs.remove('userId');
    _currentUserId = null;
    _currentUser = null;
    notifyListeners();
  }

  Future<void> updateProfile(String? bio, File? profileImage) async {
    if (_currentUserId == null) return;
    await _api.updateProfile(_currentUserId!, bio, profileImage);
    await loadCurrentUser();
  }

  Future<void> giveBlue(String username) async {
    await _api.giveBlue(username);
  }
}

class PostsProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
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
      _posts = [];
    }
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      var newPosts = await _api.getPosts(page: _currentPage);
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

  void updatePostInList(Post updatedPost) {
    int index = _posts.indexWhere((p) => p.id == updatedPost.id);
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

class BookmarksProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  List<Post> _bookmarks = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;

  List<Post> get bookmarks => _bookmarks;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> loadBookmarks(int userId, {bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _bookmarks = [];
    }
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      var newBookmarks = await _api.getBookmarks(userId, page: _currentPage);
      if (newBookmarks.isEmpty) {
        _hasMore = false;
      } else {
        _bookmarks.addAll(newBookmarks);
        _currentPage++;
      }
    } catch (e) {
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void removeBookmark(int postId) {
    _bookmarks.removeWhere((p) => p.id == postId);
    notifyListeners();
  }
}

// -------------------- Helper Widgets --------------------
class NetworkImageWidget extends StatelessWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BoxFit fit;

  const NetworkImageWidget({super.key, this.imageUrl, required this.width, required this.height, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(width: width, height: height, color: Colors.grey[300], child: Icon(Icons.person, color: Colors.grey[600]));
    }
    return CachedNetworkImage(
      imageUrl: ApiService.staticUrl + imageUrl!,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => Container(color: Colors.grey[300], child: Center(child: CircularProgressIndicator())),
      errorWidget: (context, url, error) => Container(color: Colors.grey[300], child: Icon(Icons.error)),
    );
  }
}

class BlueTick extends StatelessWidget {
  final bool isBlue;
  final double size;

  const BlueTick({super.key, required this.isBlue, this.size = 16});

  @override
  Widget build(BuildContext context) {
    if (!isBlue) return SizedBox.shrink();
    return Icon(Icons.verified, color: Colors.blue, size: size);
  }
}

class MediaDisplay extends StatefulWidget {
  final String mediaType;
  final String? mediaPath;
  final String? thumbnailPath;
  final double? width;
  final double? height;

  const MediaDisplay({super.key, required this.mediaType, this.mediaPath, this.thumbnailPath, this.width, this.height});

  @override
  State<MediaDisplay> createState() => _MediaDisplayState();
}

class _MediaDisplayState extends State<MediaDisplay> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video' && widget.mediaPath != null) {
      _videoController = VideoPlayerController.network(ApiService.staticUrl + widget.mediaPath!)
        ..initialize().then((_) {
          setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaPath == null) return SizedBox.shrink();

    String fullUrl = ApiService.staticUrl + widget.mediaPath!;
    String? thumbUrl = widget.thumbnailPath != null ? ApiService.staticUrl + widget.thumbnailPath! : null;

    switch (widget.mediaType) {
      case 'image':
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewGalleryPage(imageUrl: fullUrl))),
          child: CachedNetworkImage(
            imageUrl: fullUrl,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey[300], child: Center(child: CircularProgressIndicator())),
            errorWidget: (_, __, ___) => Container(color: Colors.grey[300], child: Icon(Icons.broken_image)),
          ),
        );
      case 'video':
        return _videoController != null && _videoController!.value.isInitialized
            ? AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              )
            : thumbUrl != null
                ? CachedNetworkImage(imageUrl: thumbUrl, fit: BoxFit.cover)
                : Container(color: Colors.black, child: Center(child: CircularProgressIndicator()));
      case 'audio':
        return ListTile(
          leading: Icon(Icons.audio_file),
          title: Text('Audio file'),
          subtitle: Text(widget.mediaPath!.split('/').last),
          onTap: () {
            _audioPlayer ??= AudioPlayer();
            _audioPlayer!.play(UrlSource(fullUrl));
          },
        );
      default:
        return ListTile(
          leading: Icon(Icons.insert_drive_file),
          title: Text('File'),
          subtitle: Text(widget.mediaPath!.split('/').last),
          onTap: () {
            // می‌توانید با url_launcher باز کنید
          },
        );
    }
  }
}

class PhotoViewGalleryPage extends StatelessWidget {
  final String imageUrl;

  const PhotoViewGalleryPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PhotoView(
        imageProvider: CachedNetworkImageProvider(imageUrl),
        backgroundDecoration: BoxDecoration(color: Colors.black),
      ),
    );
  }
}

// -------------------- Screens --------------------
// Login/Register
class AuthScreen extends StatefulWidget {
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool isLogin = true;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bioController = TextEditingController();
  File? _profileImage;
  final ImagePicker _picker = ImagePicker();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: Duration(milliseconds: 300));
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() => isLogin = !isLogin);
    _animationController.reset();
    _animationController.forward();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _profileImage = File(picked.path));
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      if (isLogin) {
        await auth.login(_usernameController.text, _passwordController.text);
      } else {
        await auth.register(_usernameController.text, _passwordController.text, _bioController.text, _profileImage);
      }
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainScreen()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.purple, Colors.blue], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(isLogin ? 'Welcome Back' : 'Create Account', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        SizedBox(height: 20),
                        if (!isLogin) ...[
                          GestureDetector(
                            onTap: _pickImage,
                            child: CircleAvatar(
                              radius: 50,
                              backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                              child: _profileImage == null ? Icon(Icons.camera_alt, size: 30) : null,
                            ),
                          ),
                          SizedBox(height: 10),
                        ],
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(labelText: 'Username'),
                          validator: (v) => v!.isEmpty ? 'Required' : null,
                        ),
                        TextFormField(
                          controller: _passwordController,
                          decoration: InputDecoration(labelText: 'Password'),
                          obscureText: true,
                          validator: (v) => v!.isEmpty ? 'Required' : null,
                        ),
                        if (!isLogin) ...[
                          TextFormField(
                            controller: _bioController,
                            decoration: InputDecoration(labelText: 'Bio'),
                            maxLines: 3,
                          ),
                        ],
                        SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _submit,
                          child: Text(isLogin ? 'Login' : 'Register'),
                          style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
                        ),
                        TextButton(
                          onPressed: _toggleMode,
                          child: Text(isLogin ? 'Need an account? Register' : 'Already have an account? Login'),
                        ),
                      ],
                    ),
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

// Main Screen with Bottom Navigation
class MainScreen extends StatefulWidget {
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(index, duration: Duration(milliseconds: 300), curve: Curves.ease);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: [
          FeedScreen(),
          ExploreScreen(),
          PostUploadScreen(),
          DirectMessagesScreen(),
          ProfileScreen(userId: auth.currentUserId!),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Explore'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Post'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Direct'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// Feed Screen
class FeedScreen extends StatefulWidget {
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PostsProvider>().loadPosts(refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<PostsProvider>().loadPosts();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Feed'), actions: [
        IconButton(icon: Icon(Icons.bookmark), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookmarksScreen()))),
        IconButton(icon: Icon(Icons.group), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen()))),
      ]),
      body: Consumer<PostsProvider>(
        builder: (context, provider, child) {
          if (provider.posts.isEmpty && provider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }
          return AnimationLimiter(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: provider.posts.length + (provider.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == provider.posts.length) {
                  return Center(child: CircularProgressIndicator());
                }
                final post = provider.posts[index];
                return AnimationConfiguration.staggeredList(
                  position: index,
                  duration: Duration(milliseconds: 375),
                  child: SlideAnimation(
                    verticalOffset: 50,
                    child: FadeInAnimation(
                      child: PostCard(post: post, userId: auth.currentUserId!),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  final Post post;
  final int userId;

  const PostCard({super.key, required this.post, required this.userId});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post _post;
  bool _isLiked = false;
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _isLiked = _post.likedByUser;
    _isBookmarked = _post.bookmarkedByUser;
  }

  Future<void> _toggleLike() async {
    final api = ApiService();
    try {
      var result = await api.toggleLike(_post.id, widget.userId);
      setState(() {
        _isLiked = result['liked'];
        if (_isLiked) {
          _post.likesCount++;
        } else {
          _post.likesCount--;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _toggleBookmark() async {
    final api = ApiService();
    try {
      var result = await api.toggleBookmark(_post.id, widget.userId);
      setState(() {
        _isBookmarked = result['bookmarked'];
      });
      // به‌روزرسانی در BookmarksProvider اگر لازم است
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _viewProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: _post.userId)));
  }

  void _viewPostDetail() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: _post.id)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: GestureDetector(
              onTap: _viewProfile,
              child: CircleAvatar(
                backgroundImage: _post.userProfileImage != null
                    ? CachedNetworkImageProvider(ApiService.staticUrl + _post.userProfileImage!)
                    : null,
                child: _post.userProfileImage == null ? Icon(Icons.person) : null,
              ),
            ),
            title: GestureDetector(
              onTap: _viewProfile,
              child: Row(
                children: [
                  Text(_post.username, style: TextStyle(fontWeight: FontWeight.bold)),
                  BlueTick(isBlue: _post.userIsBlue),
                ],
              ),
            ),
            subtitle: Text(DateFormat.yMMMd().add_jm().format(_post.createdAt)),
            trailing: _post.userId == widget.userId
                ? PopupMenuButton(
                    itemBuilder: (_) => [
                      PopupMenuItem(child: Text('Edit'), onTap: () => _editPost()),
                      PopupMenuItem(child: Text('Delete'), onTap: () => _deletePost()),
                    ],
                  )
                : null,
          ),
          if (_post.caption != null && _post.caption!.isNotEmpty)
            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text(_post.caption!)),
          if (_post.mediaPath != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: MediaDisplay(
                  mediaType: _post.mediaType,
                  mediaPath: _post.mediaPath,
                  thumbnailPath: _post.thumbnailPath,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, color: _isLiked ? Colors.red : null),
                onPressed: _toggleLike,
              ),
              Text('${_post.likesCount}'),
              IconButton(
                icon: Icon(Icons.comment),
                onPressed: _viewPostDetail,
              ),
              Text('${_post.commentsCount}'),
              IconButton(
                icon: Icon(_isBookmarked ? Icons.bookmark : Icons.bookmark_border, color: _isBookmarked ? Colors.amber : null),
                onPressed: _toggleBookmark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _editPost() async {
    String? newCaption = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit caption'),
        content: TextField(
          controller: TextEditingController(text: _post.caption),
          decoration: InputDecoration(hintText: 'New caption'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context, (context as TextField).controller?.text);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
    if (newCaption != null && newCaption != _post.caption) {
      try {
        await ApiService().updatePost(_post.id, widget.userId, newCaption);
        setState(() => _post.caption = newCaption);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _deletePost() async {
    bool confirm = await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Delete post'),
            content: Text('Are you sure?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text('No')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Yes')),
            ],
          ),
        ) ??
        false;
    if (confirm) {
      try {
        await ApiService().deletePost(_post.id, widget.userId);
        context.read<PostsProvider>().removePost(_post.id);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}

// Post Detail
class PostDetailScreen extends StatefulWidget {
  final int postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Future<Post> _postFuture;
  final TextEditingController _commentController = TextEditingController();
  int? _replyingTo; // parent comment id

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  void _loadPost() {
    final userId = context.read<AuthProvider>().currentUserId!;
    _postFuture = ApiService().getPost(widget.postId, userId: userId);
  }

  void _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;
    try {
      await ApiService().addComment(widget.postId, context.read<AuthProvider>().currentUserId!, _commentController.text, parentId: _replyingTo);
      _commentController.clear();
      setState(() {
        _replyingTo = null;
        _loadPost(); // refresh
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
          if (!snapshot.hasData) {
            return Center(child: Text('Failed to load post'));
          }
          final post = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    PostCard(post: post, userId: context.read<AuthProvider>().currentUserId!),
                    if (_replyingTo != null)
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Container(
                          color: Colors.blue[50],
                          padding: EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Text('Replying...'),
                              IconButton(icon: Icon(Icons.close), onPressed: () => setState(() => _replyingTo = null)),
                            ],
                          ),
                        ),
                      ),
                    ...?post.comments?.map((c) => CommentTile(comment: c, userId: context.read<AuthProvider>().currentUserId!, onReply: (cid) => setState(() => _replyingTo = cid))),
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
                        decoration: InputDecoration(hintText: 'Add a comment...', border: OutlineInputBorder()),
                      ),
                    ),
                    IconButton(onPressed: _submitComment, icon: Icon(Icons.send)),
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

class CommentTile extends StatefulWidget {
  final Comment comment;
  final int userId;
  final Function(int) onReply;

  const CommentTile({super.key, required this.comment, required this.userId, required this.onReply});

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  bool _isLiked = false;
  late int _likesCount;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.comment.likedByUser;
    _likesCount = widget.comment.likesCount;
  }

  Future<void> _toggleLike() async {
    try {
      var result = await ApiService().toggleCommentLike(widget.comment.id, widget.userId);
      setState(() {
        _isLiked = result['liked'];
        if (_isLiked) {
          _likesCount++;
        } else {
          _likesCount--;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: widget.comment.userProfileImage != null ? CachedNetworkImageProvider(ApiService.staticUrl + widget.comment.userProfileImage!) : null,
            child: widget.comment.userProfileImage == null ? Icon(Icons.person, size: 16) : null,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(text: widget.comment.username, style: TextStyle(fontWeight: FontWeight.bold)),
                      WidgetSpan(child: BlueTick(isBlue: widget.comment.userIsBlue, size: 14)),
                      TextSpan(text: '  ${widget.comment.content}'),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(DateFormat.yMMMd().add_jm().format(widget.comment.createdAt), style: TextStyle(fontSize: 12, color: Colors.grey)),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Icon(_isLiked ? Icons.favorite : Icons.favorite_border, size: 14, color: _isLiked ? Colors.red : null),
                    ),
                    Text(' $_likesCount', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => widget.onReply(widget.comment.id),
                      child: Text('Reply', style: TextStyle(fontSize: 12, color: Colors.blue)),
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
}

// Explore / Users Search
class ExploreScreen extends StatefulWidget {
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<User> _users = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _loadUsers();
  }

  void _onSearchChanged() {
    _page = 1;
    _users.clear();
    _hasMore = true;
    _loadUsers();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoading && _hasMore) {
      _loadUsers();
    }
  }

  Future<void> _loadUsers() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      var data = await ApiService().getAllUsers(page: _page, search: _searchController.text);
      List<User> newUsers = (data['users'] as List).map((e) => User.fromJson(e)).toList();
      setState(() {
        if (newUsers.isEmpty) {
          _hasMore = false;
        } else {
          _users.addAll(newUsers);
          _page++;
        }
      });
    } catch (e) {
      print(e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Explore')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(hintText: 'Search users...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _users.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _users.length) {
                  return Center(child: CircularProgressIndicator());
                }
                final user = _users[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user.profileImage != null ? CachedNetworkImageProvider(ApiService.staticUrl + user.profileImage!) : null,
                    child: user.profileImage == null ? Icon(Icons.person) : null,
                  ),
                  title: Row(children: [Text(user.username), BlueTick(isBlue: user.isBlue)]),
                  subtitle: Text('Posts: ${user.postsCount} | Bookmarks: ${user.bookmarksCount}'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id))),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Profile Screen
class ProfileScreen extends StatefulWidget {
  final int userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<User> _userFuture;
  final ApiService _api = ApiService();
  List<Post> _userPosts = [];
  int _postPage = 1;
  bool _hasMorePosts = true;
  bool _isLoadingPosts = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _userFuture = _api.getProfile(widget.userId);
    _loadUserPosts();
    _scrollController.addListener(_onScroll);
  }

  void _loadUserPosts({bool refresh = false}) async {
    if (refresh) {
      _postPage = 1;
      _hasMorePosts = true;
      _userPosts.clear();
    }
    if (_isLoadingPosts || !_hasMorePosts) return;
    setState(() => _isLoadingPosts = true);
    try {
      var posts = await _api.getPosts(page: _postPage, perPage: 10);
      // فیلتر پست‌های این کاربر (چون API همه پست‌ها را برمی‌گرداند)
      posts = posts.where((p) => p.userId == widget.userId).toList();
      if (posts.isEmpty) {
        _hasMorePosts = false;
      } else {
        _userPosts.addAll(posts);
        _postPage++;
      }
    } catch (e) {
      print(e);
    } finally {
      setState(() => _isLoadingPosts = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_isLoadingPosts && _hasMorePosts) {
      _loadUserPosts();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isCurrentUser = auth.currentUserId == widget.userId;
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          if (isCurrentUser)
            IconButton(icon: Icon(Icons.edit), onPressed: _editProfile),
        ],
      ),
      body: FutureBuilder<User>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data!;
          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: user.profileImage != null ? CachedNetworkImageProvider(ApiService.staticUrl + user.profileImage!) : null,
                        child: user.profileImage == null ? Icon(Icons.person, size: 50) : null,
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(user.username, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          BlueTick(isBlue: user.isBlue, size: 22),
                        ],
                      ),
                      if (user.bio != null) Text(user.bio!, style: TextStyle(fontSize: 16)),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatColumn('Posts', user.postsCount),
                          _buildStatColumn('Bookmarks', user.bookmarksCount),
                        ],
                      ),
                      Divider(),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == _userPosts.length) {
                      return _hasMorePosts ? Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())) : null;
                    }
                    final post = _userPosts[index];
                    return PostCard(post: post, userId: auth.currentUserId!);
                  },
                  childCount: _userPosts.length + (_hasMorePosts ? 1 : 0),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatColumn(String label, int count) {
    return Column(
      children: [
        Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }

  void _editProfile() async {
    String? newBio;
    File? newImage;
    await showDialog(
      context: context,
      builder: (context) {
        TextEditingController bioController = TextEditingController(text: context.read<AuthProvider>().currentUser?.bio);
        return AlertDialog(
          title: Text('Edit Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) newImage = File(picked.path);
                },
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: newImage != null ? FileImage(newImage!) : (context.read<AuthProvider>().currentUser?.profileImage != null ? CachedNetworkImageProvider(ApiService.staticUrl + context.read<AuthProvider>().currentUser!.profileImage!) : null),
                  child: Icon(Icons.camera_alt),
                ),
              ),
              TextField(
                controller: bioController,
                decoration: InputDecoration(labelText: 'Bio'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await context.read<AuthProvider>().updateProfile(bioController.text, newImage);
                  setState(() {
                    _userFuture = _api.getProfile(widget.userId);
                  });
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

// Post Upload
class PostUploadScreen extends StatefulWidget {
  @override
  State<PostUploadScreen> createState() => _PostUploadScreenState();
}

class _PostUploadScreenState extends State<PostUploadScreen> {
  final TextEditingController _captionController = TextEditingController();
  File? _mediaFile;
  final ImagePicker _picker = ImagePicker();
  String? _mediaType; // image, video, audio, file

  Future<void> _pickMedia() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => Wrap(
        children: [
          ListTile(leading: Icon(Icons.image), title: Text('Image'), onTap: () async {
            final picked = await _picker.pickImage(source: ImageSource.gallery);
            if (picked != null) setState(() {
              _mediaFile = File(picked.path);
              _mediaType = 'image';
            });
            Navigator.pop(context);
          }),
          ListTile(leading: Icon(Icons.video_library), title: Text('Video'), onTap: () async {
            final picked = await _picker.pickVideo(source: ImageSource.gallery);
            if (picked != null) setState(() {
              _mediaFile = File(picked.path);
              _mediaType = 'video';
            });
            Navigator.pop(context);
          }),
          ListTile(leading: Icon(Icons.audiotrack), title: Text('Audio'), onTap: () async {
            // انتخاب فایل صوتی از دستگاه
            // برای سادگی، اینجا فقط یک نمونه
          }),
          ListTile(leading: Icon(Icons.insert_drive_file), title: Text('File'), onTap: () async {
            // انتخاب فایل
          }),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      await ApiService().uploadPost(auth.currentUserId!, _captionController.text, _mediaFile);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Post uploaded')));
      _captionController.clear();
      setState(() {
        _mediaFile = null;
        _mediaType = null;
      });
      // به روزرسانی فید
      context.read<PostsProvider>().loadPosts(refresh: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New Post')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _captionController,
              decoration: InputDecoration(hintText: 'Caption...'),
              maxLines: 3,
            ),
            SizedBox(height: 16),
            if (_mediaFile != null && _mediaType != null)
              Container(
                height: 200,
                child: MediaDisplay(mediaType: _mediaType!, mediaPath: _mediaFile!.path), // اینجا مسیر لوکال است، برای نمایش استفاده می‌کنیم
              ),
            ElevatedButton(
              onPressed: _pickMedia,
              child: Text('Attach Media'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: Text('Post'),
              style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
            ),
          ],
        ),
      ),
    );
  }
}

// Bookmarks Screen
class BookmarksScreen extends StatefulWidget {
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthProvider>().currentUserId!;
      context.read<BookmarksProvider>().loadBookmarks(userId, refresh: true);
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final userId = context.read<AuthProvider>().currentUserId!;
      context.read<BookmarksProvider>().loadBookmarks(userId);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Bookmarks')),
      body: Consumer<BookmarksProvider>(
        builder: (context, provider, child) {
          if (provider.bookmarks.isEmpty && provider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            controller: _scrollController,
            itemCount: provider.bookmarks.length + (provider.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == provider.bookmarks.length) {
                return Center(child: CircularProgressIndicator());
              }
              final post = provider.bookmarks[index];
              return PostCard(post: post, userId: auth.currentUserId!);
            },
          );
        },
      ),
    );
  }
}

// Direct Messages List
class DirectMessagesScreen extends StatefulWidget {
  @override
  State<DirectMessagesScreen> createState() => _DirectMessagesScreenState();
}

class _DirectMessagesScreenState extends State<DirectMessagesScreen> {
  List<User> _recentUsers = []; // لیست کاربرانی که با آنها پیام داشته‌اید
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecentUsers();
  }

  Future<void> _loadRecentUsers() async {
    // برای سادگی، همه کاربران را می‌آوریم و بر اساس آخرین پیام مرتب می‌کنیم
    // در عمل باید از API خاصی استفاده کرد
  }

  void _startChat(int otherUserId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(otherUserId: otherUserId)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Direct Messages')),
      body: FutureBuilder(
        future: ApiService().getAllUsers(page: 1, perPage: 50),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          List users = (snapshot.data!['users'] as List).map((e) => User.fromJson(e)).toList();
          // فیلتر کردن خود کاربر
          users.removeWhere((u) => u.id == context.read<AuthProvider>().currentUserId);
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: user.profileImage != null ? CachedNetworkImageProvider(ApiService.staticUrl + user.profileImage!) : null,
                  child: user.profileImage == null ? Icon(Icons.person) : null,
                ),
                title: Row(children: [Text(user.username), BlueTick(isBlue: user.isBlue)]),
                onTap: () => _startChat(user.id),
              );
            },
          );
        },
      ),
    );
  }
}

// Chat Screen (Direct)
class ChatScreen extends StatefulWidget {
  final int otherUserId;

  const ChatScreen({super.key, required this.otherUserId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<DirectMessage> _messages = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  File? _mediaFile;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadMessages({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _messages.clear();
    }
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      final userId = context.read<AuthProvider>().currentUserId!;
      var newMessages = await ApiService().getDirectMessages(userId, widget.otherUserId, page: _page);
      if (newMessages.isEmpty) {
        _hasMore = false;
      } else {
        _messages.insertAll(0, newMessages.reversed);
        _page++;
      }
    } catch (e) {
      print(e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 200 && !_isLoading && _hasMore) {
      _loadMessages();
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _mediaFile == null) return;
    try {
      final userId = context.read<AuthProvider>().currentUserId!;
      var result = await ApiService().sendDirectMessage(userId, widget.otherUserId, _messageController.text, _mediaFile);
      _messageController.clear();
      setState(() {
        _mediaFile = null;
      });
      // افزودن پیام به لیست
      _loadMessages(refresh: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickMedia() async {
    // مشابه قبل
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().currentUserId!;
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              controller: _scrollController,
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0 && _isLoading) {
                  return Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
                }
                final msg = _messages[_messages.length - 1 - index];
                final isMe = msg.senderId == currentUserId;
                return Container(
                  margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isMe)
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: msg.senderProfileImage != null ? CachedNetworkImageProvider(ApiService.staticUrl + msg.senderProfileImage!) : null,
                          child: msg.senderProfileImage == null ? Icon(Icons.person, size: 16) : null,
                        ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.content != null) Text(msg.content!),
                              if (msg.mediaType != null)
                                MediaDisplay(mediaType: msg.mediaType!, mediaPath: msg.mediaPath),
                              Text(DateFormat.Hm().format(msg.createdAt), style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black54)),
                            ],
                          ),
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
                IconButton(icon: Icon(Icons.attach_file), onPressed: _pickMedia),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(hintText: 'Message...', border: OutlineInputBorder()),
                  ),
                ),
                IconButton(onPressed: _sendMessage, icon: Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Group Chat
class GroupChatScreen extends StatefulWidget {
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<GroupMessage> _messages = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  File? _mediaFile;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadMessages({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _messages.clear();
    }
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    try {
      var newMessages = await ApiService().getGroupMessages(page: _page);
      if (newMessages.isEmpty) {
        _hasMore = false;
      } else {
        _messages.insertAll(0, newMessages.reversed);
        _page++;
      }
    } catch (e) {
      print(e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 200 && !_isLoading && _hasMore) {
      _loadMessages();
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _mediaFile == null) return;
    try {
      final userId = context.read<AuthProvider>().currentUserId!;
      var result = await ApiService().sendGroupMessage(userId, _messageController.text, _mediaFile);
      _messageController.clear();
      setState(() {
        _mediaFile = null;
      });
      _loadMessages(refresh: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _pickMedia() async {
    // مشابه قبل
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().currentUserId!;
    return Scaffold(
      appBar: AppBar(title: Text('Group Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              controller: _scrollController,
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0 && _isLoading) {
                  return Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
                }
                final msg = _messages[_messages.length - 1 - index];
                final isMe = msg.senderId == currentUserId;
                return Container(
                  margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isMe)
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: msg.senderProfileImage != null ? CachedNetworkImageProvider(ApiService.staticUrl + msg.senderProfileImage!) : null,
                          child: msg.senderProfileImage == null ? Icon(Icons.person, size: 16) : null,
                        ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe) ...[
                                Row(
                                  children: [
                                    Text(msg.senderUsername, style: TextStyle(fontWeight: FontWeight.bold)),
                                    BlueTick(isBlue: msg.senderIsBlue, size: 14),
                                  ],
                                ),
                                SizedBox(height: 4),
                              ],
                              if (msg.content != null) Text(msg.content!),
                              if (msg.mediaType != null)
                                MediaDisplay(mediaType: msg.mediaType!, mediaPath: msg.mediaPath),
                              Text(DateFormat.Hm().format(msg.createdAt), style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black54)),
                            ],
                          ),
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
                IconButton(icon: Icon(Icons.attach_file), onPressed: _pickMedia),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(hintText: 'Message...', border: OutlineInputBorder()),
                  ),
                ),
                IconButton(onPressed: _sendMessage, icon: Icon(Icons.send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- Main App --------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;

  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(prefs)),
        ChangeNotifierProvider(create: (_) => PostsProvider()),
        ChangeNotifierProvider(create: (_) => BookmarksProvider()),
      ],
      child: MaterialApp(
        title: 'Tweeter App',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            if (auth.isLoggedIn) {
              return MainScreen();
            } else {
              return AuthScreen();
            }
          },
        ),
      ),
    );
  }
}