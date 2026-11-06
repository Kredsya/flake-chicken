import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../widgets/appointment_card.dart';
import '../widgets/form_widgets.dart';

class HallOfFameScreen extends StatefulWidget {
  const HallOfFameScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<HallOfFameScreen> createState() => _HallOfFameScreenState();
}

class _HallOfFameScreenState extends State<HallOfFameScreen> {
  String? _open, _error;
  final _busy = <String>{};
  Future<void> _delete(String id) async {
    setState(() {
      _busy.add(id);
      _error = null;
    });
    try {
      await widget.store.deleteCancelledAppointment(id);
      if (mounted) setState(() => _open = null);
    } catch (_) {
      if (mounted) setState(() => _error = '삭제하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hall of Fame')),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => RefreshIndicator(
          onRefresh: widget.store.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              InlineError(_error),
              if (widget.store.hallOfFame.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 72),
                  child: Center(child: Text('아직 기록이 없어요')),
                ),
              for (final a in widget.store.hallOfFame)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AppointmentCard(
                    appointment: a,
                    open: _open == a.id,
                    busy: _busy.contains(a.id),
                    onTap: () =>
                        setState(() => _open = _open == a.id ? null : a.id),
                    onDelete: () => _delete(a.id),
                    onEdit: () {},
                    onChoiceChanged: (_) {},
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
