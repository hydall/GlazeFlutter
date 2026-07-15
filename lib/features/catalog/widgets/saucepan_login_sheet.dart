import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/glaze_bottom_sheet.dart';
import '../catalog_models.dart';
import '../catalog_provider.dart';
import '../saucepan_account_provider.dart';
import '../services/saucepan_provider.dart';

/// Entry point for the menu's "Saucepan Account" item. When already signed in,
/// shows a small log-out / cancel sheet; otherwise opens the login form.
Future<void> openSaucepanAccountSheet(BuildContext context, WidgetRef ref) async {
  if (!ref.read(saucepanAccountProvider).isLoggedIn) {
    await showSaucepanLoginSheet(context);
    return;
  }
  await GlazeBottomSheet.show<void>(
    context,
    title: 'saucepan_login_menu'.tr(),
    items: [
      BottomSheetItem(
        label: 'saucepan_auth_logout'.tr(),
        icon: Icons.logout_rounded,
        isDestructive: true,
        onTap: () async {
          Navigator.of(context, rootNavigator: true).pop();
          await saucepanLogout();
          await ref.read(saucepanAccountProvider.notifier).setHandle(null);
          // Drop the authenticated catalog results so reopening shows the
          // anonymous view without an app restart.
          if (ref.read(catalogProvider).activeProvider ==
              CatalogProvider.saucepan) {
            await ref.read(catalogProvider.notifier).search(reset: true);
          }
        },
      ),
      BottomSheetItem(
        label: 'btn_cancel'.tr(),
        icon: Icons.close_rounded,
        onTap: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
  );
}

/// Opens the Saucepan login form as a modal sheet. On success the Bearer token
/// is persisted and used for all catalog + definition requests.
Future<void> showSaucepanLoginSheet(BuildContext context) {
  return GlazeBottomSheet.show<void>(
    context,
    title: 'saucepan_auth_title'.tr(),
    child: const _SaucepanLoginForm(),
  );
}

/// Handle + password form. Signs in via [saucepanLogin], stores the display
/// handle for the menu hint, and refreshes the catalog when Saucepan is the
/// active provider so the fuller authenticated set loads immediately.
class _SaucepanLoginForm extends ConsumerStatefulWidget {
  const _SaucepanLoginForm();

  @override
  ConsumerState<_SaucepanLoginForm> createState() => _SaucepanLoginFormState();
}

class _SaucepanLoginFormState extends ConsumerState<_SaucepanLoginForm> {
  final _handleController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _handleController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final handle = _handleController.text.trim();
    final password = _passwordController.text;
    if (handle.isEmpty || password.isEmpty) {
      setState(() => _error = 'saucepan_auth_fields_required'.tr());
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await saucepanLogin(handle, password);
      await ref.read(saucepanAccountProvider.notifier).setHandle(handle);
      if (ref.read(catalogProvider).activeProvider ==
          CatalogProvider.saucepan) {
        await ref.read(catalogProvider.notifier).search(reset: true);
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'saucepan_auth_error'.tr();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'saucepan_auth_desc'.tr(),
              style: TextStyle(
                color: context.cs.onSurfaceVariant,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          _Field(
            controller: _handleController,
            hint: 'saucepan_auth_handle'.tr(),
            enabled: !_loading,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 10),
          _Field(
            controller: _passwordController,
            focusNode: _passwordFocus,
            hint: 'saucepan_auth_password'.tr(),
            enabled: !_loading,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
                color: context.cs.onSurfaceVariant,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.cs.primary,
                foregroundColor: context.cs.onPrimary,
              ),
              child: _loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.cs.onPrimary,
                      ),
                    )
                  : Text(
                      'saucepan_auth_login'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded filled text field matching the catalog import dialog style.
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool enabled;
  final bool obscureText;
  final bool autofocus;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.enabled = true,
    this.obscureText = false,
    this.autofocus = false,
    this.suffix,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: TextStyle(fontSize: 14, color: context.cs.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.cs.onSurfaceVariant, fontSize: 14),
        filled: true,
        fillColor: context.cs.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
