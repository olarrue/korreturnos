import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class ColoresTurnoScreen extends StatefulWidget {
  const ColoresTurnoScreen({super.key});

  @override
  State<ColoresTurnoScreen> createState() => _ColoresTurnoScreenState();
}

class _ColoresTurnoScreenState extends State<ColoresTurnoScreen> {
  final db = DBHelper();

  List<Map<String, dynamic>> turnosLAB = [];
  List<Map<String, dynamic>> turnosSDF = [];
  List<Map<String, dynamic>> turnosOtros = [];
  Map<String, Color> colores = {};
  bool cargando = true;

  // 🎨 Paleta amplia de más de 45 colores variados y bien distribuidos
  static const List<Color> paletaColores = [
    // Rojos y Burdeos
    Color(0xFFD32F2F),
    Color(0xFFB71C1C),
    Color(0xFFEF5350),
    Color(0xFF880E4F),
    // Rosas y Magentas
    Color(0xFFE91E63),
    Color(0xFFC2185B),
    Color(0xFFFF4081),
    Color(0xFFF48FB1),
    // Púrpuras y Violetas
    Color(0xFF9C27B0),
    Color(0xFF7B1FA2),
    Color(0xFF673AB7),
    Color(0xFF512DA8),
    Color(0xFF7E57C2),
    Color(0xFFB388FF),
    // Índigos y Azules Oscuros
    Color(0xFF3F51B5),
    Color(0xFF283593),
    Color(0xFF1A237E),
    Color(0xFF303F9F),
    // Azules y Celestes
    Color(0xFF1E88E5),
    Color(0xFF1565C0),
    Color(0xFF0288D1),
    Color(0xFF03A9F4),
    Color(0xFF4FC3F7),
    Color(0xFF00B0FF),
    // Cianes y Teals
    Color(0xFF00BCD4),
    Color(0xFF00838F),
    Color(0xFF009688),
    Color(0xFF004D40),
    Color(0xFF26A69A),
    Color(0xFF80CBC4),
    // Verdes
    Color(0xFF4CAF50),
    Color(0xFF2E7D32),
    Color(0xFF1B5E20),
    Color(0xFF81C784),
    Color(0xFF00E676),
    Color(0xFF69F0AE),
    // Lima y Amarillos
    Color(0xFF8BC34A),
    Color(0xFF558B2F),
    Color(0xFFCDDC39),
    Color(0xFF9E9D24),
    Color(0xFFFFEB3B),
    Color(0xFFFBC02D),
    // Ámbares y Naranjas
    Color(0xFFFFC107),
    Color(0xFFFFA000),
    Color(0xFFFF9800),
    Color(0xFFF57C00),
    Color(0xFFFF5722),
    Color(0xFFD84315),
    // Marrones y Tierras
    Color(0xFF795548),
    Color(0xFF4E342E),
    Color(0xFF8D6E63),
    Color(0xFFA1887F),
    // Grises y Azulados
    Color(0xFF607D8B),
    Color(0xFF37474F),
    Color(0xFF78909C),
    Color(0xFF9E9E9E),
    Color(0xFF424242),
    Color(0xFF263238),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final turnosDB = await db.getTurnos();
    final coloresDB = await db.getColoresTurno();

    List<Map<String, dynamic>> lab = [];
    List<Map<String, dynamic>> sdf = [];
    List<Map<String, dynamic>> otros = [];
    Map<String, Color> mapa = {};

    for (var t in turnosDB) {
      final turno = t['turno']?.toString() ?? '';
      final tipo = t['tipo']?.toString().toUpperCase() ?? '';
      final key = "$turno-$tipo";

      final item = {
        "turno": turno,
        "tipo": tipo,
        "hasiera": t['hasiera']?.toString() ?? '',
        "amaiera": t['amaiera']?.toString() ?? '',
      };

      if (tipo == 'LAB') {
        lab.add(item);
      } else if (tipo == 'SDF') {
        sdf.add(item);
      } else {
        otros.add(item);
      }

      if (coloresDB.containsKey(key)) {
        mapa[key] = Color(coloresDB[key]!);
      } else {
        mapa[key] = Colors.blueGrey;
      }
    }

    // Ordenar alfabéticamente por turno
    lab.sort((a, b) => (a['turno'] as String).compareTo(b['turno'] as String));
    sdf.sort((a, b) => (a['turno'] as String).compareTo(b['turno'] as String));
    otros.sort((a, b) => (a['turno'] as String).compareTo(b['turno'] as String));

    if (!mounted) return;

    setState(() {
      turnosLAB = lab;
      turnosSDF = sdf;
      turnosOtros = otros;
      colores = mapa;
      cargando = false;
    });
  }

  String _horaCorta(String h) {
    if (h.isEmpty) return "";
    return h.length >= 5 ? h.substring(0, 5) : h;
  }

  Color _contrasteTexto(Color bg) {
    return bg.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
  }

