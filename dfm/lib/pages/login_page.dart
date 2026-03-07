// lib/pages/login_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../core/auth_service.dart';

class _LoginController extends GetxController {
  final isLoading = false.obs;
  final errorMsg  = ''.obs;
  final obscure   = true.obs;
  final userCtrl  = TextEditingController();
  final passCtrl  = TextEditingController();
  final formKey   = GlobalKey<FormState>();

  @override
  void onClose() { userCtrl.dispose(); passCtrl.dispose(); super.onClose(); }

  Future<void> login() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(formKey.currentState?.validate() ?? false)) return;
    isLoading.value = true;
    errorMsg.value  = '';
    final result = await AuthService.instance.login(
        userCtrl.text.trim(), passCtrl.text);
    if (result.success) {
      Get.offAllNamed('/home');
    } else {
      errorMsg.value = result.error ?? 'Login failed.';
    }
    isLoading.value = false;
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(_LoginController());

    return Scaffold(
      backgroundColor: const Color(0xFF1B4F72),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              reverse: true,
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [

                      // ── Branding ──────────────────────────
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 84, height: 84,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                  Icons.water_drop_outlined,
                                  size: 46, color: Colors.white),
                            ),
                            const SizedBox(height: 20),
                            const Text('Dairy Management',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3)),
                            const SizedBox(height: 6),
                            Text('Production · Sales · Stock',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 13)),
                          ],
                        ),
                      ),

                      // ── Form card ─────────────────────────
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28)),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          24, 32, 24,
                          32 + MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: Form(
                          key: ctrl.formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [

                              const Text('Sign In',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1B4F72))),
                              const SizedBox(height: 4),
                              Text('Enter your username and password.',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600)),
                              const SizedBox(height: 22),

                              // Username
                              TextFormField(
                                controller: ctrl.userCtrl,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const [AutofillHints.username],
                                decoration: _dec('Username',
                                    Icons.person_outline),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Enter your username'
                                        : null,
                              ),
                              const SizedBox(height: 14),

                              // Password
                              Obx(() => TextFormField(
                                controller: ctrl.passCtrl,
                                obscureText: ctrl.obscure.value,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => ctrl.login(),
                                decoration: _dec(
                                  'Password',
                                  Icons.lock_outline,
                                  suffix: IconButton(
                                    icon: Icon(
                                      ctrl.obscure.value
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.grey.shade500,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        ctrl.obscure.value =
                                            !ctrl.obscure.value,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Enter your password'
                                        : null,
                              )),

                              // Error banner
                              Obx(() => ctrl.errorMsg.value.isNotEmpty
                                  ? Container(
                                      margin: const EdgeInsets.only(top: 12),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFDECEC),
                                        border: Border.all(
                                            color: const Color(0xFFE74C3C)),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.error_outline,
                                              color: Color(0xFFE74C3C),
                                              size: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              ctrl.errorMsg.value,
                                              style: const TextStyle(
                                                  color: Color(0xFFE74C3C),
                                                  fontSize: 13,
                                                  height: 1.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox(height: 12)),

                              const SizedBox(height: 8),

                              // Sign in button
                              Obx(() => ElevatedButton(
                                onPressed: ctrl.isLoading.value
                                    ? null
                                    : ctrl.login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1B4F72),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  disabledBackgroundColor:
                                      const Color(0xFF1B4F72)
                                          .withValues(alpha: 0.6),
                                ),
                                child: ctrl.isLoading.value
                                    ? const SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5))
                                    : const Text('Sign In',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                              )),

                              const SizedBox(height: 20),
                              Center(
                                child: Text(
                                  'Contact your administrator if you\n'
                                  'have trouble signing in.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                      height: 1.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: Color(0xFF1B4F72), width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE74C3C))),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: Color(0xFFE74C3C), width: 1.5)),
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(fontSize: 14),
      );
}
