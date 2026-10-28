import 'package:flutter/material.dart';

class AppMode {
  // ValueNotifier automatic bina logout kiye poore app ke pages ko live refresh karega
  static final ValueNotifier<String> currentMode = ValueNotifier<String>("daily");

  static void toggleMode(bool isWeekly) {
    currentMode.value = isWeekly ? "weekly" : "daily";
  }
}