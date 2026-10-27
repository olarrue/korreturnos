import 'package:flutter/material.dart';
import 'busqueda_servicio.dart';
import 'colores_turno.dart';
import 'configurar_semanas.dart';
import 'copia_seguridad.dart';
import 'festivos_anuales.dart';
import 'horas_bru.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  bool huboCambios = false;

  Widget _botonMenu({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required Color colorIcono,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorIcono.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, color: colorIcono, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Al salir, CalendarioMensual siempre recarga
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Ezarpenak"),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Botón Semana orientativa
            _botonMenu(
              icono: Icons.calendar_month,
              colorIcono: Colors.indigo,
              titulo: "Orientazio-astea",
              subtitulo: "Oinarrizko astea eta txandakatzea konfiguratu (1 - 18)",
              onTap: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ConfigurarSemanasScreen(),
                  ),
                );
                if (res == true) {
                  huboCambios = true;
                }
              },
            ),

            // 2. Botón Configurar colores
            _botonMenu(
              icono: Icons.palette,
              colorIcono: Colors.deepOrange,
              titulo: "Koloreak konfiguratu",
              subtitulo: "Txanda eta mota bakoitzaren kolorea pertsonalizatu",
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ColoresTurnoScreen(),
                  ),
                );
                huboCambios = true;
              },
            ),

            // 3. Botón Copia de seguridad
            _botonMenu(
              icono: Icons.cloud_sync,
              colorIcono: Colors.teal,
              titulo: "Segurtasun kopia",
              subtitulo: "Txandak esportatu eta inportatu (PC, Nextcloud, Drive, Gmail)",
              onTap: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CopiaSeguridadScreen(),
                  ),
                );
                if (res == true) {
                  huboCambios = true;
                }
              },
            ),

            // 4. Botón BRU orduak (Horas BRU)
            _botonMenu(
              icono: Icons.timer_off_outlined,
              colorIcono: Colors.purple,
              titulo: "BRU orduak",
              subtitulo: "Hautatu egun bat bere lan-orduak zenbaketa orokorretik kentzeko",
              onTap: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HorasBruScreen(),
                  ),
                );
                if (res == true) {
                  huboCambios = true;
                }
              },
            ),

            // 5. Botón Zerbitzuaren bilaketa (Búsqueda por servicio)
            _botonMenu(
              icono: Icons.manage_search_rounded,
              colorIcono: Colors.blue.shade800,
              titulo: "Zerbitzuaren bilaketa",
              subtitulo: "Bilatu zerbitzu zenbaki bat bere ordutegia eta ibilbidea ikusteko",
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BusquedaServicioScreen(),
                  ),
                );
              },
            ),

            // 6. Botón Urteko jaiegunak (Festivos anuales)
            _botonMenu(
              icono: Icons.celebration_outlined,
              colorIcono: Colors.red.shade700,
              titulo: "Urteko jaiegunak",
              subtitulo: "Markatu urteko jaiegunak egutegian SDF abisuak jasotzeko",
              onTap: () async {
                final res = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FestivosAnualesScreen(),
                  ),
                );
                if (res == true) {
                  huboCambios = true;
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
