import 'dart:io';
import 'dart:convert';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';

class MediaFile {
  final String name;
  final String path;
  final bool isImage;
  final bool isVideo;
  final File file;

  MediaFile({
    required this.name,
    required this.path,
    required this.isImage,
    required this.isVideo,
    required this.file,
  });
}

class MediaService {
  List<MediaFile>? _cachedFiles;

  Future<List<MediaFile>> getMediaFiles({bool forceRefresh = false}) async {
    // Return cached files immediately if available and not forcing refresh
    if (!forceRefresh && _cachedFiles != null && _cachedFiles!.isNotEmpty) {
      return _cachedFiles!;
    }

    final mediaFiles = <MediaFile>[];

    try {
      // Request permission with timeout
      final permission = await PhotoManager.requestPermissionExtend()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        return PermissionState.denied;
      });
      
      if (permission.isAuth) {
        try {
          // Get images with smaller range first
          final images = await PhotoManager.getAssetListRange(
            start: 0,
            end: 1000, // Reduced from 10000 to prevent timeout
            type: RequestType.image,
          ).timeout(const Duration(seconds: 10), onTimeout: () => <AssetEntity>[]);

          // Get videos
          final videos = await PhotoManager.getAssetListRange(
            start: 0,
            end: 1000, // Reduced from 10000 to prevent timeout
            type: RequestType.video,
          ).timeout(const Duration(seconds: 10), onTimeout: () => <AssetEntity>[]);

          // Convert to MediaFile objects (limit to first 100 to prevent timeout)
          final allAssets = [...images, ...videos].take(100).toList();
          
          for (final asset in allAssets) {
            try {
              final file = await asset.file.timeout(
                const Duration(seconds: 2),
                onTimeout: () => null,
              );
              if (file != null) {
                final isImage = asset.type == AssetType.image;
                final isVideo = asset.type == AssetType.video;
                
                // Create a unique path for serving
                final fileName = asset.title ?? 'unknown_${asset.id}';
                final path = 'media/${asset.id}/$fileName';

                mediaFiles.add(MediaFile(
                  name: fileName,
                  path: path,
                  isImage: isImage,
                  isVideo: isVideo,
                  file: file,
                ));
              }
            } catch (e) {
              // Skip files that can't be accessed
              continue;
            }
          }
        } catch (e) {
          // Continue even if photo manager fails
        }
      }
    } catch (e) {
      // Continue even if photo manager fails
    }

    // Always add uploaded files (these are most reliable)
    try {
      final directory = await getApplicationDocumentsDirectory();
      final uploadsDir = Directory('${directory.path}/uploads');
      if (await uploadsDir.exists()) {
        final uploadFiles = await uploadsDir.list().toList();
        for (var entity in uploadFiles) {
          if (entity is File) {
            try {
              final fileName = entity.path.split('/').last;
              final isImage = fileName.toLowerCase().endsWith('.jpg') ||
                  fileName.toLowerCase().endsWith('.jpeg') ||
                  fileName.toLowerCase().endsWith('.png') ||
                  fileName.toLowerCase().endsWith('.gif') ||
                  fileName.toLowerCase().endsWith('.webp') ||
                  fileName.toLowerCase().endsWith('.bmp');
              final isVideo = fileName.toLowerCase().endsWith('.mp4') ||
                  fileName.toLowerCase().endsWith('.mov') ||
                  fileName.toLowerCase().endsWith('.avi') ||
                  fileName.toLowerCase().endsWith('.webm') ||
                  fileName.toLowerCase().endsWith('.mkv');

              if (isImage || isVideo) {
                mediaFiles.add(MediaFile(
                  name: fileName,
                  path: 'media/uploads/$fileName',
                  isImage: isImage,
                  isVideo: isVideo,
                  file: entity,
                ));
              }
            } catch (e) {
              // Skip problematic files
              continue;
            }
          }
        }
      }
    } catch (e) {
      // Continue if uploads directory doesn't exist
    }

    // Always update cache, even if empty
    _cachedFiles = mediaFiles;
    
    return mediaFiles;
  }

  Future<File?> getMediaFile(String path) async {
    // Path format: media/{assetId}/{filename} or media/uploads/{filename}
    final normalizedPath = path.startsWith('media/') 
        ? path.replaceFirst('media/', '') 
        : path;
    
    // Check if it's an uploaded file
    if (normalizedPath.startsWith('uploads/')) {
      final fileName = normalizedPath.replaceFirst('uploads/', '');
      final directory = await getApplicationDocumentsDirectory();
      final uploadsDir = Directory('${directory.path}/uploads');
      final file = File('${uploadsDir.path}/$fileName');
      if (await file.exists()) {
        return file;
      }
    }
    
    final parts = normalizedPath.split('/');
    if (parts.isEmpty) return null;

    final assetId = parts[0];
    final assets = await getMediaFiles();
    
    // Find the file by matching the asset ID in the path
    for (final mediaFile in assets) {
      if (mediaFile.path.contains(assetId)) {
        return mediaFile.file;
      }
    }

    return null;
  }

  void clearCache() {
    _cachedFiles = null;
  }

  Future<File?> saveUploadedFile(String filename, List<int> fileBytes) async {
    try {
      // Get the downloads directory or app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final uploadsDir = Directory('${directory.path}/uploads');
      if (!await uploadsDir.exists()) {
        await uploadsDir.create(recursive: true);
      }

      // Save file as binary
      final file = File('${uploadsDir.path}/$filename');
      await file.writeAsBytes(fileBytes);

      // Clear cache to include new file
      clearCache();
      
      return file;
    } catch (e) {
      return null;
    }
  }
}

