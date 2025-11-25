import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class MediaRoute {
  final String route;
  final String mediaPath;
  final String mediaName;
  final bool isImage;
  final bool isVideo;

  MediaRoute({
    required this.route,
    required this.mediaPath,
    required this.mediaName,
    required this.isImage,
    required this.isVideo,
  });

  Map<String, dynamic> toJson() => {
        'route': route,
        'mediaPath': mediaPath,
        'mediaName': mediaName,
        'isImage': isImage,
        'isVideo': isVideo,
      };

  factory MediaRoute.fromJson(Map<String, dynamic> json) => MediaRoute(
        route: json['route'],
        mediaPath: json['mediaPath'],
        mediaName: json['mediaName'],
        isImage: json['isImage'] ?? false,
        isVideo: json['isVideo'] ?? false,
      );
}

class RouteManager {
  static const String _routesFileName = 'media_routes.json';
  List<MediaRoute> _routes = [];

  Future<List<MediaRoute>> getRoutes() async {
    if (_routes.isNotEmpty) {
      return _routes;
    }
    await _loadRoutes();
    return _routes;
  }

  Future<void> _loadRoutes() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final routesFile = File('${directory.path}/$_routesFileName');
      
      if (await routesFile.exists()) {
        final content = await routesFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _routes = jsonList.map((json) => MediaRoute.fromJson(json)).toList();
      }
    } catch (e) {
      _routes = [];
    }
  }

  Future<void> _saveRoutes() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final routesFile = File('${directory.path}/$_routesFileName');
      final jsonList = _routes.map((route) => route.toJson()).toList();
      await routesFile.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      // Handle error
    }
  }

  Future<bool> addRoute(String route, String mediaPath, String mediaName, bool isImage, bool isVideo) async {
    // Remove leading slash if present
    final cleanRoute = route.startsWith('/') ? route.substring(1) : route;
    
    // Check if route already exists
    if (_routes.any((r) => r.route == cleanRoute)) {
      return false; // Route already exists
    }

    _routes.add(MediaRoute(
      route: cleanRoute,
      mediaPath: mediaPath,
      mediaName: mediaName,
      isImage: isImage,
      isVideo: isVideo,
    ));

    await _saveRoutes();
    return true;
  }

  Future<bool> updateRoute(String route, String mediaPath, String mediaName, bool isImage, bool isVideo) async {
    final cleanRoute = route.startsWith('/') ? route.substring(1) : route;
    final index = _routes.indexWhere((r) => r.route == cleanRoute);
    
    if (index == -1) {
      return false; // Route not found
    }

    _routes[index] = MediaRoute(
      route: cleanRoute,
      mediaPath: mediaPath,
      mediaName: mediaName,
      isImage: isImage,
      isVideo: isVideo,
    );

    await _saveRoutes();
    return true;
  }

  Future<bool> deleteRoute(String route) async {
    final cleanRoute = route.startsWith('/') ? route.substring(1) : route;
    final routeExists = _routes.any((r) => r.route == cleanRoute);
    
    if (routeExists) {
      _routes.removeWhere((r) => r.route == cleanRoute);
      await _saveRoutes();
      return true;
    }
    return false;
  }

  MediaRoute? getRoute(String route) {
    final cleanRoute = route.startsWith('/') ? route.substring(1) : route;
    try {
      return _routes.firstWhere((r) => r.route == cleanRoute);
    } catch (e) {
      return null;
    }
  }

  void clearCache() {
    _routes = [];
  }
}

