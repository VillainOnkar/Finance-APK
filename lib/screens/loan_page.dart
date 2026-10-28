import 'dart:convert';
import 'dart:io';
import 'dart:math'; 
import 'package:flutter/material.dart';
import '../database_service.dart';
import '../app_mode.dart'; // Global AppMode import
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';

class LoanPage extends StatefulWidget {
  final String userEmail; 
  const LoanPage({super.key, required this.userEmail});

  @override
  State<LoanPage> createState() => _LoanPageState();
}

class _LoanPageState extends State<LoanPage> {
  final List<Map<String, dynamic>> _allLoans = [];
  List<Map<String, dynamic>> _foundLoans = [];
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  final _srNoController = TextEditingController();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _officeNameController = TextEditingController(); // Ye line add karein
  final _phoneController = TextEditingController();
  final _refPersonController = TextEditingController();
  final _refAddressController = TextEditingController();
  final _refPhoneController = TextEditingController();
  final _ref2PersonController = TextEditingController();
  final _ref2AddressController = TextEditingController();
  final _ref2PhoneController = TextEditingController();
  final _totalAmountController = TextEditingController();
  final _daysController = TextEditingController();
  final _interestController = TextEditingController();
  final _dateController = TextEditingController();
  final _dueDateController = TextEditingController();

  String get _safeEmail => widget.userEmail.replaceAll(".", ",");

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatNativeDate(DateTime.now());
    _dueDateController.text = _formatNativeDate(DateTime.now());
    _refreshLoans();

