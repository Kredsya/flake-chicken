import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../models/appointment.dart';
import '../theme.dart';
import '../widgets/appointment_card.dart';
import '../widgets/chicken_mark.dart';
import 'appointment_editor.dart';
import 'join_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _menuOpen = false;
  String? _openId;
  String? _errorId;
  final _busy = <String>{};

  Future<void> _openPage(Widget page) async {
    setState(() {
      _menuOpen = false;
      _openId = null;
    });
    if (!widget.store.profilesReady && page is! SettingsScreen) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(store: widget.store),
        ),
      );
      if (!mounted || !widget.store.profilesReady) return;
      // Rebuild the editor after profile setup so its selected indices are valid.
      if (page is AppointmentEditor) {
        page = AppointmentEditor(store: widget.store);
      }
      if (page is JoinScreen) page = JoinScreen(store: widget.store);
    }
    if (mounted) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }

  Future<void> _setChoice(Appointment appointment, bool value) async {
    setState(() {
      _busy.add(appointment.id);
      _errorId = null;
    });
    try {
      await widget.store.setMyChoice(appointment.id, value);
    } catch (_) {
      if (mounted) setState(() => _errorId = appointment.id);
    } finally {
      if (mounted) setState(() => _busy.remove(appointment.id));
    }
  }

  Future<void> _delete(Appointment appointment) async {
    setState(() {
      _busy.add(appointment.id);
      _errorId = null;
    });
    try {
      await widget.store.deleteCancelledAppointment(appointment.id);
      if (mounted) setState(() => _openId = null);
    } catch (_) {
      if (mounted) setState(() => _errorId = appointment.id);
    } finally {
      if (mounted) setState(() => _busy.remove(appointment.id));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_menuOpen && _openId == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        setState(() {
          _menuOpen = false;
          _openId = null;
        });
      }
    },
    child: Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => RefreshIndicator(
                onRefresh: widget.store.refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  children: [
                    Row(
                      children: [
                        const ChickenMark(),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Flake Chicken',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              letterSpacing: -.6,
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xFFE9EDF3),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            key: const ValueKey('open-settings'),
                            tooltip: '환경설정',
                            icon: const Icon(Icons.settings_outlined, size: 23),
                            onPressed: () =>
                                _openPage(SettingsScreen(store: widget.store)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '언제 한 번 밥 먹자',
                      style: TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '그래그래 연락 한 번 할게',
                      style: TextStyle(color: Color(0xFF68768B), fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    if (widget.store.connectionError != null)
                      TextButton.icon(
                        onPressed: () => widget.store.refresh(),
                        icon: const Icon(Icons.refresh),
                        label: Text(widget.store.connectionError!),
                      ),
                    if (widget.store.appointments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 72),
                        child: Center(
                          child: Text(
                            '아직 약속이 없어요',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                    for (final appointment in widget.store.appointments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppointmentCard(
                              appointment: appointment,
                              open: _openId == appointment.id,
                              busy: _busy.contains(appointment.id),
                              onTap: () => setState(
                                () => _openId = _openId == appointment.id
                                    ? null
                                    : appointment.id,
                              ),
                              onEdit: () => _openPage(
                                AppointmentEditor(
                                  store: widget.store,
                                  appointment: appointment,
                                ),
                              ),
                              onDelete: () => _delete(appointment),
                              onChoiceChanged: (value) =>
                                  _setChoice(appointment, value),
                            ),
                            if (_errorId == appointment.id)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  '저장하지 못했어요. 다시 시도해주세요.',
                                  style: TextStyle(
                                    color: AppColors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_menuOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _menuOpen = false),
                ),
              ),
            if (_menuOpen)
              Positioned(
                right: 20,
                bottom: 88,
                child: Material(
                  color: Colors.white,
                  elevation: 8,
                  shadowColor: AppColors.ink.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    width: 172,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MenuItem(
                          key: const ValueKey('create-menu-item'),
                          icon: Icons.event_available_outlined,
                          label: '새 약속',
                          onTap: () =>
                              _openPage(AppointmentEditor(store: widget.store)),
                        ),
                        _MenuItem(
                          key: const ValueKey('join-menu-item'),
                          icon: Icons.keyboard_outlined,
                          label: '코드로 참여',
                          onTap: () =>
                              _openPage(JoinScreen(store: widget.store)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 20,
              bottom: 16,
              child: FloatingActionButton(
                key: const ValueKey('appointment-menu'),
                tooltip: _menuOpen ? '메뉴 닫기' : '약속 메뉴',
                backgroundColor: AppColors.blueStrong,
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                elevation: 4,
                onPressed: () => setState(() => _menuOpen = !_menuOpen),
                child: AnimatedRotation(
                  turns: _menuOpen ? .125 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.add, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
