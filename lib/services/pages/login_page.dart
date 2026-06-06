import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/stores/auth_store.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

enum _ActiveField { name, email, password }

class LoginPage extends StatefulWidget {
  final AuthStore authStore;
  const LoginPage({super.key, required this.authStore});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isRegister = false;
  String _name = '';
  String _email = '';
  String _password = '';
  _ActiveField _active = _ActiveField.email;
  bool _shift = true;
  bool _symbols = false;

  static const _lettersUpper = 'QWERTYUIOPASDFGHJKLZXCVBNM';
  static const _lettersLower = 'qwertyuiopasdfghjklzxcvbnm';
  static const _symbolsKeys = '1234567890@.-_+#!?\$%&*()/:;,';

  String _currentValue() {
    switch (_active) {
      case _ActiveField.name:
        return _name;
      case _ActiveField.email:
        return _email;
      case _ActiveField.password:
        return _password;
    }
  }

  void _setActiveValue(String v) {
    setState(() {
      switch (_active) {
        case _ActiveField.name:
          _name = v;
          break;
        case _ActiveField.email:
          _email = v;
          break;
        case _ActiveField.password:
          _password = v;
          break;
      }
    });
  }

  void _append(String ch) => _setActiveValue(_currentValue() + ch);

  void _backspace() {
    final v = _currentValue();
    if (v.isEmpty) return;
    _setActiveValue(v.substring(0, v.length - 1));
  }

  void _clear() => _setActiveValue('');

  Future<void> _submit() async {
    if (_isRegister) {
      final ok = await widget.authStore.register(
        name: _name.trim(),
        email: _email.trim(),
        password: _password,
      );
      if (!ok && mounted) _showError();
    } else {
      final ok = await widget.authStore.login(
        email: _email.trim(),
        password: _password,
      );
      if (!ok && mounted) _showError();
    }
  }

  void _showError() {
    final msg = widget.authStore.errorMessage ?? 'Failed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kNetflixRed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kDeepBlack,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.2),
                    radius: 1.4,
                    colors: [
                      kNetflixRed.withOpacity(0.18),
                      kDeepBlack,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 60.s(context),
                vertical: 40.s(context),
              ),
              child: Row(
                children: [
                  // LEFT — form
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: _buildForm(context),
                    ),
                  ),
                  SizedBox(width: 32.s(context)),
                  // RIGHT — on-screen keyboard
                  Expanded(
                    flex: 5,
                    child: _buildKeyboard(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14.s(context)),
              child: Image.asset(
                'assets/favicon.jpg',
                width: 72.s(context),
                height: 72.s(context),
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 16.s(context)),
            Text(
              'ReelixTv',
              style: TextStyle(
                color: kTextWhite,
                fontSize: 36.s(context),
                fontWeight: FontWeight.w900,
                letterSpacing: 2.s(context),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.s(context)),
        Text(
          _isRegister ? 'Create your account' : 'Sign in to continue',
          style: TextStyle(color: kTextGrey, fontSize: 16.s(context)),
        ),
        SizedBox(height: 28.s(context)),
        if (_isRegister) ...[
          _Field(
            label: 'Name',
            icon: Icons.person_outline,
            value: _name,
            active: _active == _ActiveField.name,
            onFocus: () => setState(() => _active = _ActiveField.name),
            autofocus: true,
          ),
          SizedBox(height: 12.s(context)),
        ],
        _Field(
          label: 'Email',
          icon: Icons.email_outlined,
          value: _email,
          active: _active == _ActiveField.email,
          onFocus: () => setState(() => _active = _ActiveField.email),
          autofocus: !_isRegister,
        ),
        SizedBox(height: 12.s(context)),
        _Field(
          label: 'Password',
          icon: Icons.lock_outline,
          value: _password,
          obscure: true,
          active: _active == _ActiveField.password,
          onFocus: () => setState(() => _active = _ActiveField.password),
        ),
        SizedBox(height: 24.s(context)),
        Observer(
          builder: (_) => _PrimaryButton(
            label: widget.authStore.isLoading
                ? '...'
                : (_isRegister ? 'CREATE ACCOUNT' : 'SIGN IN'),
            onPressed: widget.authStore.isLoading ? null : _submit,
          ),
        ),
        SizedBox(height: 12.s(context)),
        _TextButton(
          label: _isRegister
              ? 'Already have an account? Sign in'
              : "Don't have an account? Create one",
          onPressed: () => setState(() => _isRegister = !_isRegister),
        ),
      ],
    );
  }

