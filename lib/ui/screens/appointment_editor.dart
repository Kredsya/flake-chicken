import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_store.dart';
import '../../models/appointment.dart';
import '../theme.dart';
import '../widgets/chicken_mark.dart';
import '../widgets/form_widgets.dart';
import '../widgets/address_search_button.dart';
import 'settings_screen.dart';

class AppointmentEditor extends StatefulWidget {
  const AppointmentEditor({super.key, required this.store, this.appointment});
  final AppStore store;
  final Appointment? appointment;

  @override
  State<AppointmentEditor> createState() => _AppointmentEditorState();
}

class _AppointmentEditorState extends State<AppointmentEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.appointment?.title);
  late final _destination = TextEditingController(
    text: widget.appointment?.destination,
  );
  late DateTime _startsAt = widget.appointment?.startsAt ?? _defaultDate();
  late int _nameIndex = widget.store.profiles.names.indexWhere(
    (value) => value.isNotEmpty,
  );
  late int _addressIndex = widget.store.profiles.addresses.indexWhere(
    (value) => value.isNotEmpty,
  );
  String? _error;
  bool _saving = false;
  bool _copied = false;
  bool _confirmDelete = false;
  bool get _editing => widget.appointment != null;

  static DateTime _defaultDate() {
    final day = DateTime.now().add(const Duration(days: 7));
    return DateTime(day.year, day.month, day.day, 19);
  }

  @override
  void dispose() {
    _title.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '약속 날짜',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (date != null && mounted) {
      setState(
        () => _startsAt = DateTime(
          date.year,
          date.month,
          date.day,
          _startsAt.hour,
          _startsAt.minute,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
      helpText: '약속 시간',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (time != null && mounted) {
      setState(
        () => _startsAt = DateTime(
          _startsAt.year,
          _startsAt.month,
          _startsAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _manageProfiles() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(store: widget.store),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (widget.store.profiles.names[_nameIndex].isEmpty) {
        _nameIndex = widget.store.profiles.names.indexWhere(
          (s) => s.isNotEmpty,
        );
      }
      if (widget.store.profiles.addresses[_addressIndex].isEmpty) {
        _addressIndex = widget.store.profiles.addresses.indexWhere(
          (s) => s.isNotEmpty,
        );
      }
    });
  }

  Future<void> _delete() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.deleteOwnedAppointment(widget.appointment!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '삭제하지 못했어요. 다시 시도해주세요.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        await widget.store.updateAppointment(
          id: widget.appointment!.id,
          title: _title.text,
          startsAt: _startsAt,
          destination: _destination.text,
        );
      } else {
        await widget.store.createAppointment(
          title: _title.text,
          startsAt: _startsAt,
          destination: _destination.text,
          nameIndex: _nameIndex,
          addressIndex: _addressIndex,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장하지 못했어요. 입력 내용을 확인해주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_editing ? '약속 수정' : '새 약속'),
      actions: [
        if (_editing &&
            widget.appointment!.isOwner &&
            !widget.appointment!.isCancelled &&
            !widget.appointment!.isCompleted)
          IconButton(
            key: const ValueKey('delete-appointment'),
            tooltip: '약속 삭제',
            onPressed: _saving
                ? null
                : () => setState(() => _confirmDelete = true),
            icon: const Icon(Icons.delete_outline, color: AppColors.red),
          ),
        const ChickenMark(size: 32),
        const SizedBox(width: 20),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle('약속 정보'),
                    const SizedBox(height: 22),
                    const FormLabel('약속 이름'),
                    TextFormField(
                      key: const ValueKey('appointment-title'),
                      controller: _title,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      maxLength: 40,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: '약속 이름을 입력해주세요',
                        counterText: '',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '약속 이름을 입력해주세요.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: _PickerField(
                            key: const ValueKey('pick-date'),
                            icon: Icons.calendar_today_outlined,
                            text: formatDate(_startsAt),
                            onTap: _pickDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: _PickerField(
                            key: const ValueKey('pick-time'),
                            icon: Icons.schedule_outlined,
                            text: formatTime(_startsAt),
                            onTap: _pickTime,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const FormLabel('장소'),
                    TextFormField(
                      key: const ValueKey('appointment-destination'),
                      controller: _destination,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      maxLength: 120,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '장소 또는 주소를 입력해주세요',
                        counterText: '',
                        prefixIcon: const Icon(
                          Icons.location_on_outlined,
                          size: 20,
                        ),
                        suffixIcon: AddressSearchButton(
                          key: const ValueKey('search-appointment-address'),
                          store: widget.store,
                          onSelected: (address) => _destination.text = address,
                          onError: (message) {
                            if (mounted) setState(() => _error = message);
                          },
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '만날 장소를 입력해주세요.'
                          : null,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Divider(),
                    ),
                    if (!_editing)
                      ProfileSelector(
                        profiles: widget.store.profiles,
                        nameIndex: _nameIndex,
                        addressIndex: _addressIndex,
                        onNameChanged: (index) =>
                            setState(() => _nameIndex = index),
                        onAddressChanged: (index) =>
                            setState(() => _addressIndex = index),
                        onManage: _manageProfiles,
                      )
                    else ...[
                      const SectionTitle('이 약속의 프로필'),
                      const SizedBox(height: 16),
                      _SnapshotRow(
                        icon: Icons.person_outline,
                        text: widget.appointment!.displayName,
                      ),
                      const SizedBox(height: 10),
                      _SnapshotRow(
                        icon: Icons.location_on_outlined,
                        text: widget.appointment!.origin,
                      ),
                      const SizedBox(height: 26),
                      const FormLabel('초대 코드'),
                      Container(
                        padding: const EdgeInsets.only(left: 14, right: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                widget.appointment!.invitationCode,
                                style: const TextStyle(
                                  fontFamily: 'NotoSansKR',
                                  letterSpacing: 2,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: widget.appointment!.invitationCode,
                                  ),
                                );
                                if (mounted) setState(() => _copied = true);
                              },
                              icon: Icon(
                                _copied ? Icons.check : Icons.copy_outlined,
                                size: 16,
                              ),
                              label: Text(
                                _copied ? '복사됨' : '복사',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    InlineError(_error),
                  ],
                ),
              ),
            ),
          ),
          if (_confirmDelete)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                children: [
                  const Text(
                    '모든 참여자의 목록에서 이 약속을 삭제할까요?',
                    style: TextStyle(color: AppColors.red, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _confirmDelete = false),
                        child: const Text('취소'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        key: const ValueKey('confirm-delete-appointment'),
                        onPressed: _saving ? null : _delete,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.red,
                        ),
                        child: const Text('약속 삭제'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            BottomAction(
              label: _editing ? '변경사항 저장' : '약속 만들기',
              busy: _saving,
              onPressed: _save,
            ),
        ],
      ),
    ),
  );
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF2F5FB),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF63738A)),
            const SizedBox(width: 7),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SnapshotRow extends StatelessWidget {
  const _SnapshotRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: const Color(0xFF63738A)),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
    ],
  );
}
