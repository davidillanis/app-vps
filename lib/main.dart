import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(VpsApp(controller: VpsController()..initialize()));
}
