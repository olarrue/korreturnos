import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../config/modo_app.dart';
import '../database/db_helper.dart';
import '../widgets/celda_dia.dart';
import 'ajustes.dart';

class CalendarioMensual extends StatefulWidget {
  const CalendarioMensual({super.key});

  @override
  State<CalendarioMensual> createState() => _CalendarioMensualState();
}

typedef CalendarioMensualScreen = CalendarioMensual;

class _CalendarioMensualState extends State<CalendarioMensual>
    with WidgetsBindingObserver {
  final db = DBHelper();

  DateTime fechaVista = DateTime.now();

  // Control deslizante para pasar de mes con el dedo (PageView)
  late PageController _pageController;
  static const int _paginaBase = 1200;
  late DateTime _fechaBase;

  int? semanaBaseReal;
  int? semanaBaseOrientativa;
  DateTime? fechaBase;

  // Cachés masivos precargados
  Map<String, Map<String, dynamic>> registrosCache = {};
  Map<String, Map<String, dynamic>> turnosCache = {};
  Map<String, int> coloresCache = {};
  Map<String, String> calendarioCache = {};
  List<Map<String, dynamic>> turnosLista = [];
  Set<String> alarmasFechasCache = {};
  Set<String> adjuntosFechasCache = {};
  Timer? _timerAlarmas;

  bool cargando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final ahora = DateTime.now();
    _fechaBase = DateTime(ahora.year, ahora.month, 1);
    fechaVista = _fechaBase;
    _pageController = PageController(initialPage: _paginaBase);

    inicializar();

    // Comprobar alarmas activas periódicamente cada 3 segundos para apagar campanitas
    _timerAlarmas = Timer.periodic(const Duration(seconds: 3), (_) async {
      final alarmasFechas = await db.getFechasConAlarmasActivas();
      if (!mounted) return;
      if (alarmasFechas.length != alarmasFechasCache.length ||
          !alarmasFechas.containsAll(alarmasFechasCache)) {
        setState(() {
          alarmasFechasCache = alarmasFechas;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerAlarmas?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      inicializar();
    }
  }

  DateTime _fechaParaPagina(int index) {
    int diff = index - _paginaBase;
    return DateTime(_fechaBase.year, _fechaBase.month + diff, 1);
  }

  int _paginaParaFecha(DateTime fecha) {
    int diff = (fecha.year - _fechaBase.year) * 12 + (fecha.month - _fechaBase.month);
    return _paginaBase + diff;
  }

  Future<void> inicializar() async {
    final semanas = await db.obtenerSemanas();
    if (semanas != null) {
      semanaBaseReal = semanas['semana_real_base'];
      semanaBaseOrientativa = semanas['semana_orientativa_base'];
      fechaBase = DateTime.parse(semanas['fecha_base']);
    }

    final regList = await db.getRegistrosMap();
    final turnList = await db.getTurnosMap();
    final colList = await db.getColoresTurno();
    final calList = await db.getCalendarioOrientativo();
    final turnosDisponibles = await db.getTurnos();
    final alarmasFechas = await db.getFechasConAlarmasActivas();
    final adjuntosFechas = await db.getFechasConAdjuntos();

    Map<String, String> calMap = {};
    for (var row in calList) {
      final s = row['semana'];
      final d = row['dia_semana'];
      final t = row['tipo']?.toString();
      if (s != null && d != null && t != null) {
        calMap["$s-$d"] = t;
      }
    }

    if (!mounted) return;

    setState(() {
      registrosCache = regList;
      turnosCache = turnList;
      coloresCache = colList;
      calendarioCache = calMap;
      turnosLista = turnosDisponibles;
      alarmasFechasCache = alarmasFechas;
      adjuntosFechasCache = adjuntosFechas;
      cargando = false;
    });
  }

  int _calcularSemanaISO(DateTime fecha) {
    DateTime fechaUtc = DateTime.utc(fecha.year, fecha.month, fecha.day);
    DateTime jueves = fechaUtc.add(Duration(days: 3 - (fechaUtc.weekday - 1)));
    DateTime primerDiaAnio = DateTime.utc(jueves.year, 1, 1);

    int diasPasados = jueves.difference(primerDiaAnio).inDays;
    return (diasPasados / 7).floor() + 1;
  }

  /// Calcula la semana orientativa (1-18) usando UTC para evitar desviaciones por cambio de hora (DST)
  int? calcularSemanaOrientativa(DateTime fecha) {
    if (fechaBase == null || semanaBaseOrientativa == null) return null;

    final fUtc = DateTime.utc(fecha.year, fecha.month, fecha.day);
    final bUtc = DateTime.utc(fechaBase!.year, fechaBase!.month, fechaBase!.day);
    int dias = fUtc.difference(bUtc).inDays;
    int semanas = (dias / 7).floor();

    return ((semanaBaseOrientativa! - 1 + semanas) % 18 + 18) % 18 + 1;
  }

  void _cambiarMes(int meses) {
    if (_pageController.hasClients) {
      final paginaActual = _pageController.page?.round() ?? _paginaBase;
      _pageController.animateToPage(
        paginaActual + meses,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );
    } else {
      setState(() {
        fechaVista = DateTime(fechaVista.year, fechaVista.month + meses, 1);
      });
    }
  }

  /// Calcula el total de minutos trabajados en el mes, incluyendo sumas y restas de jornada (+/- tiempo)
  int _calcularHorasMes(DateTime mes) {
    int totalMin = 0;

    for (var entry in registrosCache.entries) {
      final r = entry.value;
      final fechaStr = r['fecha']?.toString();
      if (fechaStr == null) continue;

      try {
        final f = DateTime.parse(fechaStr);
        if (f.year == mes.year && f.month == mes.month) {
          int diaMin = 0;

          // 1. Minutos base del turno asignado
          if (r['lan_orduak'] != null && (r['lan_orduak'] as num).toInt() > 0) {
            diaMin = (r['lan_orduak'] as num).toInt();
          } else if (r['lan_horduak'] != null && (r['lan_horduak'] as num).toInt() > 0) {
            diaMin = (r['lan_horduak'] as num).toInt();
          } else {
            final turno = r['turno']?.toString();
            final tipo = r['tipo']?.toString() ?? '';
            final tInfo = turnosCache["$turno-$tipo"] ?? turnosCache[turno];

            if (tInfo != null && tInfo['lan_orduak'] != null && (tInfo['lan_orduak'] as num).toInt() > 0) {
              diaMin = (tInfo['lan_orduak'] as num).toInt();
            } else if (tInfo != null && tInfo['lan_horduak'] != null && (tInfo['lan_horduak'] as num).toInt() > 0) {
              diaMin = (tInfo['lan_horduak'] as num).toInt();
            } else if (tInfo != null) {
              final h1 = tInfo['hasiera']?.toString();
              final h2 = tInfo['amaiera']?.toString();
              if (h1 != null && h2 != null && h1.isNotEmpty && h2.isNotEmpty) {
                final p1 = h1.split(":");
                final p2 = h2.split(":");
                if (p1.length >= 2 && p2.length >= 2) {
                  final min1 = (int.tryParse(p1[0]) ?? 0) * 60 + (int.tryParse(p1[1]) ?? 0);
                  int min2 = (int.tryParse(p2[0]) ?? 0) * 60 + (int.tryParse(p2[1]) ?? 0);
                  if (min2 < min1) min2 += 24 * 60;
                  diaMin = min2 - min1;
                }
              }
            }
          }

          // 2. 🔥 SUMAR O RESTAR EL AJUSTE DEL DÍA (+ alargamientos, - retrasos)
          final ajuste = (r['ajuste_minutos'] as num?)?.toInt() ?? 0;
          diaMin += ajuste;

          if (diaMin > 0) {
            totalMin += diaMin;
          }
        }
      } catch (_) {}
    }

    return totalMin;
  }

  /// Calcula el balance neto de ajustes en minutos del mes
  int _calcularAjusteTotalMes(DateTime mes) {
    int totalAjuste = 0;

    for (var entry in registrosCache.entries) {
      final r = entry.value;
      final fechaStr = r['fecha']?.toString();
      if (fechaStr == null) continue;

      try {
        final f = DateTime.parse(fechaStr);
        if (f.year == mes.year && f.month == mes.month) {
          final ajuste = (r['ajuste_minutos'] as num?)?.toInt() ?? 0;
          totalAjuste += ajuste;
        }
      } catch (_) {}
    }

    return totalAjuste;
  }

  /// Método para que familiares actualicen el calendario cargando la copia (.db)
  Future<void> _importarCopiaFamiliar() async {
    try {
      final archivoSeleccionado = await FilePicker.pickFile(
        dialogTitle: "Hautatu segurtasun-kopiaren fitxategia (.db)",
        type: FileType.any,
      );

      if (archivoSeleccionado == null || archivoSeleccionado.path == null) {
        return;
      }

      setState(() => cargando = true);

      await db.restaurarDatabaseDesde(archivoSeleccionado.path!);
      await inicializar();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Familiako egutegia ondo eguneratu da!"),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Errorea eguneratzean"),
          content: Text(
            "Ezin izan da segurtasun-kopia kargatu:\n$e\n\nZiurtatu baliozko .db fitxategi bat hautatzen duzula.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Ulertuta"),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  Widget _construirMes(DateTime fechaMes) {
    final primerDiaMes = DateTime(fechaMes.year, fechaMes.month, 1);
    final ultimoDiaMes = DateTime(fechaMes.year, fechaMes.month + 1, 0);

    // Inicio de la cuadrícula en lunes (utilizando aritmética de fechas pura sin Duration para evitar anomalías DST)
    DateTime inicio = DateTime(
      primerDiaMes.year,
      primerDiaMes.month,
      primerDiaMes.day - (primerDiaMes.weekday - 1),
    );

    List<Widget> semanasWidgets = [];

    while (
        inicio.isBefore(ultimoDiaMes) || inicio.month == ultimoDiaMes.month) {
      semanasWidgets.add(_filaSemana(inicio, fechaMes));
      // Avanzar 7 días de forma exacta independientemente de días de 23h o 25h por cambio de hora
      inicio = DateTime(inicio.year, inicio.month, inicio.day + 7);
      if (inicio.month > ultimoDiaMes.month && inicio.weekday == 1) break;
    }

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 2),
      children: semanasWidgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalMin = _calcularHorasMes(fechaVista);
    final h = (totalMin / 60).floor();
    final m = totalMin % 60;
    final totalAjuste = _calcularAjusteTotalMes(fechaVista);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${_nombreMes(fechaVista.month)} ${fechaVista.year}",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: "Gaurko egunera joan",
            icon: const Icon(Icons.today),
            onPressed: () {
              final hoy = DateTime.now();
              final pagHoy = _paginaParaFecha(hoy);
              if (_pageController.hasClients) {
                _pageController.animateToPage(
                  pagHoy,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              } else {
                setState(() => fechaVista = hoy);
              }
            },
          ),
          if (ModoApp.esFamiliar)
            IconButton(
              tooltip: "Egutegia eguneratu (kopia kargatu)",
              icon: const Icon(Icons.sync_rounded),
              onPressed: _importarCopiaFamiliar,
            )
          else
            IconButton(
              tooltip: "Ezarpenak",
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AjustesScreen()),
                );
                await inicializar();
              },
            ),
        ],
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Selector de mes con flechas y detección de deslizamiento horizontal
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity == null) return;
                    if (details.primaryVelocity! < -150) {
                      _cambiarMes(1);
                    } else if (details.primaryVelocity! > 150) {
                      _cambiarMes(-1);
                    }
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 28),
                          onPressed: () => _cambiarMes(-1),
                        ),
                        Text(
                          "${_nombreMes(fechaVista.month).toUpperCase()} ${fechaVista.year}",
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 28),
                          onPressed: () => _cambiarMes(1),
                        ),
                      ],
                    ),
                  ),
                ),

                // Cabecera de días alineada exactamente con las celdas
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Espacio exacto para coincidir con la columna de semanas (40dp)
                      const SizedBox(
                        width: 40,
                        child: Center(
                          child: Text(
                            "AST",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ),

                      // Columnas de días de la semana
                      ...["L", "M", "X", "J", "V", "S", "D"].map(
                        (d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: (d == "S" || d == "D")
                                    ? Colors.red.shade400
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Rejilla de semanas y días con deslizamiento horizontal suave con el dedo (PageView)
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        fechaVista = _fechaParaPagina(index);
                      });
                    },
                    itemBuilder: (context, index) {
                      final fechaMes = _fechaParaPagina(index);
                      return _construirMes(fechaMes);
                    },
                  ),
                ),

                // Barra inferior de horas con suma de ajustes incluida
                SafeArea(
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E1E1E),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          offset: Offset(0, -1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      totalAjuste != 0
                          ? "Hileko orduak: $h h ${m.toString().padLeft(2, '0')} min  (${totalAjuste > 0 ? '+$totalAjuste' : '$totalAjuste'} min doik.)"
                          : "Hileko orduak: $h h ${m.toString().padLeft(2, '0')} min",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _filaSemana(DateTime inicioSemana, DateTime fechaMes) {
    final semanaISO = _calcularSemanaISO(inicioSemana);
    final semanaOrientativa = calcularSemanaOrientativa(inicioSemana);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Columna de semanas (exactamente 40dp de ancho)
          Container(
            width: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade300, width: 0.8),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "$semanaISO",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (semanaOrientativa != null)
                  Text(
                    "($semanaOrientativa)",
                    style: TextStyle(
                      fontSize: 9.5,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),

          // Celdas de los 7 días (construcción con año/mes/día exacto para evitar duplicidades por DST)
          ...List.generate(7, (i) {
            final dia = DateTime(
              inicioSemana.year,
              inicioSemana.month,
              inicioSemana.day + i,
            );
            final diaStr = "${dia.year.toString().padLeft(4, '0')}-"
                "${dia.month.toString().padLeft(2, '0')}-"
                "${dia.day.toString().padLeft(2, '0')}";

            final String? tipoOrientativo = semanaOrientativa != null
                ? calendarioCache["$semanaOrientativa-${dia.weekday}"]
                : null;

            final reg = registrosCache[diaStr];
            Map<String, dynamic>? turnoData;
            if (reg != null) {
              final turno = reg['turno']?.toString();
              final tipo = reg['tipo']?.toString() ?? '';
              turnoData = turnosCache["$turno-$tipo"] ?? turnosCache[turno];
            }

            return Expanded(
              child: CeldaDia(
                key: ValueKey(diaStr),
                fecha: dia,
                semanaOrientativa: semanaOrientativa,
                tipoOrientativo: tipoOrientativo,
                registro: reg,
                turnoData: turnoData,
                coloresDB: coloresCache,
                turnosDisponibles: turnosLista,
                esMesActual: dia.month == fechaMes.month,
                tieneAlarmaActiva: alarmasFechasCache.contains(diaStr),
                tieneAdjuntos: adjuntosFechasCache.contains(diaStr),
                onRefresh: inicializar,
              ),
            );
          }),
        ],
      ),
    );
  }

  String _nombreMes(int mes) {
    return [
      "Urtarrila",
      "Otsaila",
      "Martxoa",
      "Apirila",
      "Maiatza",
      "Ekaina",
      "Uztaila",
      "Abuztua",
      "Iraila",
      "Urria",
      "Azaroa",
      "Abendua"
    ][mes - 1];
  }
}
