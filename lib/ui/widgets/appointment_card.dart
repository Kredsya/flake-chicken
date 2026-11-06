import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/appointment.dart';
import '../theme.dart';
import 'route_map.dart';

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.open,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onChoiceChanged,
    this.busy = false,
  });
  final Appointment appointment;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onChoiceChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final reveal = !appointment.isCancelled && appointment.isOwner
        ? 136.0
        : 70.0;
    final height = cardHeight(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height + 4,
        child: Stack(
          children: [
            if (open && appointment.isCancelled)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _ActionTile(
                    color: const Color(0xFFF8EAF0),
                    onTap: busy ? null : onDelete,
                    child: Semantics(
                      label: '파토난 약속 삭제',
                      button: true,
                      child: Column(
                        key: ValueKey('delete-${appointment.id}'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.delete_outline,
                            color: AppColors.red,
                            size: 25,
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            '삭제',
                            style: TextStyle(
                              color: AppColors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (open && !appointment.isCancelled)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (appointment.isOwner)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _ActionTile(
                            color: const Color(0xFFEAF0F9),
                            onTap: onEdit,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.edit_outlined, size: 25),
                                const SizedBox(height: 7),
                                const Text(
                                  '수정',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _ActionTile(
                        color: const Color(0xFFF8EAF0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Semantics(
                              label: '파토',
                              child: SizedBox(
                                width: 57,
                                height: 40,
                                child: FittedBox(
                                  child: Switch(
                                    key: ValueKey('vote-${appointment.id}'),
                                    value: appointment.myChoice,
                                    onChanged: busy ? null : onChoiceChanged,
                                    activeTrackColor: AppColors.pink,
                                    activeThumbColor: Colors.white,
                                    inactiveThumbColor: Colors.white,
                                    inactiveTrackColor: const Color(0xFFCDD5DF),
                                    trackOutlineColor:
                                        const WidgetStatePropertyAll(
                                          Colors.transparent,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                            const Text(
                              '파토',
                              style: TextStyle(
                                color: AppColors.rose,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(open ? -reveal : 0, 0, 0),
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if ((!open && velocity < -80) || (open && velocity > 80)) {
                    onTap();
                  }
                },
                child: AppointmentFace(
                  key: ValueKey('appointment-${appointment.id}'),
                  appointment: appointment,
                  onTap: onTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double cardHeight(BuildContext context) =>
    142 +
    math.max(0, MediaQuery.textScalerOf(context).scale(14) / 14 - 1) * 128;

class AppointmentFace extends StatelessWidget {
  const AppointmentFace({
    super.key,
    required this.appointment,
    this.onTap,
    this.preview = false,
  });
  final Appointment appointment;
  final VoidCallback? onTap;
  final bool preview;

  @override
  Widget build(BuildContext context) => Container(
    height: cardHeight(context),
    margin: const EdgeInsets.only(bottom: 2),
    decoration: BoxDecoration(
      color: appointment.isCancelled ? const Color(0xFFF7F2F5) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: .045),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox(
                  width: (constraints.maxWidth * .38).clamp(94, 144),
                  height: double.infinity,
                  child: RouteMap(
                    variant: appointment.routeVariant,
                    cancelled: appointment.isCancelled,
                    connected: appointment.connected,
                    image: appointment.mapImage,
                    message: appointment.routeMessage,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        appointment.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: appointment.isCancelled
                              ? const Color(0xFF717C8B)
                              : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _DetailLine(
                        icon: Icons.calendar_today_outlined,
                        text: formatAppointmentDate(appointment.startsAt),
                        size: 11,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 5),
                      _DetailLine(
                        icon: Icons.location_on_outlined,
                        text: appointment.destination,
                        size: 11,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 14,
                        runSpacing: 3,
                        children: [
                          if (!preview)
                            _Metric(
                              icon: Icons.directions_transit_outlined,
                              text: appointment.durationMinutes == null
                                  ? '—'
                                  : '${appointment.durationMinutes}분',
                            ),
                          _Metric(
                            icon: Icons.people_outline,
                            text:
                                '${preview ? '현재 ' : ''}${appointment.participantCount}명',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.text,
    required this.size,
    this.maxLines = 1,
  });
  final IconData icon;
  final String text;
  final double size;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 14, color: const Color(0xFF63738A)),
      ),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: size, height: 1.4),
        ),
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: const Color(0xFF63738A)),
      const SizedBox(width: 5),
      Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ],
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.color, required this.child, this.onTap});
  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: cardHeight(context),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: child,
      ),
    ),
  );
}
