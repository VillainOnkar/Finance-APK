import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

class DatabaseService {
  // --- CONFIGURATION ---
  static const String API_KEY = "AIzaSyCOFv4QYpceC5zBkh2b-pl_R-r7I23PSr8";
  static const String BASE_URL = "https://financework-66cc2-default-rtdb.asia-southeast1.firebasedatabase.app/";

  // Firebase Auth Endpoints
  static const String AUTH_SIGNUP = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$API_KEY";
  static const String AUTH_SIGNIN = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$API_KEY";
  static const String AUTH_VERIFY_EMAIL = "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$API_KEY";
  static const String AUTH_LOOKUP = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$API_KEY";
  static const String AUTH_RESET_PASSWORD = "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$API_KEY";

  // Helper: Email ko Firebase-safe banana (Python wala get_safe_email)
  static String getSafeEmail(String email) => email.replaceAll('.', ',');

  // ======================1. REGISTER USER FUNCTION (Logic same as Python)==================
  static Future<Map<String, dynamic>> registerUserInDb(
      String email, String username, String password, String fullName, String phone) async {
    
    final client = http.Client(); 
    try {
      final uName = username.trim().toLowerCase();
      final cleanUrl = BASE_URL.replaceAll(RegExp(r'/$'), ''); 

      // --- 1. Check if Username exists ---
      final usersRes = await client.get(Uri.parse("$cleanUrl/users.json"));
      if (usersRes.statusCode == 200 && usersRes.body != 'null') {
        Map<String, dynamic> users = json.decode(usersRes.body);
        for (var val in users.values) {
          if (val is Map && val['username'] == uName) {
            return {"status": false, "message": "Username pehle se maujood hai!"};
          }
        }
      }

      // --- 2. Firebase Auth Signup ---
      final authPayload = {
        "email": email,
        "password": password,
        "returnSecureToken": true
      };
      final authRes = await client.post(Uri.parse(AUTH_SIGNUP), body: json.encode(authPayload));
      final authData = json.decode(authRes.body);

      if (authData.containsKey('error')) {
        return {"status": false, "message": authData["error"]["message"]};
      }

      String idToken = authData["idToken"];

      // --- 3. Save to Database PEHLE ---
      final sEmail = getSafeEmail(email);
      final userPayload = {
        "email": email,
        "username": uName,
        "password": password,
        "full_name": fullName,
        "phone": phone,
        "is_verified": false
      };

      final dbRes = await client.put(
        Uri.parse("$cleanUrl/users/$sEmail.json"),
        body: json.encode(userPayload),
      );

      if (dbRes.statusCode != 200) {
        return {"status": false, "message": "Database Error: Data save nahi ho paya."};
      }

      // --- 4. Verification Link bhejein ---
      final verifyRes = await client.post(
        Uri.parse(AUTH_VERIFY_EMAIL),
        body: json.encode({"requestType": "VERIFY_EMAIL", "idToken": idToken}),
      );

      if (verifyRes.statusCode == 200) {
        return {"status": true, "message": "Registration Successful! Email check karein aur link par click karein."};
      } else {
        return {"status": false, "message": "Account ban gaya par link send nahi hua. Login karke dobara try karein."};
      }
    } catch (e) {
      return {"status": false, "message": "Error: ${e.toString()}"};
    } finally {
      client.close();
    }
  }

  //============= 2. LOGIN USER FUNCTION (Logic same as Python)===========
  static Future<Map<String, dynamic>> loginUser(String identifier, String password) async {
    try {
      String email = identifier.trim();
      final cleanUrl = BASE_URL.replaceAll(RegExp(r'/$'), '');

      // --- 1. Agar identifier Username hai to Email dhundein ---
      if (!identifier.contains("@")) {
        final usersRes = await http.get(Uri.parse("$cleanUrl/users.json"));
        String? foundEmail;
        
        if (usersRes.statusCode == 200 && usersRes.body != 'null') {
          Map<String, dynamic> users = json.decode(usersRes.body);
          for (var val in users.values) {
            if (val is Map && val['username'] == identifier.trim().toLowerCase()) {
              foundEmail = val['email'];
              break;
            }
          }
        }

        if (foundEmail == null) {
          return {"status": false, "message": "Username nahi mila!"};
        }
        email = foundEmail;
      }

      // --- 2. Firebase Auth Signin ---
      final loginRes = await http.post(
        Uri.parse(AUTH_SIGNIN),
        body: json.encode({
          "email": email,
          "password": password,
          "returnSecureToken": true,
        }),
      );
      final loginData = json.decode(loginRes.body);

      if (loginData.containsKey('error')) {
        return {"status": false, "message": "Email ya Password galat hai!"};
      }

      // ---======================= 3. Check Verification --==================-
      String token = loginData["idToken"];
      final lookupRes = await http.post(
        Uri.parse(AUTH_LOOKUP),
        body: json.encode({"idToken": token}),
      );
      final lookupData = json.decode(lookupRes.body);

      if (lookupData.containsKey('users') && (lookupData['users'] as List).isNotEmpty) {
        bool firebaseVerified = lookupData['users'][0]['emailVerified'] ?? false;

        if (!firebaseVerified) {
          return {"status": false, "message": "Pehle apna email verify karein!"};
        }

        // --- 4. Database status update ---
        final sEmail = getSafeEmail(email);
        await http.patch(
          Uri.parse("$cleanUrl/users/$sEmail.json"),
          body: json.encode({"is_verified": true}),
        );
        return {"status": true, "email": email};
      } else {
        return {"status": false, "message": "User data lookup failed."};
      }
    } catch (e) {
      return {"status": false, "message": "Login Error: ${e.toString()}"};
    }
  }
  //================================== 3. RESET PASSWORD FUNCTION=====================
  static Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      final payload = {
        "requestType": "PASSWORD_RESET",
        "email": email
      };
      final res = await http.post(Uri.parse(AUTH_RESET_PASSWORD), body: json.encode(payload));
      final data = json.decode(res.body);
      
      if (data.containsKey('error')) {
        return {"status": false, "message": data["error"]["message"]};
      }
      
      return {"status": true, "message": "Password reset email sent successfully!"};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // ==========================4. DELETE FIREBASE AUTH USER (Helper Function)================
  static Future<bool> deleteFirebaseAuthUser(String email) async {
    try {
      final safeEmail = getSafeEmail(email);
      final userRes = await http.get(Uri.parse("$BASE_URL/users/$safeEmail.json"));
      final userData = json.decode(userRes.body);

      String? uid;
      if (userData != null) {
        if (userData.containsKey('localId')) {
          uid = userData["localId"];
        } else if (userData.containsKey('uid')) {
          uid = userData["uid"];
        } else if (userData.containsKey('id')) {
          uid = userData["id"];
        }
      }

      // Agar UID mil jata hai
      if (uid != null) {
        const deleteUrl = "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$API_KEY";
        final payload = {"localId": uid};
        await http.post(Uri.parse(deleteUrl), body: json.encode(payload));
        return true;
      }

      // Agar localId nahi mila, toh sign in karke token se delete karein
      final signinPayload = {
        "email": email, 
        "password": userData["password"], 
        "returnSecureToken": true
      };
      final signinRes = await http.post(Uri.parse(AUTH_SIGNIN), body: json.encode(signinPayload));
      
      if (signinRes.statusCode == 200) {
        final idToken = json.decode(signinRes.body)["idToken"];
        const deleteUrl = "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$API_KEY";
        final deletePayload = {"idToken": idToken};
        await http.post(Uri.parse(deleteUrl), body: json.encode(deletePayload));
        return true;
      }

      return false;
    } catch (e) {
      print("Auth deletion warning/error: $e");
      return false;
    }
  }

  // ==========================5. DELETE USER ACCOUNT (Logic: Auth + DB Data delete)========================
  static Future<Map<String, dynamic>> deleteUserAccount(String email, String password) async {
    try {
      final safeEmail = getSafeEmail(email);

      // 1. Fetch user data
      final userRes = await http.get(Uri.parse("$BASE_URL/users/$safeEmail.json"));
      final userData = json.decode(userRes.body);

      if (userData != null) {
        // 2. Password verification
        if (userData["password"] == password) {
          
          // 3. Auth se delete karein
          await deleteFirebaseAuthUser(email);
          
          // 4. Realtime Database se saara data delete karein
          await http.delete(Uri.parse("$BASE_URL/users/$safeEmail.json"));
          await http.delete(Uri.parse("$BASE_URL/loans/$safeEmail.json"));
          await http.delete(Uri.parse("$BASE_URL/archive/$safeEmail.json"));
          final deleteRes = await http.delete(Uri.parse("$BASE_URL/udari/$safeEmail.json"));
          
          if (deleteRes.statusCode == 200) {
            return {"status": true, "message": "RESULT:SUCCESS: Account and all associated data permanently deleted."};
          } else {
            return {"status": false, "message": "RESULT:ERROR: Auth deleted, but failed to delete data from Realtime Database."};
          }
        } else {
          return {"status": false, "message": "RESULT:ERROR: Incorrect password! Verification failed."};
        }
      } else {
        return {"status": false, "message": "RESULT:ERROR: User email not found in our records."};
      }
    } catch (e) {
      return {"status": false, "message": "RESULT:ERROR: ${e.toString()}"};
    }
  }

