import 'dart:convert';
import 'package:flutter/material.dart';
import '../database_service.dart'; // ✅ DatabaseService connection ke liye

class SettingsPage extends StatefulWidget {
  final String userEmail;
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const SettingsPage({
    super.key,
    required this.userEmail,
    required this.isDarkMode,
    required this.onThemeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 0;
  bool _isResetExpanded = false;
  bool _isDeleteExpanded = false; 
  bool _isLoading = false; 

  // Profile Data State
  Map<String, String> _userData = {
    "name": "Loading...",
    "phone": "...",
    "email": ""
  };

  final TextEditingController _resetEmailController = TextEditingController();
  final TextEditingController _deleteEmailController = TextEditingController();
  final TextEditingController _deletePasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _userData["email"] = widget.userEmail;
    _fetchAdminProfile(); 
  }

  @override
  void dispose() {
    _resetEmailController.dispose();
    _deleteEmailController.dispose();
    _deletePasswordController.dispose();
    super.dispose();
  }

  // ✅ --- Profile Data Fetch Logic ---
  Future<void> _fetchAdminProfile() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final result = await DatabaseService.fetchUserProfile(widget.userEmail);
      if (mounted && result['status'] == true) {
        setState(() {
          _userData = {
            "name": result['name'].toString(),
            "phone": result['phone'].toString(),
            "email": widget.userEmail,
          };
        });
      }
    } catch (e) {
      debugPrint("Fetch Profile Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ --- Action Logic ---
  Future<void> _runScript(String command, List<String> args) async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> result;
      if (command == 'reset_password') {
        result = await DatabaseService.resetPassword(args[0]);
      } else if (command == 'delete_account') {
        result = await DatabaseService.deleteUserAccount(args[0], args[1]);
      } else {
        result = {"status": false, "message": "Unknown Command"};
      }
      
      if (result['status'] == true) {
        if (command == 'delete_account') {
          _showSnackBar("Account deleted successfully!", Colors.green);
          if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        } else {
          _showSnackBar(result['message'] ?? "Action completed!", Colors.green);
        }
      } else {
        _showSnackBar(result['message'] ?? "Action failed!", Colors.red);
      }
    } catch (e) {
      _showSnackBar("System Error: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDarkMode ? const Color(0xFF1C1E21) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Logout", style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black)),
        content: Text("Kya aap sach mein logout karna chahte hain?", style: TextStyle(color: widget.isDarkMode ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Nahi")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
            child: const Text("Haan, Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = widget.isDarkMode;
    final Color bgColor = isDark ? const Color(0xFF0F1113) : const Color(0xFFF8F9FD);
    final Color cardColor = isDark ? const Color(0xFF1C1E21) : Colors.white;
    const Color accentColor = Color(0xFF4A90E2);
    final Color textColor = isDark ? Colors.white : const Color(0xFF2D3436);

    return Scaffold(
      backgroundColor: bgColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 700;

          return Row(
            children: [
              if (!isMobile) _buildSidebar(isDark, textColor, accentColor, false),
              Expanded(
                child: Column(
                  children: [
                    if (isMobile) _buildMobileHeader(isDark, textColor, accentColor),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 15 : 10, isMobile ? 10 : 30, isMobile ? 15 : 30, 30),
                        child: Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(isMobile ? 25 : 40),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.4 : 0.08), blurRadius: 30, offset: const Offset(0, 10))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(isMobile ? 25 : 40),
                            child: _getPage(_selectedIndex, isDark, textColor, accentColor),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 700 
        ? BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
            backgroundColor: cardColor,
            selectedItemColor: accentColor,
            unselectedItemColor: isDark ? Colors.white24 : Colors.black26,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
              BottomNavigationBarItem(icon: Icon(Icons.palette), label: "Theme"),
              BottomNavigationBarItem(icon: Icon(Icons.shield), label: "Security"),
            ],
          ) : null,
    );
  }

  Widget _buildMobileHeader(bool isDark, Color textColor, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const CircleAvatar(radius: 18, backgroundColor: Color(0xFF4A90E2), child: Icon(Icons.settings, color: Colors.white, size: 18)),
          IconButton(onPressed: _handleLogout, icon: const Icon(Icons.logout, color: Colors.redAccent)),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isDark, Color textColor, Color accentColor, bool isMobile) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const CircleAvatar(radius: 25, backgroundColor: Color(0xFF4A90E2), child: Icon(Icons.settings, color: Colors.white)),
          const SizedBox(height: 50),
          _sidebarIcon(0, Icons.person_outline_rounded, "Profile", isDark, accentColor),
          _sidebarIcon(1, Icons.palette_outlined, "Theme", isDark, accentColor),
          _sidebarIcon(2, Icons.shield_outlined, "Security", isDark, accentColor),
          const Spacer(),
          GestureDetector(
            onTap: _handleLogout,
            child: Column(
              children: [
                Icon(Icons.logout_rounded, color: Colors.redAccent.withOpacity(0.7), size: 28),
                const SizedBox(height: 5),
                Text("Logout", style: TextStyle(fontSize: 11, color: Colors.redAccent.withOpacity(0.7))),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sidebarIcon(int index, IconData icon, String label, bool isDark, Color accentColor) {
    bool isSel = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 15),
        height: 75,
        decoration: BoxDecoration(color: isSel ? accentColor.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSel ? accentColor : (isDark ? Colors.white24 : Colors.black26), size: 28),
            const SizedBox(height: 5),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? accentColor : (isDark ? Colors.white24 : Colors.black26))),
          ],
        ),
      ),
    );
  }

  Widget _getPage(int index, bool isDark, Color textColor, Color accentColor) {
    switch (index) {
      case 0: return _buildProfilePage(isDark, textColor, accentColor);
      case 1: return _buildThemePage(isDark, textColor, accentColor);
      case 2: return _buildSecurityPage(isDark, textColor, accentColor);
      default: return Container();
    }
  }

  Widget _buildProfilePage(bool isDark, Color textColor, Color accentColor) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 700 ? 20.0 : 50.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(MediaQuery.of(context).size.width < 700 ? 20 : 40),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(35),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: MediaQuery.of(context).size.width < 700 ? 50 : 70,
                      backgroundColor: accentColor.withOpacity(0.1),
                      child: Icon(Icons.person_rounded, size: MediaQuery.of(context).size.width < 700 ? 60 : 85, color: accentColor),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle, border: Border.all(color: isDark ? const Color(0xFF1C1E21) : Colors.white, width: 3)),
                      child: const Icon(Icons.verified_rounded, size: 14, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                _isLoading && _userData["name"] == "Loading..." 
                  ? const CircularProgressIndicator()
                  : Text(_userData["name"]!, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 4),
                Text("Member", style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5), fontWeight: FontWeight.w500, letterSpacing: 1.2)),
                const SizedBox(height: 30),
                Divider(color: textColor.withOpacity(0.1), thickness: 1),
                const SizedBox(height: 20),
                _profileInfoTile(Icons.alternate_email_rounded, "Email Address", _userData["email"]!, accentColor, textColor),
                const SizedBox(height: 20),
                _profileInfoTile(Icons.phone_android_rounded, "Phone Number", _userData["phone"]!, accentColor, textColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileInfoTile(IconData icon, String label, String value, Color accentColor, Color textColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: accentColor, size: 20),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.4), fontWeight: FontWeight.bold)),
              Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemePage(bool isDark, Color textColor, Color accentColor) {
    return Padding(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 700 ? 20.0 : 50.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Appearance", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor)),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03), borderRadius: BorderRadius.circular(25)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Dark Theme", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                Switch.adaptive(value: isDark, onChanged: widget.onThemeChanged, activeColor: accentColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPage(bool isDark, Color textColor, Color accentColor) {
    return Padding(
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 700 ? 20.0 : 50.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Security Center", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textColor)),
            const SizedBox(height: 30),
            _buildActionCard(title: "Reset Password", icon: Icons.lock_reset, isExpanded: _isResetExpanded, accentColor: accentColor, isDark: isDark, textColor: textColor, onToggle: () => setState(() => _isResetExpanded = !_isResetExpanded), 
              child: Column(children: [_buildInputField(isDark, textColor, accentColor, _resetEmailController, "Enter email"), const SizedBox(height: 15), _buildButton("Send Request", accentColor, () => _runScript('reset_password', [_resetEmailController.text.trim()]))])),
            const SizedBox(height: 15),
            _buildActionCard(title: "Delete Account", icon: Icons.delete, isExpanded: _isDeleteExpanded, accentColor: Colors.redAccent, isDark: isDark, textColor: textColor, onToggle: () => setState(() => _isDeleteExpanded = !_isDeleteExpanded), 
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Permanent action.", style: TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 15), _buildButton("Delete Now", Colors.redAccent, _showDeleteAuthDialog)]))
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({required String title, required IconData icon, required bool isExpanded, required Color accentColor, required bool isDark, required Color textColor, required VoidCallback onToggle, required Widget child}) {
    return AnimatedContainer(duration: const Duration(milliseconds: 400), decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03), borderRadius: BorderRadius.circular(25)),
      child: Column(children: [ListTile(onTap: onToggle, leading: Icon(icon, color: accentColor), title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15))), if (isExpanded) Padding(padding: const EdgeInsets.fromLTRB(15, 0, 15, 15), child: child)]));
  }

  Widget _buildInputField(bool isDark, Color textColor, Color accentColor, TextEditingController controller, String hint) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.white, borderRadius: BorderRadius.circular(12)),
      child: TextField(controller: controller, style: TextStyle(color: textColor, fontSize: 14), decoration: InputDecoration(hintText: hint, border: InputBorder.none)));
  }

  Widget _buildButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(width: double.infinity, height: 45, child: ElevatedButton(onPressed: _isLoading ? null : onPressed, style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))));
  }

  void _showDeleteAuthDialog() {
    _deleteEmailController.clear();
    _deletePasswordController.clear();
    showDialog(
      context: context,
      barrierDismissible: !_isLoading,
      builder: (context) {
        bool isObscure = true;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final bool isDark = widget.isDarkMode;
            final Color textColor = isDark ? Colors.white : const Color(0xFF2D3436);
            final Color dialogBg = isDark ? const Color(0xFF1C1E21) : Colors.white;
            return AlertDialog(
              backgroundColor: dialogBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              title: const Text("Verify Account", style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogField(_deleteEmailController, "Email", Icons.email, isDark, textColor),
                  const SizedBox(height: 12),
                  _buildDialogField(_deletePasswordController, "Password", Icons.lock, isDark, textColor, isPass: true, isObscure: isObscure, onToggle: () => setStateDialog(() => isObscure = !isObscure)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(onPressed: () { Navigator.pop(context); _showDeleteConfirmDialog(_deleteEmailController.text.trim(), _deletePasswordController.text.trim()); }, child: const Text("Next")),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogField(TextEditingController ctrl, String hint, IconData icon, bool isDark, Color textColor, {bool isPass = false, bool isObscure = false, VoidCallback? onToggle}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: isDark ? Colors.black26 : const Color(0xFFF0F2F5), borderRadius: BorderRadius.circular(15)),
      child: TextField(
        controller: ctrl,
        obscureText: isPass ? isObscure : false,
        style: TextStyle(color: textColor, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint, border: InputBorder.none, icon: Icon(icon, size: 18),
          suffixIcon: isPass ? IconButton(icon: Icon(isObscure ? Icons.visibility_off : Icons.visibility), onPressed: onToggle) : null,
        ),
      ),
    );
  }

  void _showDeleteConfirmDialog(String email, String password) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: const Text("Are you sure? This is permanent."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
          ElevatedButton(onPressed: () { Navigator.pop(context); _runScript('delete_account', [email, password]); }, child: const Text("Yes, Delete")),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }
}