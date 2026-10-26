import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
  });

  @override
  State<AuthScreen> createState() =>
      _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController =
      TextEditingController();

  final _passwordController =
      TextEditingController();

  final _formKey =
      GlobalKey<FormState>();

  bool _isRegisterMode = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  // =========================================================
  // SUBMIT
  // =========================================================

  Future<void> _submit() async {
    if (_isLoading) {
      return;
    }

    final valid =
        _formKey.currentState
                ?.validate() ??
            false;

    if (!valid) {
      return;
    }

    FocusScope.of(context)
        .unfocus();

    final email =
        _emailController.text
            .trim();

    final password =
        _passwordController.text;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isRegisterMode) {
        await _register(
          email,
          password,
        );
      } else {
        await _login(
          email,
          password,
        );
      }
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        _translateAuthError(
          e.message,
        ),
        isError: true,
      );
    } catch (e) {
      debugPrint(
        'Auth error: $e',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Сталася помилка. '
        'Перевірте підключення до інтернету.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // =========================================================
  // LOGIN
  // =========================================================

  Future<void> _login(
    String email,
    String password,
  ) async {
    await Supabase
        .instance
        .client
        .auth
        .signInWithPassword(
      email: email,
      password: password,
    );

    // AuthGate сам відкриє HomeScreen
    // після зміни auth state.
  }

  // =========================================================
  // REGISTER
  // =========================================================

  Future<void> _register(
    String email,
    String password,
  ) async {
    final response =
        await Supabase
            .instance
            .client
            .auth
            .signUp(
      email: email,
      password: password,

      emailRedirectTo:
          'io.supabase.routetracker://login-callback/',
    );

    if (!mounted) {
      return;
    }

    // Якщо Supabase вимагає підтвердження email,
    // session буде null.
    if (response.session == null) {
      setState(() {
        _isRegisterMode = false;
      });

      _passwordController.clear();

      _showMessage(
        'Реєстрація успішна. '
        'Перевірте email та підтвердьте акаунт.',
      );

      return;
    }

    _showMessage(
      'Акаунт успішно створено.',
    );
  }

  // =========================================================
  // MODE SWITCH
  // =========================================================

  void _switchMode() {
    if (_isLoading) {
      return;
    }

    FocusScope.of(context)
        .unfocus();

    setState(() {
      _isRegisterMode =
          !_isRegisterMode;
    });
  }

  // =========================================================
  // MESSAGES
  // =========================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(
            message,
          ),

          backgroundColor:
              isError
                  ? Theme.of(context)
                      .colorScheme
                      .error
                  : null,
        ),
      );
  }

  // =========================================================
  // ERROR TRANSLATION
  // =========================================================

  String _translateAuthError(
    String message,
  ) {
    final error =
        message.toLowerCase();

    if (error.contains(
      'invalid login credentials',
    )) {
      return 'Неправильний email або пароль.';
    }

    if (error.contains(
      'email not confirmed',
    )) {
      return 'Спочатку підтвердьте email.';
    }

    if (error.contains(
      'user already registered',
    )) {
      return 'Користувач із таким email уже зареєстрований.';
    }

    if (error.contains(
      'password should be at least',
    )) {
      return 'Пароль занадто короткий.';
    }

    if (error.contains(
          'email rate limit',
        ) ||
        error.contains(
          'rate limit',
        )) {
      return 'Забагато спроб. '
          'Спробуйте трохи пізніше.';
    }

    if (error.contains(
      'unable to validate email address',
    )) {
      return 'Некоректна email-адреса.';
    }

    return message;
  }

  // =========================================================
  // VALIDATION
  // =========================================================

  String? _validateEmail(
    String? value,
  ) {
    final email =
        value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Введіть email';
    }

    if (!email.contains('@') ||
        !email.contains('.')) {
      return 'Введіть коректний email';
    }

    return null;
  }

  String? _validatePassword(
    String? value,
  ) {
    final password =
        value ?? '';

    if (password.isEmpty) {
      return 'Введіть пароль';
    }

    if (password.length < 6) {
      return 'Мінімум 6 символів';
    }

    return null;
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final colorScheme =
        Theme.of(context)
            .colorScheme;

    return Scaffold(
      body: SafeArea(
        child:
            Center(
          child:
              SingleChildScrollView(
            padding:
                const EdgeInsets.all(
              24,
            ),

            child:
                ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 450,
              ),

              child:
                  Column(
                children: [
                  // =========================================
                  // LOGO
                  // =========================================

                  Container(
                    width:
                        92,

                    height:
                        92,

                    decoration:
                        BoxDecoration(
                      color:
                          colorScheme
                              .primaryContainer,

                      borderRadius:
                          BorderRadius.circular(
                        28,
                      ),
                    ),

                    child:
                        Icon(
                      Icons.route,

                      size:
                          50,

                      color:
                          colorScheme
                              .onPrimaryContainer,
                    ),
                  ),

                  const SizedBox(
                    height:
                        22,
                  ),

                  const Text(
                    'Route Tracker',

                    style:
                        TextStyle(
                      fontSize:
                          30,

                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height:
                        8,
                  ),

                  Text(
                    _isRegisterMode
                        ? 'Створіть акаунт для збереження '
                            'та синхронізації маршрутів'
                        : 'Увійдіть, щоб продовжити '
                            'відстеження маршрутів',

                    textAlign:
                        TextAlign.center,

                    style:
                        TextStyle(
                      fontSize:
                          15,

                      color:
                          colorScheme
                              .onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(
                    height:
                        32,
                  ),

                  // =========================================
                  // AUTH CARD
                  // =========================================

                  Card(
                    elevation:
                        0,

                    child:
                        Padding(
                      padding:
                          const EdgeInsets.all(
                        22,
                      ),

                      child:
                          Form(
                        key:
                            _formKey,

                        child:
                            Column(
                          children: [
                            // -------------------------------
                            // EMAIL
                            // -------------------------------

                            TextFormField(
                              controller:
                                  _emailController,

                              keyboardType:
                                  TextInputType
                                      .emailAddress,

                              textInputAction:
                                  TextInputAction
                                      .next,

                              autocorrect:
                                  false,

                              validator:
                                  _validateEmail,

                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'Email',

                                hintText:
                                    'example@email.com',

                                prefixIcon:
                                    Icon(
                                  Icons
                                      .email_outlined,
                                ),

                                border:
                                    OutlineInputBorder(),
                              ),
                            ),

                            const SizedBox(
                              height:
                                  16,
                            ),

                            // -------------------------------
                            // PASSWORD
                            // -------------------------------

                            TextFormField(
                              controller:
                                  _passwordController,

                              obscureText:
                                  _obscurePassword,

                              textInputAction:
                                  TextInputAction
                                      .done,

                              validator:
                                  _validatePassword,

                              onFieldSubmitted:
                                  (_) {
                                _submit();
                              },

                              decoration:
                                  InputDecoration(
                                labelText:
                                    'Пароль',

                                hintText:
                                    'Мінімум 6 символів',

                                prefixIcon:
                                    const Icon(
                                  Icons
                                      .lock_outline,
                                ),

                                border:
                                    const OutlineInputBorder(),

                                suffixIcon:
                                    IconButton(
                                  tooltip:
                                      _obscurePassword
                                          ? 'Показати пароль'
                                          : 'Сховати пароль',

                                  onPressed:
                                      () {
                                    setState(() {
                                      _obscurePassword =
                                          !_obscurePassword;
                                    });
                                  },

                                  icon:
                                      Icon(
                                    _obscurePassword
                                        ? Icons
                                            .visibility_outlined
                                        : Icons
                                            .visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(
                              height:
                                  22,
                            ),

                            // -------------------------------
                            // MAIN BUTTON
                            // -------------------------------

                            SizedBox(
                              width:
                                  double.infinity,

                              child:
                                  FilledButton.icon(
                                onPressed:
                                    _isLoading
                                        ? null
                                        : _submit,

                                icon:
                                    _isLoading
                                        ? const SizedBox(
                                            width:
                                                20,
                                            height:
                                                20,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth:
                                                  2,
                                            ),
                                          )
                                        : Icon(
                                            _isRegisterMode
                                                ? Icons
                                                    .person_add_outlined
                                                : Icons
                                                    .login,
                                          ),

                                label:
                                    Text(
                                  _isLoading
                                      ? 'Зачекайте...'
                                      : _isRegisterMode
                                          ? 'Зареєструватися'
                                          : 'Увійти',
                                ),

                                style:
                                    FilledButton
                                        .styleFrom(
                                  padding:
                                      const EdgeInsets
                                          .all(
                                    16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    height:
                        18,
                  ),

                  // =========================================
                  // SWITCH LOGIN / REGISTER
                  // =========================================

                  Text(
                    _isRegisterMode
                        ? 'Вже маєте акаунт?'
                        : 'Ще не маєте акаунта?',

                    style:
                        TextStyle(
                      color:
                          colorScheme
                              .onSurfaceVariant,
                    ),
                  ),

                  TextButton(
                    onPressed:
                        _isLoading
                            ? null
                            : _switchMode,

                    child:
                        Text(
                      _isRegisterMode
                          ? 'Увійти'
                          : 'Створити акаунт',
                    ),
                  ),

                  const SizedBox(
                    height:
                        18,
                  ),

                  // =========================================
                  // INFO
                  // =========================================

                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,

                    children: [
                      Icon(
                        Icons
                            .cloud_sync_outlined,

                        size:
                            17,

                        color:
                            colorScheme
                                .onSurfaceVariant,
                      ),

                      const SizedBox(
                        width:
                            7,
                      ),

                      Flexible(
                        child:
                            Text(
                          'Маршрути зберігаються '
                          'локально та синхронізуються з хмарою',

                          textAlign:
                              TextAlign.center,

                          style:
                              TextStyle(
                            fontSize:
                                12,

                            color:
                                colorScheme
                                    .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height:
                        20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}