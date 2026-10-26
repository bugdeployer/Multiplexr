import 'library_models.dart';
import 'library_service.dart';
import '../media/audio_library.dart';

/// Narrow host surface for infrastructure facades; adapters never import the
/// observable UI controller or construct another persistence/session owner.
abstract interface class LibraryAdapterHost {
  LibraryService get service;
  List<VideoCollection> get collections;
  Set<String> get scanning;
  bool get metadataRunning;
  bool Function()? get otherJobsRunning;
  bool canAccessCollection(String id);
  List<VideoAsset> items(String id);
  List<VideoAsset> indexedItems(String id);
  AudioLibrary audiobookCatalog({String? collectionId});
  Future<void> load();
  Future<void> scan(String id);
  void endCollectionSession();
  void notifyListeners();
}
