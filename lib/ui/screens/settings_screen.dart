import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_store.dart';
import '../../models/appointment.dart';
import '../theme.dart';
import '../widgets/form_widgets.dart';
import '../widgets/address_search_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late final _names = widget.store.profiles.names
      .map((text) => TextEditingController(text: text))
      .toList();
  late final _addresses = widget.store.profiles.addresses
      .map((text) => TextEditingController(text: text))
      .toList();
  late bool _gmg = widget.store.profiles.gmgMode;
  Timer? _saveTimer;
  int _revision = 0;
  int _savedRevision = 0;
  bool _leaving = false;
  bool _allowPop = false;
  String? _error;
  Map<String, dynamic> _notifications = {};
  bool _notificationBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.store.connected) unawaited(_loadNotifications());
  }

  Future<void> _loadNotifications() async {
    try {
      final status = await widget.store.notificationStatus();
      if (mounted) setState(() => _notifications = status);
    } catch (_) {
      if (mounted) setState(() => _error = '알림 상태를 확인하지 못했어요.');
    }
  }

  Future<void> _setNotifications(bool value) async {
    setState(() {
      _notificationBusy = true;
      _error = null;
    });
    try {
      if (value) {
        final status = await widget.store.notificationStatus(
          requestPermission: true,
        );
        if (mounted) setState(() => _notifications = status);
      } else {
        await widget.store.disableNotifications();
        if (mounted) {
          setState(
            () => _notifications = {..._notifications, 'enabled': false},
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = '알림 설정을 변경하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _notificationBusy = false);
    }
  }

  void _changed(String _) {
    setState(() {
      _revision++;
      _error = null;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_save()),
    );
  }

  void _setGmg(bool value) {
    setState(() {
      _gmg = value;
      _revision++;
      _error = null;
    });
    unawaited(_save());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_save());
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in [..._names, ..._addresses]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    if (_revision == _savedRevision) return;
    final revision = _revision;
    if (!widget.store.connected &&
        (!_names.any((c) => c.text.trim().isNotEmpty) ||
            !_addresses.any((c) => c.text.trim().isNotEmpty))) {
      setState(() => _error = '이름과 출발 주소를 하나 이상 입력해주세요.');
      return;
    }
    try {
      await widget.store.saveProfiles(
        ProfileSettings(
          names: _names.map((c) => c.text.trim()).toList(),
          addresses: _addresses.map((c) => c.text.trim()).toList(),
          gmgMode: _gmg,
        ),
      );
      if (revision > _savedRevision) _savedRevision = revision;
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = '저장하지 못했어요. 다시 시도해주세요.';
        });
      }
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _save();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || _revision == _savedRevision,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('환경설정'),
        leading: BackButton(onPressed: _leave),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  onChanged: _changed,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
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
                        onChanged: _changed,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        maxLength: 120,
                        textInputAction: i == 2
                            ? TextInputAction.done
                            : TextInputAction.next,
                        style: const TextStyle(fontSize: 12),
                        decoration: _decoration(hint: '주소 입력', compact: true)
                            .copyWith(
                              suffixIcon: AddressSearchButton(
                                key: ValueKey('search-profile-address-$i'),
                                store: widget.store,
                                onSelected: (address) {
                                  _addresses[i].text = address;
                                  _changed(address);
                                },
                                onError: (message) {
                                  if (mounted) setState(() => _error = message);
                                },
                              ),
                            ),
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
                  onChanged: _setGmg,
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
            if (widget.store.connected) ...[
              const SizedBox(height: 24),
              SwitchListTile(
                title: const Text('파토 알림'),
                subtitle: Text(
                  _notifications['message'] as String? ?? '시스템 알림으로 받기',
                ),
                value: _notifications['enabled'] == true,
                onChanged:
                    _notificationBusy || _notifications['supported'] == false
                    ? null
                    : _setNotifications,
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: () => widget.store.openPolicy('privacy'),
                    child: const Text('개인정보 처리방침'),
                  ),
                  TextButton(
                    onPressed: () => widget.store.openPolicy('terms'),
                    child: const Text('이용약관'),
                  ),
                ],
              ),
            ],
          ],
        ),
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
