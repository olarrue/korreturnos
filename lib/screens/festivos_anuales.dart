import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class FestivosAnualesScreen extends StatefulWidget {
  const FestivosAnualesScreen({super.key});

  @override
  State<FestivosAnualesScreen> createState() => _FestivosAnualesScreenState();
}

class _FestivosAnualesScreenState extends State<FestivosAnualesScreen> {
  final db = DBHelper();

  late DateTime _fechaBase;
  late DateTime fechaVista;
  late PageController _pageController;
  static const int _paginaBase = 1200;

  Set<String> _festivos = {};
  bool _cargando = true;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _fechaBase = DateTime(ahora.year, ahora.month, 1);
    fechaVista = _fechaBase;
    _pageController = PageController(initialPage: _paginaBase);
    _cargarFestivos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _cargarFestivos() async {
    final f = await db.getFestivosAnuales();
    if (!mounted) return;
    setState(() {
      _festivos = f;
      _cargando = false;
    });
  }

  DateTime _fechaParaPagina(int index) {
    final diff = index - _paginaBase;
    return DateTime(_fechaBase.year, _fechaBase.month + diff, 1);
  }

  int _paginaParaFecha(DateTime fecha) {
    final diff =
        (fecha.year - _fechaBase.year) * 12 + (fecha.month - _fechaBase.month);
    return _paginaBase + diff;
  }

  void _cambiarMes(int meses) {
    if (_pageController.hasClients) {
      final paginaActual = _pageController.page?.round() ?? _paginaBase;
      _pageController.animateToPage(
        paginaActual + meses,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
      );
    } else {
      setState(() {
        fechaVista = DateTime(fechaVista.year, fechaVista.month + meses, 1);
      });
    }
  }

  String _formatoFecha(DateTime d) {
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  Future<void> _alternarDia(DateTime dia) async {
    final fStr = _formatoFecha(dia);
    final marcado = await db.toggleFestivoAnual(fStr);
    _huboCambios = true;

    if (!mounted) return;
    setState(() {
      if (marcado) {
        _festivos.add(fStr);
      } else {
        _festivos.remove(fStr);
      }
    });
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

  Widget _construirRejillaMes(DateTime fechaMes) {
    final primerDiaMes = DateTime(fechaMes.year, fechaMes.month, 1);
    final ultimoDiaMes = DateTime(fechaMes.year, fechaMes.month + 1, 0);

    DateTime inicio = DateTime(
      primerDiaMes.year,
      primerDiaMes.month,
      primerDiaMes.day - (primerDiaMes.weekday - 1),
    );

    List<Widget> filas = [];
    final hoy = DateTime.now();

    while (
        inicio.isBefore(ultimoDiaMes) || inicio.month == ultimoDiaMes.month) {
      final inicioFila = inicio;
      filas.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 6),
          child: Row(
            children: List.generate(7, (i) {
              final dia = DateTime(
                inicioFila.year,
                inicioFila.month,
                inicioFila.day + i,
              );
              final fStr = _formatoFecha(dia);
              final esMesActual = dia.month == fechaMes.month;
              final esFestivo = _festivos.contains(fStr);
              final esHoy = dia.year == hoy.year &&
                  dia.month == hoy.month &&
                  dia.day == hoy.day;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _alternarDia(dia),
                  child: Container(
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      color: esFestivo
                          ? Colors.red.shade600
                          : (esMesActual ? Colors.white : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: esHoy
                            ? Colors.black
                            : (esFestivo
                                ? Colors.red.shade800
                                : Colors.grey.shade300),
                        width: esHoy ? 2.2 : 1.0,
                      ),
                      boxShadow: esFestivo
                          ? [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.25),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          "${dia.day}",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: esFestivo || esHoy
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: esFestivo
                                ? Colors.white
                                : (!esMesActual
                                    ? Colors.grey.shade400
                                    : Colors.black87),
                          ),
                        ),
                        if (esFestivo)
                          const Positioned(
                            bottom: 2,
                            child: Text(
                              "JAI",
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );

      inicio = DateTime(inicio.year, inicio.month, inicio.day + 7);
      if (inicio.month > ultimoDiaMes.month && inicio.weekday == 1) break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: filas,
    );
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = fechaVista.year.toString();
    final festivosAnio = _festivos
        .where((f) => f.startsWith("$anioActual-"))
        .toList()
      ..sort();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _huboCambios),
          ),
          title: const Text("Urteko jaiegunak"),
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
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOut,
                  );
                } else {
                  setState(() => fechaVista = hoy);
                }
              },
            ),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Banner explicativo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border(
                          bottom: BorderSide(color: Colors.red.shade200)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.celebration_outlined,
                            color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Sakatu egutegiko edozein egun jaiegun gisa markatzeko edo kentzeko.",
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.red.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Selector de mes y año
                  Padding(
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
                            fontWeight: FontWeight.w800,
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

                  // Cabecera L M X J V S D
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      children: ["L", "M", "X", "J", "V", "S", "D"]
                          .map(
                            (d) => Expanded(
                              child: Center(
                                child: Text(
                                  d,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),

                  // Calendario deslizable por meses
                  SizedBox(
                    height: 305,
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          fechaVista = _fechaParaPagina(index);
                        });
                      },
                      itemBuilder: (context, index) {
                        final fechaMes = _fechaParaPagina(index);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _construirRejillaMes(fechaMes),
                        );
                      },
                    ),
                  ),

                  const Divider(height: 1),

                  // Lista de festivos marcados en el año visible
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${fechaVista.year}. urteko jaiegunak (${festivosAnio.length})",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: festivosAnio.isEmpty
                        ? Center(
                            child: Text(
                              "Ez dago jaiegunik markatuta ${fechaVista.year}. urtean",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            itemCount: festivosAnio.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (ctx, i) {
                              final fStr = festivosAnio[i];
                              DateTime? d;
                              try {
                                d = DateTime.parse(fStr);
                              } catch (_) {}

                              final etiquetaMes = d != null
                                  ? "${d.day} ${_nombreMes(d.month)}"
                                  : fStr;

                              return Card(
                                elevation: 0.5,
                                margin: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.red.shade200),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade600,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Text(
                                      "JAI",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    "$etiquetaMes ($fStr)",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    tooltip: "Ezabatu jaieguna",
                                    onPressed: () async {
                                      await db.toggleFestivoAnual(fStr);
                                      _huboCambios = true;
                                      if (!mounted) return;
                                      setState(() {
                                        _festivos.remove(fStr);
                                      });
                                    },
                                  ),
                                  onTap: () {
                                    if (d != null) {
                                      final pag = _paginaParaFecha(d);
                                      _pageController.animateToPage(
                                        pag,
                                        duration:
                                            const Duration(milliseconds: 260),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
