import 'package:flutter/material.dart';

@immutable
class ActivityItemEntity {
  const ActivityItemEntity({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.icon,
    required this.refId,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final String kind; // book | pay | social | rooms | shop | agent
  final String title;
  final String body;
  final String icon; // emoji glyph from the backend
  final String? refId;
  final DateTime createdAt;
  final bool isRead;
}
