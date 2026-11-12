import 'dart:io';

import 'package:flutter/material.dart';

/// Full-screen preview for image files in the library (pinch to zoom).
class ImageViewer extends StatelessWidget {
  final String path;
  final String name;

  const ImageViewer({super.key, required this.path, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.file(
            File(path),
            errorBuilder: (_, __, ___) => const Text('Could not open this image', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ),
    );
  }
}
