import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import 'detalle_turno.dart';

class BusquedaServicioScreen extends StatefulWidget {
  const BusquedaServicioScreen({super.key});

  @override
  State<BusquedaServicioScreen> createState() => _BusquedaServicioScreenState();
}

class _BusquedaServicioScreenState extends State<BusquedaServicioScreen> {
  final db = DBHelper();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _resultados = [];
  Map<String, int> _coloresDB = {};
  bool _buscando = false;
  bool _haBuscado = false;

  @override
  void initState() {
    super.initState();
    _cargarColores();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarColores() async {
    final cols = await db.getColoresTurno();
    if (!mounted) return;
    setState(() {
      _coloresDB = cols;
    });
  }

  String _horaCorta(String? h) {
    if (h == null || h.isEmpty) return "--:--";
    return h.length >= 5 ? h.substring(0, 5) : h;
  }

  Future<void> _buscar(String texto) async {
    final q = texto.trim();
    if (q.isEmpty) {
      setState(() {
        _resultados = [];
        _haBuscado = false;
      });
      return;
    }

    setState(() {
      _buscando = true;
      _haBuscado = true;
    });

    final res = await db.buscarServiciosPorNumero(q);
    if (!mounted) return;

    setState(() {
      _resultados = res;
      _buscando = false;
    });
  }

  Color _colorTurno(String turno, String tipo) {
    final key = "$turno-$tipo";
    final cInt = _coloresDB[key] ?? _coloresDB[turno];
    if (cInt != null) return Color(cInt);
    return Colors.blueGrey.shade700;
  }

  Color _contrasteTexto(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Zerbitzuaren bilaketa"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recuadro buscador de número de servicio
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _buscar,
              onSubmitted: _buscar,
              decoration: InputDecoration(
                labelText: "Zerbitzu zenbakia",
                hintText: "Adib: 101, 204, 15...",
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: "Garbitu",
                        onPressed: () {
                          _searchCtrl.clear();
                          _buscar("");
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 14),

            if (_haBuscado && !_buscando)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  "Aurkitutako zerbitzuak: ${_resultados.length}",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              ),

            Expanded(
              child: _buscando
                  ? const Center(child: CircularProgressIndicator())
                  : !_haBuscado
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.train_outlined,
                                  size: 52, color: Colors.grey.shade400),
                              const SizedBox(height: 10),
                              Text(
                                "Idatzi zerbitzu zenbakia bere ordutegia\neta ibilbidea ikusteko.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _resultados.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off_rounded,
                                      size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 10),
                                  Text(
                                    "Ez da '${_searchCtrl.text.trim()}' zerbitzurik aurkitu.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _resultados.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (ctx, i) {
                                final item = _resultados[i];
                                final servicio =
                                    item['servicio']?.toString() ?? '';
                                final turno = item['turno']?.toString() ?? '';
                                final tipo = item['tipo']?.toString() ?? '';
                                final irteeraOrd = _horaCorta(
                                    item['irteera_ordua']?.toString());
                                final helmugaOrd = _horaCorta(
                                    item['helmuga_ordua']?.toString());
                                final irteera =
                                    item['irteera']?.toString() ?? '';
                                final helmuga =
                                    item['helmuga']?.toString() ?? '';
                                final itinerario =
                                    item['itinerario']?.toString() ?? '';
                                final oharrak =
                                    item['oharrak']?.toString() ?? '';

                                final bgTurno = _colorTurno(turno, tipo);
                                final txtTurno = _contrasteTexto(bgTurno);

                                return Card(
                                  elevation: 1.5,
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                        color: Colors.grey.shade300),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => DetalleTurno(
                                            turno: turno,
                                            tipo: tipo,
                                            fecha: '',
                                            soloLectura: true,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Fila superior: Número de servicio y Turno al que pertenece
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .directions_transit_rounded,
                                                      color: Colors
                                                          .blueGrey.shade800,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                      child: Text(
                                                        "Zerbitzua: $servicio"
                                                        "${itinerario.isNotEmpty ? ' · $itinerario' : ''}"
                                                        "${oharrak.isNotEmpty ? ' ($oharrak)' : ''}",
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: bgTurno,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  "Txanda $turno ($tipo)",
                                                  style: TextStyle(
                                                    color: txtTurno,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),

                                          const Divider(height: 16),

                                          // Hora de salida - Hora de llegada
                                          Row(
                                            children: [
                                              Icon(Icons.schedule_rounded,
                                                  size: 17,
                                                  color: Colors.teal.shade700),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Ordutegia: ",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              Text(
                                                "$irteeraOrd - $helmugaOrd",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.teal.shade900,
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(height: 6),

                                          // De dónde a dónde (Irteera -> Helmuga)
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.route_outlined,
                                                  size: 17,
                                                  color:
                                                      Colors.indigo.shade700),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Ibilbidea: ",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  "$irteera → $helmuga",
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
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