  void _selectorColor(String turno, String tipo, String hasiera, String amaiera) {
    final key = "$turno-$tipo";
    Color colorActual = colores[key] ?? Colors.blueGrey;
    final esLAB = tipo == 'LAB';
    final esSDF = tipo == 'SDF';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final textColor = _contrasteTexto(colorActual);

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Kolorea: $turno txanda",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: esLAB
                            ? Colors.indigo.shade50
                            : (esSDF ? Colors.deepOrange.shade50 : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: esLAB
                              ? Colors.indigo.shade300
                              : (esSDF ? Colors.deepOrange.shade300 : Colors.grey.shade400),
                        ),
                      ),
                      child: Text(
                        esLAB ? "LAB · Laneguna" : (esSDF ? "SDF · Jaieguna" : tipo),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: esLAB
                              ? Colors.indigo.shade900
                              : (esSDF ? Colors.deepOrange.shade900 : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Previsualización en vivo
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: colorActual,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Aurreikuspena: $turno ($tipo)",
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (hasiera.isNotEmpty && amaiera.isNotEmpty)
                        Text(
                          "${_horaCorta(hasiera)} - ${_horaCorta(amaiera)}",
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  alignment: WrapAlignment.center,
                  children: paletaColores.map((c) {
                    final isSelected = c.toARGB32() == colorActual.toARGB32();
                    final checkColor = _contrasteTexto(c);

                    return GestureDetector(
                      onTap: () async {
                        final nav = Navigator.of(dialogCtx);
                        await db.guardarColorTurno(
                          turno,
                          tipo,
                          c.toARGB32(),
                        );

                        if (!mounted) return;

                        setState(() {
                          colores["$turno-$tipo"] = c;
                        });

                        nav.pop();
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.black12,
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                        child: isSelected
                            ? Icon(Icons.check, size: 20, color: checkColor)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text("Utzi"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> lista, String tipoTexto, String descripcion) {
    if (lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                "Ez dago txandarik erregistratuta ($tipoTexto)",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Banner explicativo superior
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.blueGrey.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  descripcion,
                  style: TextStyle(fontSize: 12.5, color: Colors.blueGrey.shade900),
                ),
              ),
            ],
          ),
        ),

        // Cuadrícula de turnos
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final int crossAxisCount = constraints.maxWidth > 700
                  ? 4
                  : (constraints.maxWidth > 480 ? 3 : 2);

              return GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.1,
                ),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final item = lista[i];
                  final turno = item['turno'] as String;
                  final tipo = item['tipo'] as String;
                  final hasiera = item['hasiera'] as String;
                  final amaiera = item['amaiera'] as String;
                  final key = "$turno-$tipo";

                  final bg = colores[key] ?? Colors.blueGrey;
                  final textColor = _contrasteTexto(bg);
                  final esLAB = tipo == 'LAB';
                  final esSDF = tipo == 'SDF';

                  return GestureDetector(
                    onTap: () => _selectorColor(turno, tipo, hasiera, amaiera),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                turno,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: textColor,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      esLAB ? Icons.work_outline : (esSDF ? Icons.weekend_outlined : Icons.calendar_today),
                                      size: 11,
                                      color: textColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      tipo,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (hasiera.isNotEmpty && amaiera.isNotEmpty)
                                Text(
                                  "${_horaCorta(hasiera)} - ${_horaCorta(amaiera)}",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: textColor.withValues(alpha: 0.9),
                                  ),
                                )
                              else
                                const SizedBox(),
                              Icon(
                                Icons.palette_outlined,
                                size: 15,
                                color: textColor.withValues(alpha: 0.8),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text("Txanden koloreak")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final tieneOtros = turnosOtros.isNotEmpty;
    final int tabsCount = tieneOtros ? 3 : 2;

    return DefaultTabController(
      length: tabsCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Txanden koloreak"),
          bottom: TabBar(
            indicatorColor: Colors.amber.shade800,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(
                icon: const Icon(Icons.work_outline, size: 20),
                text: "LAB (${turnosLAB.length})",
              ),
              Tab(
                icon: const Icon(Icons.weekend_outlined, size: 20),
                text: "SDF (${turnosSDF.length})",
              ),
              if (tieneOtros)
                Tab(
                  icon: const Icon(Icons.more_horiz, size: 20),
                  text: "Besteak (${turnosOtros.length})",
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildGrid(
              turnosLAB,
              "LAB",
              "Lanegunetako txandak (Astelehenetik Ostiralera). Sakatu edozein txanda bere kolorea aldatzeko.",
            ),
            _buildGrid(
              turnosSDF,
              "SDF",
              "Asteburu eta Jaiegunetako txandak (Larunbat, Igande eta Jaiegunak). Sakatu edozein txanda bere kolorea aldatzeko.",
            ),
            if (tieneOtros)
              _buildGrid(
                turnosOtros,
                "Besteak",
                "Txanda bereziak edo beste izendapen batzuk dituztenak.",
              ),
          ],
        ),
      ),
    );
  }
}
