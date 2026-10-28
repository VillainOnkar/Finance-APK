import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../database_service.dart'; // ✅ DatabaseService import kiya
import '../app_mode.dart'; // 🔥 Naya AppMode import kiya

class UdariPage extends StatefulWidget {
  final String userEmail;
  const UdariPage({super.key, required this.userEmail});

  @override
  State<UdariPage> createState() => _UdariPageState();
}

class _UdariPageState extends State<UdariPage> {
  final List<Map<String, dynamic>> _ledgerList = [];
  List<Map<String, dynamic>> _filteredList = []; // 🔥 Mode aur Search dono ke liye filtered list
  String _searchQuery = "";
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _totalAmountController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  String _selectedType = "lent";

  // Firebase support ke liye email format fix
  String get _safeEmail => widget.userEmail.replaceAll(".", ",");

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDate(DateTime.now());
    _refreshLedger();
    // 🔥 AppMode change listener lagaya taaki switch badalte hi list live refresh ho
    AppMode.currentMode.addListener(_filterLedgerByModeAndSearch);
  }

  @override
  void dispose() {
    // 🔥 Memory leak se bachne ke liye listener remove kiya
    AppMode.currentMode.removeListener(_filterLedgerByModeAndSearch);
    super.dispose();
  }

  // --- DATABASE OPERATIONS (CONNECTED TO FIREBASE) ---

  Future<void> _refreshLedger() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final response = await DatabaseService.fetchUdari(_safeEmail);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response['status'] == true) {
          _ledgerList.clear();
          var decoded = jsonDecode(response['data']);
          if (decoded != null && decoded is Map) {
            decoded.forEach((key, value) {
              var item = Map<String, dynamic>.from(value);
              item['id'] = key;
              _ledgerList.add(item);
            });
          }
        }
        // 🔥 Refresh ke baad dynamic filter apply karein
        _filterLedgerByModeAndSearch();
      });
    }
  }

  // 🔥 NEW FILTER METHOD: Jo Current Mode (Daily/Weekly) aur Search Text dono ko combine filter karta hai
  void _filterLedgerByModeAndSearch() {
    if (!mounted) return;
    String activeMode = AppMode.currentMode.value; // "daily" ya "weekly"
    String query = _searchQuery.toLowerCase().trim();

    setState(() {
      _filteredList = _ledgerList.where((item) {
        // Fallback: Agar pehle se save purane data me appMode nahi hai, toh default 'daily' maano
        String itemMode = item['appMode']?.toString() ?? 'daily';
        bool matchesMode = (itemMode == activeMode);

        // Search match logic
        bool matchesSearch = item['name'].toString().toLowerCase().contains(query);

        return matchesMode && matchesSearch;
      }).toList();
    });
  }

  void _saveEntry() async {
    if (_nameController.text.isEmpty || _totalAmountController.text.isEmpty) return;

    final totalAmount = int.tryParse(_totalAmountController.text) ?? 0;
    final initialAmount = int.tryParse(_paidAmountController.text) ?? 0;

    if (initialAmount > totalAmount) {
      _showErrorSnackBar("Initial Payment (₹$initialAmount) cannot be greater than Total Amount (₹$totalAmount)!");
      return;
    }

    setState(() => _isLoading = true);

    final entry = {
      "name": _nameController.text,
      "phone": _phoneController.text.isEmpty ? "No Number" : _phoneController.text,
      "total": totalAmount,
      "payments": [
        {"amount": initialAmount, "date": _dateController.text, "isDebt": false}
      ],
      "type": _selectedType,
      "date": _dateController.text,
      "appMode": AppMode.currentMode.value, // 🔥 Naya data current active mode ke sath save hoga
    };

    final res = await DatabaseService.addUdari(_safeEmail, entry);

    if (res['status'] == true) {
      _nameController.clear();
      _phoneController.clear();
      _totalAmountController.clear();
      _paidAmountController.clear();
      _dateController.text = _formatDate(DateTime.now());
      if (mounted) Navigator.pop(context);
      _refreshLedger();
    } else {
      setState(() => _isLoading = false);
      _showErrorSnackBar(res['message']);
    }
  }

  Future<void> _deleteEntry(String id) async {
    setState(() => _isLoading = true);
    final res = await DatabaseService.deleteUdari(_safeEmail, id);
    if (res['status'] == true) {
      _refreshLedger();
    } else {
      setState(() => _isLoading = false);
      _showErrorSnackBar(res['message']);
    }
  }

  Future<void> _handlePaymentUpdate(Map<String, dynamic> updateData) async {
    setState(() => _isLoading = true);
    final res = await DatabaseService.updateUdariPayment(_safeEmail, updateData);
    if (res['status'] == true) {
      _refreshLedger();
    } else {
      setState(() => _isLoading = false);
      _showErrorSnackBar(res['message']);
    }
  }

  // --- UI HELPER METHODS ---

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  int _getTotalPaid(dynamic payments) {
    if (payments == null || payments is! List) return 0;
    return payments.fold(0, (sum, item) {
      if (item['isDebt'] == true) return sum;
      return sum + (int.tryParse(item['amount'].toString()) ?? 0);
    });
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  // 🔥 Mode ke hisab se filtered totals calculate honge dashboard cards par
  int get totalLent => _filteredList.where((e) => e['type'] == 'lent').fold(0, (sum, item) => sum + (int.tryParse(item['total'].toString()) ?? 0));
  int get totalBorrowed => _filteredList.where((e) => e['type'] == 'borrowed').fold(0, (sum, item) => sum + (int.tryParse(item['total'].toString()) ?? 0));

  int get pendingToReceive => _filteredList.where((e) => e['type'] == 'lent').fold(0, (sum, item) {
        int total = int.tryParse(item['total'].toString()) ?? 0;
        return sum + (total - _getTotalPaid(item['payments']));
      });

  int get pendingToPay => _filteredList.where((e) => e['type'] == 'borrowed').fold(0, (sum, item) {
        int total = int.tryParse(item['total'].toString()) ?? 0;
        return sum + (total - _getTotalPaid(item['payments']));
      });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = Theme.of(context).scaffoldBackgroundColor;
    
    // 🎨 HIGH-CONTRAST COLORS FOR LIGHT/DARK MODE READABILITY
    final Color textColor = isDark ? Colors.white : Colors.black87; // Pure Black for perfect clarity
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54; // Clear readable grey in light mode
    final Color cardColor = isDark ? Colors.white.withOpacity(0.06) : Colors.white; // Soft cards
    
    // Dynamic Accent text colors for green & red to look sharp in both themes
    final Color greenText = isDark ? Colors.greenAccent : const Color(0xFF007D3A);
    final Color redText = isDark ? Colors.redAccent : const Color(0xFFD32F2F);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text("Digital Ledger Pro", style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [IconButton(onPressed: _refreshLedger, icon: Icon(Icons.refresh, color: isDark ? Colors.cyanAccent : Colors.blueAccent))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(isDark, isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100, textColor, subTextColor),
        backgroundColor: isDark ? Colors.cyanAccent : Colors.blueAccent,
        icon: Icon(Icons.add_task, color: isDark ? Colors.black : Colors.white),
        label: Text("Add Entry", style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 700;

          Widget searchAndSummary = Column(
            children: [
              TextField(
                onChanged: (val) {
                  _searchQuery = val;
                  _filterLedgerByModeAndSearch();
                },
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: "Search name...",
                  hintStyle: TextStyle(color: subTextColor),
                  prefixIcon: Icon(Icons.search, color: isDark ? Colors.cyanAccent : Colors.blueAccent),
                  filled: true,
                  fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              _summaryCard("Money Lent (Out)", "₹$totalLent", "To Receive: ₹$pendingToReceive", greenText, isDark),
              const SizedBox(height: 12),
              _summaryCard("Money Borrowed (In)", "₹$totalBorrowed", "To Pay: ₹$pendingToPay", redText, isDark),
            ],
          );

          Widget listView = _filteredList.isEmpty
              ? Center(child: Text("No transactions found", style: TextStyle(color: subTextColor)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: _filteredList.length,
                  itemBuilder: (context, index) {
                    final item = _filteredList[index];
                    bool isLent = item['type'] == 'lent';
                    Color themeColor = isLent ? greenText : redText;
                    int totalAmount = int.tryParse(item['total']?.toString() ?? '0') ?? 0;
                    int balance = totalAmount - _getTotalPaid(item['payments']);

                    return InkWell(
                      onTap: () => _showHistory(item, isDark),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
                          border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black12),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: themeColor.withOpacity(0.1),
                                child: Icon(isLent ? Icons.call_made : Icons.call_received, color: themeColor, size: 20),
                              ),
                              title: Text(item['name'], style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                              subtitle: Text("📞 ${item['phone']}", style: TextStyle(color: subTextColor, fontSize: 11)),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text("Bal: ₹$balance", style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text("Total: ₹${item['total']}", style: TextStyle(color: subTextColor, fontSize: 11)),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Colors.black12),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _actionBtn(Icons.account_balance_wallet, "Settle", isDark ? Colors.orangeAccent : const Color(0xFFE65100), () => _quickPay(item, isDark)),
                                  _actionBtn(Icons.picture_as_pdf, "PDF", isDark ? Colors.cyanAccent : Colors.blueAccent, () {
                                    DatabaseService.generateUdariPdf(item).then((res) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'])));
                                    });
                                  }),
                                  _actionBtn(Icons.delete_sweep, "Delete", redText, () => _deleteEntry(item['id'])),
                                ],
                              ),
                            ),
                            const SizedBox(height: 5),
                          ],
                        ),
                      ),
                    );
                  },
                );

          if (_isLoading) {
            return Center(child: CircularProgressIndicator(color: isDark ? Colors.cyanAccent : Colors.blueAccent));
          }

          if (isMobile) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  searchAndSummary,
                  const SizedBox(height: 20),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.6, child: listView),
                ],
              ),
            );
          } else {
            return Row(
              children: [
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.all(15), child: searchAndSummary)),
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(15), child: listView)),
              ],
            );
          }
        },
      ),
    );
  }

  // --- MODALS & DIALOGS ---

  void _showHistory(Map<String, dynamic> item, bool isDark) {
    final List payments = item['payments'] ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            Text("${item['name']} - History", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: payments.length,
                itemBuilder: (context, i) {
                  final p = payments[i];
                  bool isDebt = p['isDebt'] ?? false;
                  Color itemColor = isDebt ? (isDark ? Colors.orangeAccent : const Color(0xFFE65100)) : (isDark ? Colors.cyanAccent : Colors.blueAccent);
                  return ListTile(
                    leading: Icon(isDebt ? Icons.add_circle_outline : Icons.history, color: itemColor),
                    title: Text("${isDebt ? '+' : ''}₹${p['amount']}", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                    subtitle: Text("${p['date']} ${isDebt ? '(Added Udari)' : '(Paid)'}", style: TextStyle(color: isDark ? Colors.white38 : Colors.black45)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _quickPay(Map<String, dynamic> item, bool isDark) {
    TextEditingController amountCtrl = TextEditingController();
    int totalAmount = int.tryParse(item['total']?.toString() ?? '0') ?? 0;
    int currentBalance = totalAmount - _getTotalPaid(item['payments']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Update Balance", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(hintText: "Enter amount", hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              int extra = int.tryParse(amountCtrl.text) ?? 0;
              if (extra <= 0) return;
              Map<String, dynamic> updateData = {"id": item['id'], "new_total": (int.tryParse(item['total'].toString()) ?? 0) + extra, "payment": {"amount": extra, "date": _formatDate(DateTime.now()), "isDebt": true}};
              Navigator.pop(context);
              _handlePaymentUpdate(updateData);
            },
            child: Text("Add More Udari", style: TextStyle(color: isDark ? Colors.orangeAccent : const Color(0xFFE65100))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isDark ? Colors.cyanAccent : Colors.blueAccent),
            onPressed: () {
              int paid = int.tryParse(amountCtrl.text) ?? 0;
              if (paid <= 0) return;

              if (paid > currentBalance) {
                Navigator.pop(context);
                _showErrorSnackBar("Paid Amount (₹$paid) cannot be greater than Remaining Balance (₹$currentBalance)!");
                return;
              }

              Map<String, dynamic> updateData = {"id": item['id'], "payment": {"amount": paid, "date": _formatDate(DateTime.now()), "isDebt": false}};
              Navigator.pop(context);
              _handlePaymentUpdate(updateData);
            },
            child: Text("Received/Paid", style: TextStyle(color: isDark ? Colors.black : Colors.white)),
          )
        ],
      ),
    );
  }

  String _formatDateManual(String value) {
    String clean = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length > 8) clean = clean.substring(0, 8);
    
    String formatted = '';
    for (int i = 0; i < clean.length; i++) {
      if (i == 2 || i == 4) formatted += '/';
      formatted += clean[i];
    }
    return formatted;
  }

  void _showForm(bool isDark, Color fieldColor, Color textColor, Color subTextColor) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 25, right: 25, top: 25),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("New Transaction", style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                children: [
                  _typeOption("Lent Money", "lent", isDark ? Colors.greenAccent : const Color(0xFF007D3A), setModalState, isDark),
                  const SizedBox(width: 10),
                  _typeOption("Borrowed", "borrowed", isDark ? Colors.redAccent : const Color(0xFFD32F2F), setModalState, isDark),
                ],
              ),
              const SizedBox(height: 20),
              _formField(_nameController, "Customer Name", Icons.person_outline, fieldColor, textColor, subTextColor),
              _formField(_phoneController, "Phone Number", Icons.phone_android, fieldColor, textColor, subTextColor, isNum: true),
              _formField(_totalAmountController, "Total Amount", Icons.payments_outlined, fieldColor, textColor, subTextColor, isNum: true),
              _formField(_paidAmountController, "Initial Payment", Icons.check_circle_outline, fieldColor, textColor, subTextColor, isNum: true),
              
              // 🔥 DATE FIELD WITH AUTO-SLICE (Manual Formatting)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _dateController,
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    // 1. Current cursor position save karein
                    int oldOffset = _dateController.selection.baseOffset;

                    // 2. Format function call karein
                    String formatted = _formatDateManual(value);

                    // 3. Naya cursor position calculate karein
                    // Agar length badhi hai ya ghatayi hai, toh cursor adjustment
                    int newOffset = formatted.length;
                    if (value.length < formatted.length) {
                      newOffset = oldOffset + 1; // Kuch add hua
                    } else if (value.length > formatted.length) {
                      newOffset = oldOffset - 1; // Kuch delete hua
                    } else {
                      newOffset = oldOffset;
                    }
                    
                    // Cursor ko bounds ke andar rakhein
                    newOffset = newOffset.clamp(0, formatted.length);

                    // 4. Controller update karein
                    _dateController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: newOffset),
                    );
                  },
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    labelText: "Select Date",
                    prefixIcon: Icon(Icons.event_note, color: subTextColor),
                    filled: true,
                    fillColor: fieldColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveEntry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.cyanAccent : Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text("SAVE TO LEDGER", style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    ),
  );
}

  // --- WIDGET COMPONENTS ---

  Widget _typeOption(String label, String type, Color color, StateSetter setModalState, bool isDark) {
    bool isSel = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setModalState(() => _selectedType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: isSel ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: isSel ? color : (isDark ? Colors.white10 : Colors.black12)),
          ),
          child: Center(child: Text(label, style: TextStyle(color: isSel ? color : (isDark ? Colors.white38 : Colors.black45), fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  Widget _formField(TextEditingController ctrl, String hint, IconData icon, Color fillColor, Color textColor, Color subTextColor, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Theme.of(context).brightness == Brightness.dark ? Colors.cyanAccent : Colors.blueAccent, size: 20),
          hintText: hint,
          hintStyle: TextStyle(color: subTextColor),
          filled: true,
          fillColor: fillColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 5), Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))]),
      ),
    );
  }

  Widget _summaryCard(String title, String val, String sub, Color color, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.05) : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: isDark ? color : color.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(val, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
          Divider(color: isDark ? Colors.white10 : Colors.black12, height: 20),
          Text(sub, style: TextStyle(color: isDark ? color.withOpacity(0.8) : color, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}