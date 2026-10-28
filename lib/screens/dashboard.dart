import 'dart:ui';
import 'dart:io';
import 'dart:math' as math;
import 'dart:async'; 
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'loan_page.dart';
import 'udari_page.dart';
import 'report_page.dart';
import 'archive_page.dart'; 
import 'settings_page.dart';
import '../app_mode.dart'; 
import '../database_service.dart';

void main() => runApp(const MyFinancialApp());

class MyFinancialApp extends StatefulWidget {
  const MyFinancialApp({super.key});

  @override
  State<MyFinancialApp> createState() => _MyFinancialAppState();
}

class _MyFinancialAppState extends State<MyFinancialApp> {
  bool _isDark = true; 

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        fontFamily: 'Inter',
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0C10),
        fontFamily: 'Inter',
      ),
      routes: {
        '/': (context) => const Center(child: Text("Login Page")), 
      },
      home: MainNavigationBase(
        userEmail: "onkar@example.com",
        isDarkMode: _isDark,
        onThemeToggle: (val) {
          setState(() {
            _isDark = val;
          });
        },
      ), 
    );
  }
}

class MainNavigationBase extends StatefulWidget {
  final String userEmail;
  final bool isDarkMode;
  final Function(bool) onThemeToggle;

  const MainNavigationBase({
    super.key, 
    required this.userEmail, 
    required this.isDarkMode, 
    required this.onThemeToggle
  });

  @override
  State<MainNavigationBase> createState() => _MainNavigationBaseState();
}

class _MainNavigationBaseState extends State<MainNavigationBase> {
  int _selectedIndex = 0;
  late String currentUserEmail;

  @override
  void initState() {
    super.initState();
    currentUserEmail = widget.userEmail;
  }

  final List<String> _navItems = ["Dashboard", "Loan", "Udari", "Reports", "Archive", "Settings"];

