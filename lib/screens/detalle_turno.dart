import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../config/modo_app.dart';
import '../database/db_helper.dart';
import '../widgets/celda_dia.dart';
import 'incidencia_dia.dart';
import 'nuevo_turno.dart';

class DetalleTurno extends StatefulWidget {
  final String turno;
  final String tipo;
  final String fecha;
  final bool soloLectura;

  const DetalleTurno({
    super.key,
    required this.turno,
    required this.tipo,
    required this.fecha,
    this.soloLectura = false,
  });

  @override
  State<DetalleTurno> createState() => _DetalleTurnoState();
}

class _DetalleTurnoState extends State<DetalleTurno>
    with WidgetsBindingObserver {
  final db = DBHelper();

  List<Map<String, dynamic>> servicios = [];
  Map<String, dynamic>? turnoDataInfo;
  String? hasiera;
  String? amaiera;
  String observaciones = '';
  int ajusteMinutos = 0;
  bool tieneNota = false;
  bool _huboCambios = false;
  Map<String, Map<String, String>> alarmasActivadas = {};
  Timer? _tickerTimer;
  static const MethodChannel _iosAlarmaChannel =
      MethodChannel('korreturnos/ios_alarmas');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarDatos();

    // Actualización rápida cada 1 segundo para apagar el dorado inmediatamente al sonar
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _purgarAlarmasSonadas();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver a la app tras parar o borrar la alarma en Google Reloj, refrescamos al instante
      _purgarAlarmasSonadas();
    }
  }

  /// Revisa todas las alarmas en memoria y purga las que ya hayan sonado
  Future<void> _purgarAlarmasSonadas() async {
    if (!mounted) return;

    bool huboAlarmaSonada = false;
    final aBorrar = <String>[];

    for (var entry in alarmasActivadas.entries) {
      final clave = entry.key;
      final info = entry.value;
      final horaAlarma = info['hora_alarma'];
      final fechaDisparo = info['fecha_disparo'];

      final partes = clave.split("|||");
      final nombreServ = partes[0];
      final horaSalida = partes.length > 1 ? partes[1] : "";

      if (_haSonadoAlarma(
        horaAlarma: horaAlarma,
        horaSalida: horaSalida,
        fechaDisparo: fechaDisparo,
      )) {
        aBorrar.add(clave);
        await db.eliminarAlarmaActivada(widget.fecha, nombreServ, horaSalida);
        huboAlarmaSonada = true;
      }
    }

    if (aBorrar.isNotEmpty) {
      for (var k in aBorrar) {
        alarmasActivadas.remove(k);
      }
    }

    if (huboAlarmaSonada) {
      _huboCambios = true;
    }

    if (mounted) setState(() {});
  }

  Future<void> _cargarDatos() async {
    final data = await db.getServiciosPorTurno(widget.turno, widget.tipo);
    // Buscamos el turno filtrando exactamente por nombre y tipo (LAB, SDF, etc.)
    final tData = await db.getTurno(widget.turno, widget.tipo);
    final reg = await db.getTurnoPorFecha(widget.fecha);
    final alarmas = await db.getAlarmasActivadas(widget.fecha);
    final adjuntos = await db.getAdjuntosPorFecha(widget.fecha);

    if (!mounted) return;

    final obs = reg?['observaciones']?.toString() ?? '';
    final aj = (reg?['ajuste_minutos'] as num?)?.toInt() ?? 0;
    final regH = reg?['hasiera']?.toString() ?? '';
    final regA = reg?['amaiera']?.toString() ?? '';
    final regLan = (reg?['lan_orduak'] as num?)?.toInt() ?? 0;

    final mergedTurnoInfo = <String, dynamic>{
      if (tData != null) ...tData,
      'turno': widget.turno,
      'tipo': widget.tipo,
      if (regH.isNotEmpty) 'hasiera': regH,
      if (regA.isNotEmpty) 'amaiera': regA,
      if (regLan > 0) 'lan_orduak': regLan,
    };

    setState(() {
      servicios = data;
      turnoDataInfo = mergedTurnoInfo;
      hasiera = mergedTurnoInfo['hasiera']?.toString();
      amaiera = mergedTurnoInfo['amaiera']?.toString();
      observaciones = obs;
      ajusteMinutos = aj;
      tieneNota = obs.trim().isNotEmpty || aj != 0 || adjuntos.isNotEmpty;
      alarmasActivadas = alarmas;
    });
  }

  String _horaCorta(String? h) {
    if (h == null || h.isEmpty) return "";
    return h.length >= 5 ? h.substring(0, 5) : h;
  }

  bool _esDescanso(String servicio) {
    final s = servicio.toUpperCase();
    return s.contains("GELTOKIAREN") || s.contains("ATSENALDIA");
  }

  int _toMinutos(String h) {
    final parts = h.split(":");
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Comprueba si la alarma ya ha sonado (ha llegado o pasado su hora)
  bool _haSonadoAlarma({
    required String? horaAlarma,
    required String horaSalida,
    String? fechaDisparo,
  }) {
    final ahora = DateTime.now();

    // 1. Verificación precisa por timestamp exacto de disparo
    if (fechaDisparo != null && fechaDisparo.isNotEmpty) {
      try {
        final fd = DateTime.parse(fechaDisparo);
        if (!ahora.isBefore(fd)) return true;
      } catch (_) {}
    }

    if (widget.fecha.isEmpty) return false;

    final hoyStr =
        "${ahora.year.toString().padLeft(4, '0')}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";

    // Si la fecha del turno es un día anterior a hoy, la alarma ya sonó
    final compFecha = widget.fecha.compareTo(hoyStr);
    if (compFecha < 0) return true;

    // Hora efectiva en que debe sonar (HH:mm)
    final horaEfectiva =
        (horaAlarma != null && horaAlarma.isNotEmpty) ? horaAlarma : horaSalida;
    final partes = horaEfectiva.split(":");
    if (partes.length < 2) return false;

    final h = int.tryParse(partes[0]) ?? 0;
    final m = int.tryParse(partes[1]) ?? 0;
    final alarmaMin = h * 60 + m;
    final ahoraMin = ahora.hour * 60 + ahora.minute;

    // Si el turno es de hoy: ha sonado si la hora actual es mayor o igual
    if (compFecha == 0) {
      return ahoraMin >= alarmaMin;
    }

    return false;
  }

  /// Indica si la alarma debe mostrarse dorada y activa
  bool _esAlarmaActiva(
      String claveAlarma, String? horaAlarma, String horaSalida,
      {String? fechaDisparo}) {
    if (!alarmasActivadas.containsKey(claveAlarma)) return false;
    return !_haSonadoAlarma(
      horaAlarma: horaAlarma,
      horaSalida: horaSalida,
      fechaDisparo: fechaDisparo,
    );
  }

  /// Calcula el índice del servicio o descanso en curso con máxima precisión
  int? _indiceActual() {
    if (servicios.isEmpty) return null;

    final ahora = TimeOfDay.now();
    final ahoraMin = ahora.hour * 60 + ahora.minute;

    // 1. Obtener rangos [inicio, fin] de cada fila (servicios y descansos)
    List<_RangoServicio> rangos = [];

    for (int i = 0; i < servicios.length; i++) {
      final s = servicios[i];
      final servicioNom = s['servicio']?.toString() ?? '';
      final esDescanso = _esDescanso(servicioNom);

      int? ini;
      int? fin;

      if (esDescanso || s['irteera_ordua'] == null) {
        // En los descansos: el inicio es la llegada del servicio previo
        if (i > 0 && servicios[i - 1]['helmuga_ordua'] != null) {
          ini = _toMinutos(servicios[i - 1]['helmuga_ordua'].toString());
        }
        // El fin es la salida del servicio siguiente
        if (i + 1 < servicios.length &&
            servicios[i + 1]['irteera_ordua'] != null) {
          fin = _toMinutos(servicios[i + 1]['irteera_ordua'].toString());
        }
      } else {
        if (s['irteera_ordua'] != null &&
            s['irteera_ordua'].toString().isNotEmpty) {
          ini = _toMinutos(s['irteera_ordua'].toString());
        }
        if (s['helmuga_ordua'] != null &&
            s['helmuga_ordua'].toString().isNotEmpty) {
          fin = _toMinutos(s['helmuga_ordua'].toString());
        }
      }

      rangos.add(_RangoServicio(i, ini, fin, esDescanso));
    }

    // 2. Normalización para turnos que cruzan medianoche
    int baseMin = 0;
    for (var r in rangos) {
      if (r.inicio != null) {
        baseMin = r.inicio!;
        break;
      }
    }

    int curAhora = ahoraMin;
    if (curAhora < baseMin - 120 && hasiera != null && amaiera != null) {
      final hIni = _toMinutos(hasiera!);
      final hFin = _toMinutos(amaiera!);
      if (hFin < hIni) {
        curAhora += 24 * 60;
      }
    }

    // A) Comprobar si estamos exactamente dentro del rango [ini, fin] de algún servicio o descanso
    for (int i = 0; i < rangos.length; i++) {
      final r = rangos[i];
      int? ini = r.inicio;
      int? fin = r.fin;

      if (ini != null && ini < baseMin - 120) ini += 24 * 60;
      if (fin != null && fin < baseMin - 120) fin += 24 * 60;
      if (ini != null && fin != null && fin < ini) fin += 24 * 60;

      if (ini != null && fin != null && curAhora >= ini && curAhora < fin) {
        return i;
      }
    }

    // B) Si no estamos en ninguno en marcha, buscar el próximo inminente que va a comenzar
    for (int i = 0; i < rangos.length; i++) {
      final r = rangos[i];
      int? ini = r.inicio;
      if (ini != null && ini < baseMin - 120) ini += 24 * 60;

      if (ini != null && curAhora < ini) {
        return i;
      }
    }

    // C) Si ya pasaron todas las horas del turno, destacar el último servicio de la jornada
    return servicios.length - 1;
  }

  // =====================================================
  // 🔔 GESTIÓN Y POPUP DE ALARMA EN GOOGLE RELOJ
  // =====================================================

  Future<void> _gestionarAlarma(
      String horaServicio, String nombreServicio, String claveAlarma) async {
    final infoAlarma = alarmasActivadas[claveAlarma];
    final horaAlarma = infoAlarma?['hora_alarma'];
    final fechaDisparo = infoAlarma?['fecha_disparo'];
    final yaActivada = _esAlarmaActiva(
      claveAlarma,
      horaAlarma,
      horaServicio,
      fechaDisparo: fechaDisparo,
    );

    if (yaActivada) {
      final messenger = ScaffoldMessenger.of(context);
      final accion = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.alarm_on_rounded,
                        color: Colors.amber.shade900, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Google Erlojuko alarma",
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "$nombreServicio · Irteera: ${_horaCorta(horaServicio)}"
                            "${horaAlarma != null && horaAlarma.isNotEmpty ? " · Alarma: $horaAlarma" : ""}",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const Icon(Icons.alarm_off_rounded, color: Colors.red),
                  title: const Text("Alarma ezabatu"),
                  subtitle: const Text(
                      "Kendu Korreturnoseko urre-koloreko abisua"),
                  onTap: () => Navigator.pop(ctx, "desactivar"),
                ),
                ListTile(
                  leading: const Icon(Icons.access_time_rounded,
                      color: Colors.teal),
                  title: const Text("Ireki Google Erlojua"),
                  subtitle: const Text(
                      "Ikusi edo kudeatu alarmak erlojuan"),
                  onTap: () => Navigator.pop(ctx, "abrir_reloj"),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_notifications_rounded,
                      color: Colors.indigo),
                  title: const Text("Alarma birprogramatu"),
                  subtitle: const Text(
                      "Aldatu aurrerapen minutuak"),
                  onTap: () => Navigator.pop(ctx, "reprogramar"),
                ),
              ],
            ),
          );
        },
      );

      if (accion == "desactivar") {
        setState(() {
          alarmasActivadas.remove(claveAlarma);
        });
        await db.eliminarAlarmaActivada(
            widget.fecha, nombreServicio, horaServicio);
        _huboCambios = true;

        if (Platform.isAndroid) {
          try {
            final intentDismiss = AndroidIntent(
              action: 'android.intent.action.DISMISS_ALARM',
              package: 'com.google.android.deskclock',
              arguments: {
                'android.intent.extra.alarm.SEARCH_MODE': 'android.label',
                'android.intent.extra.alarm.MESSAGE': nombreServicio,
              },
            );
            await intentDismiss.launch();
          } catch (_) {}
        } else if (Platform.isIOS) {
          try {
            await _iosAlarmaChannel.invokeMethod('cancelarAlarma', {
              'id': "${widget.fecha}_$claveAlarma",
            });
          } catch (_) {}
        }

        messenger.showSnackBar(
          SnackBar(
            content: Text("Alarma ezabatuta: $nombreServicio"),
            backgroundColor: Colors.blueGrey.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      } else if (accion == "abrir_reloj") {
        if (Platform.isAndroid) {
          try {
            const intentShow = AndroidIntent(
              action: 'android.intent.action.SHOW_ALARMS',
              package: 'com.google.android.deskclock',
            );
            await intentShow.launch();
          } catch (_) {
            try {
              const intentShowGen = AndroidIntent(
                action: 'android.intent.action.SHOW_ALARMS',
              );
              await intentShowGen.launch();
            } catch (_) {}
          }
        } else if (Platform.isIOS) {
          try {
            await _iosAlarmaChannel.invokeMethod('abrirReloj');
          } catch (_) {}
        }
        return;
      } else if (accion != "reprogramar") {
        return;
      }
    }

    await _mostrarPopupAlarma(horaServicio, nombreServicio, claveAlarma);
  }

  Future<void> _mostrarPopupAlarma(
      String horaServicio, String nombreServicio, String claveAlarma) async {
    final partes = horaServicio.split(":");
    if (partes.length < 2) return;
    final horaBase = int.tryParse(partes[0]);
    final minBase = int.tryParse(partes[1]);
    if (horaBase == null || minBase == null) return;

    final seleccion = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.alarm_add_rounded,
                      color: Colors.blueGrey.shade700, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Sortu alarma Google Erlojuan",
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "$nombreServicio · Irteera: ${_horaCorta(horaServicio)}",
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text("Zenbat denbora lehenago nahi duzu alarma?",
                  style: TextStyle(fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 12),
              _botonOpcionAlarma(ctx, 1, horaBase, minBase),
              const SizedBox(height: 8),
              _botonOpcionAlarma(ctx, 5, horaBase, minBase),
              const SizedBox(height: 8),
              _botonOpcionAlarma(ctx, 8, horaBase, minBase),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Utzi"),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (seleccion == null) return;

    int totalMin = horaBase * 60 + minBase - seleccion;
    if (totalMin < 0) totalMin += 24 * 60;
    final horaAlarma = totalMin ~/ 60;
    final minAlarma = totalMin % 60;
    final horaStr =
        "${horaAlarma.toString().padLeft(2, '0')}:${minAlarma.toString().padLeft(2, '0')}";

    // Calcular fecha y hora exacta en la que Google Reloj hará sonar la alarma:
    final ahora = DateTime.now();
    DateTime fechaDisparoCalculada = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      horaAlarma,
      minAlarma,
    );
    // Si la hora calculada para hoy ya pasó, Google Reloj la programa para el siguiente día
    if (fechaDisparoCalculada.isBefore(ahora)) {
      fechaDisparoCalculada =
          fechaDisparoCalculada.add(const Duration(days: 1));
    }
    final fechaDisparoStr = fechaDisparoCalculada.toIso8601String();

    // 🔥 1. ACTIVACIÓN INMEDIATA EN PANTALLA Y EN BASE DE DATOS
    setState(() {
      alarmasActivadas[claveAlarma] = {
        'hora_alarma': horaStr,
        'fecha_disparo': fechaDisparoStr,
      };
    });
    await db.guardarAlarmaActivada(
      widget.fecha,
      nombreServicio,
      horaServicio,
      horaAlarma: horaStr,
      fechaDisparo: fechaDisparoStr,
    );
    _huboCambios = true;

    // 2. LANZAR INTENT EN ANDROID
    if (Platform.isAndroid) {
      try {
        final intentGoogle = AndroidIntent(
          action: 'android.intent.action.SET_ALARM',
          package: 'com.google.android.deskclock',
          arguments: {
            'android.intent.extra.alarm.HOUR': horaAlarma,
            'android.intent.extra.alarm.MINUTES': minAlarma,
            'android.intent.extra.alarm.MESSAGE':
                "$nombreServicio (-$seleccion min)",
            'android.intent.extra.alarm.SKIP_UI': false,
            'android.intent.extra.alarm.VIBRATE': true,
          },
        );
        await intentGoogle.launch();
      } catch (_) {
        try {
          final intentGeneral = AndroidIntent(
            action: 'android.intent.action.SET_ALARM',
            arguments: {
              'android.intent.extra.alarm.HOUR': horaAlarma,
              'android.intent.extra.alarm.MINUTES': minAlarma,
              'android.intent.extra.alarm.MESSAGE':
                  "$nombreServicio (-$seleccion min)",
              'android.intent.extra.alarm.SKIP_UI': false,
              'android.intent.extra.alarm.VIBRATE': true,
            },
          );
          await intentGeneral.launch();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Erlojuaren abisua: $e"),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      }
    } else if (Platform.isIOS) {
      try {
        await _iosAlarmaChannel.invokeMethod('programarAlarma', {
          'id': "${widget.fecha}_$claveAlarma",
          'hora': horaAlarma,
          'minuto': minAlarma,
          'mensaje': "$nombreServicio (-$seleccion min) · Irteera: ${_horaCorta(horaServicio)}",
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("iOS alarma abisua: $e"),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Alarma programatuta: $horaStr ($nombreServicio)"),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _botonOpcionAlarma(
      BuildContext ctx, int minutosAntes, int horaBase, int minBase) {
    int totalMin = horaBase * 60 + minBase - minutosAntes;
    if (totalMin < 0) totalMin += 24 * 60;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final horaStr =
        "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.pop(ctx, minutosAntes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border.all(color: Colors.amber.shade400),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.alarm, color: Colors.amber.shade900, size: 20),
                const SizedBox(width: 10),
                Text(
                  "$minutosAntes min lehenago",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            Text(
              "Jo: $horaStr",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indiceEnCurso = _indiceActual();
    final bool esSoloLectura = widget.soloLectura || ModoApp.esFamiliar;
    final bool esTurnoManual = (turnoDataInfo?['es_manual'] == 1);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _huboCambios) {}
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "${widget.turno} (${widget.tipo})",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _huboCambios),
          ),
          actions: [
            // 🔄 Botón para cambiar de turno directamente si te has equivocado
            if (!esSoloLectura)
              IconButton(
                tooltip: "Aldatu egun honetako txanda",
                icon: const Icon(Icons.swap_horiz_rounded),
                onPressed: () async {
                  DateTime f;
                  try {
                    f = DateTime.parse(widget.fecha);
                  } catch (_) {
                    f = DateTime.now();
                  }

                  final turnosDisponibles = await db.getTurnos();
                  final coloresDB = await db.getColoresTurno();
                  final esFestivoDB =
                      await db.esFechaFestivoAnual(widget.fecha);
                  final esDiaFestivoOSdf =
                      f.weekday == DateTime.saturday ||
                          f.weekday == DateTime.sunday ||
                          esFestivoDB;

                  if (!context.mounted) return;

                  final seleccionado = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (dialogCtx) => DialogoAsignarTurno(
                      fecha: f,
                      turnos: turnosDisponibles,
                      coloresDB: coloresDB,
                      esFestivo: esDiaFestivoOSdf,
                    ),
                  );

                  if (seleccionado != null) {
                    final nuevoTurno = seleccionado['turno']?.toString() ?? '';
                    final nuevoTipo = seleccionado['tipo']?.toString() ?? '';
                    if (nuevoTurno.isNotEmpty && nuevoTipo.isNotEmpty) {
                      await db.insertRegistro(
                          widget.fecha, nuevoTurno, nuevoTipo);
                      _huboCambios = true;
                      if (!context.mounted) return;
                      // Recargamos abriendo el nuevo turno
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetalleTurno(
                            turno: nuevoTurno,
                            tipo: nuevoTipo,
                            fecha: widget.fecha,
                            soloLectura: widget.soloLectura,
                          ),
                        ),
                      );
                    }
                  }
                },
              ),

            // 🗑️ Botón para eliminar el turno asignado a este día
            if (!esSoloLectura)
              IconButton(
                tooltip: "Ezabatu eguneko txanda",
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final confirmar = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Eguneko txanda ezabatu?"),
                      content: Text(
                          "${widget.fecha} egunari esleitutako txanda ezabatuko da.\n\nJarraitu nahi duzu?"),
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
                  await db.deleteRegistro(widget.fecha);

                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                },
              ),

            // 📝 Botón de notas e incidencias (oculto en modo familiar)
            if (!esSoloLectura)
              IconButton(
                tooltip: tieneNota ? "Ikusi/Editatu oharra" : "Gehitu oharra",
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      tieneNota ? Icons.assignment : Icons.assignment_outlined,
                      color: tieneNota ? Colors.amber.shade200 : Colors.white,
                    ),
                    if (tieneNota)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: ajusteMinutos != 0
                                ? (ajusteMinutos > 0
                                    ? Colors.greenAccent
                                    : Colors.redAccent)
                                : Colors.amberAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () async {
                  final resultado = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IncidenciaDiaScreen(
                        fecha: widget.fecha,
                        turno: widget.turno,
                        tipo: widget.tipo,
                      ),
                    ),
                  );

                  if (resultado == true) {
                    _huboCambios = true;
                    await _cargarDatos();
                  }
                },
              ),

            // ✏️ Botón de edición de turno (SOLO para turnos creados manualmente)
            if (!esSoloLectura && esTurnoManual)
              IconButton(
                tooltip: "Editatu eskuzko txanda",
                icon: const Icon(Icons.edit_calendar_rounded),
                onPressed: () async {
                  final resultado = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NuevoTurnoScreen(
                        turnoExistente: turnoDataInfo,
                      ),
                    ),
                  );

                  if (resultado is Map) {
                    _huboCambios = true;
                    if (resultado['eliminado'] == true) {
                      if (!context.mounted) return;
                      Navigator.pop(context, true);
                      return;
                    }
                    final nuevoT =
                        resultado['turno']?.toString() ?? widget.turno;
                    final nuevoTipo =
                        resultado['tipo']?.toString() ?? widget.tipo;
                    // Actualizamos únicamente el día que se está editando, sin alterar días pasados
                    await db.insertRegistro(widget.fecha, nuevoT, nuevoTipo);
                    if (!context.mounted) return;
                    if (nuevoT != widget.turno || nuevoTipo != widget.tipo) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetalleTurno(
                            turno: nuevoT,
                            tipo: nuevoTipo,
                            fecha: widget.fecha,
                            soloLectura: widget.soloLectura,
                          ),
                        ),
                      );
                    } else {
                      await _cargarDatos();
                    }
                  } else if (resultado == true) {
                    _huboCambios = true;
                    await _cargarDatos();
                  }
                },
              ),
          ],
        ),
        bottomNavigationBar: (hasiera != null && amaiera != null)
            ? SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Jornada horaria (inicio → fin)
                      Text(
                        "Lanaldia: ${_horaCorta(hasiera)} → ${_horaCorta(amaiera)}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),

                      // Horas totales de trabajo del día
                      Builder(builder: (_) {
                        // Minutos base del turno (lan_orduak)
                        int lanMin =
                            (turnoDataInfo?['lan_orduak'] as num?)?.toInt() ??
                                0;
                        // Si no hay lan_orduak, calcular desde hasiera/amaiera
                        if (lanMin == 0 &&
                            hasiera != null &&
                            amaiera != null &&
                            hasiera!.isNotEmpty &&
                            amaiera!.isNotEmpty) {
                          try {
                            final p1 = hasiera!.split(':');
                            final p2 = amaiera!.split(':');
                            int t1 = int.parse(p1[0]) * 60 +
                                int.parse(p1[1]);
                            int t2 = int.parse(p2[0]) * 60 +
                                int.parse(p2[1]);
                            if (t2 < t1) t2 += 24 * 60;
                            lanMin = t2 - t1;
                          } catch (_) {}
                        }
                        final totalMin = lanMin + ajusteMinutos;
                        if (totalMin <= 0) return const SizedBox.shrink();

                        final h = totalMin ~/ 60;
                        final m = totalMin % 60;
                        final label = h > 0 && m > 0
                            ? "${h}h ${m}min"
                            : h > 0
                                ? "${h}h"
                                : "${m}min";

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 15,
                                color: Colors.blueGrey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                            // Chip de ajuste si lo hay
                            if (ajusteMinutos != 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ajusteMinutos > 0
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: ajusteMinutos > 0
                                        ? Colors.green.shade300
                                        : Colors.red.shade300,
                                  ),
                                ),
                                child: Text(
                                  ajusteMinutos > 0
                                      ? "+$ajusteMinutos min"
                                      : "$ajusteMinutos min",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: ajusteMinutos > 0
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              )
            : null,
        body: servicios.isEmpty
            ? const Center(
                child: Text(
                  "Ez dago zerbitzurik erregistratuta txanda honetarako.",
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                itemCount: servicios.length,
                itemBuilder: (context, index) {
                  final s = servicios[index];

                  final itinerario = s['itinerario']?.toString() ?? '';
                  final servicio = s['servicio']?.toString() ?? '';
                  final oharrak = s['oharrak']?.toString() ?? '';
                  final des = s['des']?.toString() ?? '';
                  final irteeraOrd = _horaCorta(s['irteera_ordua']?.toString());
                  final helmugaOrd = _horaCorta(s['helmuga_ordua']?.toString());
                  final irteera = s['irteera']?.toString() ?? '';
                  final helmuga = s['helmuga']?.toString() ?? '';

                  final horaRaw = s['irteera_ordua']?.toString() ?? '';
                  final tieneHora = horaRaw.isNotEmpty;
                  final esDescanso = _esDescanso(servicio);
                  final esActual = (indiceEnCurso == index);

                  // Horas estimadas para descanso basadas en el servicio previo y siguiente
                  String? horaIniDes;
                  String? horaFinDes;
                  if (esDescanso) {
                    if (index > 0 &&
                        servicios[index - 1]['helmuga_ordua'] != null) {
                      horaIniDes =
                          servicios[index - 1]['helmuga_ordua'].toString();
                    }
                    if (index + 1 < servicios.length &&
                        servicios[index + 1]['irteera_ordua'] != null) {
                      horaFinDes =
                          servicios[index + 1]['irteera_ordua'].toString();
                    }
                  }

                  // Clave unívoca de alarma y estado activo
                  final nombreServ =
                      servicio.isNotEmpty ? servicio : "Zerbitzua $index";
                  final claveAlarma = "$nombreServ|||$horaRaw";
                  final infoAlarmaGuardada = alarmasActivadas[claveAlarma];
                  final horaAlarmaGuardada = infoAlarmaGuardada?['hora_alarma'];
                  final fechaDisparoGuardada =
                      infoAlarmaGuardada?['fecha_disparo'];

                  // 🔥 Comprobar si la alarma está activa o si ya ha sonado
                  final alarmaActiva = _esAlarmaActiva(
                    claveAlarma,
                    horaAlarmaGuardada,
                    horaRaw,
                    fechaDisparo: fechaDisparoGuardada,
                  );

                  return Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    margin: const EdgeInsets.symmetric(
                        vertical: 2.5, horizontal: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: esActual ? Colors.green.shade50 : Colors.white,
                      border: Border.all(
                        color: esActual
                            ? Colors.green.shade600
                            : Colors.grey.shade300,
                        width: esActual ? 2.0 : 0.8,
                      ),
                      boxShadow: esActual
                          ? [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.20),
                                blurRadius: 5,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Contenido principal: Servicio o Descanso
                        Expanded(
                          child: esDescanso
                              ? _filaDescanso(
                                  servicio,
                                  des,
                                  horaIniDes,
                                  horaFinDes,
                                  esActual,
                                )
                              : _filaServicio(
                                  itinerario,
                                  servicio,
                                  oharrak,
                                  des,
                                  irteeraOrd,
                                  helmugaOrd,
                                  irteera,
                                  helmuga,
                                  esActual,
                                ),
                        ),

                        // 🔔 Botón campana de alarma con cambio de color inmediato y apagado al sonar
                        if (!esSoloLectura && !esDescanso && tieneHora)
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: alarmaActiva
                                    ? Colors.amber.shade100
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                border: alarmaActiva
                                    ? Border.all(
                                        color: Colors.amber.shade800, width: 1.5)
                                    : null,
                              ),
                              child: Icon(
                                alarmaActiva
                                    ? Icons.alarm_on_rounded
                                    : Icons.alarm_add_rounded,
                                size: 22,
                                color: alarmaActiva
                                    ? Colors.amber.shade900
                                    : (esActual
                                        ? Colors.green.shade700
                                        : Colors.blueGrey.shade400),
                              ),
                            ),
                            tooltip: alarmaActiva
                                ? "Alarma aktiboa (jo: ${horaAlarmaGuardada ?? horaRaw})"
                                : "Sortu alarma Google Erlojuan",
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                            onPressed: () => _gestionarAlarma(
                              horaRaw,
                              nombreServ,
                              claveAlarma,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _filaServicio(
    String itinerario,
    String servicio,
    String oharrak,
    String des,
    String irteeraOrd,
    String helmugaOrd,
    String irteera,
    String helmuga,
    bool esActual,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "${servicio.isNotEmpty ? servicio : ''}"
                "${itinerario.isNotEmpty ? " - $itinerario" : ''}"
                "${oharrak.isNotEmpty ? " - $oharrak" : ''}",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: esActual ? FontWeight.w700 : FontWeight.w600,
                  color: esActual ? Colors.green.shade900 : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (des.isNotEmpty)
              Text(
                des,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          "$irteeraOrd → $helmugaOrd   $irteera → $helmuga",
          style: TextStyle(
            fontSize: 11,
            color: esActual ? Colors.green.shade800 : Colors.grey.shade700,
            fontWeight: esActual ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _filaDescanso(
    String servicio,
    String des,
    String? horaInicio,
    String? horaFin,
    bool esActual,
  ) {
    final hIniCorta = _horaCorta(horaInicio);
    final hFinCorta = _horaCorta(horaFin);
    final tieneHorario = hIniCorta.isNotEmpty && hFinCorta.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.coffee_rounded,
                      size: 18,
                      color: esActual
                          ? Colors.green.shade800
                          : Colors.brown.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        servicio,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color:
                              esActual ? Colors.green.shade900 : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (des.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    "$des min",
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
          if (tieneHorario) ...[
            const SizedBox(height: 3),
            Text(
              "$hIniCorta → $hFinCorta  (Atsedenaldia)",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: esActual ? FontWeight.w600 : FontWeight.normal,
                color: esActual ? Colors.green.shade900 : Colors.grey.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Estructura interna para cálculo ordenado de horarios de servicios y descansos
class _RangoServicio {
  final int index;
  final int? inicio;
  final int? fin;
  final bool esDescanso;

  _RangoServicio(this.index, this.inicio, this.fin, this.esDescanso);
}
