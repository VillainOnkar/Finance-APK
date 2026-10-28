import 'dart:ui';
import 'package:flutter/material.dart';
import 'screens/login.dart'; 
import 'screens/register.dart';
import 'screens/dashboard.dart'; // Dashboard import ho gaya
import 'package:flutter_localizations/flutter_localizations.dart';

void main() => runApp(const MyApp());

bool _isDarkModeGlobal = true; 

class MyApp extends StatefulWidget { // StatelessWidget ko StatefulWidget mein badlein
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  
  // Theme toggle karne ka function
  void _updateTheme(bool newValue) {
    setState(() {
      _isDarkModeGlobal = newValue;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WalletFlow',

      // 🔥 2. Localization Delegates add karein
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 🔥 3. Supported locales define karein
      supportedLocales: const [
        Locale('en', 'GB'), // GB locale dd/mm/yyyy format deta hai
      ],
      locale: const Locale('en', 'GB'), // Global force locale
      
      // --- GLOBAL THEME SYSTEM ---
      themeMode: _isDarkModeGlobal ? ThemeMode.dark : ThemeMode.light,
      
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        fontFamily: 'Poppins',
      ),
      
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050505),
        fontFamily: 'Poppins',
      ),

      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/dashboard') {
          final args = settings.arguments as String?;
          return MaterialPageRoute(
            builder: (context) => MainNavigationBase(
              userEmail: args ?? "guest@example.com",
              isDarkMode: _isDarkModeGlobal,      
              onThemeToggle: _updateTheme,    
            ),
          );
        }
        return null;
      },
      routes: {
        '/': (context) => const ResponsiveLoginPage(),
      },
    );
  }
}

class ResponsiveLoginPage extends StatefulWidget {
  const ResponsiveLoginPage({super.key});

  @override
  State<ResponsiveLoginPage> createState() => _ResponsiveLoginPageState();
}

class _ResponsiveLoginPageState extends State<ResponsiveLoginPage> {
  bool isLogin = true;

  void toggleScreen() {
    setState(() {
      isLogin = !isLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // --- 1. DEEP PREMIUM BACKGROUND ---
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
              ),
            ),
          ),
          
          // --- 2. DECORATIVE BLOBS ---
          Positioned(
            top: -100,
            right: -100,
            child: _buildCircle(300, Colors.blue.withOpacity(0.2)),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: _buildCircle(200, Colors.cyan.withOpacity(0.15)),
          ),

          LayoutBuilder(
            builder: (context, constraints) {
              bool isDesktop = constraints.maxWidth > 850;
              
              Widget currentForm = AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.1, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: isLogin 
                  ? LoginForm(key: const ValueKey('login'), isDark: isDesktop, onRegisterTap: toggleScreen)
                  : RegisterForm(key: const ValueKey('register'), isDark: isDesktop, onBackToLogin: toggleScreen),
              );

              if (isDesktop) {
                return Center(
                  child: Container(
                    height: 650,
                    width: 1000,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, spreadRadius: 10)],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Row(
                          children: [
                            Expanded(child: _buildWelcomeSide()),
                            Container(
                              width: 450,
                              color: Colors.white.withOpacity(0.08),
                              padding: const EdgeInsets.all(45),
                              child: currentForm,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              } else {
                // --- IS HISSE KO REPLACE KAREIN ---
                return Stack(
                  children: [
                    SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          const SizedBox(height: 80), // Thoda upar se gap
                          _buildMobileHeader(),
                          const SizedBox(height: 50),
                          Container(
                            width: double.infinity,
                            // 'minHeight' dene se keyboard aane par ye compress nahi hoga
                            constraints: BoxConstraints(
                              minHeight: MediaQuery.of(context).size.height * 0.6,
                            ),
                            padding: const EdgeInsets.fromLTRB(30, 40, 30, 40),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1A1D21), 
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(50),
                                topRight: Radius.circular(50),
                              ),
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15)],
                            ),
                            child: currentForm,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildWelcomeSide() {
    return Container(
      padding: const EdgeInsets.all(50),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_rounded, color: Colors.cyanAccent, size: 80),
          const SizedBox(height: 30),
          const Text("ONKAR FINANCE", 
            style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold, height: 1.2)),
          const SizedBox(height: 20),
          Text("Join thousands of smart investors and take control of your wealth today.", 
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildMobileHeader() {
    return Column(
      children: [
        const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 80),
        const SizedBox(height: 20),
        const Text("Sankalp Finanace", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
        Text("Smart Finance Manager", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
      ],
    );
  }
}