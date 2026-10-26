/// File-picker results are normalized by the host, independent of its UI.
abstract interface class MediaImports {
  Future<String?> cover();
  Future<String?> chapterDocument();
  Future<void> openAudio(String uri);
}
