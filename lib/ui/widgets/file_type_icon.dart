import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../features/preview/thumbnail_service.dart';

IconData iconForCategory(PreviewCategory category) {
  return switch (category) {
    PreviewCategory.image => Icons.image_outlined,
    PreviewCategory.video => Icons.movie_outlined,
    PreviewCategory.audio => Icons.audiotrack_outlined,
    PreviewCategory.pdf => Icons.picture_as_pdf_outlined,
    PreviewCategory.document => Icons.description_outlined,
    PreviewCategory.archive => Icons.folder_zip_outlined,
    PreviewCategory.other => Icons.insert_drive_file_outlined,
  };
}

Color colorForCategory(PreviewCategory category, ColorScheme scheme) {
  return switch (category) {
    PreviewCategory.image => Colors.teal,
    PreviewCategory.video => Colors.deepPurple,
    PreviewCategory.audio => Colors.orange,
    PreviewCategory.pdf => Colors.red,
    PreviewCategory.document => Colors.blue,
    PreviewCategory.archive => Colors.brown,
    PreviewCategory.other => scheme.onSurfaceVariant,
  };
}

/// A single result-grid/list tile icon: a decoded image thumbnail when
/// available and cheap, otherwise a category icon. Lazy: the thumbnail
/// fetch only starts once this widget is actually built (i.e. once
/// `ListView.builder`/`GridView.builder` virtualization scrolls it into
/// view), and results are cached by [ThumbnailService] so re-scrolling
/// past it is free.
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({
    super.key,
    required this.path,
    required this.modifiedAt,
    required this.extension,
    required this.thumbnailService,
    this.size = 40,
  });

  final String path;
  final DateTime modifiedAt;
  final String extension;
  final ThumbnailService thumbnailService;
  final double size;

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  final _cancelToken = ThumbnailCancelToken();
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _startFetch();
  }

  @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `ListView.builder`/`GridView.builder` reuse State objects across
    // different items as the user scrolls; without this, a recycled tile
    // could keep showing (or awaiting) the *previous* file's thumbnail.
    if (oldWidget.path != widget.path ||
        oldWidget.modifiedAt != widget.modifiedAt) {
      _startFetch();
    }
  }

  void _startFetch() {
    if (categoryForExtension(widget.extension) != PreviewCategory.image) {
      _future = null;
      return;
    }
    _future = widget.thumbnailService.getThumbnail(
      widget.path,
      widget.modifiedAt,
      cancelToken: _cancelToken,
    );
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = categoryForExtension(widget.extension);
    final scheme = Theme.of(context).colorScheme;

    if (category != PreviewCategory.image) {
      return _iconBox(category, scheme);
    }

    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return _iconBox(category, scheme);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _iconBox(category, scheme),
          ),
        );
      },
    );
  }

  Widget _iconBox(PreviewCategory category, ColorScheme scheme) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: colorForCategory(category, scheme).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        iconForCategory(category),
        size: widget.size * 0.55,
        color: colorForCategory(category, scheme),
      ),
    );
  }
}
