// Foxy's chat history: every conversation is kept on this device (the
// backend's agent memory is short-term only), searchable, renameable and
// in an order the user chooses — long-press a chat in the list and drag it
// up or down.
//
// Stored as JSON in the app-support folder, one file per signed-in user.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../authentication/presentation/controllers/auth_controller.dart';
import '../../domain/entities/agent_attachment_entity.dart';
import '../../domain/entities/agent_message_entity.dart';
import '../../domain/entities/agent_plan_entity.dart';

class AgentChat extends Equatable {
  const AgentChat({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.conversationId,
    this.customTitle = false,
  });

  final String id;

  /// The backend conversation the chat continues in (null until first reply).
  final String? conversationId;
  final String title;

  /// True once the user renamed it (auto-titles stop updating).
  final bool customTitle;
  final List<AgentMessageEntity> messages;
  final DateTime updatedAt;

  String get preview {
    for (final m in messages.reversed) {
      if (m.text.trim().isNotEmpty) return m.text.replaceAll('\n', ' ').trim();
      if (m.attachments.isNotEmpty) {
        return m.attachments.map((a) => a.name).join(', ');
      }
    }
    return 'New chat';
  }

  AgentChat copyWith({
    String? title,
    bool? customTitle,
    String? conversationId,
    List<AgentMessageEntity>? messages,
    DateTime? updatedAt,
  }) =>
      AgentChat(
        id: id,
        title: title ?? this.title,
        customTitle: customTitle ?? this.customTitle,
        conversationId: conversationId ?? this.conversationId,
        messages: messages ?? this.messages,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [id, title, conversationId, messages.length, updatedAt];
}

class AgentChatsState extends Equatable {
  const AgentChatsState({this.chats = const [], this.loaded = false});

  /// In the user's order (new chats go on top; drag to rearrange).
  final List<AgentChat> chats;
  final bool loaded;

  List<AgentChat> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return chats;
    return [
      for (final c in chats)
        if (c.title.toLowerCase().contains(q) ||
            c.messages.any((m) => m.text.toLowerCase().contains(q) ||
                m.attachments.any((a) => a.name.toLowerCase().contains(q))))
          c,
    ];
  }

  @override
  List<Object?> get props => [chats, loaded];
}

final agentChatsProvider =
    NotifierProvider<AgentChatsController, AgentChatsState>(AgentChatsController.new);

class AgentChatsController extends Notifier<AgentChatsState> {
  String? _userId;
  Timer? _saveTimer;

  @override
  AgentChatsState build() {
    _userId = ref.watch(authControllerProvider.select((v) => v.valueOrNull?.id));
    ref.onDispose(() => _saveTimer?.cancel());
    _load(_userId);
    return const AgentChatsState();
  }

  /// Auto title: the first thing the user asked (or the files they sent).
  static String titleFor(List<AgentMessageEntity> messages) {
    for (final m in messages) {
      if (m.role != MessageRole.user) continue;
      final text = m.text.replaceAll('\n', ' ').trim();
      if (text.isNotEmpty) return text.length > 48 ? '${text.substring(0, 47)}…' : text;
      if (m.attachments.isNotEmpty) return m.attachments.first.name;
    }
    return 'New chat';
  }

