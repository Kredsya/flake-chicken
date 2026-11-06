import 'package:flutter/material.dart';

import '../../models/appointment.dart';
import '../theme.dart';

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      ?trailing,
    ],
  );
}

class BottomAction extends StatelessWidget {
  const BottomAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    ),
  );
}

class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            message!,
            style: const TextStyle(color: AppColors.red, fontSize: 12),
          ),
        );
}

class ProfileSelector extends StatelessWidget {
  const ProfileSelector({
    super.key,
    required this.profiles,
    required this.nameIndex,
    required this.addressIndex,
    required this.onNameChanged,
    required this.onAddressChanged,
    this.onManage,
  });
  final ProfileSettings profiles;
  final int nameIndex;
  final int addressIndex;
  final ValueChanged<int> onNameChanged;
  final ValueChanged<int> onAddressChanged;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionTitle(
        '이 약속에서 쓸 프로필',
        trailing: onManage == null
            ? null
            : TextButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('환경설정', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(left: 8),
                  minimumSize: const Size(0, 40),
                ),
              ),
      ),
      const SizedBox(height: 20),
      const FormLabel('표시 이름'),
      _Choices(
        values: profiles.names,
        selected: nameIndex,
        prefix: 'name',
        onChanged: onNameChanged,
      ),
      const SizedBox(height: 22),
      const FormLabel('출발 주소'),
      _Choices(
        values: List.generate(
          3,
          (i) => profiles.addresses[i].isEmpty ? '' : '출발지 ${i + 1}',
        ),
        selected: addressIndex,
        prefix: 'address',
        onChanged: onAddressChanged,
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.location_on_outlined,
              size: 17,
              color: Color(0xFF63738A),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              profiles.addresses[addressIndex],
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    ],
  );
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.prefix,
    required this.onChanged,
  });
  final List<String> values;
  final int selected;
  final String prefix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(
      3,
      (i) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
          child: Semantics(
            selected: selected == i,
            child: Material(
              color: selected == i
                  ? AppColors.blueStrong
                  : const Color(0xFFF9FAFE),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('$prefix-choice-$i'),
                onTap: values[i].isEmpty ? null : () => onChanged(i),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected == i
                          ? AppColors.blueStrong
                          : AppColors.border,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    values[i].isEmpty ? '미설정' : values[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected == i
                          ? Colors.white
                          : values[i].isEmpty
                          ? AppColors.muted
                          : AppColors.ink,
                      fontSize: 13,
                      fontWeight: selected == i
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
