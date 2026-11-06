import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local_store.dart';
import '../../models/appointment.dart';
import '../theme.dart';
import '../widgets/appointment_card.dart';
import '../widgets/chicken_mark.dart';
import '../widgets/form_widgets.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  Appointment? _preview;
  String? _error;
  bool _joining = false;
  late int _nameIndex = widget.store.profiles.names.indexWhere(
    (s) => s.isNotEmpty,
  );
  late int _addressIndex = widget.store.profiles.addresses.indexWhere(
    (s) => s.isNotEmpty,
  );

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _preview = null;
      _joining = true;
    });
    try {
      final preview = await widget.store.previewInvitation(_code.text);
      if (mounted) setState(() => _preview = preview);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '초대 코드를 확인하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _join() async {
    if (_preview == null) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      await widget.store.joinAppointment(_code.text, _nameIndex, _addressIndex);
      if (mounted) Navigator.of(context).pop();
    } on StateError catch (error) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = '저장하지 못했어요. 다시 시도해주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('코드로 참여'),
      actions: const [ChickenMark(size: 32), SizedBox(width: 20)],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '친구의 약속에 함께해요',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '받은 초대 코드를 입력해주세요.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF68768B)),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('invitation-code'),
                          controller: _code,
                          onTapOutside: (_) =>
                              FocusManager.instance.primaryFocus?.unfocus(),
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          enableSuggestions: false,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp('[a-zA-Z0-9 ]'),
                            ),
                            LengthLimitingTextInputFormatter(9),
                          ],
                          style: const TextStyle(
                            fontFamily: 'NotoSansKR',
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                          decoration: const InputDecoration(hintText: '초대 코드'),
                          onChanged: (_) => setState(() {
                            _preview = null;
                            _error = null;
                          }),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _check(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        key: const ValueKey('check-invitation'),
                        onPressed: _joining ? null : _check,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(88, 56),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: const BorderSide(color: AppColors.blueStrong),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '약속 확인',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  InlineError(_error),
                  if (_preview != null) ...[
                    const SizedBox(height: 24),
                    AppointmentFace(appointment: _preview!, preview: true),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Divider(),
                    ),
                    ProfileSelector(
                      profiles: widget.store.profiles,
                      nameIndex: _nameIndex,
                      addressIndex: _addressIndex,
                      onNameChanged: (value) =>
                          setState(() => _nameIndex = value),
                      onAddressChanged: (value) =>
                          setState(() => _addressIndex = value),
                    ),
                  ],
                ],
              ),
            ),
          ),
          BottomAction(
            label: '이 약속에 참여하기',
            busy: _joining,
            onPressed: _preview == null ? null : _join,
          ),
        ],
      ),
    ),
  );
}
