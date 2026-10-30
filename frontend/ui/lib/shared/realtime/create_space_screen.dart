import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design_system/colors.dart';
import '../music/song_picker.dart';
import 'space_room_screen.dart';
import 'spaces.dart';
import '../../design_system/typography.dart';

class CreateSpaceScreen extends ConsumerStatefulWidget {
  const CreateSpaceScreen({super.key});
  @override
  ConsumerState<CreateSpaceScreen> createState() => _CreateSpaceScreenState();
}

class _CreateSpaceScreenState extends ConsumerState<CreateSpaceScreen> {
  final title = TextEditingController();
  final topics = <String>[];
  bool busy = false;
  bool record = false;
  bool _recordExplained = false;
  static const _maxTitle = 120;
  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  void error(Object e) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(musicError(e))));
  }

  Future<void> chooseTopics() async {
    final selection = Set<String>.from(topics);
    final result = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => StatefulBuilder(
            builder: (c, update) => SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Choose up to 3 topics'),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, children: [
                        for (final topic in [
                          'Technology',
                          'Music',
                          'Gaming',
                          'Art',
                          'Movies',
                          'Sports',
                          'Wellness',
                          'Business',
                          'Just chatting'
                        ])
                          FilterChip(
                              label: Text(topic),
                              selected: selection.contains(topic),
                              onSelected: (on) => update(() {
                                    if (!on)
                                      selection.remove(topic);
                                    else if (selection.length < 3)
                                      selection.add(topic);
                                  }))
                      ]),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, selection.toList()),
                          child: const Text('Done'))
                    ])))));
    if (result != null && mounted)
      setState(() => topics
        ..clear()
        ..addAll(result));
  }

  Future<void> start() async {
    setState(() => busy = true);
    final navigator = Navigator.of(context);
    await openSpace(context,
        create: true,
        title: title.text.trim(),
        record: record,
        topics: List.of(topics));
    // Back from your Space: return to where you came from.
    if (mounted) {
      setState(() => busy = false);
      navigator.maybePop();
    }
  }

  Future<void> schedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 90)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (time == null || !mounted) return;
    final when =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choose a future time.')));
      return;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(musicApiProvider)
          .post('/realtime/spaces/scheduled', data: {
        'title': title.text.trim(),
        'topics': topics,
        'starts_at': when.toUtc().toIso8601String(),
        'record': record
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Space scheduled. Open Scheduled Spaces to start it.')));
    } catch (e) {
      error(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scheduled() async {
    try {
      final items =
          (await ref.read(musicApiProvider).get('/realtime/spaces/scheduled'))
              .data['items'] as List;
      if (!mounted) return;
      final item = await showModalBottomSheet<Map>(
          context: context,
          showDragHandle: true,
          builder: (c) => SafeArea(
              child: items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No scheduled Spaces yet.'))
                  : ListView(shrinkWrap: true, children: [
                      for (final item in items)
                        ListTile(
                            title: Text(item['title']),
                            subtitle: Text(DateTime.parse(item['starts_at'])
                                .toLocal()
                                .toString()),
                            trailing: const Icon(Icons.play_arrow),
                            onTap: () => Navigator.pop(c, item))
                    ])));
      if (item != null && mounted)
        await openSpace(context,
            scheduledId: item['id'].toString(),
            title: item['title'] as String? ?? 'Space',
            topics: ((item['topics'] as List?) ?? const []).cast<String>(),
            record: item['record'] == true);
    } catch (e) {
      error(e);
    }
  }

  Future<void> _scheduleMenu() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: PhlioColors.surface,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.edit_calendar_outlined,
                      color: PhlioColors.brandViolet),
                  title: const Text('Schedule this Space'),
                  subtitle: Text(title.text.trim().isEmpty
                      ? 'Add a title first'
                      : 'Pick a date and time'),
                  enabled: title.text.trim().isNotEmpty,
                  onTap: () => Navigator.pop(c, 'schedule')),
              ListTile(
                  leading: const Icon(Icons.event_note_outlined,
                      color: PhlioColors.brandViolet),
                  title: const Text('Your scheduled Spaces'),
                  onTap: () => Navigator.pop(c, 'list')),
              const SizedBox(height: 8),
            ])));
    if (choice == 'schedule') await schedule();
    if (choice == 'list') await scheduled();
  }

  Future<void> _toggleRecord(bool value) async {
    setState(() => record = value);
    if (value && !_recordExplained) {
      _recordExplained = true;
      await showRecordSpaceInfo(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final length = title.text.characters.length;
    final canStart = !busy && title.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: PhlioColors.background,
      appBar: AppBar(
          backgroundColor: PhlioColors.background,
          leadingWidth: 92,
          leading: TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: Text('Cancel',
                  style: PhlioTypography.bodyLarge
                      .copyWith(color: PhlioColors.textPrimary))),
          title: Text('Create your Space',
              style: PhlioTypography.title.copyWith(fontSize: 18)),
          centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title + remaining-characters ring.
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: TextField(
                                      controller: title,
                                      maxLength: _maxTitle,
                                      maxLines: 3,
                                      minLines: 1,
                                      autofocus: true,
                                      onChanged: (_) => setState(() {}),
                                      style: PhlioTypography.headline
                                          .copyWith(fontSize: 26, height: 1.2),
                                      decoration: InputDecoration(
                                          hintText:
                                              'What do you want to talk about?',
                                          hintStyle: PhlioTypography.headline
                                              .copyWith(
                                                  fontSize: 26,
                                                  color:
                                                      PhlioColors.textMuted),
                                          counterText: '',
                                          filled: false,
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          contentPadding: EdgeInsets.zero)),
                                ),
                                const SizedBox(width: 12),
                                _CharacterRing(
                                    used: length, max: _maxTitle),
                              ]),
                          const SizedBox(height: 18),
                          InkWell(
                            onTap: busy ? null : chooseTopics,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                  topics.isEmpty ? 'Add Topics' : 'Edit Topics',
                                  style: PhlioTypography.title.copyWith(
                                      color: PhlioColors.brandViolet,
                                      fontSize: 17)),
                            ),
                          ),
                          if (topics.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final topic in topics)
                                InputChip(
                                    label: Text(topic),
                                    side: BorderSide(
                                        color: PhlioColors.brandViolet
                                            .withValues(alpha: .5)),
                                    backgroundColor: PhlioColors.brandViolet
                                        .withValues(alpha: .14),
                                    onDeleted: busy
                                        ? null
                                        : () => setState(
                                            () => topics.remove(topic))),
                            ]),
                          ],
                          const SizedBox(height: 22),
                          Row(children: [
                            Text('Record Space',
                                style: PhlioTypography.bodyLarge
                                    .copyWith(fontSize: 17)),
                            const SizedBox(width: 6),
                            IconButton(
                                tooltip: 'About recording',
                                onPressed: () => showRecordSpaceInfo(context),
                                icon: const Icon(Icons.info_outline_rounded,
                                    color: PhlioColors.brandViolet)),
                            const Spacer(),
                            Switch(
                                value: record,
                                activeTrackColor: PhlioColors.brandViolet,
                                onChanged: busy ? null : _toggleRecord),
                          ]),
                          const SizedBox(height: 28),
                          // Or drop into someone else's live Space.
                          const SpacesBar(header: 'Join a live Space'),
                        ]),
                  ),
                ),
                Row(children: [
                  Expanded(
                      child: GradientPillButton(
                          label: busy ? 'Please wait…' : 'Start now',
                          onPressed: canStart ? start : null)),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          side: const BorderSide(color: PhlioColors.border)),
                      onPressed: busy ? null : _scheduleMenu,
                      child: const Tooltip(
                        message: 'Schedule',
                        child: Icon(Icons.edit_calendar_outlined,
                            color: PhlioColors.textPrimary),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                      onPressed: () => showGetToKnowSpaces(context),
                      child: Text('Get to know Spaces',
                          style: PhlioTypography.bodyLarge
                              .copyWith(color: PhlioColors.brandViolet))),
                ),
              ]),
        ),
      ),
    );
  }
}

/// X-style remaining-characters ring next to the title.
class _CharacterRing extends StatelessWidget {
  const _CharacterRing({required this.used, required this.max});
  final int used, max;
  @override
  Widget build(BuildContext context) {
    final left = max - used;
    final color = left <= 0
        ? PhlioColors.danger
        : left <= 20
            ? PhlioColors.warning
            : PhlioColors.brandViolet;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: (used / max).clamp(0.0, 1.0),
          strokeWidth: 2.5,
          color: color,
          backgroundColor: PhlioColors.border,
        ),
        if (left <= 20)
          Text('$left',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}
