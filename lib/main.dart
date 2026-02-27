// File: lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // 🚀 引入环境变量包

import 'login_page.dart'; 
import 'home_page.dart'; 
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🚀 核心安全升级：在 App 启动的第一时间，悄悄加载 .env 里的 API Key
  await dotenv.load(fileName: ".env"); 
  
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SafeStrideApp());
}

class SafeStrideApp extends StatelessWidget {
  const SafeStrideApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF2F2F7), 
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF3B30)), 
        useMaterial3: true,
      ),
      home: const AuthGate(), 
    );
  }
}

// 🛡️ AUTH GATE: 拦截器
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) return const HomePage(); 
        return const LoginPage(); 
      },
    );
  }
}