import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../models/appointment.dart';
import '../theme.dart';
import '../widgets/form_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _names = widget.store.profiles.names
      .map((text) => TextEditingController(text: text))
      .toList();
  late final _addresses = widget.store.profiles.addresses
      .map((text) => TextEditingController(text: text))
      .toList();
  late bool _gmg = widget.store.profiles.gmgMode;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [..._names, ..._addresses]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_names.any((c) => c.text.trim().isNotEmpty) ||
        !_addresses.any((c) => c.text.trim().isNotEmpty)) {
      setState(() => _error = '이름과 출발 주소를 하나 이상 입력해주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.saveProfiles(
        ProfileSettings(
          names: _names.map((c) => c.text.trim()).toList(),
          addresses: _addresses.map((c) => c.text.trim()).toList(),
          gmgMode: _gmg,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장하지 못했어요. 다시 시도해주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('프로필'),
      actions: [
        TextButton(
          key: const ValueKey('save-profile'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('저장', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 32),
        children: [
          InlineError(_error),
          const SectionTitle('표시 이름', trailing: _LimitBadge()),
          const SizedBox(height: 16),
          _FieldGroup(
            children: List.generate(
              3,
              (i) => TextField(
                key: ValueKey('profile-name-$i'),
                controller: _names[i],
                maxLength: 20,
                textInputAction: TextInputAction.next,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                decoration: _decoration(hint: '이름 ${i + 1} 입력'),
              ),
            ),
          ),
          const SizedBox(height: 36),
          const SectionTitle('출발 주소', trailing: _LimitBadge()),
          const SizedBox(height: 16),
          _FieldGroup(
            children: List.generate(
              3,
              (i) => Row(
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 12, right: 7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF0F7),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '출발지 ${i + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF69778A),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey('profile-address-$i'),
                      controller: _addresses[i],
                      maxLength: 120,
                      textInputAction: i == 2
                          ? TextInputAction.done
                          : TextInputAction.next,
                      style: const TextStyle(fontSize: 12),
                      decoration: _decoration(hint: '주소 입력', compact: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const SectionTitle('약속 설정'),
          const SizedBox(height: 14),
          Container(
            decoration: _groupDecoration,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: SwitchListTile(
                key: const ValueKey('gmg-mode-switch'),
                title: const Text(
                  'GMG 모드',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                value: _gmg,
                onChanged: (value) => setState(() => _gmg = value),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                activeTrackColor: AppColors.pink,
                activeThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFCDD5DF),
                inactiveThumbColor: Colors.white,
                trackOutlineColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  InputDecoration _decoration({required String hint, bool compact = false}) =>
      InputDecoration(
        hintText: hint,
        counterText: '',
        fillColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 3 : 16,
          vertical: 18,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        suffixIcon: const Icon(
          Icons.edit_outlined,
          size: 18,
          color: Color(0xFF738198),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 44,
        ),
      );
}

final _groupDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: AppColors.border),
  boxShadow: [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: .025),
      blurRadius: 5,
      offset: const Offset(0, 2),
    ),
  ],
);

class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: _groupDecoration,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i != 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Divider(height: 1),
            ),
          children[i],
        ],
      ],
    ),
  );
}

class _LimitBadge extends StatelessWidget {
  const _LimitBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFE7ECF4),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      '최대 3개',
      style: TextStyle(fontSize: 10, color: Color(0xFF69778A)),
    ),
  );
}
