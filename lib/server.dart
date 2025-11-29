import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'media_service.dart';
import 'route_manager.dart';

class Server {
  static HttpServer? _server;
  static MediaService? _mediaService;
  static RouteManager? _routeManager;
  static List<String> _allNetworkIPs = [];
  
  static List<String> get allNetworkIPs => _allNetworkIPs;

  static Future<String> start(int port, MediaService mediaService, RouteManager routeManager, {String? fixedIP}) async {
    _mediaService = mediaService;
    _routeManager = routeManager;

    final handler = Pipeline()
        .addMiddleware(_corsHeaders())
        .addMiddleware(logRequests())
        .addHandler((request) async => await _router(request));

    // Bind to all interfaces (0.0.0.0) to allow external connections
    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4, // This allows connections from other devices
      port,
      shared: true, // Allow multiple connections
    );

    // Get the local IP address - prioritize wlan0 interface
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    String? wlan0IP;
    String? hotspotIP;
    String? wifiIP;
    String? anyIP;
    List<String> allIps = [];
    
    // Scan all interfaces and categorize IPs
    for (var interface in interfaces) {
      final name = interface.name.toLowerCase();
      for (var addr in interface.addresses) {
        if (!addr.isLoopback) {
          final ip = addr.address;
          allIps.add('${interface.name}: $ip');
          
          // Priority 1: Check for wlan0 specifically
          if (name == 'wlan0') {
            wlan0IP = ip;
          }
          
          // Priority 2: Check if this is a hotspot IP (common ranges)
          if (ip.startsWith('192.168.43.') || ip.startsWith('192.168.137.')) {
            hotspotIP ??= ip;
          }
          
          // Priority 3: Check for AP/tethering interface
          if (name.contains('ap') || name.contains('softap') || 
              name.contains('tether') || name.contains('rndis')) {
            hotspotIP ??= ip;
          }
          
          // Priority 4: Check for any WLAN interface
          if (name.contains('wlan') || name.contains('wifi')) {
            wifiIP ??= ip;
          }
          
          // Keep any non-loopback IP as fallback
          anyIP ??= ip;
        }
      }
    }
    
    // Prioritize: wlan0 IP > hotspot IP > wifi IP > any non-loopback IP
    final ipAddress = wlan0IP ?? hotspotIP ?? wifiIP ?? anyIP ?? '192.168.43.1';
    
    // Store all IPs for display
    _allNetworkIPs = allIps;
    if (wlan0IP != null) {
      _allNetworkIPs.insert(0, 'wlan0 IP (auto-detected): $wlan0IP');
    } else if (hotspotIP != null) {
      _allNetworkIPs.insert(0, 'Hotspot IP (auto-detected): $hotspotIP');
    }
    
