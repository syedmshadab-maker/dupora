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
class FileThumbnail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final category = categoryForExtension(extension);
    final scheme = Theme.of(context).colorScheme;

    if (category != PreviewCategory.image) {
      return _iconBox(category, scheme);
    }

    return FutureBuilder(
      future: thumbnailService.getThumbnail(path, modifiedAt),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return _iconBox(category, scheme);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
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
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorForCategory(category, scheme).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        iconForCategory(category),
        size: size * 0.55,
        color: colorForCategory(category, scheme),
      ),
    );
  }
}
