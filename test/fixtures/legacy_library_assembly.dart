// Historical cover-download transport is opt-in for provider parser fixtures.
import 'package:multiplexr/src/bootstrap/library_assembly.dart' as production;
export 'package:multiplexr/src/bootstrap/library_assembly.dart' hide createAudioLibrary;
import 'package:multiplexr/src/library/library_service.dart';
import 'package:multiplexr/src/media/audio_library.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'legacy_audiobook_metadata_service.dart';
AudioLibrary createAudioLibrary(LibraryService service, {
  String? collectionId, bool Function(String)? authorized, AudioController? audio,
  MetadataWorkflow Function()? metadataWorkflow, Future<String> Function(String,String)? artworkDownload,
}) => production.createAudioLibrary(service,collectionId:collectionId,authorized:authorized,
  audio:audio,metadataWorkflow:metadataWorkflow,
  artworkDownload:artworkDownload ?? (url, provider) => const AudiobookMetadataService().cover(url,provider:provider));
