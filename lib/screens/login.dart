import 'package:flutter/material.dart';
import 'dart:io'; // Process.run ke liye zaruri hai
import '../database_service.dart';

class LoginForm extends StatefulWidget {
  final bool isDark;
  final VoidCallback onRegisterTap;

  const LoginForm({
    super.key,
    required this.isDark,
    required this.onRegisterTap,
  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  bool _obscureText = true;
  bool _isLoading = false;

  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  // --- SNACKBAR LOGIC ---
  void _showSnackBar(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- LOGIN HANDLE FUNCTION (UPDATED) ---
  // --- LOGIN HANDLE FUNCTION (Ab DatabaseService use karega) ---
  Future<void> _handleLogin() async {
    String identifier = _userController.text.trim();
    String password = _passController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      _showSnackBar("Email/Username aur Password bharna zaruri hai!", true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ Ab hum seedha aapki database_service file ka function call kar rahe hain
      // Isme koi path ki tension nahi hai kyunki ye pure Dart code hai.
      final result = await DatabaseService.loginUser(identifier, password);

      if (result['status'] == true) {
        
        if (mounted) {
          Navigator.pushReplacementNamed(
            context, 
            '/dashboard', 
            arguments: result['email'], // Aapka function email return karta hai
          );
        }
      } else {
        // Aapke function se jo error message aayega (like "Username nahi mila") wo yahan dikhega
        _showSnackBar(result['message'], true);
      }
    } catch (e) {
      _showSnackBar("Error: Connection nahi ho paya.", true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
Widget build(BuildContext context) {
  Color textColor = widget.isDark ? Colors.white : Colors.black87;
  Color subColor = widget.isDark ? Colors.white70 : Colors.black54;

  // 1. Sabse pehle LayoutBuilder ka use karein taaki screen size pata chale
  return LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView( // 2. ScrollView jo yellow lines hatayega
        physics: const BouncingScrollPhysics(),
        child: Container(
          // 3. Agar screen Landscape hai to padding kam kar dein
          padding: EdgeInsets.symmetric(
            horizontal: 32, 
            vertical: constraints.maxHeight < 400 ? 10 : 32 // Height kam hone par padding auto kam hogi
          ),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF232D36).withOpacity(0.95) : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(50),
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 25,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Login", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text("Manage your finance with ease.", style: TextStyle(fontSize: 14, color: subColor)),
              
              // 4. In gaps ko responsive banaya (Height kam to gap kam)
              SizedBox(height: constraints.maxHeight < 400 ? 15 : 40),

              _customTextField(
                hint: "Email or Username",
                icon: Icons.alternate_email_rounded,
                isDark: widget.isDark,
                controller: _userController,
              ),
              const SizedBox(height: 15),

              _customTextField(
                hint: "Password",
                icon: Icons.lock_person_outlined,
                isDark: widget.isDark,
                isPassword: true,
                controller: _passController,
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _handleForgotPassword, 
                  child: Text(
                    "Forgot Password?",
                    style: TextStyle(
                      color: widget.isDark ? Colors.white54 : Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              _buildLoginButton(),

              const SizedBox(height: 20),
              Center(
                child: GestureDetector(
                  onTap: widget.onRegisterTap,
                  child: RichText(
                    text: TextSpan(
                      text: "New here? ",
                      style: TextStyle(color: subColor, fontSize: 15),
                      children: [
                        TextSpan(
                          text: "Create Account",
                          style: TextStyle(
                            color: widget.isDark ? Colors.cyanAccent : Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Keyboard khulne par niche thodi extra jagah
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF00B4DB), Color(0xFF0083B0)]),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00B4DB).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: _isLoading ? null : _handleLogin,
        child: _isLoading 
          ? const SizedBox(height: 25, width: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text("SIGN IN", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    );
  }

  Widget _customTextField({
    required String hint,
    required IconData icon,
    bool isPassword = false,
    required bool isDark,
    required TextEditingController controller,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[100],
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscureText : false,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 15),
          prefixIcon: Icon(icon, color: isDark ? Colors.white60 : Colors.black45, size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility, color: isDark ? Colors.white60 : Colors.black45, size: 18),
                  onPressed: () => setState(() => _obscureText = !_obscureText),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        ),
      ),
    );
  }

  // --- FORGOT PASSWORD LOGIC ---
  void _handleForgotPassword() {
    final TextEditingController resetEmailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDark ? const Color(0xFF1A1A1A) : Colors.white,
        title: Text("Reset Password", 
          style: TextStyle(color: widget.isDark ? Colors.white : Colors.black, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Apna registered email enter karein, hum aapko password reset link bhejenge.",
              style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
            const SizedBox(height: 15),
            TextField(
              controller: resetEmailController,
              style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "Enter Email",
                hintStyle: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black38),
                prefixIcon: const Icon(Icons.email_outlined, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text("CANCEL")
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              String email = resetEmailController.text.trim();
              if (email.isEmpty || !email.contains("@")) {
                _showSnackBar("Please enter a valid email", true);
                return;
              }

              Navigator.pop(context); // Dialog band karein
              setState(() => _isLoading = true);

              // --- DATABASE CALL ---
              var result = await DatabaseService.resetPassword(email);

              setState(() => _isLoading = false);
              
              if (result['status'] == true) {
                _showSnackBar("Reset link sent! Check your inbox.", false);
              } else {
                _showSnackBar("Error: ${result['message']}", true);
              }
            },
            child: const Text("SEND LINK", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}