  // ======================6. FETCH USER PROFILE========================================
  static Future<Map<String, dynamic>> fetchUserProfile(String email) async {
    try {
      final safeEmail = getSafeEmail(email);
      final url = "$BASE_URL/users/$safeEmail.json";
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null) {
          return {
            "status": true,
            "RESULT": "SUCCESS",
            // Yahan check karein: Agar Firebase mein 'name' save hai toh 'name' likhein
            "name": data["name"] ?? data["full_name"] ?? "Unknown", 
            "phone": data["phone"] ?? data["mobile"] ?? "Not Set"
          };
        }
      }
      return {"status": false, "message": "User not found"};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // ===================================7. FETCH DASHBOARD STATS======================
  static Future<Map<String, dynamic>> fetchDashboardStats(String email, {String mode = "daily"}) async {
  try {
    final safeEmail = getSafeEmail(email).trim();
    final cleanUrl = BASE_URL.replaceAll(RegExp(r'/$'), '');
    final targetMode = mode.toLowerCase().trim();

    // --- 0. Fetch User Profile Name ---
    String displayName = "User";
    final urlUser = "$cleanUrl/users/$safeEmail.json";
    final respUser = await http.get(Uri.parse(urlUser));

    if (respUser.statusCode == 200 && respUser.body != 'null') {
      final userData = json.decode(respUser.body);
      if (userData is Map) {
        displayName = userData['full_name']?.toString() ?? 
                      userData['name']?.toString() ?? 
                      "User";
      }
    }

    int activeLoansCount = 0;
    int settledLoansCount = 0;
    double totalLoanGiven = 0.0;
    double totalArchiveGiven = 0.0;
    double actualReceivedFromHistory = 0.0;

    // Loan Size Mix Counters (Combined for Active + Archive)
    int mix0_25K = 0;
    int mix25_50K = 0;
    int mix50_1L = 0;
    int mix1LPlus = 0;

    List<Map<String, String>> recentActivity = [];
    List<Map<String, String>> settledActivity = [];
    List<Map<String, String>> alertsList = [];

    // --- 1. Active Loans & History ---
    final urlActive = "$cleanUrl/loans/$safeEmail.json";
    final respActive = await http.get(Uri.parse(urlActive));

    if (respActive.statusCode == 200 && respActive.body != 'null') {
      final data = json.decode(respActive.body);
      if (data is Map<String, dynamic>) {
        data.forEach((uid, target) {
          if (target is Map) {
            String rawMode = target['appMode']?.toString() ?? 
                             target['mode']?.toString() ?? 
                             target['loanMode']?.toString() ?? 
                             "daily";
            
            String loanMode = rawMode.toLowerCase().trim();

            if (loanMode == targetMode) {
              activeLoansCount++;

              double amt = double.tryParse(target['originalAmount']?.toString() ?? '0') ?? 0.0;
              totalLoanGiven += amt;

              // Loan Size Categorization for Active Loans
              if (amt <= 25000) {
                mix0_25K++;
              } else if (amt <= 50000) {
                mix25_50K++;
              } else if (amt <= 100000) {
                mix50_1L++;
              } else {
                mix1LPlus++;
              }

              // --- Loan Expiry & Overdue Alert Calculation ---
              String? rawDate = target['dueDate']?.toString() ?? 
                                target['endDate']?.toString() ?? 
                                target['expiryDate']?.toString();
              
              if (rawDate != null && rawDate.isNotEmpty) {
                DateTime? expiryDate;
                
                if (rawDate.contains('/')) {
                  try {
                    List<String> parts = rawDate.split('/');
                    if (parts.length == 3) {
                      int day = int.parse(parts[0]);
                      int month = int.parse(parts[1]);
                      int year = int.parse(parts[2]);
                      expiryDate = DateTime(year, month, day);
                    }
                  } catch (_) {
                    expiryDate = null;
                  }
                } else {
                  expiryDate = DateTime.tryParse(rawDate);
                }

                if (expiryDate != null) {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  final targetDate = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
                  
                  final differenceDays = targetDate.difference(today).inDays;

                  if (differenceDays <= 5 && differenceDays >= 0) {
                    String message = differenceDays == 0 
                        ? "Loan expires today" 
                        : "Loan expiring in $differenceDays ${differenceDays == 1 ? 'day' : 'days'}";
                    
                    alertsList.add({
                      "name": target['name']?.toString() ?? 'Unknown',
                      "message": message,
                      "amount": amt.toInt().toString()
                    });
                  } else if (differenceDays < 0) {
                    alertsList.add({
                      "name": target['name']?.toString() ?? 'Unknown',
                      "message": "Payment overdue",
                      "amount": amt.toInt().toString()
                    });
                  }
                }
              }

              // History Calculation
              var history = target['history'];
              if (history != null) {
                if (history is Map) {
                  history.forEach((hid, hEntry) {
                    if (hEntry is Map) {
                      double rVal = double.tryParse(hEntry['received']?.toString() ?? '0') ?? 0.0;
                      actualReceivedFromHistory += rVal;
                    }
                  });
                } else if (history is List) {
                  for (var hEntry in history) {
                    if (hEntry != null && hEntry is Map) {
                      double rVal = double.tryParse(hEntry['received']?.toString() ?? '0') ?? 0.0;
                      actualReceivedFromHistory += rVal;
                    }
                  }
                }
              }

              recentActivity.add({
                "name": target['name']?.toString() ?? 'Unknown',
                "displayAmount": amt.toInt().toString(),
                "originalAmount": amt.toInt().toString()
              });
            }
          }
        });
      }
    }

    // --- 2. Archive Loans ---
    final urlArchive = "$cleanUrl/archive/$safeEmail.json";
    final respArchive = await http.get(Uri.parse(urlArchive));

    if (respArchive.statusCode == 200 && respArchive.body != 'null') {
      final data = json.decode(respArchive.body);
      if (data is Map<String, dynamic>) {
        data.forEach((uid, target) {
          if (target is Map) {
            String rawArchiveMode = target['appMode']?.toString() ?? 
                                    target['mode']?.toString() ?? 
                                    target['loanMode']?.toString() ?? 
                                    "daily";
            
            String archiveMode = rawArchiveMode.toLowerCase().trim();

            if (archiveMode == targetMode) {
              settledLoansCount++;
              double origAmt = double.tryParse(target['originalAmount']?.toString() ?? '0') ?? 0.0;
              totalArchiveGiven += origAmt;

              // Loan Size Categorization for Archive Loans
              if (origAmt <= 25000) {
                mix0_25K++;
              } else if (origAmt <= 50000) {
                mix25_50K++;
              } else if (origAmt <= 100000) {
                mix50_1L++;
              } else {
                mix1LPlus++;
              }

              settledActivity.add({
                "name": target['name']?.toString() ?? 'Unknown',
                "displayAmount": origAmt.toInt().toString()
              });
            }
          }
        });
      }
    }

    int totalCustomers = activeLoansCount + settledLoansCount;
    double finalTotalOut = totalLoanGiven + totalArchiveGiven;
    double finalCollected = actualReceivedFromHistory + totalArchiveGiven;
    double finalPending = finalTotalOut - finalCollected;

    return {
      "displayName": displayName, // <-- Yahan name add kar diya gaya hai
      "stats": [
        totalCustomers.toString(),
        activeLoansCount.toString(),
        settledLoansCount.toString(),
        finalTotalOut.toInt().toString(),
        finalCollected.toInt().toString(),
        finalPending.toInt().toString()
      ],
      "loanMix": {
        "0-25K": mix0_25K.toString(),
        "25K-50K": mix25_50K.toString(),
        "50K-1L": mix50_1L.toString(),
        "1L+": mix1LPlus.toString(),
      },
      "recent": recentActivity.isEmpty ? [] : recentActivity.reversed.toList().sublist(0, recentActivity.length > 5 ? 5 : recentActivity.length),
      "settled": settledActivity.isEmpty ? [] : settledActivity.reversed.toList().sublist(0, settledActivity.length > 5 ? 5 : settledActivity.length),
      "alerts": alertsList
    };
  } catch (e) {
    print("Database Fetch Error: $e");
    return {
      "displayName": "User",
      "stats": List.filled(6, "0"),
      "loanMix": {"0-25K": "0", "25K-50K": "0", "50K-1L": "0", "1L+": "0"},
      "recent": [],
      "settled": [],
      "alerts": []
    };
  }
}