  /// Creates or updates chat [id] with [messages].
  void save(String id, {String? conversationId, required List<AgentMessageEntity> messages}) {
    final chats = List.of(state.chats);
    final i = chats.indexWhere((c) => c.id == id);
    if (i < 0) {
      chats.insert(
        0,
        AgentChat(
          id: id,
          conversationId: conversationId,
          title: titleFor(messages),
          messages: messages,
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      final c = chats[i];
      chats[i] = c.copyWith(
        conversationId: conversationId,
        messages: messages,
        updatedAt: DateTime.now(),
        title: c.customTitle ? null : titleFor(messages),
      );
    }
    _set(chats);
  }

  void reorder(int oldIndex, int newIndex) {
    final chats = List.of(state.chats);
    if (newIndex > oldIndex) newIndex -= 1;
    final c = chats.removeAt(oldIndex);
    chats.insert(newIndex, c);
    _set(chats);
  }

  void rename(String id, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    _set([
      for (final c in state.chats) c.id == id ? c.copyWith(title: t, customTitle: true) : c,
    ]);
  }

  void delete(String id) => _set([for (final c in state.chats) if (c.id != id) c]);

  AgentChat? byId(String id) {
    for (final c in state.chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _set(List<AgentChat> chats) {
    state = AgentChatsState(chats: chats, loaded: true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  // -------------------------------------------------------------------------
  // Persistence

  Future<File?> _file(String? userId) async {
    if (userId == null) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      return File('${dir.path}${Platform.pathSeparator}agent_chats_$safe.json');
    } catch (_) {
      return null; // e.g. widget tests without a platform channel
    }
  }

  Future<void> _load(String? userId) async {
    final file = await _file(userId);
    if (userId != _userId) return;
    var chats = <AgentChat>[];
    try {
      if (file != null && await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        chats = [
          for (final c in (data['chats'] as List<dynamic>? ?? const []))
            _chatFromJson(c as Map<String, dynamic>),
        ];
      }
    } catch (_) {
      chats = []; // corrupt file: start fresh rather than crash
    }
    if (userId != _userId) return;
    // Anything saved while loading stays on top.
    final pending = state.chats;
    state = AgentChatsState(
      chats: [...pending, for (final c in chats) if (!pending.any((p) => p.id == c.id)) c],
      loaded: true,
    );
  }

  Future<void> _persist() async {
    final file = await _file(_userId);
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'version': 1,
        'chats': [for (final c in state.chats) _chatToJson(c)],
      }));
    } catch (_) {/* history is best-effort */}
  }
}

// ---------------------------------------------------------------------------
// JSON

Map<String, dynamic> _chatToJson(AgentChat c) => {
      'id': c.id,
      'conversation_id': c.conversationId,
      'title': c.title,
      'custom_title': c.customTitle,
      'updated_at': c.updatedAt.toIso8601String(),
      'messages': [for (final m in c.messages) _messageToJson(m)],
    };

AgentChat _chatFromJson(Map<String, dynamic> j) => AgentChat(
      id: j['id'] as String,
      conversationId: j['conversation_id'] as String?,
      title: j['title'] as String? ?? 'Chat',
      customTitle: j['custom_title'] as bool? ?? false,
      updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      messages: [
        for (final m in (j['messages'] as List<dynamic>? ?? const []))
          _messageFromJson(m as Map<String, dynamic>),
      ],
    );

Map<String, dynamic> _messageToJson(AgentMessageEntity m) => {
      'id': m.id,
      'conversation_id': m.conversationId,
      'role': m.role.name,
      'text': m.text,
      'created_at': m.createdAt.toIso8601String(),
      if (m.plan != null) 'plan': _planToJson(m.plan!),
      if (m.attachments.isNotEmpty)
        'attachments': [
          for (final a in m.attachments)
            {
              'id': a.id,
              'kind': a.kind.name,
              'name': a.name,
              'mime': a.mime,
              'size': a.size,
              'url': a.url,
              'pages': a.pages,
              'words': a.words,
              'local_path': a.localPath,
            },
        ],
    };

AgentMessageEntity _messageFromJson(Map<String, dynamic> j) => AgentMessageEntity(
      id: j['id'] as String,
      conversationId: j['conversation_id'] as String? ?? '',
      role: j['role'] == 'agent' ? MessageRole.agent : MessageRole.user,
      text: j['text'] as String? ?? '',
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      plan: j['plan'] == null ? null : _planFromJson(j['plan'] as Map<String, dynamic>),
      attachments: [
        for (final a in (j['attachments'] as List<dynamic>? ?? const []))
          AgentAttachmentEntity(
            id: a['id'] as String,
            kind: AgentAttachmentKind.values.firstWhere((k) => k.name == a['kind'],
                orElse: () => AgentAttachmentKind.document),
            name: a['name'] as String? ?? 'file',
            mime: a['mime'] as String? ?? '',
            size: (a['size'] as num?)?.toInt() ?? 0,
            url: a['url'] as String? ?? '',
            pages: (a['pages'] as num?)?.toInt(),
            words: (a['words'] as num?)?.toInt(),
            localPath: a['local_path'] as String?,
          ),
      ],
    );

Map<String, dynamic> _planToJson(AgentPlanEntity p) => {
      'id': p.id,
      'summary': p.summary,
      'currency': p.currency,
      'min': p.estimatedTotalMinMinorUnits,
      'max': p.estimatedTotalMaxMinorUnits,
      'items': [
        for (final i in p.items)
          {
            'kind': i.kind.name,
            'ref_id': i.refId,
            'title': i.title,
            'subtitle': i.subtitle,
            'image_url': i.imageUrl,
            'price': i.priceMinorUnits,
            'currency': i.currency,
          },
      ],
    };

AgentPlanEntity _planFromJson(Map<String, dynamic> j) => AgentPlanEntity(
      id: j['id'] as String? ?? '',
      summary: j['summary'] as String? ?? '',
      currency: j['currency'] as String? ?? 'INR',
      estimatedTotalMinMinorUnits: (j['min'] as num?)?.toInt() ?? 0,
      estimatedTotalMaxMinorUnits: (j['max'] as num?)?.toInt() ?? 0,
      items: [
        for (final i in (j['items'] as List<dynamic>? ?? const []))
          PlanItemEntity(
            kind: PlanItemKind.values.firstWhere((k) => k.name == i['kind'],
                orElse: () => PlanItemKind.post),
            refId: i['ref_id'] as String? ?? '',
            title: i['title'] as String? ?? '',
            subtitle: i['subtitle'] as String? ?? '',
            imageUrl: i['image_url'] as String?,
            priceMinorUnits: (i['price'] as num?)?.toInt(),
            currency: i['currency'] as String?,
          ),
      ],
    );
