/// The home screen's quick-action grid is exactly the eight top-level
/// Phlio domains from Phlio_Final_Product_Blueprint.md section 3 — one
/// slot each. Order matches the backend's `_QUICK_ACTIONS` list in
/// `backend/app/domains/home/service.py`.
enum QuickActionKind { pay, social, rooms, book, shop, stream, news, agent }

class QuickActionEntity {
  const QuickActionEntity({required this.kind, required this.label, required this.isAvailable});

  factory QuickActionEntity.fromApiValue(String value, String label, bool isAvailable) {
    final kind = QuickActionKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () => QuickActionKind.shop,
    );
    return QuickActionEntity(kind: kind, label: label, isAvailable: isAvailable);
  }

  final QuickActionKind kind;
  final String label;
  final bool isAvailable;
}