  // ===============================8. ADD LOAN=========================================
  static Future<Map<String, dynamic>> addLoan(String safeEmail, Map<String, dynamic> loanData) async {
    try {
      final url = "$BASE_URL/loans/$safeEmail.json";
      final res = await http.post(Uri.parse(url), body: json.encode(loanData));
      
      if (res.statusCode == 200) {
        return {"status": true, "message": "Loan saved!"};
      } else {
        return {"status": false, "message": res.body};
      }
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 9. FETCH LOANS
  static Future<Map<String, dynamic>> fetchLoans(String safeEmail) async {
    try {
      final url = "$BASE_URL/loans/$safeEmail.json";
      final res = await http.get(Uri.parse(url));
      
      if (res.body == 'null' || res.body.isEmpty) {
        return {"status": true, "data": "{}"};
      }
      return {"status": true, "data": res.body};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 10. DELETE LOAN
  static Future<Map<String, dynamic>> deleteLoan(String safeEmail, String loanId) async {
    try {
      final url = "$BASE_URL/loans/$safeEmail/$loanId.json";
      await http.delete(Uri.parse(url));
      return {"status": true, "message": "Loan record deleted"};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 11. UPDATE LOAN PAYMENT (With History and Optional SMS logic)
  static Future<Map<String, dynamic>> updateLoanPayment(
    String safeEmail, String loanId, Map<String, dynamic> historyEntry, 
    {String? phone, String? smsMsg}) async {
  try {
    final url = "$BASE_URL/loans/$safeEmail/$loanId.json";
    
    // Get old data for history and original amount
    final res = await http.get(Uri.parse(url));
    final oldData = json.decode(res.body);
    
    if (oldData == null) return {"status": false, "message": "Record nahi mila"};

    // 1. History list update karein
    List<dynamic> history = [];
    if (oldData['history'] != null && oldData['history'] is List) {
      history = List.from(oldData['history']);
    } else if (oldData['paymentHistory'] != null && oldData['paymentHistory'] is List) {
      history = List.from(oldData['paymentHistory']);
    }
    history.add(historyEntry);

    // 2. 🔥 Poori History ka Sum calculate karein (Total Paid Amount)
    double totalPaid = 0.0;
    for (var item in history) {
      totalPaid += double.tryParse(item['received']?.toString() ?? '0') ?? 0.0;
    }

    // 3. Original Total Amount nikalein
    double originalAmount = double.tryParse(
        oldData['originalAmount']?.toString() ?? 
        oldData['totalAmount']?.toString() ?? 
        oldData['amount']?.toString() ?? '0'
    ) ?? 0.0;

    // Agar originalAmount ya totalAmount ka field pehle se saved nahi hai, toh use calculate karein
    if (oldData['originalAmount'] == null && oldData['totalAmount'] == null) {
      double currentRem = double.tryParse(oldData['remainingBalance']?.toString() ?? oldData['amount']?.toString() ?? '0') ?? 0;
      double oldPaidSum = totalPaid - (double.tryParse(historyEntry['received'].toString()) ?? 0);
      originalAmount = currentRem + oldPaidSum;
    }

    // 4. Naya Remaining Balance calculate karein
    double newRemainingBalance = originalAmount - totalPaid;
    if (newRemainingBalance < 0) newRemainingBalance = 0;

    final updateData = {
      "amount": newRemainingBalance.toStringAsFixed(2),
      "remainingBalance": newRemainingBalance.toStringAsFixed(2),
      "history": history,
      "paymentHistory": history,
    };

    await http.patch(Uri.parse(url), body: json.encode(updateData));

    // AGAR SMS DATA HAI TO (Logic as per your requirement)
    if (phone != null && smsMsg != null) {
      try {
        // Yahan aap apna SMS sending function call kar sakte hain
        // jaise: sendLaptopSms(safeEmail, phone, smsMsg);
      } catch (e) {
        // SMS fail hone par main update na ruke
      }
    }

    return {"status": true, "message": "Payment updated"};
  } catch (e) {
    return {"status": false, "message": e.toString()};
  }
}

  // 12. UPDATE LOAN (PATCH Method - only keys in payload will update)
  static Future<Map<String, dynamic>> updateLoan(String safeEmail, String loanId, Map<String, dynamic> updateData) async {
    try {
      final url = "$BASE_URL/loans/$safeEmail/$loanId.json";
      
      // PATCH use kar rahe hain taaki baaki keys (like history) chhed-chaad na hon
      await http.patch(Uri.parse(url), body: json.encode(updateData));

      return {"status": true, "message": "Loan record updated successfully"};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

    // ======================= NEW: DELETE TRANSACTION HISTORY ENTRY ========================
  static Future<Map<String, dynamic>> deleteTransaction(String safeEmail, String loanId, String date, dynamic receivedAmount) async {
  try {
    final url = "$BASE_URL/loans/$safeEmail/$loanId.json";
    
    // 1. Current loan record fetch karein
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return {"status": false, "message": "Record fetch karne mein error!"};
    
    final oldData = json.decode(res.body);
    if (oldData == null || oldData['history'] == null) {
      return {"status": false, "message": "Record ya history nahi mili!"};
    }

    // 2. History list parse karein
    List<dynamic> historyList = (oldData['history'] is String) 
        ? jsonDecode(oldData['history']) 
        : List.from(oldData['history']);
        
    // 3. Transaction delete karein
    bool itemRemoved = false;
    for (int i = 0; i < historyList.length; i++) {
      if (!itemRemoved && historyList[i]['date'] == date && 
          historyList[i]['received'].toString() == receivedAmount.toString()) {
        historyList.removeAt(i);
        itemRemoved = true;
        break; 
      }
    }

    if (!itemRemoved) {
      return {"status": false, "message": "Transaction nahi mili!"};
    }

    // 4. 🔥 Calculation: Total Collected re-calculate karein (Mismatch khatam)
    double totalCollected = 0.0;
    for (var item in historyList) {
      totalCollected += double.tryParse(item['received'].toString()) ?? 0.0;
    }
    
    // Original Principle Amount fetch karein (database mein field 'originalAmount' hai)
    double principle = double.tryParse(oldData['originalAmount']?.toString() ?? '0') ?? 0.0;
    
    // Remaining Balance = Original Principle - New Total Collected
    double newRemainingBalance = principle - totalCollected;

    // 5. Database mein Update (Patch)
    // Yahan 'amount' field (Remaining Balance) ko re-calculated value se update kar rahe hain
    final updatePayload = {
      "amount": newRemainingBalance.toStringAsFixed(2), 
      "history": historyList
    };

    final patchRes = await http.patch(Uri.parse(url), body: json.encode(updatePayload));

    if (patchRes.statusCode == 200) {
      return {"status": true, "message": "Transaction deleted & Balance corrected!"};
    } else {
      return {"status": false, "message": "Update failed: ${patchRes.statusCode}"};
    }
  } catch (e) {
    return {"status": false, "message": "Error: ${e.toString()}"};
  }
}

  // 🔥 Is method ko DatabaseService class ke andar paste karein
  static Future<Map<String, dynamic>?> getSingleLoan(String safeEmail, String loanId) async {
    try {
      final url = "$BASE_URL/loans/$safeEmail/$loanId.json";
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && res.body != "null") {
        var decoded = json.decode(res.body);
        if (decoded is Map) {
          // ID ko wapas object me inject kar rahe hain
          decoded['id'] = loanId;
          return Map<String, dynamic>.from(decoded);
        }
      }
      return null;
    } catch (e) {
      print("Error fetching single loan: $e");
      return null;
    }
  }

  // 13. GENERATE CUSTOMER REPORT (Same design as Python FPDF)
  static Future<Map<String, dynamic>> generateCustomerReport(Map<String, dynamic> loanData) async {
  try {
    final pdf = pw.Document();

    // 🔥 SMART HISTORY PARSING LOGIC (Safe for both List and Map):
    var rawHistory = loanData['history'];
    List<Map<String, dynamic>> history = [];
    
    if (rawHistory is List) {
      for (var item in rawHistory) {
        if (item != null) history.add(Map<String, dynamic>.from(item));
      }
    } else if (rawHistory is Map) {
      rawHistory.forEach((key, value) {
        if (value != null) history.add(Map<String, dynamic>.from(value));
      });
    }

    // --- Calculation (Total Paid Counter) ---
    double totalPaid = 0;
    for (var h in history) {
      String rStr = (h['received'] ?? '0').toString().replaceAll(',', '');
      totalPaid += double.tryParse(rStr) ?? 0;
    }

    double principal = double.tryParse(loanData['originalAmount']?.toString() ?? '0') ?? 0;
    String interestRate = loanData['interest']?.toString() ?? '0';
    double balance = principal - totalPaid;
    String loanTenure = loanData['days']?.toString() ?? '0';

    // 🚀 MULTI-PAGE PDF FRAMEWORK (Continuous Flow Architecture)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0), // Full width header ke liye
        build: (pw.Context context) {
          return [
            // --- HEADER (Dark Blue #2C3E50) ---
            pw.Container(
              width: double.infinity,
              height: 100,
              color: const PdfColor.fromInt(0xFF2C3E50),
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(bottom: 25),
              child: pw.Text(
                "LOAN ACCOUNT STATEMENT",
                style: pw.TextStyle(
                  fontSize: 24,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),

            // --- CUSTOMER DETAILS ---
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(" CUSTOMER DETAILS", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF2C3E50))),
                  pw.Container(height: 1, color: const PdfColor.fromInt(0xFF2C3E50)),
                  pw.SizedBox(height: 10),
                  pw.Text("Name: ${loanData['name'] ?? 'N/A'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Phone: ${loanData['phone'] ?? 'N/A'}"),
                  pw.Text("Home Address: ${loanData['address'] ?? 'N/A'}"),
                  pw.Text("Office Address: ${loanData['officeName'] ?? 'N/A'}"),
                  pw.Text("Loan Date: ${loanData['date'] ?? 'N/A'}"),
                  pw.Text("Due Date: ${loanData['dueDate'] ?? 'N/A'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
                  pw.Text("Tenure: $loanTenure Days", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),

            // --- GUARANTOR DETAILS ---
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(" GUARANTOR DETAILS", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF2C3E50))),
                  pw.Container(height: 1, color: const PdfColor.fromInt(0xFF2C3E50)),
                  pw.SizedBox(height: 10),
                  pw.Text("Guarantor 1: ${loanData['refName'] ?? 'N/A'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Phone No: ${loanData['refPhone'] ?? 'N/A'} | Address: ${loanData['refAddress'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 5),
                  pw.Text("Guarantor 2: ${loanData['ref2Name'] ?? 'N/A'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text("Phone No: ${loanData['ref2Phone'] ?? 'N/A'} | Address: ${loanData['ref2Address'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),

            // --- FINANCIAL SUMMARY (Grey Background) ---
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 25),
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                color: const PdfColor.fromInt(0xFFECF0F1),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("FINANCIAL SUMMARY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF2C3E50))),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Principal: Rs. ${principal.toStringAsFixed(2)}"),
                        pw.Text("Interest: $interestRate%"),
                        pw.Text(""), 
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Total Paid: Rs. ${totalPaid.toStringAsFixed(2)}"),
                        pw.Text("Pending: Rs. ${balance.toStringAsFixed(2)}", style: pw.TextStyle(color: PdfColors.red, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // --- TRANSACTION HISTORY SECTION ---
            // Ab heading aur table ko bilkul linear kar diya hai, bina kisi nested outer column ke wrapper ke.
            if (history.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                child: pw.Text("No payments found for this loan account.", style: pw.TextStyle(color: PdfColors.grey))
              )
            else ...[
              // Heading Alag Block me taaki chipka rahe
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 6),
                child: pw.Text(" TRANSACTION HISTORY", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF2C3E50))),
              ),

              // Sahi Table system jo Page 1 ke bottom space me tight fit hoga aur baki rows automatic next page pe le jayega
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 30),
                child: pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey, width: 0.8),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1),
                    1: pw.FlexColumnWidth(1),
                  },
                  children: [
                    // Table Header Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF2C3E50)),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6), 
                          child: pw.Text(" Date", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold))
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6), 
                          child: pw.Text(" Amount", textAlign: pw.TextAlign.center, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold))
                        ),
                      ],
                    ),
                    // Table Data Rows
                    ...history.reversed.map((entry) {
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6), 
                            child: pw.Text(" ${entry['date'] ?? 'N/A'}")
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6), 
                            child: pw.Text(" Rs. ${entry['received'] ?? '0'}", textAlign: pw.TextAlign.center)
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            ]
          ];
        },
      ),
    );

    // --- SMART SAVING LOGIC ---
    String downloadDirPath = "";
    final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final String fileName = "${loanData['name'] ?? 'Customer'}_Statement_$timestamp.pdf";

    if (Platform.isAndroid) {
      downloadDirPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      final directory = await getDownloadsDirectory();
      downloadDirPath = directory!.path;
    }

    final file = File("$downloadDirPath/$fileName");
    await file.writeAsBytes(await pdf.save());

    return {"status": true, "message": "RESULT:SUCCESS: PDF Saved in Downloads: $fileName", "path": file.path};
  } catch (e) {
    return {"status": false, "message": e.toString()};
  }
}
  // ===================================agreement page=================================
  static Future<Map<String, dynamic>> generateAgreement(Map<String, dynamic> loanData) async {
    try {
      // --- HTML CONTENT GENERATION WITH EXACT USER TEMPLATE ---
      final String htmlContent = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Noto+Sans+Devanagari:wght@400;700&display=swap');
        
        /* ✅ नियम १: प्रिंट करताना ब्राउझरचे डीफॉल्ट हेडर/फुटर (URL, Date) १००% बंद करण्यासाठी */
        @page {
            size: A4;
            margin: 0mm; /* मार्जिन 0 केल्यामुळे ब्राउझरला हेडर-फुटर लिहायला जागाच उरत नाही */
        }

        /* ✅ नियम २: मार्जिन 0 केल्यामुळे मजकूर कट होऊ नये म्हणून मुख्य बॉडीला प्रिंटसाठी सुरक्षित स्पेस (Padding) दिली आहे */
        body { 
            font-family: 'Noto Sans Devanagari', sans-serif; 
            padding: 20mm 20mm 20mm 20mm; /* पानाचा मजकूर कडेला चिटकू नये म्हणून सुरक्षित अंतर */
            color: #000; 
            line-height: 1.5; 
            font-size: 14px; 
            background-color: #ffffff; 
        }
        
        .header { text-align: center; border-bottom: 2px solid #000; padding-bottom: 10px; margin-bottom: 20px; }
        .header h3 { margin: 0; font-size: 22px; font-weight: bold; }
        
        .info { display: flex; justify-content: space-between; margin-bottom: 20px; font-weight: bold; border-bottom: 1px solid #eee; padding-bottom: 10px; }
        
        .person-container { display: flex; align-items: center; justify-content: space-between; margin-top: 20px; border: 1px solid #ccc; padding: 15px; border-radius: 8px; background-color: #f9f9f9; }
        .person-details { width: 70%; }
        .photo-box { width: 80px; height: 100px; border: 2px solid #000; display: flex; align-items: center; justify-content: center; font-size: 10px; background: #fff; text-align: center; }
        
        /* Signature Box Styling */
        .signature-box { margin-top: 10px; padding: 10px; border: 1px dashed #555; background: #fff; width: 220px; text-align: center; font-size: 11px; font-weight: normal; color: #777; border-radius: 5px; }
        
        /* ✅ नियम नवीन पानावरून सुरू करण्यासाठी page-break-before वापरले आहे */
        .rules-section { 
            margin-top: 40px; 
            font-size: 12px; 
            border: 1px solid #333; 
            padding: 15px; 
            background: #fdfdfd; 
            page-break-before: always; 
        }
        .rules-section h4 { text-align: center; text-decoration: underline; margin-top: 0; }
        
        .footer-signs { display: flex; justify-content: space-between; margin-top: 50px; }
        .sign-placeholder { text-align: center; font-weight: bold; border-top: 2px solid #000; padding-top: 10px; width: 40%; }

        /* ✅ नियम ३: प्रिंटरसाठी अधिक कडक सुरक्षा नियम */
        @media print {
            html, body {
                background-color: #fff;
                color: #000;
            }
            /* हेडर-फुटर घालवण्यासाठी काही सिस्टीममध्ये हे आवश्यक असते */
            body {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <h3>मे. संकल्प फायनान्स</h3>
        <p>मु.पो. मुळेगांव, ता.द. सोलापूर, जि. सोलापूर. ४१३००६ | Mob. 9822474452, 9421204452</p>
        <h4 style="text-decoration: underline;">-: कर्ज मागणी अर्ज :-</h4>
    </div>
    
    <div class="info">
        <span>तारीख: <b>${loanData['date'] ?? ''}</b></span>
        <span>ठिकाण: <b>${loanData['place'] ?? loanData['address'] ?? ''}</b></span>
    </div>

    <div class="body-text">
        <p>प्रति,<br>मे. संकल्प फायनान्स,<br>मु.पो. मुळेगांव, ता.द. सोलापूर, जि. सोलापूर. ४१३००६</p>
        <p>महोदय,<br>मी <b>${loanData['name'] ?? ''}</b>, 
        कारणे विनंती अर्ज करतो की मला रक्कम रु. <b>${loanData['originalAmount'] ?? ''}</b> 
        ची गरज असून मुदत हुंडी/चेक देण्यास तयार आहे.</p>
        
        <p>तसेच सदर कर्जास खालील नमूद केलेल्या व्यक्तीचा जामीन देण्यास तयार आहे.</p>
        <p>मी/आम्ही असे लिहुन देतो की, मी/आम्ही शेतकरी नाही. मी/आम्ही सदर अर्जाबद्दलचे आपले खालील नमूद केलेले नियम नं. १ ते २४ हे पूर्ण वाचले असून आम्हास वाचून दाखविले असून ते मला/आम्हास मान्य व कबूल आहेत. कर्जासंबंधी योग्य ते सर्व अनुसंघीक कागदपत्रे तुम्हांस लिहून देण्यास तयार आहे.</p>
    </div>

    <div class="person-container">
        <div class="person-details">
            <b>अर्जदार:</b> ${loanData['name'] ?? ''}<br>
            घर पत्ता: ${loanData['address'] ?? ''}<br>
            ऑफिस पत्ता: ${loanData['officeName'] ?? 'N/A'}<br>
            मो.: ${loanData['phone'] ?? ''}
            <div class="signature-box">अर्जदाराची स्वाक्षरी</div>
        </div>
        <div class="photo-box">पासपोर्ट<br>फोटो</div>
    </div>

    <div class="person-container">
        <div class="person-details">
            <b>जामीनदार १:</b> ${loanData['refName'] ?? ''}<br>
            पत्ता: ${loanData['refAddress'] ?? ''}<br>
            मो.: ${loanData['refPhone'] ?? ''}
            <div class="signature-box">जामीनदार १ ची स्वाक्षरी</div>
        </div>
        <div class="photo-box">पासपोर्ट<br>फोटो</div>
    </div>

    <div class="person-container">
        <div class="person-details">
            <b>जामीनदार २:</b> ${loanData['ref2Name'] ?? ''}<br>
            पत्ता: ${loanData['ref2Address'] ?? ''}<br>
            मो.: ${loanData['ref2Phone'] ?? ''}
            <div class="signature-box">जामीनदार २ ची स्वाक्षरी</div>
        </div>
        <div class="photo-box">पासपोर्ट<br>फोटो</div>
    </div>

    <div class="rules-section">
        <h4>कर्जा संबंधीचे नियम :-</h4>
        <p>१) सदर भागीदारी अर्थसहाय्य फायनान्स ही सर्व कर्जदारांना कोणताही भेदभाव न पाळता सर्वांना समान नियमानुसार सेवा देईल.<br>
        २) सदरील भागीदारी अर्थसहाय्य फायनान्स व्यापाऱ्यांना त्यांच्या पत मर्यादे नूसार कर्ज देईल.<br>
        ३) ज्या व्यापाऱ्यांना कर्जाची आवश्यकता असल्यास त्यांनी सदर फायनान्सचा विहित नमुन्यातील अर्ज व अनूषंधिक कागदपत्रे भरून सदर फायनान्सकडे दिला पाहिजे. व त्या अनुषंगे कागद पत्रे भागीदारी अर्थ सहाय्य फायनान्सच्या नांवे लिहून दिल्या नंतरच कर्ज रक्कम अदा करण्यात येईल.<br>
        ४) कर्ज मागणी अर्ज मंजूर किंवा नामंजूर करण्याचे सर्व अधिकार सदर भागीदारी अर्थ सहाय्य फायनान्सकडे असतील व सदर भागीदारी अर्थ सहाय्य फायनान्सच्या अधिकाराबाबत तक्रार किंवा वाद घालण्याचा कोणास ही अधिकार राहणार नाही.<br>
        ५) अर्जदाराने कर्ज मागणी अर्ज दिल्यानंतर भागीदारी अर्थसहाय्य फायनान्सने मागणी केलेले माहीती व कागदपत्रे फायनान्सकडे त्वरीत दिली पाहिजेत. तशी पूर्तता न केल्यास अर्ज नांमंजूर करण्यास योग्य कारण ठरेल.<br>
        ६) अर्जदाराची मुदतीत कर्ज परत फेड करण्याची सांपत्तीक स्थीती व उत्पन्न मार्गाच्या उपलब्धतवर कर्ज मंजूर करण्यात येईल.<br>
        ७) अर्जदाराचा कर्ज मागणी अर्ज मंजूर होवून कर्ज रक्कम अदाकरतेवेळी कर्ज मुदतीचे द.सा.द.शे. प्रमाणे होणारी रक्कम कर्जदाराने फायनान्सकडे भरणा करावी.<br>
        ८) कर्जदारानी मुदतीत कर्ज रकमेची पूर्ण फेड न केल्यास येथे रक्कमेवर कर्ज मुदत संपलेल्या तारखे पासून संपूर्ण येणे रक्कम वसूल होई पर्यंत थकबाकीदारास द. सा. व. शे. दंड व्याज द्यावे लागेल.<br>
        ९) थकबाकीदाराची सदर भागीदारी अर्थ सहाय्य फायनान्सकडे ठेवी व तारण जमा असल्यास सदर ठेवी, तारण कर्ज खात्यास जमा करण्याचा अधिकार फायनान्सला राहील. व त्यास कर्जदाराची / थकबाकीदाराची संमतीची आवश्यकता राहणार नाही.<br>
        १०) कर्जदाराने घेतलेल्या कर्ज रकमेची परत फेड ही मुदती पुर्वी त्याच्या सोयी नुसार करण्याची सोय उपलब्ध राहील.<br>
        ११) भागीदारी अर्थसहाय्य फायनान्यला कर्जदारानी दिलेले जामीनदार जामीनकीस योग्य वाटल्यास कर्ज रक्कम कर्जदारास देण्यात येईल. सदर कर्ज रक्कम परतफेडीस कर्जदार व जामीनदार हे सर्वजण व्यक्तीशः व संयुक्तरित्या जबाबدار राहतील.<br>
        १२) प्रत्येक कर्जदारास भागीदारी अर्थ सहाय्य फायनान्सकडे असलेले कर्जखाते पाहणीस व तपासणीस मिळू शकते.<br>
        १३) कर्जदाराने कर्ज परतफेड पोटी किंवा व्याजापोटी दिलेला वसूलीची पावती दिली जाईल व पावती शिवाय कोणतीही तक्रार चालणार नाही.<br>
        १४) कर्जासंबंधी जे कागदपत्रे भागीदारी फायनान्सला लिहून द्यावे लागतील त्या संबंधी होणारा खर्च व सेवा शुल्क कर्जदारास सोसावा लागेल.<br>
        १५) कर्जदारानी भागीदारी फायनान्सला दिलेल्या तारण वस्तू ठेवी वर पुन्हा दुसरे कर्ज मागील कर्ज पूर्ण फेड झाल्याशिवाय मिळणार नाही.<br>
        १६) मंजूर झालेले कर्ज मंजूर झालेल्या तारखेपासून तीन दिवसात कर्ज रक्कम न घेतल्यास मंजूर झालेले कर्ज रद्द होईल.<br>
        १७) दोन किंवा अधिक व्यक्तीनी मिळून कर्ज घेतले असल्यास कर्ज परत फेड करणयची जबाबदारी व्यक्तीशः व संयुक्तीк रित्या राहील.<br>
        १८) कर्ज परतफेड रक्कम ही भागीदारी फायनान्सच्या कार्यालयात आणून भरावी लागेल.<br>
        १९) कर्ज परतफेडीची अंतीम तारीख ही दिवसाची गणना करून काढण्यात येईल. अंतीम तारीख रविवारी अथवा सुट्टीच्या दिवशी येत असल्यास कर्ज रक्कम ही त्या पुर्वी येणाऱ्या दिवशी कार्यालयीन वेळेत भरली पाहीजे.<br>
        २०) कर्ज मुदत देय दिनांकानंतर थकीत रक्कमेवर द. सा. द. शे. दराने व्याज आकारले जाईल.<br>
        २१) भागीदारी अर्थसहाय्य फायनान्सकडे कर्जदार व जामीनदार यांच्या ठेवी व इतर स्वरूपात जमा असलेल्या रकमेवर भागीदारी फायनान्सच्या अग्रहक्काने भार (चार्ज) राहील.<br>
        २२) भागीदारी अर्थसहाय्य फायनान्स व अन्य व्यक्ती यांच्या मधील वाद सोलापूर येथील न्यायालयाच्या अखत्यारीत असेल.<br>
        २३) अर्जदाराने / कर्जदार व जामिनदारांना यांना फायनान्सच्या नियमाचे पालन करावे लागेल.<br>
        २४) मुदत देय दिनांकानंतर देय दिनांकादिवशी थकित असलेल्या रकमेवर संपुर्ण फिटे पर्यंत नियमाप्रमाणे व्याज आकारले जाईल.<br><br>
        वरिल सर्व नियम मी / आम्ही वाचलेले असून / आम्हास वाचून दाखविले असून आणि ते मला / आम्हाला पूर्णपणे समजले आहेत आणि सदर सर्व नियम मला / आम्हाला पूर्णपणे मान्य व कबूल असून ते माझे / आमचेवर बंधनकारक आहेत व राहतील.</p>
    </div>

    <div class="footer-signs">
        <div class="sign-placeholder">मॅनेजींग पार्टनर</div>
        <div class="sign-placeholder">मॅनेजींग / अकौंटंट</div>
    </div>