    // Global switch listener - Jaise hi dashboard badlega, data automatic update hoga
    AppMode.currentMode.addListener(_filterLoansByModeAndSearch);
  }

  @override
  void dispose() {
    AppMode.currentMode.removeListener(_filterLoansByModeAndSearch);
    _searchController.dispose();
    _srNoController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _refPersonController.dispose();
    _refAddressController.dispose();
    _refPhoneController.dispose();
    _ref2PersonController.dispose();
    _ref2AddressController.dispose();
    _ref2PhoneController.dispose();
    _totalAmountController.dispose();
    _daysController.dispose();
    _interestController.dispose();
    _dateController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  // --- DATABASE OPERATIONS (PYTHON INTEGRATION) ---

  Future<void> _refreshLoans() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _runPythonCommand(['fetch_loans', _safeEmail]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _runPythonCommand(List<String> args) async {
    setState(() => _isLoading = true);
    Map<String, dynamic> res = {"status": false, "message": "Unknown action"};

    try {
      String action = args[0];

      if (action == "fetch_loans") {
        res = await DatabaseService.fetchLoans(_safeEmail);
        if (res['status'] == true) {
          setState(() {
            try {
              var decoded = (res['data'] is String) ? jsonDecode(res['data']) : res['data'];
              _allLoans.clear();
              if (decoded != null && decoded is Map) {
                decoded.forEach((key, value) {
                  var loan = Map<String, dynamic>.from(value);
                  loan['id'] = key;
                  _allLoans.add(loan);
                });
              }

              // Date sorting logic
              _allLoans.sort((a, b) {
                try {
                  List<String> partsA = (a['date'] ?? '').toString().split('/');
                  List<String> partsB = (b['date'] ?? '').toString().split('/');
                  
                  DateTime dateA = DateTime(int.parse(partsA[2]), int.parse(partsA[1]), int.parse(partsA[0]));
                  DateTime dateB = DateTime(int.parse(partsB[2]), int.parse(partsB[1]), int.parse(partsB[0]));
                  
                  return dateB.compareTo(dateA);
                } catch (e) {
                  return 0; 
                }
              });

              _filterLoansByModeAndSearch();
            } catch (e) { debugPrint("JSON Parse Error: $e"); }
          });
        }
      } 
      else if (action == "add_loan" || action == "update_loan") {
        String decodedJson = utf8.decode(base64Decode(args[args.length - 1]));
        Map<String, dynamic> loanMap = jsonDecode(decodedJson);
        
        if (action == "add_loan") {
          res = await DatabaseService.addLoan(_safeEmail, loanMap);
        } else {
          res = await DatabaseService.updateLoan(_safeEmail, args[2], loanMap);
        }
      } 
      else if (action == "delete_loan") {
        res = await DatabaseService.deleteLoan(_safeEmail, args[1]);
      }
      else if (action == "update_payment") {
        if (args.length < 3) return;
        String decodedHistory = utf8.decode(base64Decode(args[3]));
        res = await DatabaseService.updateLoanPayment(
          _safeEmail, 
          args[1],  
          jsonDecode(decodedHistory)
        );
      }
      else if (action == "customerreport") {
        String decodedJson = utf8.decode(base64Decode(args[1]));
        res = await DatabaseService.generateCustomerReport(jsonDecode(decodedJson));
      }
      else if (action == "generate_agreement") {
        String decodedJson = utf8.decode(base64Decode(args[1]));
        res = await DatabaseService.generateAgreement(jsonDecode(decodedJson));
      }

      if (res['status'] == true && action != "fetch_loans") {
        _refreshLoans();
        _showSnackBar(res['message'] ?? "Operation Successful!", false);
      } else if (res['status'] == false) {
        _showSnackBar(res['message'] ?? "Error", true);
      }
    } catch (e) {
      _showSnackBar("Execution Error: $e", true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, bool isError) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg), 
        backgroundColor: isError ? Colors.redAccent : Colors.cyan[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatNativeDate(DateTime date) => "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";

  void _calculateDays() {
    if (_dateController.text.isEmpty || _dueDateController.text.isEmpty) return;

    try {
      List<String> startParts = _dateController.text.split('/');
      List<String> endParts = _dueDateController.text.split('/');

      DateTime startDate = DateTime(int.parse(startParts[2]), int.parse(startParts[1]), int.parse(startParts[0]));
      DateTime endDate = DateTime(int.parse(endParts[2]), int.parse(endParts[1]), int.parse(endParts[0]));

      int difference = endDate.difference(startDate).inDays;

      setState(() {
        _daysController.text = difference >= 0 ? difference.toString() : "0";
      });
    } catch (e) {
      debugPrint("Error calculating days: $e");
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _dateController.text = _formatNativeDate(picked);
      });
      _calculateDays(); 
    }
  }

  // 🔥 FILTER LOGIC: Jo mode active hai dashboard par strictly wahi loans dikhenge
  // 🔥 FIXED FILTER LOGIC: Sr No और Name के लिए सटीक खोज
  void _filterLoansByModeAndSearch() {
    if (!mounted) return;
    String activeMode = AppMode.currentMode.value.toLowerCase().trim(); 
    String query = _searchController.text.toLowerCase().trim();

    setState(() {
      _foundLoans = _allLoans.where((loan) {
        String loanMode = (loan["mode"] ?? "daily").toString().toLowerCase().trim();
        bool matchesMode = (loanMode == activeMode);

        final name = (loan["name"] ?? "").toString().toLowerCase();
        final sr = (loan["sr"] ?? loan["srno"] ?? "").toString().toLowerCase().trim();
        
        bool dateMatch = false;
        if (loan['history'] != null && loan['history'] is List) {
          for (var entry in loan['history']) {
            if (entry['date'] != null && entry['date'].toString().toLowerCase().contains(query)) {
              dateMatch = true;
              break; 
            }
          }
        }

        // 🔍 यहाँ सुधार किया गया है:
        // यदि यूजर ने सिर्फ नंबर टाइप किया है (जैसे 14, 15), तो Sr No का मिलान सटीक (Exact match या .contains) होना चाहिए,
        // लेकिन यह बाकी फील्ड्स (जैसे phone या random text) से बिना मतलब मैच होकर कचरा रिकॉर्ड न दिखाए।
        bool matchesSearch = false;
        if (query.isEmpty) {
          matchesSearch = true;
        } else {
          // अगर यूजर ने Sr No से सर्च किया है
          bool srMatch = sr == query || sr.contains(query);
          // अगर यूजर ने नाम से सर्च किया है
          bool nameMatch = name.contains(query);

          // अगर query एक नंबर है, तो प्राथमिकता Sr No को दें ताकि गलत रिकॉर्ड न आएं
          if (RegExp(r'^[0-9]+$').hasMatch(query)) {
            matchesSearch = srMatch; // केवल वही रिकॉर्ड आएगा जिसका Sr No मेल खाता हो
          } else {
            matchesSearch = nameMatch || srMatch || dateMatch;
          }
        }

        return matchesMode && matchesSearch;
      }).toList();
    });
  }

  void _showAddLoanDialog() {
    _clearControllers();
    int randomSr = Random().nextInt(9000) + 1000;
    _srNoController.text = randomSr.toString();
    _showLoanFormDialog(title: "New ${AppMode.currentMode.value} Entry", isEdit: false);
  }

  void _showEditLoanDialog(Map<String, dynamic> loan) {
    _srNoController.text = loan['sr']?.toString() ?? "";
    _nameController.text = loan['name'] ?? "";
    _addressController.text = loan['address'] ?? "";
    _officeNameController.text = loan['officeName'] ?? "";
    _phoneController.text = loan['phone'] ?? "";
    _refPersonController.text = loan['refName'] ?? "";
    _refAddressController.text = loan['refAddress'] ?? "";
    _refPhoneController.text = loan['refPhone'] ?? "";
    _ref2PersonController.text = loan['ref2Name'] ?? "";
    _ref2AddressController.text = loan['ref2Address'] ?? "";
    _ref2PhoneController.text = loan['ref2Phone'] ?? "";
    _totalAmountController.text = loan['originalAmount']?.toString() ?? "";
    _interestController.text = loan['interest']?.toString() ?? "";
    _daysController.text = loan['days']?.toString() ?? "";
    _dateController.text = loan['date'] ?? _formatNativeDate(DateTime.now());
    _dueDateController.text = loan['dueDate'] ?? _formatNativeDate(DateTime.now());

    _showLoanFormDialog(
      title: "Edit Record", 
      isEdit: true, 
      loanId: loan['id'].toString(), 
      history: loan['history'], 
      currentAmount: loan['amount'],
      existingMode: loan['mode'] // Purana mode retain karne ke liye
    );
  }

  String _formatDateManual(String value) {
    var clean = value.replaceAll(RegExp(r'\D'), '');
    if (clean.length > 8) clean = clean.substring(0, 8);
    if (clean.length > 4) {
      return "${clean.substring(0, 2)}/${clean.substring(2, 4)}/${clean.substring(4)}";
    } else if (clean.length > 2) {
      return "${clean.substring(0, 2)}/${clean.substring(2)}";
    }
    return clean;
  }
  
  void _showLoanFormDialog({
  required String title,
  required bool isEdit,
  String? loanId,
  dynamic history,
  dynamic currentAmount,
  String? existingMode,
}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color dialogBg = isDark ? const Color(0xFF121212) : Colors.white;
  final Color textColor = isDark ? Colors.white : Colors.black87;
  final Color fieldColor = isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03);
  final Color dividerColor = isDark ? Colors.white10 : Colors.black12;

  // Date Field helper function
  // Date Field helper function (Updated with Cursor Logic)
Widget _dateField(TextEditingController controller, String label, IconData icon, Color themeColor) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: (value) {
        // 1. Current cursor position save karein
        int oldOffset = controller.selection.baseOffset;
        
        // 2. Format function call karein
        String formatted = _formatDateManual(value);
        
        // 3. New cursor position calculate karein
        int newOffset = formatted.length;
        if (value.length < formatted.length) {
          newOffset = oldOffset + 1;
        } else if (value.length > formatted.length) {
          newOffset = oldOffset - 1;
        } else {
          newOffset = oldOffset;
        }
        newOffset = newOffset.clamp(0, formatted.length);

        // 4. Controller update karein bina jump kiye
        controller.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: newOffset),
        );
        
        if (formatted.length == 10) _calculateDays();
      },
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: "dd/mm/yyyy",
        prefixIcon: Icon(icon, color: themeColor, size: 18),
        suffixIcon: IconButton(
          icon: Icon(Icons.calendar_month, color: themeColor),
          onPressed: () async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2101),
              initialEntryMode: DatePickerEntryMode.calendarOnly,
            );
            if (picked != null) {
              String dateText = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
              controller.value = TextEditingValue(
                text: dateText,
                selection: TextSelection.collapsed(offset: dateText.length),
              );
              _calculateDays();
            }
          },
        ),
        filled: true,
        fillColor: fieldColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    ),
  );
}

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
      ),
      title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        height: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _formField(_srNoController, "Sr No", Icons.tag, keyboardType: TextInputType.number, enabled: true, isDark: isDark),
              
              // Date Fields
              _dateField(_dateController, "Loan Date", Icons.calendar_today, isDark ? Colors.cyanAccent : Colors.cyan[600]!),
              _dateField(_dueDateController, "Due Date", Icons.calendar_month, isDark ? Colors.orangeAccent : Colors.orange[600]!),
              
              _formField(_daysController, "Days", Icons.timer, keyboardType: TextInputType.number, isDark: isDark),
              
              Text("Customer Details", style: TextStyle(color: isDark ? Colors.cyanAccent : Colors.cyan[700], fontWeight: FontWeight.bold)),
              _formField(_nameController, "Customer Name", Icons.person, isDark: isDark),
              _formField(_addressController, "Home Address", Icons.home_rounded, isDark: isDark),
              _formField(_officeNameController, "Office Address", Icons.business, isDark: isDark),
              _formField(_phoneController, "Phone Number", Icons.phone, keyboardType: TextInputType.phone, isDark: isDark),
              
              Divider(color: dividerColor),
              Text("Guarantor 1", style: TextStyle(color: isDark ? Colors.cyanAccent : Colors.cyan[700], fontWeight: FontWeight.bold)),
              _formField(_refPersonController, "Guarantor Name", Icons.person_add, isDark: isDark),
              _formField(_refAddressController, "Guarantor Address", Icons.location_on, isDark: isDark),
              _formField(_refPhoneController, "Guarantor Phone", Icons.phone_android, keyboardType: TextInputType.phone, isDark: isDark),
              
              Divider(color: dividerColor),
              Text("Guarantor 2", style: TextStyle(color: isDark ? Colors.cyanAccent : Colors.cyan[700], fontWeight: FontWeight.bold)),
              _formField(_ref2PersonController, "Guarantor 2 Name", Icons.person_add_alt_1, isDark: isDark),
              _formField(_ref2AddressController, "Guarantor 2 Address", Icons.location_on, isDark: isDark),
              _formField(_ref2PhoneController, "Guarantor 2 Phone", Icons.phone_android, keyboardType: TextInputType.phone, isDark: isDark),
              
              Divider(color: dividerColor),
              Text("Amount Details", style: TextStyle(color: isDark ? Colors.cyanAccent : Colors.cyan[700], fontWeight: FontWeight.bold)),
              _formField(_totalAmountController, "Principal Amount", Icons.currency_rupee, keyboardType: TextInputType.number, isDark: isDark),
              _formField(_interestController, "Interest (%)", Icons.percent, keyboardType: TextInputType.number, isDark: isDark),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isEdit ? Colors.orangeAccent : (isDark ? Colors.cyanAccent : Colors.cyan[600]),
            foregroundColor: Colors.black,
          ),
          onPressed: () async {
            if (_nameController.text.isEmpty || _totalAmountController.text.isEmpty) {
              _showSnackBar("Name and Amount are required!", true);
              return;
            }

            String enteredSrNo = _srNoController.text.trim();
            
            if (!isEdit) {
              bool idExists = _allLoans.any((loan) => (loan['sr'] ?? '').toString().trim() == enteredSrNo);
              if (idExists) { _showSnackBar("Error: Customer ID #$enteredSrNo already exists!", true); return; }
            }

            Map<String, dynamic> loanData = {
              "sr": enteredSrNo,
              "name": _nameController.text,
              "address": _addressController.text,
              "officeName": _officeNameController.text,
              "phone": _phoneController.text,
              "refName": _refPersonController.text,
              "refAddress": _refAddressController.text,
              "refPhone": _refPhoneController.text,
              "ref2Name": _ref2PersonController.text,
              "ref2Address": _ref2AddressController.text,
              "ref2Phone": _ref2PhoneController.text,
              "originalAmount": _totalAmountController.text,
              "interest": _interestController.text,
              "days": _daysController.text,
              "date": _dateController.text,
              "dueDate": _dueDateController.text,
              "mode": existingMode ?? AppMode.currentMode.value.toLowerCase().trim(),
            };

            if (isEdit) {
              if (currentAmount != null) loanData["amount"] = currentAmount.toString();
              if (history != null) loanData["history"] = history;
            } else {
              loanData["amount"] = _totalAmountController.text;
            }

            String loanJson = jsonEncode(loanData);
            String base64Loan = base64Encode(utf8.encode(loanJson));

            Navigator.pop(context);
            setState(() => _isLoading = true);

            if (isEdit && loanId != null) {
              var currentLoan = _allLoans.firstWhere((l) => l['id'].toString() == loanId, orElse: () => {});
              if ((currentLoan['sr'] ?? '').toString().trim() != enteredSrNo) {
                await DatabaseService.deleteLoan(_safeEmail, loanId);
                await _runPythonCommand(['add_loan', _safeEmail, base64Loan]);
              } else {
                await _runPythonCommand(['update_loan', _safeEmail, loanId, base64Loan]);
              }
            } else {
              await _runPythonCommand(['add_loan', _safeEmail, base64Loan]);
            }
          },
          child: Text(isEdit ? "Update" : "Save"),
        ),
      ],
    ),
  );
}

 void _editPayment(int index) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color dialogBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
  final Color textColor = isDark ? Colors.white : Colors.black87;
  final Color borderLineColor = isDark ? Colors.cyanAccent : Colors.cyan[700]!;

  final TextEditingController payController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  dateController.text = _formatNativeDate(DateTime.now());
  var loan = _foundLoans[index];

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        bool isProcessing = false;

        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("Payment: ${loan['name']}", style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: payController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: "Enter Amount",
                  hintStyle: const TextStyle(color: Colors.white24),
                  prefixText: "₹ ",
                  prefixStyle: TextStyle(color: textColor),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderLineColor)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderLineColor, width: 2)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: dateController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: textColor),
                onChanged: (value) {
                  int oldOffset = dateController.selection.baseOffset;
                  String formatted = _formatDateManual(value);
                  int newOffset = formatted.length;
                  
                  if (value.length < formatted.length) {
                    newOffset = oldOffset + 1;
                  } else if (value.length > formatted.length) {
                    newOffset = oldOffset - 1;
                  } else {
                    newOffset = oldOffset;
                  }
                  newOffset = newOffset.clamp(0, formatted.length);

                  dateController.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(offset: newOffset),
                  );
                },
                decoration: InputDecoration(
                  hintText: "DD/MM/YYYY",
                  hintStyle: const TextStyle(color: Colors.white24),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.calendar_today, color: borderLineColor, size: 20),
                    onPressed: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                        initialEntryMode: DatePickerEntryMode.calendarOnly,
                      );
                      if (picked != null) {
                        String dateText = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
                        setDialogState(() {
                          dateController.value = TextEditingValue(
                            text: dateText,
                            selection: TextSelection.collapsed(offset: dateText.length),
                          );
                        });
                      }
                    },
                  ),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderLineColor)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderLineColor, width: 2)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(dialogContext),
              child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.cyanAccent : Colors.cyan[600],
                  foregroundColor: isDark ? Colors.black : Colors.white),
              onPressed: isProcessing ? null : () async {
                double received = double.tryParse(payController.text) ?? 0;
                if (received <= 0) return;

                double current = double.tryParse(loan['remainingBalance']?.toString() ?? loan['amount'].toString()) ?? 0;

                if (received > current) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Error: Amount cannot be greater than balance!"),
                    backgroundColor: Colors.redAccent,
                  ));
                  return;
                }

                setDialogState(() => isProcessing = true);

                List historyList = [];
                if (loan['history'] != null) {
                  historyList = loan['history'] is String ? jsonDecode(loan['history']) : List.from(loan['history']);
                } else if (loan['paymentHistory'] != null) {
                  historyList = loan['paymentHistory'] is String ? jsonDecode(loan['paymentHistory']) : List.from(loan['paymentHistory']);
                }

                // 🔥 Duplicate Date Validation Check
                bool dateExists = historyList.any((item) => item['date'] == dateController.text);
                if (dateExists) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Error: Is date par pehle se hi transaction hai!"),
                    backgroundColor: Colors.orange,
                  ));
                  setDialogState(() => isProcessing = false);
                  return;
                }

                Map<String, dynamic> historyEntry = {
                  'received': received.toStringAsFixed(2),
                  'date': dateController.text,
                };

                // 🔥 Check karne ke liye ki kya naya balance zero ho raha hai (Archiving ke liye)
                double totalPaidSoFar = received;
                for (var item in historyList) {
                  totalPaidSoFar += double.tryParse(item['received']?.toString() ?? '0') ?? 0.0;
                }
                double originalAmt = double.tryParse(loan['originalAmount']?.toString() ?? loan['totalAmount']?.toString() ?? (current + totalPaidSoFar - received).toString()) ?? 0;
                double estimatedNewBalance = originalAmt - totalPaidSoFar;
                if (estimatedNewBalance < 0) estimatedNewBalance = 0;

                try {
                  bool isArchived = false;
                  if (estimatedNewBalance <= 0.01) {
                    List tempHistory = List.from(historyList);
                    tempHistory.add(historyEntry);

                    Map<String, dynamic> archiveData = Map<String, dynamic>.from(loan);
                    archiveData['remainingBalance'] = "0.00";
                    archiveData['amount'] = "0.00";
                    archiveData['history'] = tempHistory;
                    archiveData['paymentHistory'] = tempHistory;
                    archiveData['mode'] = loan['mode'] ?? AppMode.currentMode.value.toLowerCase();

                    var result = await DatabaseService.archiveLoan(_safeEmail, loan['id'].toString(), archiveData);
                    if (result['status'] == true) isArchived = true;
                  } else {
                    // 🔥 Yahan se newAmount hata diya gaya hai taaki backend history sum se calculate kare
                    await DatabaseService.updateLoanPayment(_safeEmail, loan['id'].toString(), historyEntry);
                  }

                  await _refreshLoans();

                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isArchived ? "Loan Settled & Archived!" : "Payment Successful!"),
                      backgroundColor: Colors.green,
                    ));
                  }
                } catch (e) {
                  setDialogState(() => isProcessing = false);
                }
              },
              child: isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Pay Now"),
            ),
          ],
        );
      },
    ),
  );
}

  void _deleteLoan(int index) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    var loan = _foundLoans[index];
    
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        title: Text("Delete Record?", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        content: Text("${loan['name']} ka record delete karein?", style: TextStyle(color: isDark ? Colors.white70 : Colors.black38)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: Text("No", style: TextStyle(color: isDark ? Colors.white38 : Colors.black38))
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Yes, Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    ) ?? false;

    if (confirm && loan['id'] != null) {
      setState(() => _isLoading = true);

      var result = await DatabaseService.deleteLoan(_safeEmail, loan['id'].toString());

      if (result['status'] == true) {
        setState(() {
          _allLoans.removeWhere((item) => item['id'] == loan['id']);
          _foundLoans.removeWhere((item) => item['id'] == loan['id']);
        });
        _showSnackBar("Record Deleted Successfully!", false);
      } else {
        _showSnackBar("Error: ${result['message']}", true);
      }
      setState(() => _isLoading = false);
    }
  }

  void _clearControllers() {
    _srNoController.clear();
    _nameController.clear();
    _addressController.clear();
    _officeNameController.clear();
    _phoneController.clear();
    _refPersonController.clear();
    _refAddressController.clear();
    _refPhoneController.clear();
    _ref2PersonController.clear();
    _ref2AddressController.clear();
    _ref2PhoneController.clear();
    _totalAmountController.clear();
    _interestController.clear();
    _daysController.clear();
    _dateController.text = _formatNativeDate(DateTime.now());
    _dueDateController.text = _formatNativeDate(DateTime.now());
  }

  // 📌 Agreement बटन पर यह डायलॉग खुलेगा जिसमें 3 ऑप्शन्स होंगे
  void _showAgreementOptionsDialog(Map<String, dynamic> loan, dynamic pythonResult) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  
  // पाइथन से मिलने वाले पाथ को सुरक्षित रूप से स्ट्रिंग में बदलना
  String filePath = pythonResult?.toString() ?? ""; 

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        "Agreement Options", 
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. PRINT PREVIEW (HTML to PDF direct conversion & safe execution)
          ListTile(
            leading: const Icon(Icons.print, color: Colors.blueAccent),
            title: const Text("Print Preview"),
            subtitle: const Text("Direct print ya PDF preview dekhein"),
            onTap: () async {
              Navigator.pop(context);
              try {
                if (filePath.isNotEmpty && await File(filePath).exists()) {
                  // HTML फाइल का डेटा रीड करें
                  String htmlContent = await File(filePath).readAsString();

                  // Printing पैकेज का उपयोग करके HTML को लाइव PDF में बदलकर प्रीव्यू दिखाएं
                  await Printing.layoutPdf(
                    onLayout: (PdfPageFormat format) async {
                      return await Printing.convertHtml(
                        format: format,
                        html: htmlContent,
                      );
                    },
                  );
                } else {
                  _showSnackBar("Print file not found!", true);
                }
              } catch (e) {
                // क्रैश होने से बचाने के लिए सुरक्षित मैसेज
                _showSnackBar("Printing Error: इस डिवाइस पर यह फीचर समर्थित नहीं है या फाइल करप्ट है।", true);
              }
            },
          ),
          const Divider(),

          // 2. SHARE (Safe for WhatsApp & Apps)
          ListTile(
            leading: const Icon(Icons.share, color: Colors.green),
            title: const Text("Share Agreement"),
            subtitle: const Text("WhatsApp ya anya apps par bhejein"),
            onTap: () async {
              Navigator.pop(context);
              try {
                if (filePath.isNotEmpty && await File(filePath).exists()) {
                  await Share.shareXFiles(
                    [XFile(filePath)], 
                    text: "Loan Agreement for ${loan['name'] ?? 'Customer'}"
                  );
                } else {
                  _showSnackBar("Share file not found!", true);
                }
              } catch (e) {
                _showSnackBar("Sharing Error: इस डिवाइस पर शेयरिंग उपलब्ध नहीं है।", true);
              }
            },
          ),
          const Divider(),

          // 3. DOWNLOAD / SAVED
          ListTile(
            leading: const Icon(Icons.download, color: Colors.orangeAccent),
            title: const Text("Download / Saved"),
            subtitle: const Text("Downloads folder me saved hai"),
            onTap: () async {
              Navigator.pop(context);
              try {
                if (filePath.isNotEmpty && await File(filePath).exists()) {
                  _showSnackBar("Agreement successfully saved at: $filePath", false);
                } else {
                  _showSnackBar("File not found in storage!", true);
                }
              } catch (e) {
                _showSnackBar("Error accessing file storage.", true);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
        ),
      ],
    ),
  );
}

