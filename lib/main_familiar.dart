import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'config/modo_app.dart';
import 'screens/calendario_mensual.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Activamos el modo familiar de solo lectura
  ModoApp.esFamiliar = true;

  // Inicialización SQLite para escritorio si aplica
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const MyAppFamiliar());
}

class MyAppFamiliar extends StatelessWidget {
  const MyAppFamiliar({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Korreturnos Familiar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 1,
        ),
      ),
      home: const CalendarioMensual(),
    );
  }
}
