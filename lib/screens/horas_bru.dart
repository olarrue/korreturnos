import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class HorasBruScreen extends StatefulWidget {
  const HorasBruScreen({super.key});

  @override
  State<HorasBruScreen> createState() => _HorasBruScreenState();
}

class _HorasBruScreenState extends State<HorasBruScreen> {
  final db = DBHelper();
  List<Map<String, dynamic>> _diasBru = [];
  Map<String, Map<String, dynamic>> _turnosCache = {};
  bool _cargando = true;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final lista = await db.getDiasBru();
    final tMap = await db.getTurnosMap();

    if (!mounted) return;
    setState(() {
      _diasBru = lista;
      _turnosCache = tMap;
      _cargando = false;
    });
  }

  String _horaCorta(String? h) {
    if (h == null || h.isEmpty) return "";
    return h.length >= 5 ? h.substring(0, 5) : h;
  }

  int _calcularMinutosDia(Map<String, dynamic> r) {
    int diaMin = 0;
    final regHasiera = r['hasiera']?.toString() ?? '';
    final regAmaiera = r['amaiera']?.toString() ?? '';

    if (r['lan_orduak'] != null && (r['lan_orduak'] as num).toInt() > 0) {
      diaMin = (r['lan_orduak'] as num).toInt();
    } else if (regHasiera.isNotEmpty && regAmaiera.isNotEmpty) {
      final p1 = regHasiera.split(":");
      final p2 = regAmaiera.split(":");
      if (p1.length >= 2 && p2.length >= 2) {
        final min1 =
            (int.tryParse(p1[0]) ?? 0) * 60 + (int.tryParse(p1[1]) ?? 0);
        int min2 =
            (int.tryParse(p2[0]) ?? 0) * 60 + (int.tryParse(p2[1]) ?? 0);
        if (min2 < min1) min2 += 24 * 60;
        diaMin = min2 - min1;
      }
    } else {
      final turno = r['turno']?.toString() ?? '';
      final tipo = r['tipo']?.toString() ?? '';
      final tInfo = _turnosCache["$turno-$tipo"] ?? _turnosCache[turno];
      if (tInfo != null &&
          tInfo['lan_orduak'] != null &&
          (tInfo['lan_orduak'] as num).toInt() > 0) {
        diaMin = (tInfo['lan_orduak'] as num).toInt();
      } else if (tInfo != null) {
        final h1 = tInfo['hasiera']?.toString() ?? '';
        final h2 = tInfo['amaiera']?.toString() ?? '';
        if (h1.isNotEmpty && h2.isNotEmpty) {
          final p1 = h1.split(":");
          final p2 = h2.split(":");
          if (p1.length >= 2 && p2.length >= 2) {
            final min1 =
                (int.tryParse(p1[0]) ?? 0) * 60 + (int.tryParse(p1[1]) ?? 0);
            int min2 =
                (int.tryParse(p2[0]) ?? 0) * 60 + (int.tryParse(p2[1]) ?? 0);
            if (min2 < min1) min2 += 24 * 60;
            diaMin = min2 - min1;
          }
        }
      }
    }

    final ajuste = (r['ajuste_minutos'] as num?)?.toInt() ?? 0;
    diaMin += ajuste;
    return diaMin > 0 ? diaMin : 0;
  }

  String _formatearMinutos(int min) {
    final h = min ~/ 60;
    final m = min % 60;
    if (h > 0 && m > 0) return "${h}h ${m}min";
    if (h > 0) return "${h}h";
    return "${m}min";
  }

  Future<void> _seleccionarDia() async {
    final ahora = DateTime.now();
    final fechaElegida = await showDatePicker(
      context: context,
      initialDate: ahora,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: "Hautatu BRU eguna",
      cancelText: "Utzi",
      confirmText: "Aukeratu",
    );

    if (fechaElegida == null || !mounted) return;

    final fechaStr = "${fechaElegida.year.toString().padLeft(4, '0')}-"
        "${fechaElegida.month.toString().padLeft(2, '0')}-"
        "${fechaElegida.day.toString().padLeft(2, '0')}";

    final reg = await db.getTurnoPorFecha(fechaStr);
    if (!mounted) return;

    if (reg == null || (reg['turno']?.toString() ?? '').isEmpty) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Txandarik gabe"),
          content: Text(
              "Aukeratutako egunak ($fechaStr) ez du txandarik esleituta egutegian."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Ulertuta"),
            ),
          ],
        ),
      );
      return;
    }

    final turno = reg['turno']?.toString() ?? '';
    final tipo = reg['tipo']?.toString() ?? '';
    final yaEsBru = ((reg['es_bru'] as num?)?.toInt() ?? 0) == 1;

    if (yaEsBru) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$fechaStr eguna dagoeneko BRU gisa markatuta dago."),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    final minutosDia = _calcularMinutosDia(reg);
    final horasTexto = _formatearMinutos(minutosDia);

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("BRU orduak"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Eguna: $fechaStr",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Txanda: $turno ($tipo)  ·  Lan-orduak: $horasTexto",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.purple.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "Egun hau ez da ordu guztien zenbaketan kontuan hartuko, eta egun horretan lan egindako orduak zenbaketa orokorretik kenduko dira.",
              style: TextStyle(fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 10),
            const Text(
              "Ados zaude?",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Utzi"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Bai, kendu orduak"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await db.setDiaBru(fechaStr, true);
    _huboCambios = true;
    await _cargarDatos();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$fechaStr ($turno) BRU gisa markatu da (-$horasTexto)"),
        backgroundColor: Colors.purple.shade700,
      ),
    );
  }

  Future<void> _quitarDiaBru(Map<String, dynamic> reg) async {
    final fechaStr = reg['fecha']?.toString() ?? '';
    final turno = reg['turno']?.toString() ?? '';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("BRU marka kendu?"),
        content: Text(
            "$fechaStr ($turno) eguneko orduak berriro hileko zenbaketa orokorrean kontuan hartuko dira."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Utzi"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Berreskuratu"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    await db.setDiaBru(fechaStr, false);
    _huboCambios = true;
    await _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _huboCambios),
          ),
          title: const Text("BRU orduak"),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner informativo
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.purple.shade800, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Hautatu egutegiko egun bat BRU gisa markatzeko. Egun horretako lan-orduak ez dira hileko ordu guztien zenbaketan kontuan hartuko.",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.purple.shade900,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Botón para añadir día BRU
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.event_available_outlined),
                        label: const Text(
                          "Hautatu egutegiko eguna",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _seleccionarDia,
                      ),
                    ),

                    const SizedBox(height: 22),
                    Text(
                      "Markatutako BRU egunak (${_diasBru.length})",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Expanded(
                      child: _diasBru.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.event_busy_outlined,
                                      size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 10),
                                  Text(
                                    "Ez dago BRU egunik markatuta",
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _diasBru.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final reg = _diasBru[i];
                                final fecha = reg['fecha']?.toString() ?? '';
                                final turno = reg['turno']?.toString() ?? '';
                                final tipo = reg['tipo']?.toString() ?? '';
                                final minDia = _calcularMinutosDia(reg);
                                final horasStr = _formatearMinutos(minDia);

                                String hIni = _horaCorta(reg['hasiera']?.toString());
                                String hFin = _horaCorta(reg['amaiera']?.toString());
                                if (hIni.isEmpty || hFin.isEmpty) {
                                  final tInfo = _turnosCache["$turno-$tipo"] ??
                                      _turnosCache[turno];
                                  hIni = _horaCorta(
                                      tInfo?['hasiera']?.toString());
                                  hFin = _horaCorta(
                                      tInfo?['amaiera']?.toString());
                                }

                                return Card(
                                  elevation: 1,
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                        color: Colors.purple.shade200),
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade700,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        "BRU",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      "$fecha  ·  Txanda $turno ($tipo)",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    subtitle: Text(
                                      "${hIni.isNotEmpty && hFin.isNotEmpty ? '$hIni - $hFin  ·  ' : ''}Kendutako orduak: -$horasStr",
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.purple.shade900,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      tooltip: "Kendu BRU marka",
                                      onPressed: () => _quitarDiaBru(reg),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
