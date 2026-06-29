import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Works around the known firebase_auth "PigeonUserDetails" type-cast bug:
/// the native sign-in succeeds, but deserializing the returned user throws a
/// `type 'List<Object?>' is not a subtype of type 'PigeonUserDetails?'` error.
/// Returns true if the user is actually signed in despite that error.
Future<bool> _signedInDespiteError() async {
  if (FirebaseAuth.instance.currentUser != null) return true;
  final user = await FirebaseAuth.instance
      .authStateChanges()
      .firstWhere((u) => u != null)
      .timeout(const Duration(seconds: 4), onTimeout: () => null);
  return user != null;
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade900, Colors.blue.shade300],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.account_balance_wallet,
                    size: 100, color: Colors.white),
                const SizedBox(height: 20),
                const Text(
                  'Smart Expense Tracker',
                  style: TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.blue.shade900,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Login', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen())),
                  child: const Text('Register',
                      style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    signInOption: SignInOption.standard,
  );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Login failed')),
        );
      }
    } catch (e) {
      // Tolerate the firebase_auth pigeon cast bug.
      if (await _signedInDespiteError()) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      // Try silent sign in first
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();

      // If silent sign in fails, try interactive sign in
      googleUser ??= await _googleSignIn.signIn();

      // Handle user cancellation
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      // Tolerate the firebase_auth pigeon cast bug: proceed if actually signed in.
      if (await _signedInDespiteError()) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome Back',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                      .hasMatch(value)) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _signInWithEmail,
                  child: const Text('Login', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 4,
                  ),
                  icon: Image.network(
                    'https://www.google.com/favicon.ico',
                    height: 24,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.g_mobiledata, size: 24),
                  ),
                  label: const Text('Sign in with Google',
                      style: TextStyle(fontSize: 16)),
                  onPressed: _signInWithGoogle,
                ),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text('Need an account? Register',
                    style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    signInOption: SignInOption.standard,
  );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _registerWithEmail() async {
    if (_isLoading) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Registration failed')),
        );
      }
    } catch (e) {
      // Tolerate the firebase_auth pigeon cast bug.
      if (await _signedInDespiteError()) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _registerWithGoogle() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      // Try silent sign in first
      GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();

      // If silent sign in fails, try interactive sign in
      googleUser ??= await _googleSignIn.signIn();

      // Handle user cancellation
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Get auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      // Tolerate the firebase_auth pigeon cast bug: proceed if actually signed in.
      if (await _signedInDespiteError()) {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Get Started',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                      .hasMatch(value)) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.blue.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _registerWithEmail,
                  child: const Text('Register', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 4,
                  ),
                  icon: Image.network(
                    'https://www.google.com/favicon.ico',
                    height: 24,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.g_mobiledata, size: 24),
                  ),
                  label: const Text('Register with Google',
                      style: TextStyle(fontSize: 16)),
                  onPressed: _registerWithGoogle,
                ),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: const Text('Already have an account? Login',
                    style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