</body>
</html>
""";

      // --- SMART SAVING LOGIC FOR HTML FILE ---
      String downloadDirPath = "";
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = "Sankalp_Agreement_$timestamp.html";

      if (Platform.isAndroid) {
        // Android साठी डायरेक्ट Public Downloads फोल्डरचा पाथ
        downloadDirPath = '/storage/emulated/0/Download';
        final dir = Directory(downloadDirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        // Laptop/PC साठी path_provider चा पाथ वापरला जाईल
        final directory = await getDownloadsDirectory();
        downloadDirPath = directory!.path;
      }

      final file = File("$downloadDirPath/$fileName");
      await file.writeAsString(htmlContent);

      return {
        "status": true,
        "message": "RESULT:SUCCESS: Agreement Saved in Downloads: $fileName",
        "path": file.path,
        "html_string": htmlContent // हा डेटा तुम्ही कन्व्हर्टरला किंवा वेब-व्ह्यूला पाठवू शकता
      };
    } catch (e) {
      return {"status": false, "message": "Error: $e"};
    }
  }

  static Future<Map<String, dynamic>> exportLoanList(String safeEmail, {String? mode}) async {
  try {
    // 1. Firebase se saare loans fetch karein
    final url = "$BASE_URL/loans/$safeEmail.json";
    final res = await http.get(Uri.parse(url));
    
    if (res.body == 'null' || res.body.isEmpty) {
      return {"status": false, "message": "Export ke liye koi loan records nahi mile!"};
    }

    Map<String, dynamic> loansMap = json.decode(res.body);
    List<Map<String, dynamic>> loanList = [];
    
    loansMap.forEach((key, value) {
      if (value is Map) {
        var item = Map<String, dynamic>.from(value);
        item['id'] = key;

        // Mode Filter Logic (Daily / Weekly)
        if (mode != null && mode.isNotEmpty) {
          String loanMode = (item['mode'] ?? "daily").toString().toLowerCase().trim();
          if (loanMode == mode.toLowerCase().trim()) {
            loanList.add(item);
          }
        } else {
          loanList.add(item);
        }
      }
    });

    if (loanList.isEmpty) {
      String modeText = (mode != null && mode.isNotEmpty) ? "$mode mode ke" : "";
      return {"status": false, "message": "Export ke liye koi $modeText loan records nahi mile!"};
    }

    final pdf = pw.Document();
    String reportTitle = (mode != null && mode.isNotEmpty) ? "${mode.toUpperCase()} LOANS TABLE REPORT" : "ALL LOANS TABLE REPORT";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return [
            // --- Header Banner ---
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF2C3E50),
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(bottom: 15),
              child: pw.Text(
                reportTitle,
                style: pw.TextStyle(
                  fontSize: 18,
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),

            // --- Loop Through Each Loan as a Structured Table ---
            ...loanList.asMap().entries.map((entry) {
              int listIndex = entry.key + 1;
              var loan = entry.value;
              
              // Yahan 'sr' field ko priority di gayi hai, agar na mile toh firebase key ('id') use hogi
              String loanId = loan['sr']?.toString() ?? loan['id']?.toString() ?? 'N/A';

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 15),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Customer Header bar inside Table with 'sr' ID
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFF34495E),
                        borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            "Loan #$listIndex : ${loan['name'] ?? 'N/A'}",
                            style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
                          ),
                          pw.Text(
                            "SRNO: #$loanId (${mode ?? 'DAILY'})",
                            style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
                          ),
                        ],
                      ),
                    ),

                    // Table View including Loan & Guarantor Details
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(2),
                        1: pw.FlexColumnWidth(3),
                        2: pw.FlexColumnWidth(2),
                        3: pw.FlexColumnWidth(3),
                      },
                      children: [
                        // Row 1: Addresses
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Home Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['homeAddress'] ?? loan['address'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Office Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['officeAddress'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                        // Row 2: Phone & Reg Date
                        pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Phone", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['phone'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Reg. Date", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['date'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                        // Row 3: Due Date & Principal Amount
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Due Date", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['dueDate'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Principal Amount", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Rs. ${loan['originalAmount'] ?? loan['amount'] ?? '0'}", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                        // Row 4: Interest Rate & Tenure
                        pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Interest Rate", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['interest'] ?? '1'}%", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Loan Tenure", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['tenure'] ?? loan['days'] ?? '5'} Days", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                        // --- GUARANTOR 1 DETAILS SECTION ---
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAECEE)),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 1 Name", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['refName'] ?? loan['g1Name'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 1 Phone", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['refPhone'] ?? loan['g1Phone'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAECEE)),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 1 Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['refAddress'] ?? loan['g1Address'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                        // --- GUARANTOR 2 DETAILS SECTION ---
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 2 Name", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['ref2Name'] ?? loan['g2Name'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 2 Phone", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['ref2Phone'] ?? loan['g2Phone'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 2 Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['ref2Address'] ?? loan['g2Address'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("", style: const pw.TextStyle(fontSize: 8))),
                            pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("", style: const pw.TextStyle(fontSize: 8))),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              "Generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} - Digital Ledger Pro",
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey, fontStyle: pw.FontStyle.italic),
            ),
          );
        },
      ),
    );

    // 3. Save PDF to Downloads Folder
    String downloadDirPath = "";
    final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final String fileName = "Loan_Table_Report_$timestamp.pdf";

    if (Platform.isAndroid) {
      downloadDirPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      final directory = await getDownloadsDirectory();
      downloadDirPath = directory!.path;
    }

    final file = File("$downloadDirPath/$fileName");
    await file.writeAsBytes(await pdf.save());

    return {
      "status": true,
      "message": "RESULT:SUCCESS: Table format PDF saved in Downloads: $fileName",
      "path": file.path
    };
  } catch (e) {
    return {"status": false, "message": "Error: ${e.toString()}"};
  }
}


  // ==================================1. Add Udari===============================
  static Future<Map<String, dynamic>> addUdari(String safeEmail, Map<String, dynamic> data) async {
    try {
      final url = "$BASE_URL/udari/$safeEmail.json";
      final res = await http.post(Uri.parse(url), body: json.encode(data));
      return res.statusCode == 200 
          ? {"status": true, "message": "Udari saved!"} 
          : {"status": false, "message": res.body};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 2. Fetch Udari
  static Future<Map<String, dynamic>> fetchUdari(String safeEmail) async {
    try {
      final url = "$BASE_URL/udari/$safeEmail.json";
      final res = await http.get(Uri.parse(url));
      if (res.body == 'null' || res.body.isEmpty) return {"status": true, "data": "{}"};
      return {"status": true, "data": res.body};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 3. Delete Udari
  static Future<Map<String, dynamic>> deleteUdari(String safeEmail, String entryId) async {
    try {
      final url = "$BASE_URL/udari/$safeEmail/$entryId.json";
      await http.delete(Uri.parse(url));
      return {"status": true, "message": "Udari record deleted"};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 4. Update Udari (General Patch)
  static Future<Map<String, dynamic>> updateUdari(String safeEmail, String entryId, Map<String, dynamic> updateData) async {
    try {
      final url = "$BASE_URL/udari/$safeEmail/$entryId.json";
      await http.patch(Uri.parse(url), body: json.encode(updateData));
      return {"status": true, "message": "Udari updated"};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 5. Update Udari Payment (Specially for Payments List & Total)
  // Yeh wahi naya function hai jo aapne Python me diya tha
  static Future<Map<String, dynamic>> updateUdariPayment(String safeEmail, Map<String, dynamic> payload) async {
    try {
      String entryId = payload["id"];
      var newPayment = payload["payment"];
      var newTotal = payload["new_total"]; // Naya total

      final url = "$BASE_URL/udari/$safeEmail/$entryId.json";
      
      // Get old data (Logic same as Python: requests.get(url).json())
      final res = await http.get(Uri.parse(url));
      final oldData = json.decode(res.body);
      
      if (oldData == null) return {"status": false, "message": "Record nahi mila"};

      // Payments list handle karein
      List<dynamic> payments = [];
      if (oldData['payments'] != null && oldData['payments'] is List) {
        payments = List.from(oldData['payments']);
      }
      
      payments.add(newPayment); // Naya payment append kiya

      // Patch payload taiyar karein
      Map<String, dynamic> updatePayload = {"payments": payments};
      if (newTotal != null) {
        updatePayload["total"] = newTotal; // Database mein total update karega
      }

      await http.patch(Uri.parse(url), body: json.encode(updatePayload));
      return {"status": true, "message": "Payment and Total updated successfully"};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 6. Generate Udari PDF Statement (Border Error Fixed)
  static Future<Map<String, dynamic>> generateUdariPdf(Map<String, dynamic> item) async {
  try {
    final pdf = pw.Document();

    // --- 1. Calculations (Safe Calculation Outside the Layout Loop) ---
    List payments = item['payments'] ?? [];
    double totalPaid = 0;
    double totalAmt = double.tryParse(item['total']?.toString() ?? '0') ?? 0;
    String accType = item['type']?.toString().toUpperCase() ?? 'N/A';

    // Loop through payments beforehand to avoid layout phase recalculations
    for (var p in payments) {
      bool isDebt = p['isDebt'] ?? false;
      double amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0;
      if (!isDebt) {
        totalPaid += amt;
      }
    }

    // 🚀 MULTI-PAGE PDF FRAMEWORK (Continuous Flow Architecture)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0), // Full width header ke liye 0 margin
        build: (pw.Context context) {
          return [
            // --- Stylish Header (Blue Rect) ---
            pw.Container(
              width: double.infinity,
              height: 120,
              color: const PdfColor.fromInt(0xFF2196F3), // Blue shade
              padding: const pw.EdgeInsets.symmetric(vertical: 20),
              margin: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text("TRANSACTION STATEMENT",
                      style: pw.TextStyle(fontSize: 24, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 5),
                  pw.Text("Generated on: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}",
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.white, fontStyle: pw.FontStyle.italic)),
                ],
              ),
            ),

            // --- Customer Info Box (Gray Background) ---
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 20),
              child: pw.Container(
                color: const PdfColor.fromInt(0xFFF0F0F0),
                padding: const pw.EdgeInsets.all(10),
                child: pw.Column(
                  children: [
                    pw.Row(children: [
                      pw.Text("Customer Name: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text("${item['name'] ?? 'N/A'}"),
                    ]),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Phone: ${item['phone'] ?? 'N/A'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text("Type: $accType", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // --- TRANSACTION TABLE SECTION (Bina outer column ke flat render hoga) ---
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 30),
              child: pw.Table(
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FlexColumnWidth(2),
                },
                children: [
                  // Table Header Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF34495E)),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(" Date", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(" Description", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(" Amount (Rs.) ", textAlign: pw.TextAlign.right, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold))),
                    ],
                  ),

                  // Table Data Rows Loop (Zebra Striping & Automatic Pagination Split)
                  ...payments.asMap().entries.map((entry) {
                    int idx = entry.key;
                    var p = entry.value;
                    bool isDebt = p['isDebt'] ?? false;
                    double amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0;

                    String desc = isDebt 
                        ? "Added to Balance" 
                        : (item['type'] == 'lent' ? "Received Back" : "Paid Back");

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: idx % 2 != 0 ? const PdfColor.fromInt(0xFFF5F5F5) : PdfColors.white,
                      ),
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(" ${p['date'] ?? 'N/A'}")),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(" $desc")),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("Rs. ${amt.toStringAsFixed(2)} ", textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ),

            // --- Summary Section ---
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 30),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 15),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 10),

                  _buildSummaryRow(
                    item['type'] == 'lent' ? "Total Lent:" : "Total Borrowed:",
                    "Rs. ${totalAmt.toStringAsFixed(2)}",
                    PdfColors.black,
                    11
                  ),
                  _buildSummaryRow(
                    item['type'] == 'lent' ? "Total Received:" : "Total Paid:",
                    "Rs. ${totalPaid.toStringAsFixed(2)}",
                    PdfColors.black,
                    11
                  ),
                  pw.SizedBox(height: 5),
                  _buildSummaryRow(
                    "Remaining Balance:",
                    "Rs. ${(totalAmt - totalPaid).toStringAsFixed(2)}",
                    PdfColors.red800,
                    14,
                    isBold: true
                  ),
                ],
              ),
            ),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Text("Thank you for using Digital Ledger Pro - Professional Statement",
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey, fontStyle: pw.FontStyle.italic)),
          );
        },
      ),
    );

    // --- SMART SAVING LOGIC (WITHOUT OPEN FILE) ---
    String downloadDirPath = "";
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = "Statement_${item['name'] ?? 'Customer'}_$timestamp.pdf";

    if (Platform.isAndroid) {
      downloadDirPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      final directory = await getDownloadsDirectory();
      downloadDirPath = directory!.path;
    }

    final file = File("$downloadDirPath/$fileName");
    await file.writeAsBytes(await pdf.save());

    return {"status": true, "message": "RESULT:SUCCESS: PDF Saved in Downloads: $fileName", "path": file.path};
  } catch (e) {
    return {"status": false, "message": "Error: $e"};
  }
}

// Helper function for summary rows
static pw.Widget _buildSummaryRow(String label, String value, PdfColor color, double fontSize, {bool isBold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Container(
          width: 120,
          child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: fontSize, color: color, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ),
      ],
    ),
  );
}

  // ====================== ARCHIVE FUNCTIONS (Same Logic as Python) ======================

  // 1. Archive Loan (Logic: Put to Archive -> Delete from Loans -> Send SMS)
  static Future<Map<String, dynamic>> archiveLoan(
    String safeEmail, 
    String loanId, 
    Map<String, dynamic> loanData, 
    {String? phone, String? base64Msg}
  ) async {
    try {
      if (loanData.isEmpty) return {"status": false, "message": "Data empty hai!"};

      // Archive URL
      final archiveUrl = "$BASE_URL/archive/$safeEmail/$loanId.json";
      
      // Update data with timestamp and status (Logic same as Python)
      loanData['closed_at'] = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      loanData['status'] = "SETTLED";

      // requests.put(archive_url, json=loan_data)
      final archiveRes = await http.put(Uri.parse(archiveUrl), body: json.encode(loanData));

      if (archiveRes.statusCode == 200) {
        // Successful archive, now delete from loans
        final deleteUrl = "$BASE_URL/loans/$safeEmail/$loanId.json";
        await http.delete(Uri.parse(deleteUrl));

        // SMS Logic (Logic same as Python)
        if (phone != null && base64Msg != null) {
          try {
            // Decode base64 message
            List<int> msgBytes = base64.decode(base64Msg);
            String plainMsg = utf8.decode(msgBytes);
            
            // Note: send_laptop_sms ko call karne ke liye aapka method
            // hum yahan assume kar rahe hain ki aapne Flutter me banaya hoga
            await sendLaptopSms(safeEmail, phone, plainMsg);
          } catch (e) {
            // Silence error as per Python "except: pass"
          }
        }
        
        return {"status": true, "message": "Loan moved to archive"};
      } else {
        return {"status": false, "message": "Archive failed"};
      }
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // 2. Fetch Archives
  static Future<Map<String, dynamic>> fetchArchives(String safeEmail) async {
    try {
      final url = "$BASE_URL/archive/$safeEmail.json";
      final res = await http.get(Uri.parse(url));
      
      if (res.body == 'null' || res.body.isEmpty) {
        return {"status": true, "data": "{}"};
      }
      return {"status": true, "data": res.body};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // Helper placeholder for SMS (Agar aapne implement nahi kiya hai toh)
  static Future<void> sendLaptopSms(String safeEmail, String phone, String msg) async {
     // SMS trigger logic yahan aayegi
     print("Sending SMS to $phone: $msg");
  }

  //======delete archive
  static Future<Map<String, dynamic>> deleteArchive(String userEmail, String archiveId) async {
    try {
      // PATH FIX: /archive/$userEmail/$archiveId.json
      final String url = "$BASE_URL/archive/$userEmail/$archiveId.json";
      
      final response = await http.delete(Uri.parse(url));

      if (response.statusCode == 200) {
        return {
          "status": true, 
          "message": "Record deleted from archives"
        };
      } else {
        return {
          "status": false, 
          "message": "Firebase Error: ${response.statusCode}"
        };
      }
    } catch (e) {
      return {
        "status": false, 
        "message": e.toString()
      };
    }
  }

  static Future<Map<String, dynamic>> generateLoanSettlementPdf(Map<String, dynamic> loanData) async {
    try {
      final pdf = pw.Document();

      // --- Financial Calculations (Safe Parsing) ---
      List history = loanData['history'] ?? [];
      double totalPaid = history.fold(0, (sum, item) => sum + (double.tryParse(item['received']?.toString() ?? '0') ?? 0));

      // 🚀 MULTI-PAGE PDF FRAMEWORK (Sahi Layout Flow Ke Liye Flat Array Use Kiya)
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0), // Full width header ke liye zero margin
          build: (pw.Context context) {
            return [
              // --- PDF HEADER DESIGN (Teal Color) ---
              pw.Container(
                width: double.infinity,
                height: 100,
                color: const PdfColor.fromInt(0xFF009688), // Teal color
                alignment: pw.Alignment.center,
                margin: const pw.EdgeInsets.only(bottom: 25),
                child: pw.Text(
                  "LOAN SETTLEMENT REPORT",
                  style: pw.TextStyle(fontSize: 20, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                ),
              ),

              // --- CUSTOMER INFORMATION ---
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 15),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("CUSTOMER INFORMATION"),
                    pw.SizedBox(height: 5),
                    pw.Row(children: [
                      pw.Expanded(child: pw.Text("Name: ${loanData['name'] ?? 'N/A'}")),
                      pw.Expanded(child: pw.Text("Phone: ${loanData['phone'] ?? 'N/A'}")),
                    ]),
                    pw.Text("Home Address: ${loanData['address'] ?? 'N/A'}"),
                    pw.Text("Office Address: ${loanData['officeName'] ?? 'N/A'}"),
                    pw.Text("Loan Date: ${loanData['date'] ?? 'N/A'}"), // 🔥 LOAN DATE ADD KIYA
                    pw.Text("Due Date: ${loanData['dueDate'] ?? 'N/A'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF009688))),
                    pw.Text("Loan Tenure: ${loanData['days'] ?? '0'} Days"),
                  ],
                ),
              ),

              // --- GUARANTOR INFORMATION ---
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 15),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("GUARANTOR INFORMATION"),
                    pw.SizedBox(height: 5),
                    // Guarantor 1
                    pw.Text("Guarantor 1:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Row(children: [
                      pw.Expanded(child: pw.Text("Name: ${loanData['refName'] ?? 'N/A'}")),
                      pw.Expanded(child: pw.Text("Phone: ${loanData['refPhone'] ?? 'N/A'}")),
                    ]),
                    pw.Text("Address: ${loanData['refAddress'] ?? 'N/A'}"),
                    pw.SizedBox(height: 10),
                    // Guarantor 2
                    pw.Text("Guarantor 2:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Row(children: [
                      pw.Expanded(child: pw.Text("Name: ${loanData['ref2Name'] ?? 'N/A'}")),
                      pw.Expanded(child: pw.Text("Phone: ${loanData['ref2Phone'] ?? 'N/A'}")),
                    ]),
                    pw.Text("Address: ${loanData['ref2Address'] ?? 'N/A'}"),
                  ],
                ),
              ),

              // --- FINANCIAL SUMMARY ---
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader("FINANCIAL SUMMARY"),
                    pw.SizedBox(height: 5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text("Principal: Rs. ${loanData['originalAmount'] ?? '0'}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text("Interest: ${loanData['interest'] ?? '0'}%", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text("Total Paid: Rs. $totalPaid", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),

              // --- TRANSACTION TABLE SECTION (Ab bina outer Column ke tight fit start hoga) ---
              if (history.isEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                  child: pw.Text("No payments found for this loan account.", style: pw.TextStyle(color: PdfColors.grey))
                )
              else ...[
                // Heading directly array me pass ki, taaki yeh hamesha table ke upar chipki rahe
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 30, right: 30, bottom: 5),
                  child: _buildSectionHeader("TRANSACTION HISTORY"),
                ),

                // Sahi Native Table structure jo pehle hi page ke khali space se automatic populate shuru ho jayega
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 30),
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(1),
                      1: pw.FlexColumnWidth(1),
                    },
                    children: [
                      // Table Header Row
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF009688)), // Teal
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text("  Date", style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text("  Amount Received", textAlign: pw.TextAlign.center, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      // Table Data Rows Loop (Smart Split/Break automatically handled by pdf package)
                      ...history.map((entry) {
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8), 
                              child: pw.Text("  ${entry['date'] ?? 'N/A'}")
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8), 
                              child: pw.Text("  Rs. ${entry['received'] ?? '0'}", textAlign: pw.TextAlign.center)
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ];
          },
        ),
      );

      // --- FIXED SAVING LOGIC FOR MOBILE AND LAPTOP ---
      String downloadDirPath = "";
      final String timestamp = DateFormat('HHmmss').format(DateTime.now());
      final String fileName = "${loanData['name'] ?? 'Customer'}_Report_$timestamp.pdf";

      if (Platform.isAndroid) {
        downloadDirPath = '/storage/emulated/0/Download';
        final dir = Directory(downloadDirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        final directory = await getDownloadsDirectory();
        downloadDirPath = directory!.path;
      }

      final file = File("$downloadDirPath/$fileName");
      await file.writeAsBytes(await pdf.save());

      return {"status": true, "message": "RESULT:SUCCESS: PDF Saved in Downloads: $fileName", "path": file.path};
    } catch (e) {
      return {"status": false, "message": e.toString()};
    }
  }

  // Helper function for Section Headers
  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      color: const PdfColor.fromInt(0xFFE6E6E6), // Light gray
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        "  $title",
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  // ====================== EXPORT ARCHIVE LOANS PDF ======================
  static Future<Map<String, dynamic>> exportArchivePdf(String safeEmail, {String? mode}) async {
    try {
      // 1. Firebase se saare archived loans fetch karein
      final url = "$BASE_URL/archive/$safeEmail.json";
      final res = await http.get(Uri.parse(url));
      
      if (res.body == 'null' || res.body.isEmpty) {
        return {"status": false, "message": "Export ke liye koi archived loan records nahi mile!"};
      }

      Map<String, dynamic> archivesMap = json.decode(res.body);
      List<Map<String, dynamic>> archiveList = [];
      
      archivesMap.forEach((key, value) {
        if (value is Map) {
          var item = Map<String, dynamic>.from(value);
          item['id'] = key;

          // Mode Filter Logic (Daily / Weekly) with multi-key fallback
          if (mode != null && mode.isNotEmpty) {
            String rawMode = item['appMode']?.toString() ?? 
                             item['mode']?.toString() ?? 
                             item['loanMode']?.toString() ?? 
                             "daily";
            String loanMode = rawMode.toLowerCase().trim();
            if (loanMode == mode.toLowerCase().trim()) {
              archiveList.add(item);
            }
          } else {
            archiveList.add(item);
          }
        }
      });

      if (archiveList.isEmpty) {
        String modeText = (mode != null && mode.isNotEmpty) ? "$mode mode ke" : "";
        return {"status": false, "message": "Export ke liye koi $modeText archived loan records nahi mile!"};
      }

      final pdf = pw.Document();
      String reportTitle = (mode != null && mode.isNotEmpty) ? "${mode.toUpperCase()} SETTELED LOANS TABLE REPORT" : "ALL SETTELED LOANS TABLE REPORT";

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return [
              // --- Header Banner ---
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF2C3E50),
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                alignment: pw.Alignment.center,
                margin: const pw.EdgeInsets.only(bottom: 15),
                child: pw.Text(
                  reportTitle,
                  style: pw.TextStyle(
                    fontSize: 18,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              // --- Loop Through Each Archive Loan as a Structured Table ---
              ...archiveList.asMap().entries.map((entry) {
                int listIndex = entry.key + 1;
                var loan = entry.value;
                
                String loanId = loan['sr']?.toString() ?? loan['id']?.toString() ?? 'N/A';

                // Closed date ko 'dd/MM/yyyy' format mein convert karne ke liye robust logic
                String rawClosedAt = loan['closed_at']?.toString() ?? '';
                String formattedClosedDate = 'N/A';

                if (rawClosedAt.isNotEmpty && rawClosedAt != 'N/A') {
                  try {
                    DateTime parsedDate = DateTime.parse(rawClosedAt);
                    formattedClosedDate = DateFormat('dd/MM/yyyy').format(parsedDate);
                  } catch (_) {
                    String datePart = rawClosedAt.contains(' ') 
                        ? rawClosedAt.split(' ')[0] 
                        : (rawClosedAt.contains('T') ? rawClosedAt.split('T')[0] : rawClosedAt);
                    
                    List<String> parts = datePart.split('-');
                    if (parts.length == 3 && parts[0].length == 4) {
                      formattedClosedDate = "${parts[2]}/${parts[1]}/${parts[0]}";
                    } else {
                      formattedClosedDate = datePart; 
                    }
                  }
                }

                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 15),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Header bar inside Table
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFF34495E),
                          borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              "Settled Loan #$listIndex : ${loan['name'] ?? 'N/A'}",
                              style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
                            ),
                            pw.Text(
                              "SRNO: #$loanId | Status: SETTLED",
                              style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
                            ),
                          ],
                        ),
                      ),

                      // Table View for Archived Loan Details (Including Guarantor / References & Clean Closed Date)
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                        columnWidths: const {
                          0: pw.FlexColumnWidth(2),
                          1: pw.FlexColumnWidth(3),
                          2: pw.FlexColumnWidth(2),
                          3: pw.FlexColumnWidth(3),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                            children: [
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Home Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['homeAddress'] ?? loan['address'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Office Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['officeAddress'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            ],
                          ),
                          pw.TableRow(
                            children: [
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Phone", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['phone'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Loan Date", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['date'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            ],
                          ),
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                            children: [
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Closed Date", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(formattedClosedDate, style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Principal Amount", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Rs. ${loan['originalAmount'] ?? loan['amount'] ?? '0'}", style: const pw.TextStyle(fontSize: 8))),
                            ],
                          ),
                          pw.TableRow(
                            children: [
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Interest Rate", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['interestRate'] ?? loan['interest'] ?? '1'}%", style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Loan Tenure", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['tenure'] ?? loan['days'] ?? '5'} Days", style: const pw.TextStyle(fontSize: 8))),
                            ],
                          ),
                          // --- Guarantor 1 Details ---
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                            children: [
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 1 Name", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['refName'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 2 Name", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['ref2Name'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            ],
                          ),
                          pw.TableRow(
                            children: [
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 1 Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['refAddress'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 2 Address", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['ref2Address'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            ],
                          ),
                          // --- Guarantor 2 Details ---
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                            children: [
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 1 Phone", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['refPhone'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("Guarantor 2 Phone", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                              pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text("${loan['ref2Phone'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 8))),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ];
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                "Generated on ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} - Digital Ledger Pro (Archives)",
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey, fontStyle: pw.FontStyle.italic),
              ),
            );
          },
        ),
      );

      // 3. Save PDF to Downloads Folder
      String downloadDirPath = "";
      final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String fileName = "Archived_Loans_Report_$timestamp.pdf";

      if (Platform.isAndroid) {
        downloadDirPath = '/storage/emulated/0/Download';
        final dir = Directory(downloadDirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        final directory = await getDownloadsDirectory();
        downloadDirPath = directory!.path;
      }

      final file = File("$downloadDirPath/$fileName");
      await file.writeAsBytes(await pdf.save());

      return {
        "status": true,
        "message": "RESULT:SUCCESS: Archive table format PDF saved in Downloads: $fileName",
        "path": file.path
      };
    } catch (e) {
      return {"status": false, "message": "Error: ${e.toString()}"};
    }
  }
  
  //=================================report page==============================
  static Future<Map<String, dynamic>> getLoanReport(String email, String filterType, String dateStr, {String mode = "daily"}) async {
  try {
    String sEmail = email.replaceAll('.', ','); // get_safe_email logic
    final targetMode = mode.toLowerCase().trim(); // Safe trim and lowercase

    // 1. Active Loans fetch karein
    final resLoans = await http.get(Uri.parse("$BASE_URL/loans/$sEmail.json"));
    Map<String, dynamic> dataLoans = {};
    if (resLoans.body != 'null' && resLoans.body.isNotEmpty) {
      dataLoans = json.decode(resLoans.body);
    }

    // 2. Archive Loans fetch karein
    final resArchive = await http.get(Uri.parse("$BASE_URL/archive/$sEmail.json"));
    Map<String, dynamic> dataArchive = {};
    if (resArchive.body != 'null' && resArchive.body.isNotEmpty) {
      dataArchive = json.decode(resArchive.body);
    }

    // Dono ko merge karein
    Map<String, dynamic> data = {...dataLoans, ...dataArchive};

    double totalGiven = 0.0;
    double totalCollected = 0.0;
    List<Map<String, dynamic>> filteredTransactions = [];

    // Date formatting logic
    String firebaseDate = "";
    String targetMonth = "";
    String targetYear = "";
    
    DateTime? dObj;
    List<String> weekDatesList = [];

    try {
      dObj = DateTime.parse(dateStr); // Expects YYYY-MM-DD
      firebaseDate = DateFormat('dd/MM/yyyy').format(dObj);
      targetMonth = DateFormat('/MM/yyyy').format(dObj);
      targetYear = DateFormat('yyyy').format(dObj);

      // WEEK LOGIC: Selected date se pichle 6 din calculate karke list me daalein (Total 7 Days)
      if (filterType == 'week') {
        for (int i = 0; i < 7; i++) {
          DateTime checkDate = dObj.subtract(Duration(days: i));
          weekDatesList.add(DateFormat('dd/MM/yyyy').format(checkDate));
        }
      }
    } catch (e) {
      firebaseDate = dateStr;
      targetMonth = dateStr;
      targetYear = dateStr;
    }

    if (data.isNotEmpty) {
      data.forEach((loanId, details) {
        if (details is Map) {
          // Loan ka mode extract karo (multi-key fallback implementation)
          String rawMode = details['appMode']?.toString() ?? 
                           details['mode']?.toString() ?? 
                           details['loanMode']?.toString() ?? 
                           "daily";
          
          String loanMode = rawMode.toLowerCase().trim();

          // CRITICAL CHECK: Agar loan ka mode current selected mode se match nahi karta, toh aage bado hi mat!
          if (loanMode != targetMode) {
            return; // Skip this customer completely
          }

          // --- GIVEN AMOUNT LOGIC ---
          String dbDate = details['date']?.toString() ?? '';
          bool isMatch = false;

          // 🔥 FIX: Added 'all' filter support to bypass date checking for all-time records
          if (filterType == 'all') {
            isMatch = true;
          } else if (filterType == 'day' && dbDate == firebaseDate) {
            isMatch = true;
          } else if (filterType == 'week' && weekDatesList.contains(dbDate)) {
            isMatch = true;
          } else if (filterType == 'month' && dbDate.contains(targetMonth)) {
            isMatch = true;
          } else if (filterType == 'year' && dbDate.contains(targetYear)) {
            isMatch = true;
          }

          if (isMatch) {
            var rawAmt = details['originalAmount'] ?? 0;
            double amt = double.tryParse(rawAmt.toString().replaceAll(',', '')) ?? 0.0;
            totalGiven += amt;
            filteredTransactions.add({
              "name": details['name'] ?? 'Unknown',
              "amount": amt,
              "type": "loan",
              "date": dbDate,
              "appMode": loanMode // 🔥 FIX: Frontend ke liye appMode pass karna jaroori hai!
            });
          }

          // --- COLLECTED AMOUNT (HISTORY) LOGIC ---
          var history = details['history'];
          List hList = [];
          if (history is List) {
            hList = history;
          } else if (history is Map) {
            hList = history.values.toList();
          }

          for (var entry in hList) {
            if (entry is Map) {
              String hDate = entry['date']?.toString() ?? '';
              bool hMatch = false;

              // 🔥 FIX: Added 'all' filter support for collection history as well
              if (filterType == 'all') {
                hMatch = true;
              } else if (filterType == 'day' && hDate == firebaseDate) {
                hMatch = true;
              } else if (filterType == 'week' && weekDatesList.contains(hDate)) {
                hMatch = true;
              } else if (filterType == 'month' && hDate.contains(targetMonth)) {
                hMatch = true;
              } else if (filterType == 'year' && hDate.contains(targetYear)) {
                hMatch = true;
              }

              if (hMatch) {
                var hRaw = entry['received'] ?? 0;
                double hAmt = double.tryParse(hRaw.toString().replaceAll(',', '')) ?? 0.0;
                totalCollected += hAmt;
                filteredTransactions.add({
                  "name": details['name'] ?? 'Unknown',
                  "amount": hAmt,
                  "type": "collection",
                  "date": hDate,
                  "appMode": loanMode // 🔥 FIX: History transaction me bhi appMode attach karo!
                });
              }
            }
          }
        }
      });
    }

    Map<String, dynamic> report = {
      "total_given": double.parse(totalGiven.toStringAsFixed(2)),
      "total_collected": double.parse(totalCollected.toStringAsFixed(2)),
      "transactions": filteredTransactions
    };

    return {"status": true, "data": json.encode(report)};
  } catch (e) {
    return {"status": false, "message": e.toString()};
  }
}

  //report pdf
  static Future<Map<String, dynamic>> generateFullReportPdf(Map<String, dynamic> data) async {
  try {
    final pdf = pw.Document();
    
    List transactions = data['transactions'] ?? [];
    String filterName = (data['filter'] ?? 'Day').toString().toUpperCase();
    String dateText = data['date_text'] ?? '';
    double totalGiven = double.tryParse(data['total_given']?.toString() ?? '0') ?? 0.0;
    double totalCollected = double.tryParse(data['total_collected']?.toString() ?? '0') ?? 0.0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (pw.Context context) {
          return [
            // --- MODERN HEADER DESIGN (Black/Dark) --- (NO CHANGE)
            pw.Container(
              width: double.infinity,
              height: 130,
              color: const PdfColor.fromInt(0xFF121212),
              padding: const pw.EdgeInsets.symmetric(vertical: 20),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text("FINANCIAL ANALYTICS",
                      style: pw.TextStyle(fontSize: 22, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 5),
                  pw.Text("STATEMENT PERIOD: $filterName ($dateText)",
                      style: const pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFFB4B4B4))),
                ],
              ),
            ),

            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 30),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 20),
                  
                  // --- SUMMARY CARDS (Red for Given, Green for Collected) --- (NO CHANGE)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: [
                      // Card 1: Total Given
                      _buildSummaryCard(
                        "TOTAL GIVEN", 
                        "Rs. ${totalGiven.toStringAsFixed(0)}", 
                        const PdfColor.fromInt(0xFFFFF5F5), // Fill
                        const PdfColor.fromInt(0xFFFFC8C8), // Border
                        const PdfColor.fromInt(0xFFC80000)  // Text
                      ),
                      // Card 2: Total Collected
                      _buildSummaryCard(
                        "TOTAL COLLECTED", 
                        "Rs. ${totalCollected.toStringAsFixed(0)}", 
                        const PdfColor.fromInt(0xFFF5FFF5), // Fill
                        const PdfColor.fromInt(0xFFC8FFC8), // Border
                        const PdfColor.fromInt(0xFF007800)  // Text
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 30),
                  pw.Text("Activity Log Details", 
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF323232))),
                  pw.SizedBox(height: 10),

                  // --- 🚀 FLEXIBLE & HIGHLY RESPONSIVE CUSTOM TABLE ---
                  // Ithe pw.Table block kadhun regular Column Rows use kele ahet jyamule table high flexibility child framework sarkha directly cards chya khali print hoil.
                  
                  // 1. Table Header Row (Tech Alignment Ani Color)
                  pw.Container(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF282C34)),
                    child: pw.Row(
                      children: [
                        pw.Expanded(flex: 1, child: _headerCell("S.N.", align: pw.TextAlign.center)),
                        pw.Expanded(flex: 5, child: _headerCell("Customer Name")),
                        pw.Expanded(flex: 3, child: _headerCell("Category", align: pw.TextAlign.center)),
                        pw.Expanded(flex: 3, child: _headerCell("Date", align: pw.TextAlign.center)),
                        pw.Expanded(flex: 3, child: _headerCell("Amount", align: pw.TextAlign.right)),
                      ],
                    ),
                  ),

                  // 2. Table Data Rows Loop (Zebra Effect Perfectly Preserved)
                  ...transactions.asMap().entries.map((entry) {
                    int i = entry.key + 1;
                    var t = entry.value;
                    bool isCol = t['type']?.toString().toLowerCase() == 'collection';
                    bool isEven = i % 2 == 0;

                    return pw.Container(
                      decoration: pw.BoxDecoration(
                        color: isEven ? const PdfColor.fromInt(0xFFF8F9FA) : PdfColors.white,
                        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5)) // Halki bottom line sathi
                      ),
                      child: pw.Row(
                        children: [
                          pw.Expanded(flex: 1, child: _dataCell("$i", align: pw.TextAlign.center)),
                          pw.Expanded(flex: 5, child: _dataCell(t['name'] ?? 'Unknown', isBold: true)),
                          pw.Expanded(
                            flex: 3, 
                            child: _dataCell(
                              isCol ? "RECEIVED" : "GIVEN", 
                              color: isCol ? const PdfColor.fromInt(0xFF008000) : const PdfColor.fromInt(0xFFC80000),
                              align: pw.TextAlign.center
                            )
                          ),
                          pw.Expanded(flex: 3, child: _dataCell(t['date'] ?? '', color: const PdfColor.fromInt(0xFF505050), align: pw.TextAlign.center)),
                          pw.Expanded(flex: 3, child: _dataCell("Rs. ${double.tryParse(t['amount']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}", isBold: true, align: pw.TextAlign.right)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Text(
              "Report Generated on ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())} - Digital Ledger Pro",
              style: pw.TextStyle(fontSize: 8, color: const PdfColor.fromInt(0xFFA0A0A0), fontStyle: pw.FontStyle.italic),
            ),
          );
        },
      ),
    );

    // --- SMART SAVING LOGIC (WITHOUT OPEN FILE) --- (NO CHANGE)
    String downloadDirPath = "";
    final String timestamp = DateFormat('HHmmss').format(DateTime.now());
    final String fileName = "Report_${filterName}_$timestamp.pdf";

    if (Platform.isAndroid) {
      downloadDirPath = '/storage/emulated/0/Download';
      final dir = Directory(downloadDirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      final directory = await getDownloadsDirectory();
      downloadDirPath = directory!.path;
    }

    final file = File("$downloadDirPath/$fileName");
    await file.writeAsBytes(await pdf.save());

    return {"status": true, "message": "RESULT:SUCCESS: PDF Saved in Downloads: $fileName", "path": file.path};
  } catch (e) {
    return {"status": false, "message": e.toString()};
  }
}

// Helper: Summary Cards (Exactly Same)
static pw.Widget _buildSummaryCard(String title, String value, PdfColor fill, PdfColor border, PdfColor textColor) {
  return pw.Container(
    width: 180,
    height: 70,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: fill,
      border: pw.Border.all(color: border, width: 1),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textColor)),
        pw.SizedBox(height: 5),
        pw.Text(value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: textColor)),
      ],
    ),
  );
}

// Helper: Header Cell (Exactly Same)
static pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(10),
    child: pw.Text(text, textAlign: align, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
  );
}

// Helper: Data Cell (Exactly Same)
static pw.Widget _dataCell(String text, {bool isBold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(10),
    child: pw.Text(text, 
      textAlign: align, 
      style: pw.TextStyle(
        fontSize: 10, 
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? PdfColors.black
      )
    ),
  );
}



  




































}

