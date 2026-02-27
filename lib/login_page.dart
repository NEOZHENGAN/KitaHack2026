// File: lib/login_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _nameController = TextEditingController(); // 🚀 新增：用户名输入框
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLoginMode = true; // 🚀 新增：控制当前是登录模式还是注册模式

  // --- Sign In Logic ---
  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login Failed: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Registration Logic (With Username) ---
  Future<void> _register() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a username.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 1. Create the user
      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      // 2. 🚀 Update the Firebase Auth profile with the Username!
      await cred.user?.updateDisplayName(_nameController.text.trim());
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration Successful!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration Failed: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Password Reset Logic ---
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your email address first.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), 
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_rounded, size: 100, color: Color(0xFFFF3B30)),
              const SizedBox(height: 20),
              const Text('SafeStride', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Color(0xFFFF3B30), letterSpacing: -1)),
              Text(_isLoginMode ? 'Welcome Back' : 'Create an Account', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 40),
              
              // 🚀 新增：只有在注册模式下，才显示 Username 输入框
              if (!_isLoginMode) ...[
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Username (e.g. John)', 
                    filled: true, fillColor: Colors.white, 
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.black45),
                  ),
                ),
                const SizedBox(height: 15),
              ],

              // Email Input
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  hintText: 'Email', 
                  filled: true, fillColor: Colors.white, 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.black45),
                ),
              ),
              const SizedBox(height: 15),
              
              // Password Input
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Password', 
                  filled: true, fillColor: Colors.white, 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.black45),
                ),
              ),
              
              // Forgot Password Button (Only in Login Mode)
              if (_isLoginMode)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.w600)),
                  ),
                )
              else
                const SizedBox(height: 20),
              
              _isLoading 
                  ? const CircularProgressIndicator(color: Color(0xFFFF3B30))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3B30), foregroundColor: Colors.white, 
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
                          ),
                          onPressed: _isLoginMode ? _signIn : _register,
                          child: Text(_isLoginMode ? 'Login' : 'Sign Up', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 12),
                        // Toggle between Login and Register Mode
                        TextButton(
                          onPressed: () => setState(() {
                            _isLoginMode = !_isLoginMode;
                            _nameController.clear();
                            _passwordController.clear();
                          }),
                          child: Text(
                            _isLoginMode ? "Don't have an account? Sign Up" : "Already have an account? Login", 
                            style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w600)
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}