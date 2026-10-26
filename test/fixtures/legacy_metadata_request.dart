class MetadataSearchRequest {
  MetadataSearchRequest(this.type, this.query, {this.page}) {
    if (!{'movie', 'tv'}.contains(type) ||
        query.trim().isEmpty ||
        (page != null && (page! < 1 || page! > 500))) {
      throw ArgumentError('Invalid metadata query.');
    }
  }
  final String type, query;
  final int? page;
  Map<String, Object> toWire() => {'type': type, 'query': query, 'page': ?page};
}