  Widget _getBodyContent(String mode) {
    switch (_selectedIndex) {
      case 0:
        return DashboardContent(key: ValueKey("dashboard_$mode"), userEmail: widget.userEmail);
      case 1:
        return LoanPage(key: ValueKey("loan_$mode"), userEmail: currentUserEmail);
      case 2:
        return UdariPage(key: ValueKey("udari_$mode"), userEmail: currentUserEmail);
      case 3:
        return ReportPage(key: ValueKey("report_$mode"), userEmail: currentUserEmail);
      case 4:
        return ArchivePage(key: ValueKey("archive_$mode"), userEmail: currentUserEmail);
      case 5:
        return SettingsPage(
          key: ValueKey("settings_$mode"),
          userEmail: currentUserEmail,
          isDarkMode: widget.isDarkMode, 
          onThemeChanged: widget.onThemeToggle, 
        );
      default:
        return DashboardContent(key: ValueKey("dashboard_$mode"), userEmail: widget.userEmail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black87;
    
    return ValueListenableBuilder<String>(
      valueListenable: AppMode.currentMode,
      builder: (context, currentMode, child) {
        return Scaffold(
          body: Stack(
            children: [
              Positioned(top: -150, left: -100, child: _buildOrb(600, widget.isDarkMode ? Colors.blueAccent.withOpacity(0.12) : Colors.blue.withOpacity(0.08))),
              Positioned(bottom: -150, right: -100, child: _buildOrb(500, widget.isDarkMode ? Colors.deepPurpleAccent.withOpacity(0.12) : Colors.purple.withOpacity(0.06))),
              
              SafeArea(
                child: Column(
                  children: [
                    _buildTopMenu(textColor, currentMode),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(15, 5, 15, 15), 
                        decoration: BoxDecoration(
                          color: widget.isDarkMode ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: widget.isDarkMode ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                          boxShadow: widget.isDarkMode ? [] : [
                            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))
                          ]
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                            child: _getBodyContent(currentMode),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildTopMenu(Color textColor, String mode) {
    bool isWeekly = mode.toLowerCase().trim() == "weekly";
    
    Color activeBadgeColor = widget.isDarkMode ? Colors.orangeAccent : Colors.orange[800]!;
    Color inactiveBadgeColor = widget.isDarkMode ? Colors.greenAccent : Colors.green[800]!;
    Color containerBg = isWeekly ? activeBadgeColor.withOpacity(0.15) : inactiveBadgeColor.withOpacity(0.15);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: widget.isDarkMode ? [Colors.cyanAccent, Colors.blueAccent] : [Colors.indigo, Colors.blue]
                    ).createShader(bounds),
                    child: const Icon(Icons.account_balance_wallet_rounded, size: 28, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "FINANCE",
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: containerBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isWeekly ? activeBadgeColor.withOpacity(0.4) : inactiveBadgeColor.withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isWeekly ? "WEEKLY" : "DAILY",
                      style: TextStyle(
                        color: isWeekly ? activeBadgeColor : inactiveBadgeColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: isWeekly,
                        activeColor: activeBadgeColor,
                        inactiveThumbColor: inactiveBadgeColor,
                        activeTrackColor: activeBadgeColor.withOpacity(0.3),
                        inactiveTrackColor: inactiveBadgeColor.withOpacity(0.2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (value) => AppMode.toggleMode(value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: _navItems.asMap().entries.map((entry) {
                bool isSelected = _selectedIndex == entry.key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIndex = entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? (widget.isDarkMode ? Colors.white.withOpacity(0.1) : Colors.indigo.withOpacity(0.1)) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border(
                        bottom: BorderSide(
                          color: isSelected ? (widget.isDarkMode ? Colors.cyanAccent : Colors.indigo) : Colors.transparent, 
                          width: 2.5
                        )
                      ),
                    ),
                    child: Center(
                      child: Text(
                        entry.value, 
                        style: TextStyle(
                          color: isSelected ? (widget.isDarkMode ? Colors.cyanAccent : Colors.indigo[800]) : (widget.isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(double size, Color color) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 130, sigmaY: 130), child: Container()),
    );
  }
}

class LiveClockWidget extends StatefulWidget {
  final bool isDark;
  const LiveClockWidget({super.key, required this.isDark});

  @override
  State<LiveClockWidget> createState() => _LiveClockWidgetState();
}

class _LiveClockWidgetState extends State<LiveClockWidget> {
  late Timer _timer;
  String _currentTime = "";
  String _currentDate = "";
  String _currentDay = "";

  @override
  void initState() {
    super.initState();
    _updateDateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDateTime();
    });
  }

  void _updateDateTime() {
    final now = DateTime.now();
    if (mounted) {
      setState(() {
        _currentTime = "${now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour).toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}";
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        _currentDay = days[now.weekday % 7];
        _currentDate = "${now.day} ${months[now.month - 1]}, ${now.year}";
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.isDark 
              ? [Colors.blueGrey.withOpacity(0.2), Colors.cyan.withOpacity(0.1)] 
              : [Colors.indigo.withOpacity(0.08), Colors.blue.withOpacity(0.03)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark ? Colors.cyanAccent.withOpacity(0.3) : Colors.indigo.withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded, size: 14, color: widget.isDark ? Colors.cyanAccent : Colors.indigo),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentTime,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: widget.isDark ? Colors.cyanAccent : Colors.indigo[900]),
              ),
              const SizedBox(height: 1),
              Text(
                "$_currentDay, $_currentDate",
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: widget.isDark ? Colors.white70 : Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DashboardContent extends StatefulWidget {
  final String userEmail;
  const DashboardContent({super.key, required this.userEmail});

  @override
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchData(String mode) async {
    try {
      final result = await DatabaseService.fetchDashboardStats(widget.userEmail, mode: mode.toLowerCase().trim());
      return result;
    } catch (e) {
      debugPrint("Dashboard Fetch Error: $e");
      return {
        "displayName": "Onkar",
        "stats": ["0", "0", "0", "0", "0", "0"],
        "loanMix": {"0-25K": "0", "25K-50K": "0", "50K-1L": "0", "1L+": "0"},
        "recent": [],
        "settled": [],
        "alerts": []
      };
    }
  }

  double _parseVal(String val) {
    try {
      String clean = val.replaceAll(',', '').trim();
      return double.parse(clean);
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<String>(
      valueListenable: AppMode.currentMode,
      builder: (context, currentMode, child) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _fetchData(currentMode),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: isDark ? Colors.cyanAccent : Colors.indigo));
            }

            final data = snapshot.data ?? {
              "displayName": "Onkar",
              "stats": ["0", "0", "0", "0", "0", "0"],
              "loanMix": {"0-25K": "0", "25K-50K": "0", "50K-1L": "0", "1L+": "0"},
              "recent": [],
              "settled": [],
              "alerts": []
            };
            
            final String displayName = data['displayName']?.toString() ?? "Onkar";
            final List<String> stats = List<String>.from(data['stats']);
            final Map<String, dynamic> loanMix = Map<String, dynamic>.from(data['loanMix'] ?? {});
            final List recentItems = data['recent'] ?? [];
            final List settledItems = data['settled'] ?? [];
            final List alertItems = data['alerts'] ?? [];

            double totalOutstanding = _parseVal(stats[3]);
            double totalCollection = _parseVal(stats[4]);

            return LayoutBuilder(
              builder: (context, constraints) {
                bool isDesktop = constraints.maxWidth > 900;

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Wrap(
                            runSpacing: 10,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isDark ? Colors.cyanAccent.withOpacity(0.15) : Colors.indigo.withOpacity(0.1),
                                    child: Text(
                                      displayName.isNotEmpty ? displayName[0].toUpperCase() : "O",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.cyanAccent : Colors.indigo,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            "Hello, $displayName 👋",
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: isDark ? Colors.white : Colors.black87,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: currentMode.toLowerCase().trim() == "weekly" 
                                                  ? Colors.orange.withOpacity(0.2) 
                                                  : Colors.green.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: currentMode.toLowerCase().trim() == "weekly" 
                                                    ? Colors.orange 
                                                    : Colors.green,
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              "${currentMode.toUpperCase()} MODE",
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: currentMode.toLowerCase().trim() == "weekly" 
                                                    ? (isDark ? Colors.orangeAccent : Colors.orange[800]) 
                                                    : (isDark ? Colors.greenAccent : Colors.green[800]),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Financial analytics overview",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              LiveClockWidget(isDark: isDark),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 15),

                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: isDesktop ? 6 : 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: isDesktop ? 1.15 : 1.5, 
                        children: [
                          _topMetricCard("Total Customers", stats[0], Icons.people_alt_rounded, isDark ? const Color(0xFF18283B) : const Color(0xFFEFF6FF), isDark ? Colors.blueAccent : const Color(0xFF1D4ED8), isDark),
                          _topMetricCard("Active Loans", stats[1], Icons.bolt_rounded, isDark ? const Color(0xFF332014) : const Color(0xFFFFF7ED), isDark ? Colors.orangeAccent : const Color(0xFFC2410C), isDark),
                          _topMetricCard("Settled Loans", stats[2], Icons.check_circle_rounded, isDark ? const Color(0xFF142B1E) : const Color(0xFFF0FDF4), isDark ? Colors.greenAccent : const Color(0xFF15803D), isDark),
                          _topMetricCard("Total Outstanding", "₹${stats[3]}", Icons.account_balance_wallet_rounded, isDark ? const Color(0xFF261A3B) : const Color(0xFFF3E8FF), isDark ? Colors.purpleAccent : const Color(0xFF7E22CE), isDark),
                          _topMetricCard("Total Collection", "₹${stats[4]}", Icons.savings_rounded, isDark ? const Color(0xFF132F24) : const Color(0xFFECFDF5), isDark ? Colors.tealAccent : const Color(0xFF047857), isDark),
                          _topMetricCard("Pending Amount", "₹${stats[5]}", Icons.warning_rounded, isDark ? const Color(0xFF361822) : const Color(0xFFFFF1F2), isDark ? Colors.pinkAccent : const Color(0xFFBE123C), isDark),
                        ],
                      ),

                      const SizedBox(height: 20),

                      isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildDisbursedVsCollectionChart(totalOutstanding, totalCollection, isDark)),
                            const SizedBox(width: 15),
                            Expanded(child: _buildLoanSizeMixChartFromBackend(loanMix, isDark)),
                          ],
                        )
                      : Column(
                          children: [
                            _buildDisbursedVsCollectionChart(totalOutstanding, totalCollection, isDark),
                            const SizedBox(height: 15),
                            _buildLoanSizeMixChartFromBackend(loanMix, isDark),
                          ],
                        ),

                      const SizedBox(height: 20),

                      isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildRecentLoansTable(recentItems, isDark)),
                            const SizedBox(width: 15),
                            Expanded(child: _buildListSection("Recently Settled", settledItems, Icons.inventory_2_rounded, isDark ? Colors.orangeAccent : Colors.orange[800]!, isDark)),
                            const SizedBox(width: 15),
                            Expanded(child: _buildAlertsListSection("Loan Expiry & Alerts", alertItems, Icons.notifications_active_rounded, isDark ? Colors.redAccent : Colors.red[700]!, isDark)),
                          ],
                        )
                      : Column(
                          children: [
                            _buildRecentLoansTable(recentItems, isDark),
                            const SizedBox(height: 15),
                            _buildListSection("Recently Settled", settledItems, Icons.inventory_2_rounded, isDark ? Colors.orangeAccent : Colors.orange[800]!, isDark),
                            const SizedBox(height: 15),
                            _buildAlertsListSection("Loan Expiry & Alerts", alertItems, Icons.notifications_active_rounded, isDark ? Colors.redAccent : Colors.red[700]!, isDark),
                          ],
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              }
            );
          },
        );
      },
    );
  }

  Widget _buildDisbursedVsCollectionChart(double totalDisbursed, double totalCollected, bool isDark) {
    double disbursedVal = totalDisbursed > 0 ? totalDisbursed : 50000;
    double collectedVal = totalCollected > 0 ? totalCollected : 30000;
    double totalSum = disbursedVal + collectedVal;
    
    double collectedPercent = (collectedVal / totalSum) * 100;
    double disbursedPercent = (disbursedVal / totalSum) * 100;

    final List<ChartSegmentData> segments = [
      ChartSegmentData(title: "Total Disbursed", value: disbursedVal, color: const Color(0xFF3B82F6)),
      ChartSegmentData(title: "Total Collected", value: collectedVal, color: const Color(0xFF10B981)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13151D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Disbursed vs Collected %", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              Icon(Icons.pie_chart_rounded, color: isDark ? Colors.cyanAccent : Colors.indigo, size: 18),
            ],
          ),
          const SizedBox(height: 15),
          Center(
            child: SizedBox(
              height: 160,
              width: 160,
              child: CustomPaint(
                painter: DonutChartPainter(segments: segments, total: totalSum),
                child: const Center(child: Text("💰", style: TextStyle(fontSize: 32))),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendItem("Disbursed", const Color(0xFF3B82F6), "₹${disbursedVal.toStringAsFixed(0)} (${disbursedPercent.toStringAsFixed(1)}%)", isDark),
              _legendItem("Collected", const Color(0xFF10B981), "₹${collectedVal.toStringAsFixed(0)} (${collectedPercent.toStringAsFixed(1)}%)", isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoanSizeMixChartFromBackend(Map<String, dynamic> loanMix, bool isDark) {
    double bin1 = double.tryParse(loanMix['0-25K']?.toString() ?? '0') ?? 0;
    double bin2 = double.tryParse(loanMix['25K-50K']?.toString() ?? '0') ?? 0;
    double bin3 = double.tryParse(loanMix['50K-1L']?.toString() ?? '0') ?? 0;
    double bin4 = double.tryParse(loanMix['1L+']?.toString() ?? '0') ?? 0;

    double totalMix = bin1 + bin2 + bin3 + bin4;
    if (totalMix == 0) totalMix = 1.0;

    double p1 = (bin1 / totalMix) * 100;
    double p2 = (bin2 / totalMix) * 100;
    double p3 = (bin3 / totalMix) * 100;
    double p4 = (bin4 / totalMix) * 100;

    List<MapEntry<String, double>> categories = [
      MapEntry("₹0–25K", bin1),
      MapEntry("₹25–50K", bin2),
      MapEntry("₹50K–1L", bin3),
      MapEntry("₹1L+", bin4),
    ];
    
    categories.sort((a, b) => b.value.compareTo(a.value));
    String highestCategory = categories.first.key;
    double highestValue = categories.first.value;
    double highestPercent = (highestValue / totalMix) * 100;

    final List<ChartSegmentData> mixSegments = [
      ChartSegmentData(title: "₹0–25K", value: bin1 > 0 ? bin1 : 0.001, color: const Color(0xFF38BDF8)),
      ChartSegmentData(title: "₹25–50K", value: bin2 > 0 ? bin2 : 0.001, color: const Color(0xFFF59E0B)),
      ChartSegmentData(title: "₹50K–1L", value: bin3 > 0 ? bin3 : 0.001, color: const Color(0xFF8B5CF6)),
      ChartSegmentData(title: "₹1L+", value: bin4 > 0 ? bin4 : 0.001, color: const Color(0xFFEC4899)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13151D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Loan Size Mix %", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              Icon(Icons.donut_large_rounded, color: isDark ? Colors.cyanAccent : Colors.indigo, size: 18),
            ],
          ),
          const SizedBox(height: 15),
          Center(
            child: SizedBox(
              height: 160,
              width: 160,
              child: CustomPaint(
                painter: DonutChartPainter(segments: mixSegments, total: totalMix),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        totalMix > 1 ? "${highestPercent.toStringAsFixed(1)}%" : "0.0%", 
                        style: TextStyle(fontSize: 16, color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w900)
                      ),
                      const SizedBox(height: 2),
                      Text(highestCategory, style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendItem("₹0–25K", const Color(0xFF38BDF8), "${p1.toStringAsFixed(1)}%", isDark),
              _legendItem("₹25–50K", const Color(0xFFF59E0B), "${p2.toStringAsFixed(1)}%", isDark),
              _legendItem("₹50K–1L", const Color(0xFF8B5CF6), "${p3.toStringAsFixed(1)}%", isDark),
              _legendItem("₹1L+", const Color(0xFFEC4899), "${p4.toStringAsFixed(1)}%", isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String title, Color color, String subtext, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w600)),
            Text(subtext, style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _topMetricCard(String title, String value, IconData icon, Color cardBgColor, Color accentColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.3), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.25 : 0.05), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6), 
                decoration: BoxDecoration(color: accentColor.withOpacity(0.25), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: accentColor, size: 16),
              ),
              Container(width: 5, height: 5, decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildRecentLoansTable(List items, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13151D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Recent Loans", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              Text("View All", style: TextStyle(fontSize: 11, color: isDark ? Colors.cyanAccent : Colors.indigo, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Center(child: Text("No recent loans found", style: TextStyle(color: Colors.grey, fontSize: 12))),
            ),
          ...items.map((item) {
            final Map<String, dynamic> data = Map<String, dynamic>.from(item);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.02) : Colors.grey.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 14, backgroundColor: Colors.blueAccent.withOpacity(0.2), child: Icon(Icons.person, color: isDark ? Colors.cyanAccent : Colors.indigo, size: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['name']?.toString() ?? "Customer", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                        Text("Original: ₹${data['originalAmount'] ?? data['displayAmount']}", style: TextStyle(fontSize: 9, color: isDark ? Colors.white54 : Colors.black54)),
                      ],
                    ),
                  ),
                  Text("₹${data['displayAmount']}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: isDark ? Colors.greenAccent : Colors.green[700])),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildListSection(String title, List items, IconData icon, Color color, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13151D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Center(child: Text("No records found", style: TextStyle(color: Colors.grey, fontSize: 12))),
            ),
          ...items.map((item) {
            final Map<String, dynamic> data = Map<String, dynamic>.from(item);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.02) : Colors.grey.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 14, backgroundColor: color.withOpacity(0.2), child: Icon(icon, color: color, size: 14)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(data['name']?.toString() ?? "", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87), overflow: TextOverflow.ellipsis)),
                  Text("₹${data['displayAmount']}", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAlertsListSection(String title, List items, IconData icon, Color color, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13151D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Center(child: Text("No active alerts", style: TextStyle(color: Colors.grey, fontSize: 12))),
            ),
          ...items.map((item) {
            final Map<String, dynamic> data = Map<String, dynamic>.from(item);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? color.withOpacity(0.1) : color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 14, backgroundColor: color.withOpacity(0.2), child: Icon(icon, color: color, size: 14)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['name']?.toString() ?? "Alert Item", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                        Text(data['message']?.toString() ?? "Loan expiring soon", style: TextStyle(fontSize: 10, color: isDark ? Colors.redAccent.withOpacity(0.9) : Colors.red[800], fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Text("₹${data['amount'] ?? '0'}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class ChartSegmentData {
  final String title;
  final double value;
  final Color color;
  ChartSegmentData({required this.title, required this.value, required this.color});
}

class DonutChartPainter extends CustomPainter {
  final List<ChartSegmentData> segments;
  final double total;

  DonutChartPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const strokeWidth = 30.0;
    
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    double startAngle = -math.pi / 2;
    double safeTotal = total > 0 ? total : 1.0;

    for (var seg in segments) {
      double sweepAngle = (seg.value / safeTotal) * 2 * math.pi;
      paint.color = seg.color;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - (strokeWidth / 2)),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}