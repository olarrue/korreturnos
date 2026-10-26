import 'package:flutter/material.dart';
import '../config/modo_app.dart';
import '../database/db_helper.dart';
import '../screens/detalle_turno.dart';
import '../screens/nuevo_turno.dart';

class CeldaDia extends StatelessWidget {
  final DateTime fecha;
  final int? semanaOrientativa;
  final String? tipoOrientativo;
  final Map<String, dynamic>? registro;
  final Map<String, dynamic>? turnoData;
  final Map<String, int> coloresDB;
  final List<Map<String, dynamic>> turnosDisponibles;
  final bool esMesActual;
  final bool tieneAlarmaActiva;
  final bool tieneAdjuntos;
  final VoidCallback? onRefresh;

  const CeldaDia({
    super.key,
    required this.fecha,
    required this.semanaOrientativa,
    required this.tipoOrientativo,
    required this.registro,
    required this.turnoData,
    required this.coloresDB,
    required this.turnosDisponibles,
    required this.esMesActual,
    this.tieneAlarmaActiva = false,
    this.tieneAdjuntos = false,
    this.onRefresh,
  });

  String _fechaStr() {
    return "${fecha.year.toString().padLeft(4, '0')}-"
        "${fecha.month.toString().padLeft(2, '0')}-"
        "${fecha.day.toString().padLeft(2, '0')}";
  }

  String _horaCorta(String? h) {
    if (h == null || h.isEmpty) return "";
    return h.length >= 5 ? h.substring(0, 5) : h;
  }

  Color _colorFondo(String? turno, String? tipo) {
    if (turno != null && tipo != null) {
      final key = "$turno-$tipo";
      final colorInt = coloresDB[key] ?? coloresDB[turno];
      if (colorInt != null) {
        return Color(colorInt);
      }
      return Colors.blueGrey.shade600;
    }

    // Color según tipo orientativo si no hay turno asignado
    switch (tipoOrientativo) {
      case "M":
        return Colors.orange.withValues(alpha: 0.20);
      case "T":
        return Colors.green.withValues(alpha: 0.20);
      case "DES":
        return Colors.red.withValues(alpha: 0.20);
      case "ABS":
        return Colors.blue.withValues(alpha: 0.20);
      default:
        return esMesActual ? Colors.white : Colors.grey.shade100;
    }
  }

  Color _contrasteTexto(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final turno = registro?['turno']?.toString();
    final tipo = registro?['tipo']?.toString();
    final hasiera = turnoData?['hasiera']?.toString();
    final amaiera = turnoData?['amaiera']?.toString();

    // Comprobar si hay alguna nota o incidencia escrita o archivo adjunto para este día
    final observaciones = registro?['observaciones']?.toString() ?? '';
    final tieneNota = observaciones.trim().isNotEmpty || tieneAdjuntos;

    final bg = _colorFondo(turno, tipo);
    final tieneTurno = turno != null;
    final textColor = tieneTurno
        ? _contrasteTexto(bg)
        : (esMesActual ? Colors.black87 : Colors.grey.shade400);

    final hoy = DateTime.now();
    final esHoy = fecha.year == hoy.year &&
        fecha.month == hoy.month &&
        fecha.day == hoy.day;

    final db = DBHelper();

    return GestureDetector(
      onTap: () async {
        if (tieneTurno) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetalleTurno(
                turno: turno,
                tipo: tipo ?? '',
                fecha: _fechaStr(),
                soloLectura: ModoApp.esFamiliar,
              ),
            ),
          );

          // Refrescar siempre al volver para actualizar horas del mes y notas al instante
          onRefresh?.call();
        } else {
          // Si es modo familiar, no se pueden asignar turnos
          if (ModoApp.esFamiliar) return;

          // Selector de turnos por pestañas (Invierno, Otros y futuros correturnos)
          final seleccionado = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (dialogCtx) => DialogoAsignarTurno(
              fecha: fecha,
              turnos: turnosDisponibles,
              coloresDB: coloresDB,
            ),
          );

