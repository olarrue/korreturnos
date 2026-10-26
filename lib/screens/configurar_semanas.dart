import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class ConfigurarSemanasScreen extends StatefulWidget {
  const ConfigurarSemanasScreen({super.key});

  @override
  State<ConfigurarSemanasScreen> createState() =>
      _ConfigurarSemanasScreenState();
}

class _ConfigurarSemanasScreenState extends State<ConfigurarSemanasScreen> {
  final db = DBHelper();

  int? semanaReal;
  int? semanaOrientativa;
  DateTime? fechaBase;
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final datos = await db.obtenerSemanas();

    if (datos != null && mounted) {
      setState(() {
        semanaReal = datos['semana_real_base'];
        semanaOrientativa = datos['semana_orientativa_base'];

        if (datos['fecha_base'] != null) {
          fechaBase = DateTime.parse(datos['fecha_base']);
        }
        cargando = false;
      });
    } else if (mounted) {
      setState(() => cargando = false);
    }
  }

  Future<void> _guardar() async {
    if (semanaReal == null || semanaOrientativa == null || fechaBase == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mesedez, bete eremu guztiak")),
      );
      return;
    }

    await db.guardarSemanas(
      semanaReal: semanaReal!,
      semanaOrientativa: semanaOrientativa!,
      fechaBase: fechaBase!.toIso8601String(),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Asteen konfigurazioa ondo gorde da"),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context, true);
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fechaBase ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => fechaBase = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Orientazio-astea"),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Erreferentzia eta Txandakatze Doikuntza",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Ezarri abiapuntuko data bat bere aste errealarekin eta orientazio-astearekin, egutegiaren txandakatzea automatikoki kalkulatzeko.",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 20),

                  // Semana real
                  DropdownButtonFormField<int>(
                    key: ValueKey("real_$semanaReal"),
                    initialValue: semanaReal,
                    decoration: const InputDecoration(
                      labelText: "Oinarrizko aste erreala (ISO)",
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      53,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text("${i + 1}. astea"),
                      ),
                    ),
                    onChanged: (v) => setState(() => semanaReal = v),
                  ),
                  const SizedBox(height: 16),

                  // Semana orientativa
                  DropdownButtonFormField<int>(
                    key: ValueKey("orientativa_$semanaOrientativa"),
                    initialValue: semanaOrientativa,
                    decoration: const InputDecoration(
                      labelText: "Oinarrizko orientazio-astea (1 - 18)",
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      18,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text("${i + 1}. astea"),
                      ),
                    ),
                    onChanged: (v) => setState(() => semanaOrientativa = v),
                  ),
                  const SizedBox(height: 16),

                  // Fecha base
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(color: Colors.grey.shade400),
                    ),
                    title: Text(
                      fechaBase == null
                          ? "Hautatu oinarrizko data"
                          : "Oinarrizko data: ${fechaBase!.day}/${fechaBase!.month}/${fechaBase!.year}",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: _seleccionarFecha,
                  ),
                  const SizedBox(height: 30),

                  // Botón Guardar
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade800,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _guardar,
                      child: const Text(
                        "Konfigurazioa gorde",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
