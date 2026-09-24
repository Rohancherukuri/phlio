import 'package:flutter/material.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../domain/entities/room_entity.dart';

class RoomCard extends StatelessWidget {
  const RoomCard({required this.room, required this.onTap, super.key});

  final RoomEntity room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PhlioCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PhlioColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(room.icon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: PhlioSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name, style: PhlioTypography.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  room.description,
                  style: PhlioTypography.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: PhlioSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.groups_outlined, size: 16, color: PhlioColors.textMuted),
              const SizedBox(height: 2),
              Text('${room.memberCount}', style: PhlioTypography.caption),
            ],
          ),
        ],
      ),
    );
  }
}