          if (seleccionado != null) {
            if (seleccionado['turno'] != null && seleccionado['tipo'] != null) {
              await db.insertRegistro(
                _fechaStr(),
                seleccionado['turno'].toString(),
                seleccionado['tipo'].toString(),
              );
            }
            onRefresh?.call();
          }
        }
      },
      onLongPress: () async {
        if (ModoApp.esFamiliar || !tieneTurno) return;

        final accion = await showModalBottomSheet<String>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.blue),
                    title: Text("Ikusi xehetasunak: $turno ($tipo)"),
                    onTap: () => Navigator.pop(ctx, "detalle"),
                  ),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded, color: Colors.teal),
                    title: const Text("Aldatu egun honetako txanda"),
                    subtitle: const Text("Hautatu beste txanda bat okertu bazara"),
                    onTap: () => Navigator.pop(ctx, "cambiar"),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text("Ezabatu egun honetako txanda"),
                    subtitle: const Text("Utzi egun hau libre txandarik gabe"),
                    onTap: () => Navigator.pop(ctx, "borrar"),
                  ),
                ],
              ),
            ),
          ),
        );

        if (!context.mounted) return;

        if (accion == "detalle") {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetalleTurno(
                turno: turno,
                tipo: tipo ?? '',
                fecha: _fechaStr(),
                soloLectura: ModoApp.esFamiliar,
              ),
            ),
          );
          onRefresh?.call();
        } else if (accion == "cambiar") {
          final seleccionado = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (dialogCtx) => DialogoAsignarTurno(
              fecha: fecha,
              turnos: turnosDisponibles,
              coloresDB: coloresDB,
            ),
          );

          if (seleccionado != null) {
            if (seleccionado['turno'] != null && seleccionado['tipo'] != null) {
              await db.insertRegistro(
                _fechaStr(),
                seleccionado['turno'].toString(),
                seleccionado['tipo'].toString(),
              );
              onRefresh?.call();
            }
          }
        } else if (accion == "borrar") {
          final confirmar = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Eguneko txanda ezabatu?"),
              content: Text(
                  "${_fechaStr()} egunari esleitutako txanda ezabatuko da.\n\nJarraitu?"),
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

          if (confirmar == true) {
            await db.deleteRegistro(_fechaStr());
            onRefresh?.call();
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 4.5),
        constraints: const BoxConstraints(minHeight: 90),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            // Marca del día de hoy en NEGRO con buen grosor para máxima visibilidad
            color: esHoy
                ? Colors.black
                : (tieneTurno ? Colors.black12 : Colors.grey.shade300),
            width: esHoy ? 2.5 : 0.6,
          ),
          boxShadow: tieneTurno
              ? [
                  const BoxShadow(
                    color: Colors.black12,
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Fila superior: número de día, estrella si hay nota, y distintivo orientativo
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${fecha.day}",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: esHoy || tieneTurno
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: esHoy && !tieneTurno ? Colors.black : textColor,
                      ),
                    ),
                    // ⭐ Estrella visible al lado del número del día si tiene notas escritas
                    if (tieneNota) ...[
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: Colors.amber,
                      ),
                    ],
                    // 🔔 Campanita visible si tiene alarma activa
                    if (tieneAlarmaActiva) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.alarm_on_rounded,
                        size: 12,
                        color: Colors.amber.shade900,
                      ),
                    ],
                  ],
                ),
                if (!tieneTurno &&
                    tipoOrientativo != null &&
                    tipoOrientativo!.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      tipoOrientativo!,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
              ],
            ),

            // Información del turno si está asignado
            if (tieneTurno) ...[
              const SizedBox(height: 3),
              Text(
                turno,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  height: 1.2,
                ),
              ),
              Text(
                tipo ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.85),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              // Horarios limpios sin símbolos ni iconos
              Text(
                _horaCorta(hasiera),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.95),
                  height: 1.1,
                ),
              ),
              Text(
                _horaCorta(amaiera),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: textColor.withValues(alpha: 0.85),
                  height: 1.1,
                ),
              ),
            ] else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 🗂️ DIÁLOGO CON PESTAÑAS: INVIERNO (LAB / SDF), OTROS Y FUTUROS CORRETURNOS
