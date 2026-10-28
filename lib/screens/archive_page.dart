import 'package:flutter/material.dart';
import 'dart:convert';
import '../database_service.dart'; // ✅ DatabaseService connection ke liye
import '../app_mode.dart'; // 🔥 Global AppMode switch import kiya

class ArchivePage extends StatefulWidget {
  final String userEmail;
  const ArchivePage({super.key, required this.userEmail});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<dynamic> _allArchived = [];         // Backend se aaya poora data store karne ke liye
  List<dynamic> _filteredArchived = [];    // 🔥 Mode aur Search ke baad filter kiya huva live data
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 1. Initial data fetch hoga
    _fetchArchivedData();

    // 2. 🔥 Main switch badalte hi bina reload kiye automatic data filter karega
    AppMode.currentMode.addListener(_filterArchiveByMode);
  }

  @override
  void dispose() {
    // Memory leaks se bachne ke liye controller aur listener remove kiya
    AppMode.currentMode.removeListener(_filterArchiveByMode);
    _searchController.dispose();
    super.dispose();
  }

  // Firebase support ke liye email fix
  String get _safeEmail => widget.userEmail.replaceAll(".", ",");

  // 🔥 Map aur List dono formats ko handle karne ke liye safe dynamic total calculation
  double _calculateTotal(dynamic history) {
    if (history == null) return 0.0;
    
    List hList = [];
    if (history is List) {
      hList = history;
    } else if (history is Map) {
      hList = history.values.toList();
    }

    return hList.fold(0.0, (sum, item) {
      if (item is Map) {
        double val = double.tryParse(item['received']?.toString() ?? '0') ?? 0.0;
        return sum + val;
      }
      return sum;
    });
  }

  // 🔥 Multi-key support (appMode, mode, loanMode) ke saath foolproof split logic
  void _filterArchiveByMode() {
    if (!mounted) return;
    String activeMode = AppMode.currentMode.value.toLowerCase().trim(); // "daily" ya "weekly"
    String searchQuery = _searchController.text.toLowerCase().trim();

    setState(() {
      _filteredArchived = _allArchived.where((user) {
        // Safe multi-key check lagaya hai jo mix data ko pehchanta hai
        String recordMode = user['appMode']?.toString() ?? 
                           user['mode']?.toString() ?? 
                           user['loanMode']?.toString() ?? 
                           'daily';
        
        bool matchesMode = (recordMode.toLowerCase().trim() == activeMode);

        // Search query filter
        bool matchesSearch = true;
        if (searchQuery.isNotEmpty) {
          String userName = (user['name'] ?? "").toString().toLowerCase();
          matchesSearch = userName.contains(searchQuery);
        }

        // Dono conditions match hone par hi item list me rahega
        return matchesMode && matchesSearch;
      }).toList();
    });
  }

  // --- DATABASE OPERATIONS (CONNECTED TO FIREBASE) ---
  Future<void> _fetchArchivedData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Seedha DatabaseService se data mangwaya
      final result = await DatabaseService.fetchArchives(_safeEmail);
      
      if (result['status'] == true) {
        final Map<String, dynamic> decodedData = jsonDecode(result['data']);
        List<dynamic> tempList = [];
        
        decodedData.forEach((key, value) {
          if (value is Map) {
            var val = Map<String, dynamic>.from(value);
            val['id'] = key; // Firebase key ko ID banaya
            tempList.add(val);
          }
        });

        _allArchived = tempList;
        
        // Naya data aane ke baad active split mode apply kiya
        _filterArchiveByMode();
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- DELETE WITH CONFIRMATION (CONNECTED TO FIREBASE) ---
  Future<void> _deleteArchive(String id) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Confirm Delete?", style: TextStyle(color: Colors.white, fontSize: 18)),
        content: const Text("Kya aap waqai is record ko hamesha ke liye delete karna chahte hain?", style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Nahi", style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Haa, Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        final res = await DatabaseService.deleteArchive(_safeEmail, id);

        if (res['status'] == true) {
          _fetchArchivedData(); // List refresh karein
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Record deleted successfully")));
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete Fail: ${res['message']}")));
          }
        }
      } catch (e) {
        debugPrint("Delete failed error: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // --- PDF GENERATION (CONNECTED TO FIREBASE DATA) ---
  Future<void> _generatePDF(Map<String, dynamic> data) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generating PDF...")));
      
      // DatabaseService ka generate function use kiya
      final res = await DatabaseService.generateLoanSettlementPdf(data);
      
      if (mounted) {
        if (res['status'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'])));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF Error: ${res['message']}")));
        }
      }
    } catch (e) {
      debugPrint("PDF Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ValueListenableBuilder use kiya taaki dashboard switch par tap karte hi AppBar title aur List instant change ho sakein
    return ValueListenableBuilder<String>(
      valueListenable: AppMode.currentMode,
      builder: (context, currentMode, child) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              "Archive (${currentMode.toUpperCase()})", 
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black, 
                fontWeight: FontWeight.bold
              )
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
          ),
          body: Column(
            children: [

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text("EXPORT TO PDF", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        // 1. Check karein ki filtered archive list khali toh nahi hai
                        if (_filteredArchived.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Export karne ke liye koi archived record nahi hai!"),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        // 2. Processing / Loading message dikhayein
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Archive PDF generate ho rahi hai..."),
                          ),
                        );

                        try {
                          // 3. Current mode ('Daily' ya 'Weekly') fetch karke pass karein
                          String currentModeValue = AppMode.currentMode.value;
                          var result = await DatabaseService.exportArchivePdf(_safeEmail, mode: currentModeValue);

                          // 4. Result ke hisab se SnackBar show karein
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result['message']),
                                backgroundColor: result['status'] == true ? Colors.green : Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Error: ${e.toString()}"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    // Jab user search field me kuch type karega tab bhi live filter run hoga
                    _filterArchiveByMode();
                  },
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: "Search archived customer...",
                    hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
                    prefixIcon: const Icon(Icons.search, color: Colors.greenAccent),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
              ),

              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                  : _filteredArchived.isEmpty 
                    ? Center(child: Text("No archives found in ${currentMode.toLowerCase()} mode", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26)))
                    : _buildArchiveList(isDark), 
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArchiveList(bool isDark) {
    // UI me '_filteredArchived' list run karega jo split logic par structured hai
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _filteredArchived.length,
      itemBuilder: (context, index) {
        var user = _filteredArchived[index];
        double totalCollected = _calculateTotal(user['history']);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03), 
            borderRadius: BorderRadius.circular(15), 
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12)
          ),
          child: ListTile(
            // 🔥 FIX: user ko explicitly Map<String, dynamic> me cast karke bheja taaki type error na aaye
            onTap: () => _showArchiveDetails(Map<String, dynamic>.from(user), isDark),
            leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.done_all, color: Colors.white, size: 18)),
            title: Text(
              user['name'] ?? "Unknown", 
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)
            ),
            subtitle: Text("Settled: ₹${totalCollected.toStringAsFixed(0)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
              onPressed: () => _deleteArchive(user['id']),
            ),
          ),
        );
      },
    );
  }

  // 🔥 PROFILE OPEN MODAL MODIFIED FOR LIGHT/DARK MODE SUPPORT
  void _showArchiveDetails(Map<String, dynamic> data, bool isDark) {
    double totalRec = _calculateTotal(data['history']);
    
    // History entries extraction handle map or list safely
    List historyEntries = [];
    if (data['history'] != null) {
      if (data['history'] is List) {
        historyEntries = List.from(data['history']);
      } else if (data['history'] is Map) {
        historyEntries = (data['history'] as Map).values.toList();
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 🔥 Dynamic Background Color based on Mode
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("FULL REPORT", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.orangeAccent),
                    onPressed: () => _generatePDF(data),
                  ),
                ],
              ),
              Divider(color: isDark ? Colors.white10 : Colors.black12),
              
              // --- CUSTOMER INFORMATION ---
              _sectionTitle("CUSTOMER INFORMATION", isDark),
              _infoTile(Icons.person, "Name", data['name'], isDark),
              _infoTile(Icons.phone, "Phone", data['phone'], isDark),
              _infoTile(Icons.home, "Home Address", data['address'], isDark),
              _infoTile(Icons.business, "Office Address", data['officeName'], isDark),
              _infoTile(Icons.calendar_today, "Loan Date", data['date'], isDark), 
              _infoTile(Icons.calendar_month, "Due Date", data['dueDate'], isDark), 
              _infoTile(Icons.timer, "Loan Tenure", "${data['days'] ?? '0'} Days", isDark),

              const SizedBox(height: 20),
              _sectionTitle("GUARANTOR 1 INFORMATION", isDark),
              _infoTile(Icons.verified_user, "Name", data['refName'], isDark),
              _infoTile(Icons.phone_android, "Phone", data['refPhone'], isDark),
              _infoTile(Icons.location_on, "Address", data['refAddress'], isDark),

              const SizedBox(height: 20),
              _sectionTitle("GUARANTOR 2 INFORMATION", isDark),
              _infoTile(Icons.verified_user, "Name", data['ref2Name'], isDark),
              _infoTile(Icons.phone_android, "Phone", data['ref2Phone'], isDark),
              _infoTile(Icons.location_on, "Address", data['ref2Address'], isDark),

              const SizedBox(height: 20),
              _sectionTitle("FINANCIAL SUMMARY", isDark),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statBox("Principal", "₹${data['originalAmount'] ?? '0'}", isDark),
                  _statBox("Total Paid", "₹${totalRec.toStringAsFixed(0)}", isDark),
                  _statBox("Rate", "${data['interest'] ?? '0'}%", isDark),
                ],
              ),
              const SizedBox(height: 30),
              _sectionTitle("TRANSACTION LOGS", isDark),
              if (historyEntries.isEmpty)
                Text("No transactions found", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26))
              else
                ...historyEntries.reversed.map((h) => h is Map ? _historyRow(h, isDark) : const SizedBox.shrink()),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- Theme Protected UI Widgets ---

  Widget _sectionTitle(String t, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _infoTile(IconData i, String l, String? v, bool isDark) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Icon(i, size: 16, color: Colors.greenAccent),
      const SizedBox(width: 10),
      Text("$l: ", style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13)),
      Expanded(child: Text(v ?? "N/A", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _statBox(String l, String v, bool isDark) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    decoration: BoxDecoration(
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04), 
      borderRadius: BorderRadius.circular(10)
    ),
    child: Column(children: [
      Text(l, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 10)),
      Text(v, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _historyRow(Map h, bool isDark) => Container(
    margin: const EdgeInsets.only(bottom: 5),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02), 
      borderRadius: BorderRadius.circular(10)
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(h['date'] ?? "N/A", style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 12)),
            Text("Received Payment", style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 10)),
          ],
        ),
        Text("₹${h['received']}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}