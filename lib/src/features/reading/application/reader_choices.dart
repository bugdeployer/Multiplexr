class InstalledReader {
  const InstalledReader({required this.package, required this.label});
  final String package, label;
}

abstract interface class ReaderChoices {
  Future<List<InstalledReader>> installedReaders(String format);
}
