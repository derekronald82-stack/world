class User8DCreation {
  final int id;
  final String title;
  final String sourceFilename;
  final String outputUrl;
  final bool savedToCatws;
  final DateTime createdAt;

  const User8DCreation({
    required this.id,
    required this.title,
    required this.sourceFilename,
    required this.outputUrl,
    required this.savedToCatws,
    required this.createdAt,
  });

  factory User8DCreation.fromJson(Map<String, dynamic> j) => User8DCreation(
        id: j['id'] as int,
        title: (j['title'] ?? 'My 8D Song').toString(),
        sourceFilename: (j['source_filename'] ?? 'audio').toString(),
        outputUrl: (j['output_url'] ?? '').toString(),
        savedToCatws: j['saved_to_catws'] == true,
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ?? DateTime.now(),
      );
}
