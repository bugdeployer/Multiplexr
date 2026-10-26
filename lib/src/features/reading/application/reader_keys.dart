abstract interface class ComicVolumeKeys {
  Future<void> configure(bool enabled, void Function(bool forward) turn);
  Future<void> close();
}

class NoReaderKeys implements ComicVolumeKeys {
  const NoReaderKeys();
  @override
  Future<void> configure(
    bool enabled,
    void Function(bool forward) turn,
  ) async {}
  @override
  Future<void> close() async {}
}
