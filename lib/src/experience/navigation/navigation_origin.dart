/// Serializable source state, independent of Flutter routes and widgets.
class NavigationOrigin {
  const NavigationOrigin({
    required this.routeId,
    this.collectionId,
    this.query = '',
    this.sort = '',
    this.filter = '',
    this.folder = '',
    this.tag = '',
    this.tab = 0,
    this.scrollOffset = 0,
    this.layout = '',
  });
  final String routeId, query, sort, filter, folder, tag, layout;
  final String? collectionId;
  final int tab;
  final double scrollOffset;
  Map<String, dynamic> toJson() => {
    'routeId': routeId,
    'collectionId': collectionId,
    'query': query,
    'sort': sort,
    'filter': filter,
    'folder': folder,
    'tag': tag,
    'tab': tab,
    'scrollOffset': scrollOffset,
    'layout': layout,
  };
  factory NavigationOrigin.fromJson(Map<String, dynamic> data) {
    final offset = data['scrollOffset'];
    if (data['routeId'] is! String ||
        (data['routeId'] as String).isEmpty ||
        data['tab'] is! int ||
        (data['tab'] as int) < 0 ||
        offset is! num ||
        !offset.isFinite ||
        offset < 0 ||
        (data['collectionId'] != null && data['collectionId'] is! String) ||
        [
          'query',
          'sort',
          'filter',
          'folder',
          'tag',
          'layout',
        ].any((k) => data[k] is! String)) {
      throw const FormatException('Invalid navigation origin.');
    }
    return NavigationOrigin(
      routeId: data['routeId'],
      collectionId: data['collectionId'],
      query: data['query'],
      sort: data['sort'],
      filter: data['filter'],
      folder: data['folder'],
      tag: data['tag'],
      tab: data['tab'],
      scrollOffset: offset.toDouble(),
      layout: data['layout'],
    );
  }
}
