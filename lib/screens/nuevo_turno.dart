import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class NuevoTurnoScreen extends StatefulWidget {
  final Map<String, dynamic>? turnoExistente;

  const NuevoTurnoScreen({super.key, this.turnoExistente});

  @override
  State<NuevoTurnoScreen> createState() => _NuevoTurnoScreenState();
}

class _NuevoTurnoScreenState extends State<NuevoTurnoScreen> {
  final db = DBHelper();

  late TextEditingController turnoCtrl;
  late TextEditingController tipoCtrl;

  TimeOfDay? hasiera;
  TimeOfDay? amaiera;

  bool get esEdicion => widget.turnoExistente != null;

  @override
  void initState() {
    super.initState();
    turnoCtrl = TextEditingController(
        text: widget.turnoExistente?['turno']?.toString() ?? '');
    tipoCtrl = TextEditingController(
        text: widget.turnoExistente?['tipo']?.toString() ?? '');

    final hStr = widget.turnoExistente?['hasiera']?.toString();
    final aStr = widget.turnoExistente?['amaiera']?.toString();
    if (hStr != null && hStr.isNotEmpty) {
      final p = hStr.split(":");
      if (p.length >= 2) {
        hasiera = TimeOfDay(
          hour: int.tryParse(p[0]) ?? 0,
          minute: int.tryParse(p[1]) ?? 0,
        );
      }
    }
    if (aStr != null && aStr.isNotEmpty) {
      final p = aStr.split(":");
      if (p.length >= 2) {
        amaiera = TimeOfDay(
          hour: int.tryParse(p[0]) ?? 0,
          minute: int.tryParse(p[1]) ?? 0,
        );
      }
    }
  }

  @override
  void dispose() {
    turnoCtrl.dispose();
    tipoCtrl.dispose();
    super.dispose();
  }

  // =========================
  // PICK HORA
  // =========================
  Future<void> _pickHora(bool esInicio) async {
    final hora = await showTimePicker(
      context: context,
      initialTime: (esInicio ? hasiera : amaiera) ?? TimeOfDay.now(),
    );

    if (hora != null) {
      setState(() {
        if (esInicio) {
          hasiera = hora;
        } else {
          amaiera = hora;
        }
      });
    }
  }

  String _formato(TimeOfDay? t) {
    if (t == null) return "--:--";
    return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  // =========================
  // CÁLCULO DE MINUTOS
  // =========================
  int _calcularMinutos() {
    if (hasiera == null || amaiera == null) return 0;

    final ini = hasiera!.hour * 60 + hasiera!.minute;
    final fin = amaiera!.hour * 60 + amaiera!.minute;

    if (fin >= ini) {
      return fin - ini;
    } else {
      // 🔥 Turno nocturno que cruza medianoche
      return (24 * 60 - ini) + fin;
    }
  }

  String _formatearDuracion(int minutos) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    return "${h}h ${m}m";
  }

  // =========================
  // GUARDAR O MODIFICAR
  // =========================
  Future<void> _guardar() async {
    final turno = turnoCtrl.text.trim().toUpperCase();
    final tipo = tipoCtrl.text.trim().toUpperCase();

    if (turno.isEmpty || tipo.isEmpty || hasiera == null || amaiera == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bete eremu guztiak")),
      );
      return;
    }

    final minutos = _calcularMinutos();

    final turnoAnt = widget.turnoExistente?['turno']?.toString();
    final tipoAnt = widget.turnoExistente?['tipo']?.toString();

    await db.guardarTurno(
      turno: turno,
      tipo: tipo,
      hasiera: "${_formato(hasiera)}:00",
      amaiera: "${_formato(amaiera)}:00",
      lanOrduak: minutos,
      esManual: 1,
      turnoAnterior: turnoAnt,
      tipoAnterior: tipoAnt,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(esEdicion
            ? "$turno ($tipo) txanda ondo aldatu da"
            : "$turno ($tipo) txanda ondo sortu da"),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context, {
      'turno': turno,
      'tipo': tipo,
      'hasiera': "${_formato(hasiera)}:00",
      'amaiera': "${_formato(amaiera)}:00",
      'lan_orduak': minutos,
      'es_manual': 1,
    });
  }

  // =========================
  // ELIMINAR TURNO MANUAL
  // =========================
  Future<void> _eliminar() async {
    final turno = widget.turnoExistente?['turno']?.toString() ?? '';
    final tipo = widget.turnoExistente?['tipo']?.toString() ?? '';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$turno ($tipo) txanda ezabatu?"),
        content: const Text(
            "Eskuzko txanda hau zerrendatik ezabatuko da. Ekintza hau ezin da desegin."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Utzi"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Ezabatu"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await db.deleteTurnoManual(turno, tipo);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$turno ($tipo) txanda ezabatuta"),
        backgroundColor: Colors.red.shade700,
      ),
    );

    Navigator.pop(context, {'eliminado': true, 'turno': turno, 'tipo': tipo});
  }

  @override
  Widget build(BuildContext context) {
    final minutos = _calcularMinutos();

    return Scaffold(
      appBar: AppBar(
        title: Text(esEdicion ? "Eskuzko txanda aldatu" : "Txanda berria"),
        actions: [
          if (esEdicion)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: "Eskuzko txanda ezabatu",
              onPressed: _eliminar,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: turnoCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: "Txandaren izena",
                hintText: "Adib. T1, 101, M2...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: tipoCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: "Mota / Kategoria",
                hintText: "Adib. LAB, SDF, VERANO, etab.",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text("Hasiera ordua",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Text(
                        _formato(hasiera),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.access_time, size: 18),
                      label: const Text("Aukeratu"),
                      onPressed: () => _pickHora(true),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text("Amaiera ordua",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Text(
                        _formato(amaiera),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.access_time, size: 18),
                      label: const Text("Aukeratu"),
                      onPressed: () => _pickHora(false),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Aurreikusitako lanaldia:",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                    _formatearDuracion(minutos),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  esEdicion ? "Aldaketak gorde" : "Txanda sortu",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _guardar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