  Widget _buildKeyboard(BuildContext context) {
    final letters = _shift ? _lettersUpper : _lettersLower;
    final keys = _symbols ? _symbolsKeys : letters;

    return Container(
      padding: EdgeInsets.all(16.s(context)),
      decoration: BoxDecoration(
        color: kSurfaceGrey.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16.s(context)),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // mode toggle row
          Row(
            children: [
              _KeyTile(
                label: _symbols ? 'ABC' : '123',
                wide: true,
                onPressed: () => setState(() => _symbols = !_symbols),
              ),
              SizedBox(width: 6.s(context)),
              if (!_symbols)
                _KeyTile(
                  label: _shift ? '⇧ AaA' : '⇧ aaa',
                  wide: true,
                  onPressed: () => setState(() => _shift = !_shift),
                ),
              SizedBox(width: 6.s(context)),
              _KeyTile(
                label: '⌫',
                wide: true,
                onPressed: _backspace,
              ),
              SizedBox(width: 6.s(context)),
              _KeyTile(
                label: 'Clear',
                wide: true,
                onPressed: _clear,
              ),
            ],
          ),
          SizedBox(height: 8.s(context)),
          // letter grid
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 10,
                mainAxisSpacing: 6.s(context),
                crossAxisSpacing: 6.s(context),
                childAspectRatio: 1.0,
              ),
              itemCount: keys.length,
              itemBuilder: (ctx, i) {
                final ch = keys[i];
                return _KeyTile(label: ch, onPressed: () => _append(ch));
              },
            ),
          ),
          SizedBox(height: 8.s(context)),
          // email shortcuts row
          Row(
            children: [
              Expanded(
                child: _KeyTile(
                  label: '@gmail.com',
                  wide: true,
                  onPressed: () => _append('@gmail.com'),
                ),
              ),
              SizedBox(width: 6.s(context)),
              Expanded(
                child: _KeyTile(
                  label: '@yahoo.com',
                  wide: true,
                  onPressed: () => _append('@yahoo.com'),
                ),
              ),
              SizedBox(width: 6.s(context)),
              Expanded(
                child: _KeyTile(
                  label: '@outlook.com',
                  wide: true,
                  onPressed: () => _append('@outlook.com'),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.s(context)),
          // space + @ + .
          Row(
            children: [
              Expanded(
                flex: 4,
                child: _KeyTile(
                  label: 'Space',
                  wide: true,
                  onPressed: () => _append(' '),
                ),
              ),
              SizedBox(width: 6.s(context)),
              _KeyTile(label: '@', onPressed: () => _append('@')),
              SizedBox(width: 6.s(context)),
              _KeyTile(label: '.', onPressed: () => _append('.')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final bool active;
  final bool obscure;
  final bool autofocus;
  final VoidCallback onFocus;

  const _Field({
    required this.label,
    required this.icon,
    required this.value,
    required this.active,
    required this.onFocus,
    this.obscure = false,
    this.autofocus = false,
  });

  String get _display {
    if (value.isEmpty) return '';
    if (!obscure) return value;
    return '•' * value.length;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: autofocus,
      onFocusChange: (f) {
        if (f) onFocus();
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        final ringColor = focused ? kAccent : (active ? kNetflixRed : Colors.white12);
        return GestureDetector(
          onTap: onFocus,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.symmetric(
              horizontal: 14.s(context),
              vertical: 14.s(context),
            ),
            decoration: BoxDecoration(
              color: kSurfaceHi.withOpacity(focused || active ? 1.0 : 0.7),
              borderRadius: BorderRadius.circular(10.s(context)),
              border: Border.all(color: ringColor, width: 2.s(context)),
            ),
            child: Row(
              children: [
                Icon(icon, color: kTextGrey, size: 20.s(context)),
                SizedBox(width: 12.s(context)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(color: kTextGrey, fontSize: 11.s(context)),
                      ),
                      SizedBox(height: 2.s(context)),
                      Text(
                        _display.isEmpty ? '—' : _display,
                        style: TextStyle(
                          color: _display.isEmpty ? Colors.white24 : kTextWhite,
                          fontSize: 18.s(context),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (active)
                  Container(
                    width: 8.s(context),
                    height: 8.s(context),
                    decoration: const BoxDecoration(
                      color: kNetflixRed,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _KeyTile extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool wide;

  const _KeyTile({
    required this.label,
    required this.onPressed,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: wide
                ? EdgeInsets.symmetric(
                    horizontal: 14.s(context),
                    vertical: 12.s(context),
                  )
                : null,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? kNetflixRed : kSurfaceHi,
              borderRadius: BorderRadius.circular(8.s(context)),
              border: focused
                  ? null
                  : Border.all(color: Colors.white10),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: kTextWhite,
                fontSize: (wide ? 12 : 16).s(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _PrimaryButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 56.s(context),
            decoration: BoxDecoration(
              color: focused ? kNetflixRed : kNetflixRed.withOpacity(0.85),
              borderRadius: BorderRadius.circular(10.s(context)),
              boxShadow: focused
                  ? [BoxShadow(color: kNetflixRed.withOpacity(0.5), blurRadius: 24.s(context))]
                  : [],
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: kTextWhite,
                fontSize: 18.s(context),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5.s(context),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _TextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _TextButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: focused ? kAccent : kTextGrey,
                fontSize: 14.s(context),
                decoration: focused ? TextDecoration.underline : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}
