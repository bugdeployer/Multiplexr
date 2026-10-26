class MetadataBatchJournal {
  MetadataBatchJournal({
    this.implementationEpoch = '',
    this.done = 0,
    this.total = 0,
    Iterable<String> remaining = const [],
    Map<String, Map<String, dynamic>> entries = const {},
  }) : remaining = List.unmodifiable(remaining),
       entries = Map.unmodifiable(
         entries.map((key, value) => MapEntry(key, _freezeMap(value))),
       );
  final String implementationEpoch;
  final int done, total;
  final List<String> remaining;
  final Map<String, Map<String, dynamic>> entries;
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) =>
    Map.unmodifiable(value.map((key, item) => MapEntry(key, _freeze(item))));
Object? _freeze(Object? value) => switch (value) {
  Map<String, dynamic> map => _freezeMap(map),
  List list => List.unmodifiable(list.map(_freeze)),
  _ => value,
};
