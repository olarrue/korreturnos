import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';

class IncidenciaDiaScreen extends StatefulWidget {
  final String fecha;
  final String turno;
  final String tipo;

  const IncidenciaDiaScreen({
    super.key,
    required this.fecha,
    required this.turno,
    required this.tipo,
  });

  @override
  State<IncidenciaDiaScreen> createState() => _IncidenciaDiaScreenState();
}

class _IncidenciaDiaScreenState extends State<IncidenciaDiaScreen> {
  final db = DBHelper();

  late TextEditingController _notasController;
  late TextEditingController _minutosInputController;

  int _ajusteMinutos = 0;
  bool _cargando = true;
  String? hasiera;
  String? amaiera;
  int? lanOrduakBase;
  List<Map<String, dynamic>> _adjuntos = [];
  bool _huboCambiosAdjuntos = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _notasController = TextEditingController();
    _minutosInputController = TextEditingController();
    _cargarDatos();
  }

  @override
  void dispose() {
    _notasController.dispose();
    _minutosInputController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final registro = await db.getTurnoPorFecha(widget.fecha);
    final turnoData = await db.getTurno(widget.turno, widget.tipo);
    final adjuntosDB = await db.getAdjuntosPorFecha(widget.fecha);

    if (!mounted) return;

    final obs = registro?['observaciones']?.toString() ?? '';
    final ajuste = (registro?['ajuste_minutos'] as int?) ?? 0;
    final regH = registro?['hasiera']?.toString() ?? '';
    final regA = registro?['amaiera']?.toString() ?? '';
    final regLan = (registro?['lan_orduak'] as num?)?.toInt() ?? 0;

    setState(() {
      _notasController.text = obs;
      _ajusteMinutos = ajuste;
      _minutosInputController.text = _ajusteMinutos == 0 ? "" : "$_ajusteMinutos";
      hasiera = regH.isNotEmpty ? regH : turnoData?['hasiera']?.toString();
      amaiera = regA.isNotEmpty ? regA : turnoData?['amaiera']?.toString();
      lanOrduakBase = regLan > 0 ? regLan : (turnoData?['lan_orduak'] as int?);
      _adjuntos = adjuntosDB;
      _cargando = false;
    });
  }

  bool _esImagenPorNombre(String nombre, String tipo) {
    if (tipo == 'imagen') return true;
    final ext = p.extension(nombre).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic']
        .contains(ext);
  }

  Future<void> _sacarFoto() async {
    try {
      final XFile? foto = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (foto == null) return;

      final ahora = DateTime.now();
      final nombreFoto =
          "Argazkia_${ahora.hour.toString().padLeft(2, '0')}${ahora.minute.toString().padLeft(2, '0')}${ahora.second.toString().padLeft(2, '0')}.jpg";

      final nuevo = await db.guardarAdjuntoIncidencia(
        fecha: widget.fecha,
        rutaOrigen: foto.path,
        nombreOriginal: nombreFoto,
        tipo: 'imagen',
      );

      if (!mounted) return;
      setState(() {
        _adjuntos.add(nuevo);
        _huboCambiosAdjuntos = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Argazkia ondo gorde da"),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Errorea kamera irekitzean: $e"),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _adjuntarArchivo() async {
    try {
      final archivo = await FilePicker.pickFile(
        dialogTitle: "Hautatu fitxategia edo argazkia",
        type: FileType.any,
      );
      if (archivo == null || archivo.path == null) return;

      final nombre = archivo.name.isNotEmpty
          ? archivo.name
          : p.basename(archivo.path!);
      final esImg = _esImagenPorNombre(nombre, '');

      final nuevo = await db.guardarAdjuntoIncidencia(
        fecha: widget.fecha,
        rutaOrigen: archivo.path!,
        nombreOriginal: nombre,
        tipo: esImg ? 'imagen' : 'archivo',
      );

      if (!mounted) return;
      setState(() {
        _adjuntos.add(nuevo);
        _huboCambiosAdjuntos = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erantsita: $nombre"),
          backgroundColor: Colors.teal,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Errorea fitxategia eranstean: $e"),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _eliminarAdjunto(Map<String, dynamic> adj) async {
    final id = adj['id'] as int?;
    final nombre = adj['nombre']?.toString() ?? '';
    if (id == null) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Fitxategia ezabatu?"),
        content: Text("'$nombre' betiko ezabatuko da."),
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

    await db.eliminarAdjuntoIncidencia(id);
    if (!mounted) return;

    setState(() {
      _adjuntos.removeWhere((item) => item['id'] == id);
      _huboCambiosAdjuntos = true;
    });
  }

  Future<void> _abrirOCompartirAdjunto(Map<String, dynamic> adj) async {
    final ruta = adj['ruta_local']?.toString() ?? '';
    final nombre = adj['nombre']?.toString() ?? 'fitxategia';
    final tipo = adj['tipo']?.toString() ?? '';

    if (ruta.isEmpty || !await File(ruta).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Fitxategia ez da aurkitu"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_esImagenPorNombre(nombre, tipo)) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(File(ruta)),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.share_rounded),
                      tooltip: "Partekatu / Ireki",
                      onPressed: () async {
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [XFile(ruta)],
                            text: "$nombre (${widget.fecha})",
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close),
                      tooltip: "Itxi",
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Text(
                  nombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(ruta)],
          text: "$nombre (${widget.fecha})",
        ),
      );
    }
  }

  String _horaCorta(String? h) {
    if (h == null || h.isEmpty) return "";
    return h.length >= 5 ? h.substring(0, 5) : h;
  }

  int _minutosBaseEstimados() {
    if (lanOrduakBase != null && lanOrduakBase! > 0) {
      return lanOrduakBase!;
    }
    if (hasiera != null && amaiera != null && hasiera!.isNotEmpty && amaiera!.isNotEmpty) {
      final p1 = hasiera!.split(":");
      final p2 = amaiera!.split(":");
      if (p1.length >= 2 && p2.length >= 2) {
        final h1 = int.tryParse(p1[0]) ?? 0;
        final m1 = int.tryParse(p1[1]) ?? 0;
        final h2 = int.tryParse(p2[0]) ?? 0;
        final m2 = int.tryParse(p2[1]) ?? 0;
        int t1 = h1 * 60 + m1;
        int t2 = h2 * 60 + m2;
        if (t2 < t1) t2 += 24 * 60; // turno nocturno
        return t2 - t1;
      }
    }
    return 0;
  }

  String _formatearHorasMinutos(int totalMinutos) {
    final signo = totalMinutos < 0 ? "-" : "";
    final absMin = totalMinutos.abs();
    final h = absMin ~/ 60;
    final m = absMin % 60;
    if (h > 0 && m > 0) return "$signo${h}h ${m}m";
    if (h > 0) return "$signo${h}h";
    return "$signo${m}m";
  }

  void _modificarAjuste(int delta) {
    setState(() {
      _ajusteMinutos += delta;
      _minutosInputController.text = _ajusteMinutos == 0 ? "" : "$_ajusteMinutos";
    });
  }

  void _fijarAjuste(int valor) {
    setState(() {
      _ajusteMinutos = valor;
      _minutosInputController.text = _ajusteMinutos == 0 ? "" : "$_ajusteMinutos";
    });
  }

  Future<void> _guardar() async {
    final notas = _notasController.text.trim();
    await db.guardarIncidenciaDia(widget.fecha, notas, _ajusteMinutos);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Oharrak eta doikuntza ondo gorde dira"),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final minutosBase = _minutosBaseEstimados();
    final minutosFinales = minutosBase + _ajusteMinutos;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _huboCambiosAdjuntos) {}
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _huboCambiosAdjuntos),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Eguneko oharrak",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              "${widget.fecha}  ·  ${widget.turno} (${widget.tipo})",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, size: 26),
            tooltip: "Gorde",
            onPressed: _guardar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Tarjeta informativa del turno
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Txanda: ${widget.turno} (${widget.tipo})",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            if (hasiera != null && amaiera != null && hasiera!.isNotEmpty)
                              Text(
                                "Ordutegia: ${_horaCorta(hasiera)} - ${_horaCorta(amaiera)}",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                          ],
                        ),
                        if (minutosBase > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade800,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "Oinarria: ${_formatearHorasMinutos(minutosBase)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 2. Primer recuadro: Notas e Incidencias del día
                  Row(
                    children: [
                      Icon(Icons.edit_note_rounded, color: Colors.blueGrey.shade800, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        "Zerbait gertatu da gaur?",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Hemen zerbait idazten baduzu, ⭐ bat agertuko da egunaren ondoan egutegian.",
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notasController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: "Adib: Trafiko handia 4. linean (+15 min). Ibilgailu aldaketa txandaren erdian. Erreleboko gidaria falta...",
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.blueGrey.shade700, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 📎 2B. Botones para adjuntar archivo o sacar foto con la cámara
                  Row(
                    children: [
                      Icon(Icons.attach_file_rounded,
                          color: Colors.blueGrey.shade800, size: 20),
                      const SizedBox(width: 6),
                      const Text(
                        "Dokumentuak eta argazkiak",
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal.shade800,
                            side: BorderSide(color: Colors.teal.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 20),
                          label: const Text(
                            "Atera argazkia",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          onPressed: _sacarFoto,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo.shade800,
                            side: BorderSide(color: Colors.indigo.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon:
                              const Icon(Icons.upload_file_outlined, size: 20),
                          label: const Text(
                            "Erantsi fitxategia",
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          onPressed: _adjuntarArchivo,
                        ),
                      ),
                    ],
                  ),

                  // Lista de fotos y documentos guardados en este día
                  if (_adjuntos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _adjuntos.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade300),
                        itemBuilder: (ctx, i) {
                          final adj = _adjuntos[i];
                          final nombre =
                              adj['nombre']?.toString() ?? 'Fitxategia';
                          final tipo = adj['tipo']?.toString() ?? '';
                          final ruta = adj['ruta_local']?.toString() ?? '';
                          final esImg = _esImagenPorNombre(nombre, tipo);
                          final existeArchivo =
                              ruta.isNotEmpty && File(ruta).existsSync();

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            leading: esImg && existeArchivo
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      File(ruta),
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      esImg
                                          ? Icons.image_outlined
                                          : Icons.description_outlined,
                                      color: Colors.indigo.shade700,
                                    ),
                                  ),
                            title: Text(
                              nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              esImg
                                  ? "Sakatu argazkia ikusteko"
                                  : "Sakatu dokumentua irekitzeko",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    esImg
                                        ? Icons.visibility_outlined
                                        : Icons.open_in_new_rounded,
                                    size: 20,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                  tooltip: "Ikusi / Ireki",
                                  onPressed: () =>
                                      _abrirOCompartirAdjunto(adj),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.red,
                                  ),
                                  tooltip: "Ezabatu",
                                  onPressed: () => _eliminarAdjunto(adj),
                                ),
                              ],
                            ),
                            onTap: () => _abrirOCompartirAdjunto(adj),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 3. Segundo recuadro: Sumar o restar tiempo a la jornada
                  Row(
                    children: [
                      Icon(Icons.more_time_rounded, color: Colors.blueGrey.shade800, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        "Lanaldiaren doikuntza (+ / - denbora)",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Gehitu denbora lanaldia luzatu bada edo kendu denbora berandu iritsi bazara edo lehenago irten bazara.",
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),

                  // Indicador visual del ajuste
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: _ajusteMinutos > 0
                          ? Colors.green.shade50
                          : (_ajusteMinutos < 0 ? Colors.red.shade50 : Colors.grey.shade100),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _ajusteMinutos > 0
                            ? Colors.green.shade300
                            : (_ajusteMinutos < 0 ? Colors.red.shade300 : Colors.grey.shade300),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _ajusteMinutos > 0
                                  ? Icons.add_circle
                                  : (_ajusteMinutos < 0 ? Icons.remove_circle : Icons.timer_outlined),
                              color: _ajusteMinutos > 0
                                  ? Colors.green.shade800
                                  : (_ajusteMinutos < 0 ? Colors.red.shade800 : Colors.grey.shade700),
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _ajusteMinutos > 0
                                  ? "+$_ajusteMinutos min (${_formatearHorasMinutos(_ajusteMinutos)})"
                                  : (_ajusteMinutos < 0
                                      ? "$_ajusteMinutos min (${_formatearHorasMinutos(_ajusteMinutos)})"
                                      : "0 min (Doikuntzarik gabe)"),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _ajusteMinutos > 0
                                    ? Colors.green.shade900
                                    : (_ajusteMinutos < 0 ? Colors.red.shade900 : Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        if (_ajusteMinutos != 0)
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => _fijarAjuste(0),
                            child: const Text("0-ra jarri"),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Botones rápidos para restar
                  Row(
                    children: [
                      const Text("Kendu:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildBotonAjuste("-60m", -60, Colors.red.shade700),
                            _buildBotonAjuste("-30m", -30, Colors.red.shade700),
                            _buildBotonAjuste("-15m", -15, Colors.red.shade700),
                            _buildBotonAjuste("-5m", -5, Colors.red.shade700),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Botones rápidos para sumar
                  Row(
                    children: [
                      const Text("Gehitu:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildBotonAjuste("+5m", 5, Colors.green.shade700),
                            _buildBotonAjuste("+15m", 15, Colors.green.shade700),
                            _buildBotonAjuste("+30m", 30, Colors.green.shade700),
                            _buildBotonAjuste("+45m", 45, Colors.green.shade700),
                            _buildBotonAjuste("+60m", 60, Colors.green.shade700),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // O escribir minutos exactos
                  Row(
                    children: [
                      const Text("Minutu zehatzak:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 90,
                        height: 38,
                        child: TextField(
                          controller: _minutosInputController,
                          keyboardType: const TextInputType.numberWithOptions(signed: true),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: "adib: 25",
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null) {
                              setState(() {
                                _ajusteMinutos = parsed;
                              });
                            } else if (val.isEmpty || val == "-") {
                              setState(() {
                                _ajusteMinutos = 0;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  if (minutosBase > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Azken lanaldia guztira:",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            _formatearHorasMinutos(minutosFinales),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 30),

                  // Botón principal de guardado
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.save_outlined, size: 20),
                      label: const Text("Gorde aldaketak", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: _guardar,
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildBotonAjuste(String etiqueta, int delta, Color color) {
    return ActionChip(
      label: Text(
        etiqueta,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () => _modificarAjuste(delta),
    );
  }
}
