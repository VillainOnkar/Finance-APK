import 'package:flutter/material.dart';
import 'dart:io';
import '../database_service.dart';
class RegisterForm extends StatefulWidget {
  final bool isDark;
  final VoidCallback onBackToLogin;

  const RegisterForm({super.key, required this.isDark, required this.onBackToLogin});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  bool _isObscure = true;
  bool _acceptTerms = false;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  void _showCustomSnackBar(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        duration: const Duration(seconds: 4), // Error padhne ke liye thoda extra time
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isError 
                ? [Colors.redAccent.shade400, Colors.red.shade900] 
                : [const Color(0xFF00c6ff), const Color(0xFF0072ff)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isError ? Colors.red.withOpacity(0.3) : Colors.blue.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Row(
            children: [
              Icon(isError ? Icons.error_outline_rounded : Icons.verified_user_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 15),
              Expanded(
                child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _validateFields() {
    if (_nameController.text.trim().isEmpty || 
        _userController.text.trim().isEmpty || 
        _emailController.text.trim().isEmpty || 
        _phoneController.text.trim().isEmpty || 
        _passController.text.isEmpty) {
      _showCustomSnackBar("Sabhie details bharna zaroori hai!", true);
      return false;
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text.trim())) {
      _showCustomSnackBar("Email ka format sahi nahi hai!", true);
      return false;
    }
    if (_passController.text != _confirmPassController.text) {
      _showCustomSnackBar("Passwords match nahi ho rahe!", true);
      return false;
    }
    if (!_acceptTerms) {
      _showCustomSnackBar("Terms accept karein!", true);
      return false;
    }
    return true;
  }

  Future<void> _handleRegister() async {
    if (!_acceptTerms) {
      _showCustomSnackBar("Please accept Terms & Conditions", true);
      return;
    }

    String fullName = _nameController.text.trim();
    String username = _userController.text.trim();
    String email = _emailController.text.trim();
    String phone = _phoneController.text.trim();
    String password = _passController.text.trim();
    String confirmPass = _confirmPassController.text.trim();

    // Basic Validation
    if (fullName.isEmpty || username.isEmpty || email.isEmpty || phone.isEmpty || password.isEmpty) {
      _showCustomSnackBar("Sabhi fields bharna zaruri hai!", true);
      return;
    }

    if (password != confirmPass) {
      _showCustomSnackBar("Passwords match nahi ho rahe!", true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ Aapke naye registerUserInDb function ka use
      final result = await DatabaseService.registerUserInDb(
        email, 
        username, 
        password, 
        fullName, 
        phone
      );

      if (result['status'] == true) {
        _showCustomSnackBar(result['message'], false);
        
        // Registration success ke baad login page par bhejein
        Future.delayed(const Duration(seconds: 2), () {
          widget.onBackToLogin();
        });
      } else {
        // Error message dikhayein (Username exists, etc.)
        _showCustomSnackBar(result['message'], true);
      }
    } catch (e) {
      _showCustomSnackBar("Registration Error: Connection fail ho gaya.", true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color txtColor = widget.isDark ? Colors.white : Colors.black87;
    Color subColor = widget.isDark ? Colors.white70 : Colors.black54;

    return SingleChildScrollView(
      // 1. Physics ko smooth banaya
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 2. Jitna content utni height
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Text("Create Account", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: txtColor)),
              const SizedBox(height: 5),
              Text("Join us to manage your finances.", style: TextStyle(fontSize: 14, color: subColor)),
              const SizedBox(height: 25),
              
              // Input fields ka gap thoda responsive rakha hai
              _inputField("Full Name", Icons.person_outline, _nameController),
              const SizedBox(height: 12),
              _inputField("Username", Icons.alternate_email_rounded, _userController),
              const SizedBox(height: 12),
              _inputField("Email Address", Icons.email_outlined, _emailController, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _inputField("Phone Number", Icons.phone_android_outlined, _phoneController, keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _inputField("Password", Icons.lock_outline, _passController, isPass: true),
              const SizedBox(height: 12),
              _inputField("Confirm Password", Icons.lock_reset_outlined, _confirmPassController, isPass: true),
              
              const SizedBox(height: 15),
              Row(
                children: [
                  Checkbox(
                    value: _acceptTerms,
                    activeColor: Colors.cyanAccent,
                    checkColor: Colors.black,
                    onChanged: (value) => setState(() => _acceptTerms = value!),
                  ),
                  Expanded(child: Text("I agree to the Terms & Privacy Policy", style: TextStyle(color: subColor, fontSize: 13))),
                ],
              ),
            ],
          ),
          
          // 3. Buttons ko bhi scroll view ke andar rakha taaki keyboard inhe na dabaye
          const SizedBox(height: 20),
          _buildRegisterButton(),
          const SizedBox(height: 5),
          TextButton(
            onPressed: widget.onBackToLogin,
            child: Text(
              "Already have an account? Login", 
              style: TextStyle(
                color: widget.isDark ? Colors.cyanAccent : Colors.blue, 
                fontWeight: FontWeight.w600
              )
            ),
          ),
          // 4. Keyboard khulne par last button ke niche thodi jagah
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildRegisterButton() {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: _acceptTerms 
          ? const LinearGradient(colors: [Color(0xFF00c6ff), Color(0xFF0072ff)])
          : LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade500]),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
        onPressed: _isLoading ? null : _handleRegister,
        child: _isLoading 
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text("REGISTER NOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _inputField(String hint, IconData icon, TextEditingController controller, {bool isPass = false, TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.white.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPass ? _isObscure : false,
        keyboardType: keyboardType,
        style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black45, fontSize: 14),
          prefixIcon: Icon(icon, color: widget.isDark ? Colors.cyanAccent : Colors.blueAccent),
          suffixIcon: isPass ? IconButton(
            icon: Icon(_isObscure ? Icons.visibility_off : Icons.visibility, color: widget.isDark ? Colors.white60 : Colors.black45),
            onPressed: () => setState(() => _isObscure = !_isObscure),
          ) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        ),
      ),
    );
  }
}