// ✅ TextInputType fixation included to safeguard layout runtime assignment
Widget _formField(TextEditingController controller, String hint, IconData icon, {TextInputType keyboardType = TextInputType.text, bool enabled = true, required bool isDark}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 12),
        prefixIcon: Icon(icon, color: isDark ? Colors.cyanAccent : Colors.cyan[600], size: 18),
        filled: true, 
        fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    ),
  );
}

  @override
Widget build(BuildContext context) {
  final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
  
  final Color bgColor = Theme.of(context).scaffoldBackgroundColor;
  final Color textColor = isDarkMode ? Colors.white : Colors.black87;
  final Color subTextColor = isDarkMode ? Colors.white38 : Colors.black45;
  final Color cardColor = isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.shade200;
  final Color themeAccent = isDarkMode ? Colors.cyanAccent : Colors.cyan[600]!;

  return Scaffold(
    backgroundColor: bgColor,
    floatingActionButton: FloatingActionButton(
      backgroundColor: themeAccent,
      foregroundColor: isDarkMode ? Colors.black : Colors.white,
      onPressed: _showAddLoanDialog,
      elevation: 4,
      child: const Icon(Icons.add),
    ),
    body: Padding(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Section with Title, Subtitle and Refresh Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text(
                    "${AppMode.currentMode.value} Loans", 
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)
                  ),
                  Text(
                    "Financial Records Dashboard", 
                    style: TextStyle(fontSize: 13, color: subTextColor)
                  ),
                ],
              ),
              IconButton(
                onPressed: _refreshLoans, 
                icon: Icon(Icons.refresh, color: themeAccent)
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // 🚀 EXPORT TO PDF Button placed right under the heading on the left side
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 2,
            ),
            icon: const Icon(Icons.picture_as_pdf, size: 16),
            label: const Text("EXPORT TO PDF", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: () async {
              // 1. Check karein ki list khali toh nahi hai
              if (_foundLoans.isEmpty) {
                _showSnackBar("Export karne ke liye koi record nahi hai!", true);
                return;
              }

              // 2. Processing message dikhayein
              _showSnackBar("PDF generate ho rahi hai...", false);

              try {
                // 3. Current mode ('Daily' ya 'Weekly') yahan pass kiya gaya hai
                String currentMode = AppMode.currentMode.value;
                var result = await DatabaseService.exportLoanList(_safeEmail, mode: currentMode);

                // 4. Result handle karein
                if (result['status'] == true) {
                  _showSnackBar(result['message'], false);
                } else {
                  _showSnackBar(result['message'], true);
                }
              } catch (e) {
                _showSnackBar("Error: ${e.toString()}", true);
              }
            },
          ),
          
          const SizedBox(height: 25),
          
          TextField(
            controller: _searchController,
            onChanged: (val) => _filterLoansByModeAndSearch(),
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: "Search name or SR...",
              hintStyle: TextStyle(color: subTextColor),
              prefixIcon: Icon(Icons.search, color: themeAccent),
              filled: true, 
              fillColor: cardColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15), 
                borderSide: BorderSide.none
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: themeAccent))
                : _foundLoans.isEmpty
                    ? Center(
                        child: Text(
                          "No ${AppMode.currentMode.value} records found", 
                          style: TextStyle(color: subTextColor)
                        )
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _foundLoans.length,
                        itemBuilder: (context, index) {
                          var loan = _foundLoans[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: isDarkMode ? Colors.white10 : Colors.black12
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              onTap: () => _showFullCustomerDetails(loan),
                              leading: CircleAvatar(
                                backgroundColor: themeAccent.withOpacity(0.1),
                                child: Text(
                                  loan['sr']?.toString() ?? "!", 
                                  style: TextStyle(color: themeAccent, fontSize: 12, fontWeight: FontWeight.bold)
                                ),
                              ),
                              title: Text(
                                loan['name'] ?? "Unknown", 
                                style: TextStyle(color: textColor, fontWeight: FontWeight.bold)
                              ),
                              subtitle: Text(
                                "Remaining: ₹${loan['amount']}", 
                                style: TextStyle(color: subTextColor, fontSize: 12)
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, color: subTextColor),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                onSelected: (val) {
                                  if (val == 'pay') _editPayment(index);
                                  if (val == 'edit') _showEditLoanDialog(loan);
                                  if (val == 'del') _deleteLoan(index);
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'pay', child: Text("Add Payment")),
                                  const PopupMenuItem(value: 'edit', child: Text("Edit Details")),
                                  const PopupMenuItem(
                                    value: 'del', 
                                    child: Text("Delete Record", style: TextStyle(color: Colors.redAccent))
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    ),
  );
}

  void _showFullCustomerDetails(Map<String, dynamic> initialLoan) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color bgColor = isDark ? const Color(0xFF0A0A0A) : Theme.of(context).scaffoldBackgroundColor;
  final Color mainTxt = isDark ? Colors.white : Colors.black87;
  final Color subTxt = isDark ? Colors.white38 : Colors.black45;
  final Color cardBg = isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03);
  final Color themeAccent = isDark ? Colors.cyanAccent : Colors.cyan[600]!;
  
  Map<String, dynamic> loan = Map<String, dynamic>.from(initialLoan);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: bgColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (context) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setModalState) {
        double principal = double.tryParse(loan['originalAmount']?.toString() ?? "0") ?? 0;
        double currentBalance = double.tryParse(loan['amount']?.toString() ?? "0") ?? 0;
        double totalPaid = 0.0;
        List historyList = (loan['history'] != null) ? List.from(loan['history']) : [];
        
        // 🔥 DESCENDING ORDER SORTING (Nayi date sabse upar)
        historyList.sort((a, b) {
          try {
            List<String> partsA = (a['date'] ?? '').toString().split('/');
            List<String> partsB = (b['date'] ?? '').toString().split('/');
            DateTime dateA = DateTime(int.parse(partsA[2]), int.parse(partsA[1]), int.parse(partsA[0]));
            DateTime dateB = DateTime(int.parse(partsB[2]), int.parse(partsB[1]), int.parse(partsB[0]));
            return dateB.compareTo(dateA); // b compare to a for Descending
          } catch (e) { return 0; }
        });

        for (var entry in historyList) {
          if (entry != null && entry['received'] != null) {
            double amt = double.tryParse(entry['received'].toString().replaceAll(',', '')) ?? 0.0;
            totalPaid += amt;
          }
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        borderRadius: BorderRadius.circular(10)
                      )
                    )
                  ),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: themeAccent.withOpacity(0.1),
                        child: Icon(Icons.person, color: themeAccent, size: 30)
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loan['name'] ?? "Unknown",
                              style: TextStyle(color: mainTxt, fontSize: 24, fontWeight: FontWeight.bold)
                            ),
                            Text(
                              "Customer ID: #${loan['sr']} (${(loan['mode'] ?? 'daily').toString().toUpperCase()})",
                              style: TextStyle(color: themeAccent, fontSize: 12, fontWeight: FontWeight.w500)
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  _sectionHeader("CONTACT DETAILS", subTxt),
                  _infoTile(Icons.home, "Home Address", loan['address'] ?? "N/A", themeAccent, mainTxt, subTxt),
                  _infoTile(Icons.business, "Office Address", loan['officeName'] ?? "N/A", themeAccent, mainTxt, subTxt),
                  _infoTile(Icons.phone, "Phone", loan['phone'] ?? "N/A", themeAccent, mainTxt, subTxt),
                  _infoTile(Icons.calendar_month, "Reg. Date", loan['date'] ?? "N/A", themeAccent, mainTxt, subTxt),
                  _infoTile(Icons.calendar_month, "Due Date (Kab tak)", loan['dueDate'] ?? "N/A", themeAccent, mainTxt, subTxt),
                  const SizedBox(height: 20),
                  Divider(color: isDark ? Colors.white10 : Colors.black12),
                  const SizedBox(height: 20),
                  _sectionHeader("GUARANTOR 1 DETAILS", subTxt),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.cyanAccent.withOpacity(0.05) : Colors.cyan.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: themeAccent.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        _infoTile(Icons.verified_user, "Name", loan['refName'] ?? "N/A", themeAccent, mainTxt, subTxt),
                        _infoTile(Icons.location_on, "Address", loan['refAddress'] ?? "N/A", themeAccent, mainTxt, subTxt),
                        _infoTile(Icons.phone_android, "Phone", loan['refPhone'] ?? "N/A", themeAccent, mainTxt, subTxt),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  _sectionHeader("GUARANTOR 2 DETAILS", subTxt),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.orangeAccent.withOpacity(0.05) : Colors.orange.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: isDark ? Colors.orangeAccent.withOpacity(0.2) : Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        _infoTile(Icons.person_add_alt_1, "Name", loan['ref2Name'] ?? "N/A", isDark ? Colors.orangeAccent : Colors.orange[700]!, mainTxt, subTxt),
                        _infoTile(Icons.location_on, "Address", loan['ref2Address'] ?? "N/A", isDark ? Colors.orangeAccent : Colors.orange[700]!, mainTxt, subTxt),
                        _infoTile(Icons.phone_android, "Phone", loan['ref2Phone'] ?? "N/A", isDark ? Colors.orangeAccent : Colors.orange[700]!, mainTxt, subTxt),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  _sectionHeader("PAYMENT SUMMARY", subTxt),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(15)),
                    child: Column(children: [
                      _calcRow("Principal Amount", "₹${principal.toStringAsFixed(2)}", isDark: isDark),
                      _calcRow("Interest Rate", "${loan['interest']}%", isDark: isDark),
                      _calcRow("Loan Tenure (Days)", "${loan['days'] ?? '0'} Days", color: themeAccent, isDark: isDark),
                      _calcRow("Total Paid (Collected)", "₹${totalPaid.toStringAsFixed(2)}", color: isDark ? Colors.greenAccent : Colors.green[700], isDark: isDark),
                      Divider(color: isDark ? Colors.white10 : Colors.black12, height: 20),
                      _calcRow("REMAINING BALANCE", "₹${currentBalance.toStringAsFixed(2)}", isBold: true, color: isDark ? Colors.orangeAccent : Colors.orange[700], isDark: isDark),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.receipt_long),
                      label: const Text("View Statement of Account"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: () => _openStatement(loan), 
                    ),
                  ),
                  const SizedBox(height: 25),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                          label: const Text("Report PDF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () async {
                            String jsonString = jsonEncode(loan);
                            String base64Data = base64Encode(utf8.encode(jsonString));
                            await _runPythonCommand(['customerreport', base64Data]);
                            if (mounted) {
                              Navigator.pop(context);
                              _showSnackBar("${AppMode.currentMode.value} Report generated successfully!", false);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
  child: ElevatedButton.icon(
    icon: const Icon(Icons.print, color: Colors.white),
    label: const Text(
      "Agreement", 
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.blueAccent, 
      padding: const EdgeInsets.symmetric(vertical: 12), 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
    ),
    onPressed: () async {
      // 1. लोडिंग शुरू करें
      setState(() => _isLoading = true);
      
      // 2. आपका DatabaseService वाला generateAgreement फंक्शन कॉल करें
      // (यह सीधे Map रिटर्न करता है जिसमें status, message और path होता है)
      Map<String, dynamic> result = await DatabaseService.generateAgreement(loan);
      
      // 3. लोडिंग बंद करें
      setState(() => _isLoading = false);

      if (!mounted) return;

      // 4. चेक करें कि फाइल सफलतापूर्वक बन गई है या नहीं
      if (result['status'] == true) {
        String filePath = result['path']; // यहाँ से आपको सही फाइल पाथ मिल जाएगा
        
        // 5. अब अपना डायलॉग बॉक्स कॉल करें और उसमें filePath पास करें
        _showAgreementOptionsDialog(loan, filePath);
      } else {
        // अगर कोई एरर आई हो तो यूजर को मैसेज दिखाएं
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? "एरर आ गई है!"))
        );
      }
    },
  ),
),
                    ],
                  ),
                  const SizedBox(height: 25),
                  _sectionHeader("RECENT TRANSACTIONS", subTxt),
                  if (historyList.isEmpty)
                    Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text("No payments yet", style: TextStyle(color: subTxt))))
                  else
                    ...historyList.map((h) => _historyTile(
                          h, mainTxt, subTxt, isDark, loanId: loan['id'].toString(),
                          onDeleteSuccess: () async {
                            try {
                              String sEmail = DatabaseService.getSafeEmail(widget.userEmail);
                              var freshData = await DatabaseService.getSingleLoan(sEmail, loan['id'].toString());
                              if (freshData != null) {
                                setModalState(() { loan = freshData; });
                                int idx = _allLoans.indexWhere((l) => l['id'].toString() == loan['id'].toString());
                                if (idx != -1) {
                                  _allLoans[idx] = freshData;
                                  setState(() {
                                    int foundIdx = _foundLoans.indexWhere((l) => l['id'].toString() == loan['id'].toString());
                                    if (foundIdx != -1) _foundLoans[foundIdx] = freshData;
                                  });
                                }
                              }
                            } catch (e) { debugPrint("Error syncing history: $e"); }
                          },
                        )).toList(),
                  const SizedBox(height: 50),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

  Widget _sectionHeader(String title, Color subTxt) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title, 
      style: TextStyle(color: subTxt, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold)
    ),
  );

  Widget _infoTile(IconData icon, String label, String value, Color accent, Color mainTxt, Color subTxt) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: accent, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Text(label, style: TextStyle(color: subTxt, fontSize: 10)),
              Text(value, style: TextStyle(color: mainTxt, fontSize: 14)),
            ]
          ),
        ),
      ],
    ),
  );

  Widget _calcRow(String label, String val, {bool isBold = false, Color? color, required bool isDark}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 14)),
        Text(
          val, 
          style: TextStyle(
            color: color ?? (isDark ? Colors.white : Colors.black87), 
            fontSize: 15, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal
          )
        ),
      ],
    ),
  );
  

  Widget _historyTile(Map h, Color mainTxt, Color subTxt, bool isDark, {String loanId = "", VoidCallback? onDeleteSuccess}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.01) : Colors.black.withOpacity(0.02), 
        borderRadius: BorderRadius.circular(12)
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: isDark ? Colors.greenAccent : Colors.green[700], size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(h['date'] ?? "", style: TextStyle(color: subTxt, fontSize: 12)),
          ),
          Text("₹${h['received']}", style: TextStyle(color: mainTxt, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
            onPressed: () {
              if (loanId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Error: Loan ID missing!"), backgroundColor: Colors.red),
                );
                return;
              }

              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return AlertDialog(
                    backgroundColor: isDark ? const Color(0xFF161616) : Colors.white,
                    title: Text("Delete Transaction?", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                    content: Text(
                      "Kya aap sach me is history entry ko delete karna chahte hain? Isse remaining amount revert ho jayegi.",
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
                    ),
                    actions: [
                      TextButton(
                        child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                      TextButton(
                        child: const Text("Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop(); // Dialog close
                          
                          try {
                            String sEmail = DatabaseService.getSafeEmail(widget.userEmail);
                            
                            final result = await DatabaseService.deleteTransaction(
                              sEmail, 
                              loanId, 
                              (h['date'] ?? "").toString(), 
                              h['received']
                            );

                            if (mounted) {
                              if (result['status'] == true) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Transaction deleted successfully!"), backgroundColor: Colors.green),
                                );
                                
                                // 🔥 Sheet ke dynamic re-render function ko trigger karein
                                if (onDeleteSuccess != null) {
                                  onDeleteSuccess();
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Error: ${result['message']}"), backgroundColor: Colors.red),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _openStatement(Map<String, dynamic> loan) {
  // 1. Data Sort aur Prepare karein
  List history = (loan['history'] ?? []).toList();
  history.sort((a, b) {
    try {
      List<String> pA = a['date'].split('/');
      List<String> pB = b['date'].split('/');
      return DateTime(int.parse(pA[2]), int.parse(pA[1]), int.parse(pA[0]))
          .compareTo(DateTime(int.parse(pB[2]), int.parse(pB[1]), int.parse(pB[0])));
    } catch (e) { return 0; }
  });

  List<Map<String, dynamic>> statementData = [];
  double runningTotal = 0.0;
  for (var item in history) {
    double received = double.tryParse(item['received'].toString()) ?? 0.0;
    runningTotal += received;
    statementData.add({
      'date': item['date'],
      'received': received,
      'total': runningTotal
    });
  }

  // 2. UI Display
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Account Statement", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            
            // Header Row with Sr. No.
            Row(children: const [
              Expanded(flex: 1, child: Text("Sr.", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text("Date", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text("Received", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text("Total", style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: statementData.length,
                itemBuilder: (context, index) {
                  var item = statementData[index];
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      // Sr. No. logic
                      Expanded(flex: 1, child: Text("${index + 1}.")),
                      Expanded(flex: 2, child: Text(item['date'])),
                      Expanded(flex: 2, child: Text("₹${(item['received'] as double).toStringAsFixed(0)}")),
                      Expanded(flex: 2, child: Text("₹${(item['total'] as double).toStringAsFixed(0)}", 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal))),
                    ]),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
}
