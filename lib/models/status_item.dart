class StatusItem {
  StatusItem({
    required this.uri,
    required this.name,
    required this.isVideo,
    required this.lastModified,
  });

  factory StatusItem.fromMap(Map<dynamic, dynamic> map) => StatusItem(
        uri: map['uri'] as String,
        name: map['name'] as String,
        isVideo: map['isVideo'] as bool,
        lastModified: DateTime.fromMillisecondsSinceEpoch(
          (map['lastModified'] as num).toInt(),
        ),
      );

  /// content:// (SAF / MediaStore) or file:// (legacy) URI.
  final String uri;
  final String name;
  final bool isVideo;
  final DateTime lastModified;

  String get heroTag => 'status-$uri';
}