// =========================================================================
class DialogoAsignarTurno extends StatefulWidget {
  final DateTime fecha;
  final List<Map<String, dynamic>> turnos;
  final Map<String, int> coloresDB;

  const DialogoAsignarTurno({
    super.key,
    required this.fecha,
    required this.turnos,
    required this.coloresDB,
  });

  @override
  State<DialogoAsignarTurno> createState() => _DialogoAsignarTurnoState();
}

class _DialogoAsignarTurnoState extends State<DialogoAsignarTurno> {
  // Filtro interno para la pestaña Invierno: 'TODOS', 'LAB', 'SDF'
  String filtroInvierno = 'TODOS';

  String _horaCorta(String? h) {
    if (h == null || h.isEmpty) return "";
    return h.length >= 5 ? h.substring(0, 5) : h;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Agrupar turnos en: Invierno (LAB y SDF), Otros y categorías futuras
    List<Map<String, dynamic>> turnosInvierno = [];
    List<Map<String, dynamic>> turnosOtros = [];
    Map<String, List<Map<String, dynamic>>> categoriasFuturas = {};

    for (var t in widget.turnos) {
      final tipo = (t['tipo']?.toString() ?? '').trim().toUpperCase();

      if (tipo == 'LAB' || tipo == 'SDF') {
        turnosInvierno.add(t);
      } else if (tipo.startsWith('VERANO')) {
        categoriasFuturas.putIfAbsent("Uda", () => []).add(t);
      } else if (tipo.startsWith('NAVIDAD') || tipo.startsWith('NAVIDADES')) {
        categoriasFuturas.putIfAbsent("Gabonak", () => []).add(t);
      } else {
        turnosOtros.add(t);
      }
    }

    // Lista de todas las pestañas a mostrar
    List<Widget> tabs = [
      Tab(
        text: "Negua (${turnosInvierno.length})",
      ),
      ...categoriasFuturas.keys.map(
        (nombre) => Tab(text: "$nombre (${categoriasFuturas[nombre]!.length})"),
      ),
      Tab(
        text: "Besteak (${turnosOtros.length})",
      ),
    ];

    // Vistas para cada pestaña
    List<Widget> tabViews = [
      // Pestaña Invierno: con filtro rápido LAB / SDF
      _buildVistaInvierno(turnosInvierno),

      // Pestañas dinámicas futuras (Verano, Navidades, etc.)
      ...categoriasFuturas.keys.map(
        (nombre) => _buildListaTurnos(categoriasFuturas[nombre]!, nombre),
      ),

      // Pestaña Otros
      _buildListaTurnos(turnosOtros, "Besteak"),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        child: SizedBox(
          width: double.maxFinite,
          height: 580,
          child: Column(
            children: [
              // Encabezado del diálogo
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Txanda esleitu (${widget.fecha.day}/${widget.fecha.month})",
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Barra de pestañas (Invierno, Otros...)
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.amber.shade900,
                unselectedLabelColor: Colors.grey.shade700,
                indicatorColor: Colors.amber.shade900,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                tabs: tabs,
              ),

              const Divider(height: 1),

              // Contenido de las pestañas
              Expanded(
                child: TabBarView(
                  children: tabViews,
                ),
              ),

              const Divider(height: 1),

              // Botón inferior para crear turno nuevo
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 24),
                title: const Text(
                  "Txanda berria sortu",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                onTap: () async {
                  final nav = Navigator.of(context);
                  final nuevo = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NuevoTurnoScreen(),
                    ),
                  );

                  if (nuevo != null) {
                    nav.pop(nuevo);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Vista para la pestaña Invierno con selector de filtro [Todos] [LAB] [SDF]
  Widget _buildVistaInvierno(List<Map<String, dynamic>> listaTotal) {
    final labCount = listaTotal.where((t) => (t['tipo']?.toString().toUpperCase() ?? '') == 'LAB').length;
    final sdfCount = listaTotal.where((t) => (t['tipo']?.toString().toUpperCase() ?? '') == 'SDF').length;

    List<Map<String, dynamic>> filtrada = listaTotal;
    if (filtroInvierno == 'LAB') {
      filtrada = listaTotal.where((t) => (t['tipo']?.toString().toUpperCase() ?? '') == 'LAB').toList();
    } else if (filtroInvierno == 'SDF') {
      filtrada = listaTotal.where((t) => (t['tipo']?.toString().toUpperCase() ?? '') == 'SDF').toList();
    }

    return Column(
      children: [
        // Sub-filtro para alternar entre LAB y SDF dentro de Invierno
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              _buildFiltroChip("TODOS", "Denak (${listaTotal.length})"),
              const SizedBox(width: 6),
              _buildFiltroChip("LAB", "LAB ($labCount)"),
              const SizedBox(width: 6),
              _buildFiltroChip("SDF", "SDF ($sdfCount)"),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _buildListaTurnos(filtrada, "Negua"),
        ),
      ],
    );
  }

  Widget _buildFiltroChip(String valor, String etiqueta) {
    final seleccionado = filtroInvierno == valor;
    return ChoiceChip(
      label: Text(
        etiqueta,
        style: TextStyle(
          fontSize: 12,
          fontWeight: seleccionado ? FontWeight.bold : FontWeight.normal,
          color: seleccionado ? Colors.white : Colors.black87,
        ),
      ),
      selected: seleccionado,
      selectedColor: Colors.blueGrey.shade800,
      backgroundColor: Colors.grey.shade100,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) {
        setState(() {
          filtroInvierno = valor;
        });
      },
    );
  }

  // Lista de tarjetas de turnos para cada pestaña
  Widget _buildListaTurnos(List<Map<String, dynamic>> turnos, String categoria) {
    if (turnos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                "Ez dago txandarik eskuragarri ($categoria)",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                "Beheko 'Txanda berria sortu' erabil dezakezu.",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: turnos.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (ctx, index) {
        final t = turnos[index];
        final tTurno = t['turno']?.toString() ?? '';
        final tTipo = t['tipo']?.toString() ?? '';
        final key = "$tTurno-$tTipo";
        final colorInt = widget.coloresDB[key] ?? widget.coloresDB[tTurno];
        final c = colorInt != null ? Color(colorInt) : Colors.blueGrey;

        final hasiera = _horaCorta(t['hasiera']?.toString());
        final amaiera = _horaCorta(t['amaiera']?.toString());

        final esLAB = tTipo.toUpperCase() == 'LAB';
        final esSDF = tTipo.toUpperCase() == 'SDF';
        // Comprobar si el turno fue introducido manualmente
        final esManual = (t['es_manual'] == 1);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: c,
            radius: 14,
            child: Text(
              tTurno.isNotEmpty ? tTurno[0] : '?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: c.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
              ),
            ),
          ),
          title: Row(
            children: [
              Text(
                tTurno,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: esLAB
                      ? Colors.indigo.shade50
                      : (esSDF ? Colors.deepOrange.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: esLAB
                        ? Colors.indigo.shade200
                        : (esSDF ? Colors.deepOrange.shade200 : Colors.grey.shade400),
                  ),
                ),
                child: Text(
                  tTipo,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: esLAB
                        ? Colors.indigo.shade900
                        : (esSDF ? Colors.deepOrange.shade900 : Colors.black87),
                  ),
                ),
              ),
              if (esManual) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    "Eskuzkoa",
                    style: TextStyle(fontSize: 8.5, color: Colors.blue, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
          subtitle: hasiera.isNotEmpty && amaiera.isNotEmpty
              ? Text(
                  "$hasiera - $amaiera",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✏️ Botón para modificar los datos del turno si fue introducido manualmente
              if (esManual)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blueGrey),
                  tooltip: "Aldatu eskuzko txanda honen datuak",
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    final modificado = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NuevoTurnoScreen(turnoExistente: t),
                      ),
                    );

                    if (modificado != null) {
                      nav.pop(modificado);
                    }
                  },
                ),
              const Icon(Icons.arrow_forward_ios, size: 13, color: Colors.grey),
            ],
          ),
          onTap: () => Navigator.pop(context, t),
        );
      },
    );
  }
}
