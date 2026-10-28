import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../database_service.dart';
import '../app_mode.dart'; // Global AppMode switch import

class ReportPage extends StatefulWidget {
  final String userEmail;
  const ReportPage({super.key, required this.userEmail});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  
  String _selectedFilter = 'Day';
  String _searchQuery = '';
  DateTime _focusedDate = DateTime.now(); 
  
  List<dynamic> _allTransactions = []; 
  List<dynamic> _filteredTransactions = []; 
  
  bool _isLoading = false;
  double totalGiven = 0.0;     
  double totalCollected = 0.0; 

  @override
  void initState() {
    super.initState();
    _fetchReportData();
    AppMode.currentMode.addListener(_onModeChangedRefresh);
    
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _filterReportByMode();
      });
    });
  }

  @override
  void dispose() {
    AppMode.currentMode.removeListener(_onModeChangedRefresh);
    _searchController.dispose();
    super.dispose();
  }

  void _onModeChangedRefresh() {
    _fetchReportData();
  }

  int get _currentTransactionCount {
    return _filteredTransactions.length;
  }

  // Strict Date Range, Mode, Search Query & 'All' Filter Logic
  void _filterReportByMode() {
    if (!mounted) return;
    String activeMode = AppMode.currentMode.value.toLowerCase().trim();

    setState(() {
      _filteredTransactions = _allTransactions.where((item) {
        // 1. Check Global App Mode (Daily / Weekly)
        String itemMode = item['appMode']?.toString().toLowerCase().trim() ?? 
                          item['mode']?.toString().toLowerCase().trim() ?? 
                          'daily';
        if (itemMode != activeMode) return false;

        // 2. Date Filtration Logic (Skipped if 'All' is selected)
        if (_selectedFilter != 'All') {
          if (item['date'] == null) return false;
          
          try {
            DateTime itemDate;
            String dateRaw = item['date'].toString().trim();
            if (dateRaw.contains('-')) {
              itemDate = DateTime.parse(dateRaw); 
            } else if (dateRaw.contains('/')) {
              itemDate = DateFormat('dd/MM/yyyy').parse(dateRaw);
            } else {
              return false; 
            }

            DateTime itemZeroTime = DateTime(itemDate.year, itemDate.month, itemDate.day);
            DateTime focusedZeroTime = DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day);

            bool dateMatched = false;
            if (_selectedFilter == 'Week') {
              DateTime startOfRange = focusedZeroTime.subtract(const Duration(days: 6));
              dateMatched = itemZeroTime.isAfter(startOfRange.subtract(const Duration(seconds: 1))) && 
                            itemZeroTime.isBefore(focusedZeroTime.add(const Duration(days: 1)));
            } else if (_selectedFilter == 'Day') {
              dateMatched = itemZeroTime.isAtSameMomentAs(focusedZeroTime);
            } else if (_selectedFilter == 'Month') {
              dateMatched = itemDate.month == _focusedDate.month && itemDate.year == _focusedDate.year;
            } else if (_selectedFilter == 'Year') {
              dateMatched = itemDate.year == _focusedDate.year;
            }

            if (!dateMatched) return false;

          } catch (e) {
            debugPrint("Date Parsing Skip Error: $e for value ${item['date']}");
            return false;
          }
        }

        // 3. Search Query Filter (Name, Amount, Phone)
        if (_searchQuery.isNotEmpty) {
          String name = item['name']?.toString().toLowerCase() ?? '';
          String amount = item['amount']?.toString().toLowerCase() ?? '';
          String phone = item['phone']?.toString().toLowerCase() ?? '';
          String query = _searchQuery.toLowerCase().trim();
          
          if (!name.contains(query) && !amount.contains(query) && !phone.contains(query)) {
            return false;
          }
        }

        return true;
      }).toList();

      totalGiven = _filteredTransactions
          .where((item) => item['type'] != 'collection')
          .fold(0.0, (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0.0));

      totalCollected = _filteredTransactions
          .where((item) => item['type'] == 'collection')
          .fold(0.0, (sum, item) => sum + (double.tryParse(item['amount'].toString()) ?? 0.0));
    });
  }

  Future<void> _fetchReportData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      String apiTypeParam = 'month'; 
      if (_selectedFilter == 'Year') {
        apiTypeParam = 'year'; 
      } else if (_selectedFilter == 'All') {
        apiTypeParam = 'all'; // Fixed to fetch all-time records correctly
      }

      String dateStr = "${_focusedDate.year}-${_focusedDate.month.toString().padLeft(2, '0')}-${_focusedDate.day.toString().padLeft(2, '0')}";
      final currentGlobalMode = AppMode.currentMode.value; 

      final result = await DatabaseService.getLoanReport(
        widget.userEmail, 
        apiTypeParam, 
        dateStr,
        mode: currentGlobalMode, 
      );

      if (!mounted) return;

      if (result['status'] == true) {
        var data = jsonDecode(result['data']);
        _allTransactions = data['transactions'] ?? [];
        _filterReportByMode();
      } else {
        _clearData();
        debugPrint("Report Service Error: ${result['message']}");
      }
    } catch (e) {
      debugPrint("Flutter Report Error: $e");
      _clearData();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generatePDF() async {
    if (_filteredTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No transactions to generate PDF"), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      Map<String, dynamic> reportData = {
        'transactions': _filteredTransactions,
        'filter': "${_selectedFilter} (${AppMode.currentMode.value.toUpperCase()})",
        'date_text': _selectedFilter == 'All' ? 'All Time Records' : _getReadableDate(),
        'total_given': totalGiven,
        'total_collected': totalCollected,
      };

      final result = await DatabaseService.generateFullReportPdf(reportData);

      if (mounted) {
        if (result['status'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("PDF Generated: ${result['message']}"), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${result['message']}"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Flutter Error during PDF generation: $e");
    }
  }

  void _clearData() {
    setState(() {
      _allTransactions = [];
      _filteredTransactions = [];
      totalGiven = 0.0;
      totalCollected = 0.0;
    });
  }

  String _getReadableDate() {
    List<String> months = [
      'January', 'February', 'March', 'April', 'May', 'June', 
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    try {
      if (_selectedFilter == 'All') return 'All Time Records';
      if (_selectedFilter == 'Month') return "${months[_focusedDate.month - 1]} ${_focusedDate.year}";
      if (_selectedFilter == 'Year') return "${_focusedDate.year}";
      
      if (_selectedFilter == 'Week') {
        DateTime startOfWeek = _focusedDate.subtract(const Duration(days: 6));
        return "${startOfWeek.day} ${_focusedDate.month == startOfWeek.month ? '' : months[startOfWeek.month - 1].substring(0, 3)} - ${_focusedDate.day} ${months[_focusedDate.month - 1].substring(0, 3)}";
      }
      return "${_focusedDate.day} ${months[_focusedDate.month - 1].substring(0, 3)}";
    } catch (e) {
      return DateFormat('dd/MM/yyyy').format(_focusedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? const Color(0xFF0D0D0D) : Colors.grey.shade100;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color cardColor = isDark ? const Color(0xFF161616) : Colors.white;

    return ValueListenableBuilder<String>(
      valueListenable: AppMode.currentMode,
      builder: (context, currentMode, child) {
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: bgColor,
          body: LayoutBuilder(
            builder: (context, constraints) {
              bool isMobile = constraints.maxWidth < 800;

              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.5,
                    colors: [
                      isDark ? Colors.orangeAccent.withOpacity(0.05) : Colors.orangeAccent.withOpacity(0.1), 
                      Colors.transparent
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    _buildNav(textColor, isDark, currentMode),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: isMobile 
                        ? ListView( 
                            children: [
                              _buildSummaryCard(textColor, cardColor, isDark),
                              const SizedBox(height: 20),
                              _buildSearchBar(textColor, cardColor, isDark),
                              const SizedBox(height: 20),
                              _buildSectionHeader(textColor, currentMode),
                              const SizedBox(height: 15),
                              _buildActivityLogList(textColor, cardColor, isDark),
                              const SizedBox(height: 20),
                            ],
                          )
                        : Row( 
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 65, 
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSearchBar(textColor, cardColor, isDark),
                                    const SizedBox(height: 15),
                                    _buildSectionHeader(textColor, currentMode),
                                    const SizedBox(height: 15),
                                    Expanded(child: _buildActivityLogList(textColor, cardColor, isDark)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(flex: 35, child: _buildSummaryCard(textColor, cardColor, isDark)),
                            ],
                          ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(Color textColor, Color cardColor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: textColor, fontSize: 13),
        decoration: InputDecoration(
          hintText: "Search by name, amount, or phone...",
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
          prefixIcon: const Icon(Icons.search, color: Colors.orangeAccent, size: 20),
          suffixIcon: _searchQuery.isNotEmpty 
              ? IconButton(
                  icon: Icon(Icons.clear, size: 18, color: isDark ? Colors.white38 : Colors.black38),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(Color textColor, String currentMode) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Activity Log (${currentMode.toUpperCase()})", 
          style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
          ),
          child: Text(
            "$_selectedFilter: $_currentTransactionCount found",
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildNav(Color textColor, bool isDark, String currentMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      child: Wrap( 
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 15,
        runSpacing: 15,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("ANALYTICS", style: TextStyle(color: textColor, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(width: 10),
              Text("(${currentMode.toUpperCase()})", style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 15),
              IconButton(
                tooltip: "Download PDF Report",
                icon: const Icon(Icons.picture_as_pdf, color: Colors.orangeAccent, size: 20),
                onPressed: _generatePDF, 
              ),
            ],
          ),
          _buildFilterChips(isDark), 
        ],
      ),
    );
  }

  Widget _buildActivityLogList(Color textColor, Color cardColor, bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
    
    if (_filteredTransactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text("No records found", style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true, 
      physics: const ClampingScrollPhysics(),
      itemCount: _filteredTransactions.length,
      itemBuilder: (context, i) => _buildTile(_filteredTransactions[i], textColor, cardColor, isDark),
    );
  }

  Widget _buildTile(var item, Color textColor, Color cardColor, bool isDark) {
    bool isCollection = item['type'] == 'collection';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardColor, 
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isCollection ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            radius: 18,
            child: Icon(
              isCollection ? Icons.arrow_downward : Icons.arrow_upward, 
              color: isCollection ? Colors.greenAccent : Colors.redAccent, 
              size: 16
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] ?? "Unknown", style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                Text(isCollection ? "Received" : "Loan Given", 
                    style: TextStyle(color: isCollection ? Colors.green : Colors.red, fontSize: 10)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("Rs. ${item['amount']}", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              Text(item['date'] ?? "", style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(Color textColor, Color cardColor, bool isDark) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.4 : 0.05), blurRadius: 15)],
            border: isDark ? null : Border.all(color: Colors.black.withOpacity(0.05)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(child: _metricSmall("COLLECTED", totalCollected, Colors.green, isDark)),
                  Container(
                    width: 1, 
                    height: 30, 
                    color: isDark ? Colors.white10 : Colors.black12
                  ),
                  Expanded(child: _metricSmall("GIVEN", totalGiven, Colors.red, isDark)),
                ],
              ),
              const Divider(height: 30),
              Text(_getReadableDate(), style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(height: 15),
        _calendarBtn(),
      ],
    );
  }

  Widget _metricSmall(String label, double val, Color col, bool isDark) {
    return Column(children: [
      Text(label, style: TextStyle(color: isDark ? Colors.white24 : Colors.black45, fontSize: 8)),
      Text("Rs. ${val.toStringAsFixed(0)}", style: TextStyle(color: col, fontSize: 15, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _calendarBtn() {
    return InkWell(
      onTap: () async {
        final DateTime? p = await showDatePicker(
          context: context, 
          initialDate: _focusedDate, 
          firstDate: DateTime(2020), 
          lastDate: DateTime(2030)
        );
        if (p != null) { 
          setState(() => _focusedDate = p); 
          _fetchReportData(); 
        }
      },
      child: Container(
        height: 50,
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(15)),
        child: const Center(child: Icon(Icons.calendar_month, color: Colors.black)),
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['All', 'Day', 'Week', 'Month', 'Year'].map((f) => GestureDetector(
        onTap: () { 
          setState(() {
            _selectedFilter = f;
          }); 
          _fetchReportData(); 
        },
        child: Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _selectedFilter == f ? Colors.orangeAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: _selectedFilter != f ? Border.all(color: isDark ? Colors.white10 : Colors.black12) : null,
          ),
          child: Text(f, style: TextStyle(color: _selectedFilter == f ? Colors.black : (isDark ? Colors.white38 : Colors.black45), fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      )).toList(),
    );
  }
}