    return 'http://$ipAddress:$port';
  }

  static Middleware _corsHeaders() {
    return createMiddleware(
      requestHandler: (Request request) {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeadersMap);
        }
        return null;
      },
      responseHandler: (Response response) {
        return response.change(headers: _corsHeadersMap);
      },
    );
  }

  static Map<String, String> get _corsHeadersMap => {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Max-Age': '3600',
      };

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static Future<Response> _router(Request request) async {
    final path = request.url.path;

    // Root path - show index page
    if (path.isEmpty || path == '/') {
      return _indexPage();
    }

    // API endpoints
    if (path == 'api/media') {
      return await _getMediaList(request);
    }

    // Routes API
    if (path == 'api/routes' && request.method == 'GET') {
      return await _getRoutes(request);
    }

    if (path == 'api/routes' && request.method == 'POST') {
      return await _addRoute(request);
    }

    if (path == 'api/routes' && request.method == 'DELETE') {
      return await _deleteRoute(request);
    }

    // Refresh cache endpoint
    if (path == 'api/refresh' && request.method == 'POST') {
      _mediaService!.clearCache();
      return Response.ok(
        jsonEncode({'success': true, 'message': 'Cache cleared'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Upload endpoint
    if (path == 'api/upload' && request.method == 'POST') {
      return await _handleUpload(request);
    }

    // Check custom routes first (path is already cleaned by request.url.path)
    // Remove leading slash if present for route lookup
    final routePath = path.startsWith('/') ? path.substring(1) : path;
    final customRoute = _routeManager!.getRoute(routePath);
    if (customRoute != null) {
      // Check if this is a direct file request (from <video> or <img> tag)
      // Query parameter ?file=1 indicates direct file request
      final isFileRequest = request.url.queryParameters['file'] == '1';
      
      // Also check Accept header as fallback
      final acceptHeader = request.headers['accept'] ?? '';
      final isVideoRequest = acceptHeader.contains('video/') && 
                            !acceptHeader.contains('text/html');
      final isImageRequest = acceptHeader.contains('image/') && 
                            !acceptHeader.contains('text/html');
      
      // If it's a direct file request, serve the file directly
      if (isFileRequest) {
        if (customRoute.isVideo) {
          return await _serveVideoFile(customRoute);
        } else {
          return await _serveImageFile(customRoute);
        }
      }
      
      // Also check Accept header for direct file requests
      if (customRoute.isVideo && isVideoRequest) {
        return await _serveVideoFile(customRoute);
      }
      if (customRoute.isImage && isImageRequest) {
        return await _serveImageFile(customRoute);
      }
      
      // Otherwise serve the HTML page (for both videos and images)
      return await _serveCustomRoute(customRoute);
    }

    // Serve media files
    if (path.startsWith('media/')) {
      return await _serveMediaFile(path);
    }
    
    // Handle direct file requests (fallback)
    if (path.contains('/')) {
      return await _serveMediaFile(path);
    }

    return Response.notFound('Not found');
  }

  static Response _indexPage() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final html = '''
<!DOCTYPE html>
<html>
<head>
    <title>Media Gallery</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #6C63FF 0%, #4CAF50 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            padding: 40px 20px;
            color: white;
        }
        
        .header-icon {
            font-size: 64px;
            margin-bottom: 16px;
            animation: float 3s ease-in-out infinite;
        }
        
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-10px); }
        }
        
        .header h1 {
            font-size: 48px;
            font-weight: 700;
            margin-bottom: 12px;
            text-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        
        .header p {
            font-size: 18px;
            opacity: 0.9;
        }
        
        .content-wrapper {
            background: white;
            border-radius: 32px 32px 0 0;
            padding: 40px 20px;
            min-height: 60vh;
            box-shadow: 0 -8px 32px rgba(0,0,0,0.1);
        }
        
        .stats-bar {
            display: flex;
            justify-content: center;
            gap: 32px;
            margin-bottom: 40px;
            flex-wrap: wrap;
        }
        
        .stat-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 16px 24px;
            background: linear-gradient(135deg, #6C63FF 0%, #5A52D5 100%);
            border-radius: 16px;
            color: white;
            box-shadow: 0 4px 12px rgba(108, 99, 255, 0.3);
        }
        
        .stat-icon {
            font-size: 32px;
        }
        
        .stat-info {
            text-align: left;
        }
        
        .stat-label {
            font-size: 12px;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .stat-value {
            font-size: 24px;
            font-weight: 700;
        }
        
        .media-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 24px;
            margin-top: 20px;
        }
        
        .media-item {
            background: white;
            border-radius: 20px;
            overflow: hidden;
            box-shadow: 0 8px 24px rgba(0,0,0,0.08);
            cursor: pointer;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
        }
        
        .media-item:hover {
            transform: translateY(-8px);
            box-shadow: 0 16px 40px rgba(0,0,0,0.15);
        }
        
        .media-preview {
            position: relative;
            width: 100%;
            height: 280px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            overflow: hidden;
        }
        
        .media-item img, .media-item video {
            width: 100%;
            height: 100%;
            object-fit: cover;
            transition: transform 0.3s ease;
        }
        
        .media-item:hover img,
        .media-item:hover video {
            transform: scale(1.1);
        }
        
        .media-type-badge {
            position: absolute;
            top: 16px;
            right: 16px;
            padding: 8px 16px;
            background: rgba(0,0,0,0.7);
            backdrop-filter: blur(10px);
            color: white;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .media-type-badge.image {
            background: rgba(33, 150, 243, 0.9);
        }
        
        .media-type-badge.video {
            background: rgba(156, 39, 176, 0.9);
        }
        
        .media-info {
            padding: 20px;
        }
        
        .media-name {
            font-weight: 600;
            font-size: 16px;
            color: #2D2D2D;
            margin-bottom: 8px;
            word-break: break-word;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
        }
        
        .media-meta {
            display: flex;
            align-items: center;
            gap: 8px;
            color: #999;
            font-size: 13px;
        }
        
        .loading {
            text-align: center;
            padding: 80px 20px;
        }
        
        .loading-spinner {
            display: inline-block;
            width: 60px;
            height: 60px;
            border: 6px solid rgba(108, 99, 255, 0.2);
            border-top-color: #6C63FF;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        .loading-text {
            margin-top: 24px;
            font-size: 18px;
            color: #666;
        }
        
        .empty-state {
            text-align: center;
            padding: 80px 20px;
        }
        
        .empty-icon {
            font-size: 96px;
            opacity: 0.3;
            margin-bottom: 24px;
        }
        
        .empty-title {
            font-size: 28px;
            font-weight: 700;
            color: #2D2D2D;
            margin-bottom: 12px;
        }
        
        .empty-text {
            font-size: 16px;
            color: #666;
            line-height: 1.6;
        }
        
        .error-state {
            text-align: center;
            padding: 80px 20px;
        }
        
        .error-icon {
            font-size: 80px;
            margin-bottom: 24px;
        }
        
        .error-title {
            font-size: 24px;
            font-weight: 700;
            color: #f44336;
            margin-bottom: 12px;
        }
        
        .error-text {
            font-size: 16px;
            color: #666;
            line-height: 1.6;
        }
        
        @media (max-width: 768px) {
            .header h1 {
                font-size: 36px;
            }
            
            .media-grid {
                grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
                gap: 16px;
            }
            
            .stats-bar {
                gap: 16px;
            }
            
            .stat-item {
                padding: 12px 16px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-icon">🎬</div>
            <h1>Media Gallery</h1>
            <p>Browse and view your shared media</p>
        </div>
        
        <div class="content-wrapper">
            <div class="stats-bar" id="stats-bar" style="display: none;">
                <div class="stat-item">
                    <div class="stat-icon">📸</div>
                    <div class="stat-info">
                        <div class="stat-label">Images</div>
                        <div class="stat-value" id="image-count">0</div>
                    </div>
                </div>
                <div class="stat-item">
                    <div class="stat-icon">🎥</div>
                    <div class="stat-info">
                        <div class="stat-label">Videos</div>
                        <div class="stat-value" id="video-count">0</div>
                    </div>
                </div>
                <div class="stat-item">
                    <div class="stat-icon">📁</div>
                    <div class="stat-info">
                        <div class="stat-label">Total</div>
                        <div class="stat-value" id="total-count">0</div>
                    </div>
                </div>
            </div>
            
            <div id="routes-container" class="loading">
                <div class="loading-spinner"></div>
                <div class="loading-text">Loading routes...</div>
            </div>
        </div>
    </div>
    
    <script>
        async function loadRoutes() {
            const container = document.getElementById('routes-container');
            const statsBar = document.getElementById('stats-bar');
            
            // Show loading state
            container.className = 'loading';
            container.innerHTML = '<div class="loading-spinner"></div><div class="loading-text">Loading routes...</div>';
            
            try {
                // Add timeout to fetch
                const controller = new AbortController();
                const timeoutId = setTimeout(function() {
                    controller.abort();
                }, 10000); // 10 second timeout
                
                const response = await fetch('/api/routes?t=' + Date.now(), {
                    method: 'GET',
                    headers: {
                        'Accept': 'application/json',
                    },
                    cache: 'no-cache',
                    signal: controller.signal
                });
                
                clearTimeout(timeoutId);
                
                if (!response.ok) {
                    const errorText = await response.text();
                    throw new Error('HTTP ' + response.status + ': ' + errorText);
                }
                
                const text = await response.text();
                let routes;
                try {
                    routes = JSON.parse(text);
                } catch (e) {
                    throw new Error('Invalid JSON response: ' + text.substring(0, 100));
                }
                
                // Hide loading immediately
                container.className = '';
                container.innerHTML = '';
                
                if (!routes || !Array.isArray(routes) || routes.length === 0) {
                    statsBar.style.display = 'none';
                    container.className = 'empty-state';
                    container.innerHTML = 
                        '<div class="empty-icon">🗺️</div>' +
                        '<div class="empty-title">No Routes Yet</div>' +
                        '<div class="empty-text">Add routes using the mobile app<br>to access your media here</div>';
                    return;
                }
                
                // Calculate stats
                const imageCount = routes.filter(function(route) { return route.isImage === true; }).length;
                const videoCount = routes.filter(function(route) { return route.isVideo === true; }).length;
                
                document.getElementById('image-count').textContent = imageCount;
                document.getElementById('video-count').textContent = videoCount;
                document.getElementById('total-count').textContent = routes.length;
                statsBar.style.display = 'flex';
                
                container.className = 'media-grid';
                container.innerHTML = routes.map(function(route) {
                    const isImage = route.isImage === true;
                    const typeClass = isImage ? 'image' : 'video';
                    const icon = isImage ? '📷' : '🎬';
                    const routePath = '/' + (route.route || '');
                    const mediaName = route.mediaName || 'Unknown';
                    
                    return '<div class="media-item" data-route="' + routePath.replace(/"/g, '&quot;') + '">' +
                        '<div class="media-preview" style="display: flex; align-items: center; justify-content: center; background: linear-gradient(135deg, ' + 
                        (isImage ? '#2196F3, #1976D2' : '#9C27B0, #7B1FA2') + ');">' +
                            '<div style="font-size: 80px;">' + icon + '</div>' +
                            '<div class="media-type-badge ' + typeClass + '">' + (isImage ? 'image' : 'video') + '</div>' +
                        '</div>' +
                        '<div class="media-info">' +
                            '<div class="media-name">' + routePath.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</div>' +
                            '<div class="media-meta">' +
                                '<span>' + icon + '</span>' +
                                '<span>' + mediaName.replace(/</g, '&lt;').replace(/>/g, '&gt;') + '</span>' +
                            '</div>' +
                        '</div>' +
                    '</div>';
                }).join('');
                
                // Add click event listeners to all media items
                container.querySelectorAll('.media-item').forEach(function(item) {
                    item.addEventListener('click', function() {
                        const route = item.getAttribute('data-route');
                        if (route) {
                            window.open(route, '_blank');
                        }
                    });
                });
            } catch (error) {
                console.error('Error loading routes:', error);
                statsBar.style.display = 'none';
                container.className = 'error-state';
                const errorMsg = error.name === 'AbortError' ? 'Request timeout. Please try again.' : (error.message || 'Unknown error');
                container.innerHTML = 
                    '<div class="error-icon">⚠️</div>' +
                    '<div class="error-title">Unable to Load Routes</div>' +
                    '<div class="error-text">' + errorMsg + '<br><button onclick="loadRoutes()" style="margin-top: 20px; padding: 10px 20px; background: #6C63FF; color: white; border: none; border-radius: 8px; cursor: pointer;">Retry</button></div>';
            }
        }
        
        // Load routes when page is ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', loadRoutes);
        } else {
            loadRoutes();
        }
    </script>
</body>
</html>
''';
    return Response.ok(html, headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
      'Pragma': 'no-cache',
      'Expires': '0',
      'Last-Modified': DateTime.now().toUtc().toIso8601String(),
      'ETag': '$timestamp',
    });
  }

  static Future<Response> _getMediaList(Request request) async {
    try {
      // Get query parameter for refresh
      final refresh = request.url.queryParameters['refresh'] == 'true';
      
      // Add timeout to prevent hanging
      final mediaFiles = await _mediaService!.getMediaFiles(forceRefresh: refresh)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        return <MediaFile>[];
      });
      
      final jsonList = mediaFiles.map((file) => <String, dynamic>{
        'name': file.name,
        'path': file.path,
        'type': file.isImage ? 'image' : 'video',
      }).toList();

      return Response.ok(
        jsonEncode(jsonList),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      // Return empty list on error instead of failing
      return Response.ok(
        jsonEncode(<Map<String, dynamic>>[]),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  static Future<Response> _serveMediaFile(String path) async {
    try {
      // Remove 'media/' prefix to get the asset path
      final assetPath = path.replaceFirst('media/', '');
      final file = await _mediaService!.getMediaFile(assetPath);

      if (file == null) {
        return Response.notFound('File not found');
      }

      final fileContent = await file.readAsBytes();
      
      // Determine content type based on file extension
      final fileName = file.path.toLowerCase();
      String contentType;
      if (fileName.endsWith('.mp4') || fileName.endsWith('.m4v')) {
        contentType = 'video/mp4';
      } else if (fileName.endsWith('.mov')) {
        contentType = 'video/quicktime';
      } else if (fileName.endsWith('.avi')) {
        contentType = 'video/x-msvideo';
      } else if (fileName.endsWith('.webm')) {
        contentType = 'video/webm';
      } else if (fileName.endsWith('.png')) {
        contentType = 'image/png';
      } else if (fileName.endsWith('.gif')) {
        contentType = 'image/gif';
      } else if (fileName.endsWith('.webp')) {
        contentType = 'image/webp';
      } else {
        contentType = 'image/jpeg';
      }

      return Response.ok(
        fileContent,
        headers: {
          'Content-Type': contentType,
          'Content-Length': fileContent.length.toString(),
          'Cache-Control': 'public, max-age=3600',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error serving file: $e');
    }
  }

  static Future<Response> _handleUpload(Request request) async {
    try {
      final contentType = request.headers['content-type'] ?? '';
      
      if (!contentType.contains('multipart/form-data')) {
        return Response.badRequest(body: 'Expected multipart/form-data');
      }

      // Read all bytes from the stream
      final bodyStream = request.read();
      final bodyBytesList = <int>[];
      await for (final chunk in bodyStream) {
        bodyBytesList.addAll(chunk);
      }
      final bodyBytes = bodyBytesList;
      
      // Extract boundary
      final boundaryMatch = RegExp(r'boundary=([^;]+)').firstMatch(contentType);
      if (boundaryMatch == null) {
        return Response.badRequest(body: 'No boundary found');
      }
      final boundary = '--${boundaryMatch.group(1)!.trim()}';
      final boundaryBytes = utf8.encode(boundary);
      
      // Find all boundary positions
      final boundaries = <int>[];
      int pos = 0;
      while (pos < bodyBytes.length) {
        final found = _findBytes(bodyBytes, boundaryBytes, pos);
        if (found == -1) break;
        boundaries.add(found);
        pos = found + boundaryBytes.length;
      }
      
      if (boundaries.length < 2) {
        return Response.badRequest(body: 'Invalid multipart data');
      }
      
      // Process each part between boundaries
      for (int i = 0; i < boundaries.length - 1; i++) {
        final partStart = boundaries[i] + boundaryBytes.length;
        final partEnd = boundaries[i + 1];
        
        // Skip CRLF after boundary
        int dataStart = partStart;
        if (dataStart < bodyBytes.length - 1 && 
            bodyBytes[dataStart] == 13 && bodyBytes[dataStart + 1] == 10) {
          dataStart += 2;
        }
        
        final partBytes = bodyBytes.sublist(dataStart, partEnd);
        final partString = utf8.decode(partBytes.take(500).toList()); // Only decode header part
        
        if (partString.contains('Content-Disposition') && partString.contains('filename=')) {
          // Extract filename
          final filenameMatch = RegExp(r'filename="?([^";\r\n]+)"?').firstMatch(partString);
          if (filenameMatch != null) {
            final filename = filenameMatch.group(1)!.trim();
            
            // Find where file data starts (after headers)
            final headerEnd = partString.indexOf('\r\n\r\n');
            if (headerEnd > 0) {
              final headerBytes = utf8.encode(partString.substring(0, headerEnd + 4));
              final fileDataStart = headerBytes.length;
              final fileBytes = partBytes.sublist(fileDataStart);
              
              // Remove trailing CRLF and boundary markers
              while (fileBytes.isNotEmpty && 
                     (fileBytes.last == 10 || fileBytes.last == 13)) {
                fileBytes.removeLast();
              }
              
              // Save file
              final saved = await _mediaService!.saveUploadedFile(filename, fileBytes);
              if (saved != null) {
                // Clear cache to refresh media list
                _mediaService!.clearCache();
                return Response.ok(
                  jsonEncode({'success': true, 'message': 'File uploaded successfully', 'file': filename}),
                  headers: {'Content-Type': 'application/json'},
                );
              }
            }
          }
        }
      }

      return Response.badRequest(body: 'No file found in upload');
    } catch (e) {
      return Response.internalServerError(body: 'Error uploading file: $e');
    }
  }

  static Future<Response> _getRoutes(Request request) async {
    try {
      final routes = await _routeManager!.getRoutes();
      final jsonList = routes.map((route) => route.toJson()).toList();
      return Response.ok(
        jsonEncode(jsonList),
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  static Future<Response> _addRoute(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      
      final route = data['route'] as String;
      final mediaPath = data['mediaPath'] as String;
      final mediaName = data['mediaName'] as String;
      final isImage = data['isImage'] as bool? ?? false;
      final isVideo = data['isVideo'] as bool? ?? false;

      final success = await _routeManager!.addRoute(route, mediaPath, mediaName, isImage, isVideo);
      
      if (success) {
        return Response.ok(
          jsonEncode({'success': true, 'message': 'Route added successfully'}),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'message': 'Route already exists'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  static Future<Response> _deleteRoute(Request request) async {
    try {
      final route = request.url.queryParameters['route'];
      if (route == null) {
        return Response.badRequest(body: 'Route parameter required');
      }

      final success = await _routeManager!.deleteRoute(route);
      
      if (success) {
        return Response.ok(
          jsonEncode({'success': true, 'message': 'Route deleted successfully'}),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.notFound(
          jsonEncode({'success': false, 'message': 'Route not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response.internalServerError(body: 'Error: $e');
    }
  }

  static Future<Response> _serveVideoFile(MediaRoute route) async {
    try {
      final file = File(route.mediaPath);
      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      final fileContent = await file.readAsBytes();
      
      // Determine video content type
      String contentType;
      if (route.mediaPath.toLowerCase().endsWith('.mp4') || 
          route.mediaPath.toLowerCase().endsWith('.m4v')) {
        contentType = 'video/mp4';
      } else if (route.mediaPath.toLowerCase().endsWith('.mov')) {
        contentType = 'video/quicktime';
      } else if (route.mediaPath.toLowerCase().endsWith('.webm')) {
        contentType = 'video/webm';
      } else if (route.mediaPath.toLowerCase().endsWith('.mkv')) {
        contentType = 'video/x-matroska';
      } else {
        contentType = 'video/mp4';
      }

      return Response.ok(
        fileContent,
        headers: {
          'Content-Type': contentType,
          'Content-Length': fileContent.length.toString(),
          'Cache-Control': 'public, max-age=3600',
          'Accept-Ranges': 'bytes',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error serving video: $e');
    }
  }

  static Future<Response> _serveImageFile(MediaRoute route) async {
    try {
      final file = File(route.mediaPath);
      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      final fileContent = await file.readAsBytes();
      
      // Determine image content type
      String contentType;
      if (route.mediaPath.toLowerCase().endsWith('.png')) {
        contentType = 'image/png';
      } else if (route.mediaPath.toLowerCase().endsWith('.gif')) {
        contentType = 'image/gif';
      } else if (route.mediaPath.toLowerCase().endsWith('.webp')) {
        contentType = 'image/webp';
      } else if (route.mediaPath.toLowerCase().endsWith('.bmp')) {
        contentType = 'image/bmp';
      } else if (route.mediaPath.toLowerCase().endsWith('.svg')) {
        contentType = 'image/svg+xml';
      } else {
        contentType = 'image/jpeg';
      }

      return Response.ok(
        fileContent,
        headers: {
          'Content-Type': contentType,
          'Content-Length': fileContent.length.toString(),
          'Cache-Control': 'public, max-age=3600',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error serving image: $e');
    }
  }

  static Future<Response> _serveCustomRoute(MediaRoute route) async {
    try {
      final file = File(route.mediaPath);
      if (!await file.exists()) {
        return Response.notFound('File not found');
      }

      // For videos, serve an HTML page with fullscreen autoplay video
      if (route.isVideo) {
        final videoUrl = '/' + route.route + '?file=1';
        final html = _createVideoPage(videoUrl, route.mediaName);
        return Response.ok(
          html,
          headers: {
            'Content-Type': 'text/html; charset=utf-8',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        );
      }

      // For images, serve as video (single frame) to use fullscreen feature
      final imageUrl = '/' + route.route + '?file=1';
      final html = _createImageAsVideoPage(imageUrl, route.mediaName);
      return Response.ok(
        html,
        headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: 'Error serving route: $e');
    }
  }

  static String _createVideoPage(String videoUrl, String videoName) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>${videoName}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        html, body {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: #000;
            position: fixed;
            top: 0;
            left: 0;
        }
        
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        video {
            width: 100vw;
            height: 100vh;
            object-fit: contain;
            outline: none;
            background: #000;
        }
        
        .loading {
            position: absolute;
            color: white;
            font-size: 18px;
            opacity: 0.7;
            z-index: 1;
        }
    </style>
</head>
<body>
    <div class="loading" id="loading" style="display: none;"></div>
    <video 
        id="videoPlayer"
        autoplay 
        loop 
        playsinline
        controls
        preload="auto"
        onloadeddata="enterFullscreen()"
        onerror="handleError()">
        <source src="${videoUrl}" type="video/mp4">
    </video>
    
    <script>
        const video = document.getElementById('videoPlayer');
        const loading = document.getElementById('loading');
        
        function enterFullscreen() {
            loading.style.display = 'none';
            
            // Enter fullscreen automatically
            setTimeout(function() {
                if (document.documentElement.requestFullscreen) {
                    document.documentElement.requestFullscreen().catch(function(err) {
                        console.log('Fullscreen request failed:', err);
                    });
                } else if (document.documentElement.webkitRequestFullscreen) {
                    document.documentElement.webkitRequestFullscreen();
                } else if (document.documentElement.mozRequestFullScreen) {
                    document.documentElement.mozRequestFullScreen();
                } else if (document.documentElement.msRequestFullscreen) {
                    document.documentElement.msRequestFullscreen();
                }
            }, 100);
            
            // Ensure video plays
            video.play().catch(function(err) {
                console.log('Autoplay failed:', err);
            });
        }
        
        function handleError() {
            loading.textContent = 'Error loading video';
            loading.style.color = '#f44336';
            loading.style.display = 'block';
        }
        
        // Handle fullscreen changes - re-enter if exited
        document.addEventListener('fullscreenchange', function() {
            if (!document.fullscreenElement) {
                setTimeout(function() {
                    if (document.documentElement.requestFullscreen) {
                        document.documentElement.requestFullscreen().catch(function() {});
                    }
                }, 300);
            }
        });
        
        document.addEventListener('webkitfullscreenchange', function() {
            if (!document.webkitFullscreenElement) {
                setTimeout(function() {
                    if (document.documentElement.webkitRequestFullscreen) {
                        document.documentElement.webkitRequestFullscreen();
                    }
                }, 300);
            }
        });
        
        document.addEventListener('mozfullscreenchange', function() {
            if (!document.mozFullScreenElement) {
                setTimeout(function() {
                    if (document.documentElement.mozRequestFullScreen) {
                        document.documentElement.mozRequestFullScreen();
                    }
                }, 300);
            }
        });
        
        // Ensure video restarts when it ends
        video.addEventListener('ended', function() {
            video.currentTime = 0;
            video.play();
        });
        
        // Handle visibility change - restart video when page becomes visible
        document.addEventListener('visibilitychange', function() {
            if (!document.hidden && video.paused) {
                video.play();
            }
        });
        
        // Prevent context menu
        document.addEventListener('contextmenu', function(e) {
            e.preventDefault();
        });
        
        // Prevent text selection
        document.addEventListener('selectstart', function(e) {
            e.preventDefault();
        });
    </script>
</body>
</html>
''';
  }

  static String _createImageAsVideoPage(String imageUrl, String imageName) {
    return '''
<!DOCTYPE html>
<html>
<head>
    <title>${imageName}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        html, body {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: #000;
            position: fixed;
            top: 0;
            left: 0;
        }
        
        body {
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        video {
            width: 100vw;
            height: 100vh;
            object-fit: contain;
            outline: none;
            background: #000;
        }
        
        canvas {
            display: none;
        }
        
        .loading {
            position: absolute;
            color: white;
            font-size: 18px;
            opacity: 0.7;
            z-index: 1;
        }
    </style>
</head>
<body>
    <div class="loading" id="loading">Loading image...</div>
    <canvas id="imageCanvas"></canvas>
    <video 
        id="videoPlayer"
        autoplay 
        loop 
        playsinline
        muted
        controls
        preload="auto"
        onloadeddata="enterFullscreen()"
        onerror="handleError()">
    </video>
    
    <script>
        const video = document.getElementById('videoPlayer');
        const canvas = document.getElementById('imageCanvas');
        const loading = document.getElementById('loading');
        const ctx = canvas.getContext('2d');
        const img = new Image();
        
        img.crossOrigin = 'anonymous';
        img.onload = function() {
            // Set canvas size to match image
            canvas.width = img.width;
            canvas.height = img.height;
            
            // Draw image on canvas
            ctx.drawImage(img, 0, 0);
            
            // Convert canvas to video stream (30 FPS for smooth playback)
            const stream = canvas.captureStream(30);
            
            // Set video source to the stream
            video.srcObject = stream;
            
            // Play the video
            video.play().then(function() {
                loading.style.display = 'none';
                enterFullscreen();
            }).catch(function(err) {
                console.log('Video play failed:', err);
                loading.style.display = 'none';
                enterFullscreen();
            });
        };
        
        img.onerror = function() {
            handleError();
        };
        
        // Load the image
        img.src = '${imageUrl}';
        
        function enterFullscreen() {
            // Enter fullscreen automatically
            setTimeout(function() {
                if (document.documentElement.requestFullscreen) {
                    document.documentElement.requestFullscreen().catch(function(err) {
                        console.log('Fullscreen request failed:', err);
                    });
                } else if (document.documentElement.webkitRequestFullscreen) {
                    document.documentElement.webkitRequestFullscreen();
                } else if (document.documentElement.mozRequestFullScreen) {
                    document.documentElement.mozRequestFullScreen();
                } else if (document.documentElement.msRequestFullscreen) {
                    document.documentElement.msRequestFullscreen();
                }
            }, 100);
        }
        
        function handleError() {
            loading.textContent = 'Error loading image';
            loading.style.color = '#f44336';
            loading.style.display = 'block';
        }
        
        // Handle fullscreen changes - re-enter if exited
        document.addEventListener('fullscreenchange', function() {
            if (!document.fullscreenElement) {
                setTimeout(function() {
                    if (document.documentElement.requestFullscreen) {
                        document.documentElement.requestFullscreen().catch(function() {});
                    }
                }, 300);
            }
        });
        
        document.addEventListener('webkitfullscreenchange', function() {
            if (!document.webkitFullscreenElement) {
                setTimeout(function() {
                    if (document.documentElement.webkitRequestFullscreen) {
                        document.documentElement.webkitRequestFullscreen();
                    }
                }, 300);
            }
        });
        
        document.addEventListener('mozfullscreenchange', function() {
            if (!document.mozFullScreenElement) {
                setTimeout(function() {
                    if (document.documentElement.mozRequestFullScreen) {
                        document.documentElement.mozRequestFullScreen();
                    }
                }, 300);
            }
        });
        
        // Ensure video restarts when it ends (loop should handle this, but as backup)
        video.addEventListener('ended', function() {
            video.currentTime = 0;
            video.play();
        });
        
        // Handle visibility change - restart video when page becomes visible
        document.addEventListener('visibilitychange', function() {
            if (!document.hidden && video.paused) {
                video.play();
            }
        });
        
        // Prevent context menu
        document.addEventListener('contextmenu', function(e) {
            e.preventDefault();
        });
        
        // Prevent text selection
        document.addEventListener('selectstart', function(e) {
            e.preventDefault();
        });
    </script>
</body>
</html>
''';
  }

  static int _findBytes(List<int> haystack, List<int> needle, int start) {
    for (int i = start; i <= haystack.length - needle.length; i++) {
      bool found = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          found = false;
          break;
        }
      }
      if (found) return i;
    }
    return -1;
  }
}

