import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';

class CopiaSeguridadScreen extends StatefulWidget {
  const CopiaSeguridadScreen({super.key});

  @override
  State<CopiaSeguridadScreen> createState() => _CopiaSeguridadScreenState();
}

class _CopiaSeguridadScreenState extends State<CopiaSeguridadScreen> {
  final db = DBHelper();
  bool procesando = false;
  bool huboRestauracion = false;

  // =====================================================
  // 🔥 EXPORTAR COPIA DE SEGURIDAD
  // =====================================================
  Future<void> _exportarCopia() async {
    setState(() => procesando = true);

    try {
      final rutaCopia = await db.exportarCopiaSeguridad();

      if (!mounted) return;

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // En PC: Guardar directamente en la carpeta deseada (Nextcloud, Drive, etc.)
        final nombreArchivo = rutaCopia.split(Platform.pathSeparator).last;
        final bytes = await File(rutaCopia).readAsBytes();

        final uriGuardado = await FilePicker.saveFile(
          dialogTitle: "Segurtasun kopia gorde",
          fileName: nombreArchivo,
          bytes: bytes,
        );

        if (uriGuardado != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Kopia ondo gorde da: ${uriGuardado.path}"),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      } else {
        // En Móvil: Compartir con Nextcloud, Drive, Gmail, WhatsApp
        final xFile = XFile(rutaCopia);
        await SharePlus.instance.share(
          ShareParams(
            files: [xFile],
            subject: "Korreturnos segurtasun kopia",
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Errorea esportatzean: $e"),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => procesando = false);
    }
  }

  // =====================================================
  // 🔥 RESTAURAR COPIA DE SEGURIDAD
  // =====================================================
  Future<void> _restaurarCopia() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Segurtasun kopia berreskuratu?"),
        content: const Text(
          "Ekintza honek egungo txandak eta erregistroak hautatutako kopiako fitxategikoekin ordezkatuko ditu.\n\nJarraitu nahi duzu?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Utzi"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Fitxategia hautatu"),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => procesando = true);

    try {
      final archivoSeleccionado = await FilePicker.pickFile(
        dialogTitle: "Hautatu segurtasun kopia fitxategia (.db)",
        type: FileType.any,
      );

      if (archivoSeleccionado == null || archivoSeleccionado.path == null) {
        setState(() => procesando = false);
        return;
      }

      await db.restaurarDatabaseDesde(archivoSeleccionado.path!);

      huboRestauracion = true;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Segurtasun kopia ondo berreskuratu da!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Errorea berreskuratzean"),
          content: Text(
            "Ezin izan da segurtasun kopia berreskuratu:\n$e\n\nZiurtatu baliozko .db fitxategi bat hautatu duzula.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Ados"),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && huboRestauracion) {
          // El resultado ya se gestiona si se hace pop manual
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Segurtasun Kopia"),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, huboRestauracion),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                color: Colors.blueGrey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.blueGrey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blueGrey.shade700),
                          const SizedBox(width: 8),
                          Text(
                            "Sinkronizazioa PC ↔ Mugikorra",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.blueGrey.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "• PCan: Esportatu eta gorde fitxategia zure Nextcloud edo Google Drive karpetan.\n"
                        "• Mugikorrean: Sakatu Berreskuratu eta hautatu fitxategia zure Nextcloud, Drive edo Deskargetatik.\n"
                        "• Partekatzeko: Bidali fitxategia Gmailez edo WhatsAppez lankideei.",
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.blueGrey.shade800,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (procesando)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                // Opción 1: Exportar
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "1. Segurtasun kopia sortu",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Platform.isWindows
                              ? "Gorde zure txanden kopia bat zuzenean diskoan edo Nextcloud/Drive karpeta sinkronizatuan."
                              : "Esportatu zure txandak Gmailez edo WhatsAppez bidaltzeko edo Drive/Nextcloud-era igotzeko.",
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey.shade800,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              Platform.isWindows
                                  ? "Esportatu eta Gorde PCan"
                                  : "Esportatu eta Partekatu",
                            ),
                            onPressed: _exportarCopia,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Opción 2: Restaurar
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "2. Segurtasun kopia berreskuratu",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Kargatu txandak aurrez sortutako .db fitxategi batetik zure egutegia berehala eguneratzeko.",
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: Colors.blueGrey.shade700, width: 1.2),
                            ),
                            icon: const Icon(Icons.download),
                            label: const Text(
                              "Kopia berreskuratu (Inportatu)",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onPressed: _restaurarCopia,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
