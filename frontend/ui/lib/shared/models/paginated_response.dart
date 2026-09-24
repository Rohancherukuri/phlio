// Generic cursor-paginated response, mirroring the backend's
// `app/common/schemas.py::Page[T]`. Each feature's data layer parses its
// own item type `T` and hands back a `PaginatedResponse<T>` so
// controllers have one consistent shape to manage "load more" with.

class PaginatedResponse<T> {
  const PaginatedResponse({required this.items, required this.nextCursor, required this.hasMore});

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final items = (json['items'] as List<dynamic>)
        .map((item) => itemFromJson(item as Map<String, dynamic>))
        .toList();
    final meta = json['meta'] as Map<String, dynamic>;
    return PaginatedResponse(
      items: items,
      nextCursor: meta['next_cursor'] as String?,
      hasMore: meta['has_more'] as bool? ?? false,
    );
  }

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
}
