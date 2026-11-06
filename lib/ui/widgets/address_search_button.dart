import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local_store.dart';

class AddressSearchButton extends StatefulWidget {
  const AddressSearchButton({
    super.key,
    required this.store,
    required this.onSelected,
    required this.onError,
  });
  final AppStore store;
  final ValueChanged<String> onSelected;
  final ValueChanged<String?> onError;
  @override
  State<AddressSearchButton> createState() => _AddressSearchButtonState();
}

class _AddressSearchButtonState extends State<AddressSearchButton> {
  bool _busy = false;
  Future<void> _search() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    widget.onError(null);
    try {
      final address = await widget.store.pickAddress();
      if (mounted && address != null) widget.onSelected(address);
    } on StateError catch (error) {
      if (mounted) widget.onError(error.message);
    } catch (_) {
      if (mounted) widget.onError('주소 검색창을 열지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    if (_busy) unawaited(widget.store.cancelAddressSearch());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '주소 검색',
    onPressed: _busy ? null : _search,
    icon: _busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.search, size: 20),
  );
}
