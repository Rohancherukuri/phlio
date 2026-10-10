import 'package:phlio/shared/content/content_surface.dart';
// Phlio Book — discover bookable experiences and confirm a booking.
//
// Mirrors the reference "Plan. Meet. Experience." surface: a category chip
// row, listing cards with venue/price/rating, and a bottom-sheet booking
// flow (date + time + participants) that ends in the signature ember
// gradient "Book This Plan" pill.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/colors.dart';
import '../../../../design_system/radii.dart';
import '../../../../design_system/spacing.dart';
import '../../../../design_system/typography.dart';
import '../../../../design_system/widgets/phlio_button.dart';
import '../../../../design_system/widgets/phlio_card.dart';
import '../../../../design_system/widgets/phlio_fox.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../domain/entities/book_entities.dart';
import '../controllers/book_controller.dart';
import '../widgets/listing_placeholder.dart';

class BookScreen extends ConsumerWidget {
  const BookScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(listingsControllerProvider);
    final selectedCategory = ref.watch(selectedBookCategoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Phlio Book'),
            Text(
              'Plan. Meet. Experience.',
              style: PhlioTypography.caption.copyWith(height: 1.2),
            ),
          ],
        ),
      ),
      body: listingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PhlioErrorView(
          failure: error is Failure ? error : const Failure.unknown(),
          onRetry: () => ref.invalidate(listingsControllerProvider),
        ),
        data: (listings) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(listingsControllerProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              PhlioSpacing.lg,
              PhlioSpacing.md,
              PhlioSpacing.lg,
              PhlioSpacing.xxl,
            ),
            children: [
              // Category chips.
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _categoryChip(context, ref, null, selectedCategory == null),
                    for (final category in BookCategory.values)
                      _categoryChip(
                          context, ref, category, selectedCategory == category),
                  ],
                ),
              ),
              const SizedBox(height: PhlioSpacing.lg),
              if (listings.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: PhlioSpacing.massive),
                  child: Column(
                    children: [
                      const PhlioFox(size: 120, pose: PhlioFoxPose.curious),
                      const SizedBox(height: PhlioSpacing.lg),
                      Text('Nothing here yet', style: PhlioTypography.title),
                      const SizedBox(height: PhlioSpacing.xs),
                      Text(
                        'Try another category — Foxy is always looking.',
                        style: PhlioTypography.body,
                      ),
                    ],
                  ),
                )
              else
                for (final listing in listings) ...[
                  _ListingCard(listing: listing),
                  const SizedBox(height: PhlioSpacing.md),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(
    BuildContext context,
    WidgetRef ref,
    BookCategory? category,
    bool selected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: PhlioSpacing.sm),
      child: PhlioChipButton(
        label: category?.label ?? 'All',
        selected: selected,
        onPressed: () =>
            ref.read(selectedBookCategoryProvider.notifier).state = category,
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing});

  final BookListingEntity listing;

  @override
  Widget build(BuildContext context) {
    return ContentSurface(
        platform: 'book', contentId: listing.id, child: _content(context));
  }

  Widget _content(BuildContext context) {
    return PhlioCard(
      onTap: () => _openBookingSheet(context),
      padding: const EdgeInsets.all(PhlioSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: PhlioRadii.mdRadius,
            child: Image.asset(
              listingPlaceholderImage(listing),
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: PhlioColors.surfaceElevated,
                alignment: Alignment.center,
                child: const Icon(Icons.confirmation_number_outlined,
                    color: PhlioColors.domainBook, size: 22),
              ),
            ),
          ),
          const SizedBox(width: PhlioSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listing.title,
                        style: PhlioTypography.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (listing.rating != null) ...[
                      const Icon(Icons.star_rounded,
                          size: 14, color: PhlioColors.warning),
                      const SizedBox(width: 2),
                      Text(
                        listing.rating!.toStringAsFixed(1),
                        style: PhlioTypography.caption,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: PhlioSpacing.xxs),
                Text(
                  listing.locationNote.isNotEmpty
                      ? '${listing.venue} · ${listing.locationNote}'
                      : listing.venue,
                  style: PhlioTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: PhlioSpacing.sm),
                Row(
                  children: [
                    Text(
                      listing.displayPrice,
                      style: PhlioTypography.label.copyWith(
                        color: listing.isFree
                            ? PhlioColors.success
                            : PhlioColors.brandOrange,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (listing.durationLabel.isNotEmpty) ...[
                      const Spacer(),
                      Text(listing.durationLabel,
                          style: PhlioTypography.caption),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openBookingSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BookingSheet(listing: listing),
    );
  }
}

class _BookingSheet extends ConsumerStatefulWidget {
  const _BookingSheet({required this.listing});

  final BookListingEntity listing;

  @override
  ConsumerState<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<_BookingSheet> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 19, minute: 0);
  int _participants = 2;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _selectedTime);
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _confirm() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final repository = ref.read(bookRepositoryProvider);
    final result = await repository.createBooking(
      listingId: widget.listing.id,
      date: _selectedDate,
      time: DateTime(2026, 1, 1, _selectedTime.hour, _selectedTime.minute),
      participants: _participants,
    );

    if (!mounted) return;
    result.when(
      success: (booking) {
        ref.invalidate(myBookingsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Booked! ${booking.title} on ${_formatDate(booking.date)}.'),
          ),
        );
      },
      failure: (failure) => setState(() {
        _isSubmitting = false;
        _error = failure.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: PhlioSpacing.xl,
          right: PhlioSpacing.xl,
          top: PhlioSpacing.xl,
          bottom: PhlioSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.listing.title,
                          style: PhlioTypography.headline),
                      const SizedBox(height: PhlioSpacing.xxs),
                      Text(widget.listing.venue, style: PhlioTypography.body),
                    ],
                  ),
                ),
                const PhlioFox(
                    size: 44, pose: PhlioFoxPose.hello, animate: false),
              ],
            ),
            const SizedBox(height: PhlioSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: _pickerTile(
                    icon: Icons.calendar_today_outlined,
                    label: _formatDate(_selectedDate),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: PhlioSpacing.md),
                Expanded(
                  child: _pickerTile(
                    icon: Icons.schedule_outlined,
                    label: _selectedTime.format(context),
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PhlioSpacing.md),
            // Participants stepper.
            Row(
              children: [
                Text('Participants', style: PhlioTypography.bodyStrong),
                const Spacer(),
                IconButton(
                  onPressed: _participants > 1
                      ? () => setState(() => _participants--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text('$_participants', style: PhlioTypography.title),
                IconButton(
                  onPressed: _participants < 20
                      ? () => setState(() => _participants++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: PhlioSpacing.lg),
            // Estimated total, mirroring the Agent plan card.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PhlioSpacing.lg,
                vertical: PhlioSpacing.md,
              ),
              decoration: BoxDecoration(
                color: PhlioColors.surfaceElevated,
                borderRadius: PhlioRadii.mdRadius,
              ),
              child: Row(
                children: [
                  Text('Estimated total', style: PhlioTypography.label),
                  const Spacer(),
                  Text(
                    widget.listing.displayPrice,
                    style: PhlioTypography.title
                        .copyWith(color: PhlioColors.brandOrange),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: PhlioSpacing.sm),
              Text(_error!,
                  style: PhlioTypography.caption
                      .copyWith(color: PhlioColors.danger)),
            ],
            const SizedBox(height: PhlioSpacing.lg),
            PhlioPrimaryButton(
              label: 'Book This Plan',
              isLoading: _isSubmitting,
              onPressed: _confirm,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: PhlioRadii.mdRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PhlioSpacing.md, vertical: PhlioSpacing.md),
        decoration: BoxDecoration(
          color: PhlioColors.surfaceInput,
          borderRadius: PhlioRadii.mdRadius,
          border: Border.all(color: PhlioColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: PhlioColors.textSecondary),
            const SizedBox(width: PhlioSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: PhlioTypography.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
