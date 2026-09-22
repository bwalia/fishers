import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/fishers_models.dart';
import '../../stores/session_store.dart';
import '../../theme/fishers_theme.dart';

/// Sign in, or join — a port of `ios/Fishers/Views/Auth/AuthView.swift`.
///
/// Email and password only, for now. The Swift screen also offers Google and
/// Sign in with Apple; Apple is a settled gap for v1, and Google needs a
/// native SDK and platform config that have not landed — the service layer is
/// ported but nothing calls it yet. Both slot in above the divider without
/// disturbing the form, which is why the divider says "or with email" rather
/// than being the top of the card.
class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

enum _Mode { login, signup }

enum _Method { email, phone }

class _AuthViewState extends State<AuthView> {
  final TextEditingController _name = TextEditingController();

  /// One field for both: signing in it is an address or a number; signing up
  /// it is whichever [_method] says.
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _password = TextEditingController();

  _Mode _mode = _Mode.login;
  _Method _method = _Method.email;
  RoleIntent? _role;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_identifier.text.trim().isEmpty || _password.text.isEmpty) return false;
    if (_mode == _Mode.signup && _name.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _submit(SessionStore session) async {
    if (!_canSubmit || session.isLoading) return;
    final String identifier = _identifier.text.trim();
    if (_mode == _Mode.login) {
      await session.signIn(identifier: identifier, password: _password.text);
    } else {
      await session.signUp(
        name: _name.text.trim(),
        email: _method == _Method.email ? identifier : null,
        phone: _method == _Method.phone ? identifier : null,
        password: _password.text,
        role: _role,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final SessionStore session = context.watch<SessionStore>();
    final FishersColors colors = FishersColors.of(context);
    final bool signingUp = _mode == _Mode.signup;

    return Scaffold(
      backgroundColor: colors.mist,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FishersTheme.space3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Fishers', textAlign: TextAlign.center, style: FishersTheme.brand(context)),
                  const SizedBox(height: FishersTheme.space1),
                  Text(
                    'Clubs, calendars, and match day — organised.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: FishersTheme.space3),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(FishersTheme.space3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            signingUp ? 'Join your club' : 'Welcome back',
                            style: FishersTheme.contentTitle(context),
                          ),
                          const SizedBox(height: FishersTheme.space1),
                          Text(
                            signingUp
                                ? 'Create an account — you can be in a match within a minute.'
                                : 'Sign in to see fixtures, chats and selection.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: FishersTheme.space2),
                          if (signingUp) ..._signupFields(),
                          TextField(
                            key: const Key('auth.identifier'),
                            controller: _identifier,
                            keyboardType: _method == _Method.phone
                                ? TextInputType.phone
                                : TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: signingUp && _method == _Method.phone
                                  ? 'Mobile number'
                                  : signingUp
                                  ? 'Email'
                                  : 'Email or mobile number',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: FishersTheme.space2),
                          TextField(
                            key: const Key('auth.password'),
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                tooltip: _obscure ? 'Show password' : 'Hide password',
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            onSubmitted: (_) => _submit(session),
                            onChanged: (_) => setState(() {}),
                          ),
                          if (session.errorMessage != null) ...<Widget>[
                            const SizedBox(height: FishersTheme.space2),
                            Text(
                              session.errorMessage!,
                              key: const Key('auth.error'),
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: colors.unavailable),
                            ),
                          ],
                          const SizedBox(height: FishersTheme.space3),
                          FilledButton(
                            key: const Key('auth.submit'),
                            onPressed: _canSubmit && !session.isLoading
                                ? () => _submit(session)
                                : null,
                            child: session.isLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(signingUp ? 'Create account' : 'Sign in'),
                          ),
                          const SizedBox(height: FishersTheme.space1),
                          TextButton(
                            key: const Key('auth.toggle'),
                            onPressed: session.isLoading
                                ? null
                                : () => setState(() {
                                    _mode = signingUp ? _Mode.login : _Mode.signup;
                                  }),
                            child: Text(
                              signingUp
                                  ? 'Already have an account? Sign in'
                                  : 'Need an account? Sign up',
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
        ),
      ),
    );
  }

  List<Widget> _signupFields() => <Widget>[
    TextField(
      key: const Key('auth.name'),
      controller: _name,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Name'),
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: FishersTheme.space2),
    SegmentedButton<_Method>(
      segments: const <ButtonSegment<_Method>>[
        ButtonSegment<_Method>(value: _Method.email, label: Text('Email')),
        ButtonSegment<_Method>(value: _Method.phone, label: Text('Mobile number')),
      ],
      selected: <_Method>{_method},
      onSelectionChanged: (Set<_Method> picked) => setState(() => _method = picked.first),
    ),
    const SizedBox(height: FishersTheme.space2),
    // What they came to do. Asked here because it changes what Home offers
    // first, and it is the one question worth asking before the app opens.
    Align(
      alignment: Alignment.centerLeft,
      child: Text("I'm here to…", style: FishersTheme.overline(context)),
    ),
    const SizedBox(height: 6),
    SegmentedButton<RoleIntent>(
      segments: const <ButtonSegment<RoleIntent>>[
        ButtonSegment<RoleIntent>(value: RoleIntent.player, label: Text('Play')),
        ButtonSegment<RoleIntent>(value: RoleIntent.secretary, label: Text('Run a club')),
      ],
      selected: <RoleIntent>{?_role},
      emptySelectionAllowed: true,
      onSelectionChanged: (Set<RoleIntent> picked) =>
          setState(() => _role = picked.isEmpty ? null : picked.first),
    ),
    const SizedBox(height: FishersTheme.space2),
  ];
}
