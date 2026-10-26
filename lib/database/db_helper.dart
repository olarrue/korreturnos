import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

// 🔥 WINDOWS
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<String> getDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, 'datos.db');
  }

  Future<void> cerrarDatabase() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _initDB() async {
    final path = await getDatabasePath();

    // 1. Comprobamos si la base de datos ya existe en el dispositivo
    final existe = await databaseExists(path);

    if (!existe) {
      // 2. Si NO existe, la copiamos desde los assets (solo la primera vez)
      debugPrint("Copiando base de datos desde assets por primera vez...");

      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (_) {}

      final data = await rootBundle.load('assets/datos.db');
      final bytes = data.buffer.asUint8List();
      await File(path).writeAsBytes(bytes, flush: true);
    }

    // 3. Abrimos la base de datos normal
    final db = await openDatabase(path);

    await _asegurarColumnas(db);

    return db;
  }

  // =====================================================
  // 🔥 MIGRACIONES AUTOMÁTICAS
  // =====================================================
  Future<void> _asegurarColumnas(Database db) async {
    await _asegurarColumnaTipo(db);

    // Asegurar columnas de notas y ajuste de minutos en registro_diario
    try {
      final res = await db.rawQuery("PRAGMA table_info(registro_diario)");
      final cols = res.map((c) => c['name']?.toString()).toSet();

      if (!cols.contains('observaciones')) {
        await db.execute(
            "ALTER TABLE registro_diario ADD COLUMN observaciones TEXT DEFAULT ''");
      }
      if (!cols.contains('ajuste_minutos')) {
        await db.execute(
            "ALTER TABLE registro_diario ADD COLUMN ajuste_minutos INTEGER DEFAULT 0");
      }
      if (!cols.contains('hasiera')) {
        await db.execute(
            "ALTER TABLE registro_diario ADD COLUMN hasiera TEXT DEFAULT ''");
      }
      if (!cols.contains('amaiera')) {
        await db.execute(
            "ALTER TABLE registro_diario ADD COLUMN amaiera TEXT DEFAULT ''");
      }
      if (!cols.contains('lan_orduak')) {
        await db.execute(
            "ALTER TABLE registro_diario ADD COLUMN lan_orduak INTEGER DEFAULT 0");
      }

      // Rellenar (congelar) horario e información de jornada en los días ya registrados
      // para que futuros cambios en un turno no alteren los días pasados/ya metidos.
      await db.execute('''
        UPDATE registro_diario
        SET
          hasiera = COALESCE(
            NULLIF(hasiera, ''),
            (SELECT t.hasiera FROM turnos t WHERE t.turno = registro_diario.turno AND t.tipo = registro_diario.tipo LIMIT 1),
            (SELECT t.hasiera FROM turnos t WHERE t.turno = registro_diario.turno LIMIT 1),
            ''
          ),
          amaiera = COALESCE(
            NULLIF(amaiera, ''),
            (SELECT t.amaiera FROM turnos t WHERE t.turno = registro_diario.turno AND t.tipo = registro_diario.tipo LIMIT 1),
            (SELECT t.amaiera FROM turnos t WHERE t.turno = registro_diario.turno LIMIT 1),
            ''
          ),
          lan_orduak = COALESCE(
            CASE WHEN lan_orduak IS NOT NULL AND lan_orduak > 0 THEN lan_orduak ELSE NULL END,
            (SELECT t.lan_orduak FROM turnos t WHERE t.turno = registro_diario.turno AND t.tipo = registro_diario.tipo LIMIT 1),
            (SELECT t.lan_orduak FROM turnos t WHERE t.turno = registro_diario.turno LIMIT 1),
            0
          )
        WHERE hasiera IS NULL OR hasiera = '' OR amaiera IS NULL OR amaiera = '' OR lan_orduak IS NULL OR lan_orduak = 0
      ''');
    } catch (e) {
      debugPrint("Error asegurando columnas en registro_diario: $e");
    }

    // Asegurar columna es_manual en turnos
    try {
      final resTurnos = await db.rawQuery("PRAGMA table_info(turnos)");
      final colsTurnos = resTurnos.map((c) => c['name']?.toString()).toSet();

      if (!colsTurnos.contains('es_manual')) {
        await db.execute(
            "ALTER TABLE turnos ADD COLUMN es_manual INTEGER DEFAULT 0");

        // Cualquier turno que no tenga servicios asociados es considerado manual
        await db.execute('''
          UPDATE turnos SET es_manual = 1 
          WHERE NOT EXISTS (
            SELECT 1 FROM servicios 
            WHERE servicios.turno = turnos.turno AND servicios.tipo = turnos.tipo
          )
        ''');
      }
    } catch (e) {
      debugPrint("Error asegurando columna es_manual en turnos: $e");
    }

    // Asegurar tabla para registro de alarmas activadas (con columna hora_alarma)
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS alarmas_activadas (
          fecha TEXT,
          servicio TEXT,
          hora TEXT,
          hora_alarma TEXT,
          PRIMARY KEY (fecha, servicio, hora)
        )
      ''');

      final resAlarmas =
          await db.rawQuery("PRAGMA table_info(alarmas_activadas)");
      final colsAlarmas =
          resAlarmas.map((c) => c['name']?.toString()).toSet();

      if (!colsAlarmas.contains('hora_alarma')) {
        await db.execute(
            "ALTER TABLE alarmas_activadas ADD COLUMN hora_alarma TEXT DEFAULT ''");
      }
      if (!colsAlarmas.contains('fecha_disparo')) {
        await db.execute(
            "ALTER TABLE alarmas_activadas ADD COLUMN fecha_disparo TEXT DEFAULT ''");
      }
    } catch (e) {
      debugPrint("Error asegurando tabla alarmas_activadas: $e");
    }

    // Asegurar tabla para archivos y fotos adjuntas en incidencias del día
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS adjuntos_incidencia (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          fecha TEXT,
          nombre TEXT,
          tipo TEXT,
          ruta_local TEXT,
          datos BLOB,
          creado_en TEXT
        )
      ''');
    } catch (e) {
      debugPrint("Error asegurando tabla adjuntos_incidencia: $e");
    }

    // Corregir itinerarios de servicios según la tabla itinerarios2
    await _corregirItinerariosServicios(db);
  }

  /// Corrige los itinerarios de la tabla servicios según oharrak e itinerarios2
  Future<void> _corregirItinerariosServicios(Database db) async {
    try {
      final tablas = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='itinerarios2'");
      if (tablas.isEmpty) return;

      // Actualizar itinerarios en servicios según la regla:
      // - Si en servicios oharrak es 'MATERIAL' -> itinerario de 'sin correspondencia'
      // - Si oharrak es NULL o vacío -> itinerario de 'con correspondencia'
      // - Si oharrak es 'S.S.' o contiene 'S.S' / 'SS' -> itinerario de 'sin servicio'
      await db.execute('''
        UPDATE servicios
        SET itinerario = COALESCE(
          (
            SELECT i.itinerario FROM itinerarios2 i
            WHERE LOWER(REPLACE(REPLACE(i.irteera, ' ', ''), '-', '')) = LOWER(REPLACE(REPLACE(servicios.irteera, ' ', ''), '-', ''))
              AND LOWER(REPLACE(REPLACE(i.helmuga, ' ', ''), '-', '')) = LOWER(REPLACE(REPLACE(servicios.helmuga, ' ', ''), '-', ''))
              AND LOWER(TRIM(i.oharrak)) = CASE 
                    WHEN UPPER(COALESCE(servicios.oharrak, '')) LIKE '%MATERIAL%' THEN 'sin correspondencia'
                    WHEN UPPER(COALESCE(servicios.oharrak, '')) LIKE '%S.S%' OR UPPER(COALESCE(servicios.oharrak, '')) LIKE '%SS%' THEN 'sin servicio'
                    ELSE 'con correspondencia'
                  END
            LIMIT 1
          ),
          (
            SELECT i.itinerario FROM itinerarios2 i
            WHERE LOWER(REPLACE(REPLACE(i.irteera, ' ', ''), '-', '')) = LOWER(REPLACE(REPLACE(servicios.irteera, ' ', ''), '-', ''))
              AND LOWER(REPLACE(REPLACE(i.helmuga, ' ', ''), '-', '')) = LOWER(REPLACE(REPLACE(servicios.helmuga, ' ', ''), '-', ''))
            LIMIT 1
          ),
          servicios.itinerario
        )
        WHERE servicios.irteera IS NOT NULL AND servicios.irteera != '';
      ''');
    } catch (e) {
      debugPrint("Error al corregir itinerarios de servicios: $e");
    }
  }

  Future<void> _asegurarColumnaTipo(Database db) async {
    try {
      final res = await db.rawQuery("PRAGMA table_info(config_colores)");
      final pkCols = res
          .where((col) => (col['pk'] as int? ?? 0) > 0)
          .map((col) => col['name']?.toString())
          .toSet();
      final hasTipo = res.any((col) => col['name'] == 'tipo');

      // Si la clave primaria no incluye tanto 'letra' como 'tipo', migramos la tabla
      // para que los turnos LAB y SDF puedan tener colores independientes sin sobrescribirse.
      if (!pkCols.contains('letra') || !pkCols.contains('tipo')) {
        debugPrint("Migrando config_colores a clave compuesta (letra, tipo)...");

        await db.execute('''
          CREATE TABLE config_colores_new (
            letra TEXT,
            tipo TEXT DEFAULT '',
            color INTEGER,
            PRIMARY KEY (letra, tipo)
          )
        ''');

        if (hasTipo) {
          await db.execute('''
            INSERT OR REPLACE INTO config_colores_new (letra, tipo, color)
            SELECT letra, COALESCE(tipo, ''), color FROM config_colores
          ''');
        } else {
          await db.execute('''
            INSERT OR REPLACE INTO config_colores_new (letra, tipo, color)
            SELECT letra, '', color FROM config_colores
          ''');
        }

        await db.execute('DROP TABLE config_colores');
        await db.execute(
            'ALTER TABLE config_colores_new RENAME TO config_colores');
        debugPrint("Migración de config_colores completada con éxito.");
      }
    } catch (e) {
      debugPrint("Error asegurando clave compuesta en config_colores: $e");
    }
  }

  // =====================================================
  // 🔥 ALARMAS ACTIVADAS
  // =====================================================

  Future<void> guardarAlarmaActivada(
      String fecha, String servicio, String hora,
      {String? horaAlarma, String? fechaDisparo}) async {
    final dbClient = await database;
    await dbClient.insert(
      'alarmas_activadas',
      {
        'fecha': fecha,
        'servicio': servicio,
        'hora': hora,
        'hora_alarma': horaAlarma ?? '',
        'fecha_disparo': fechaDisparo ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> eliminarAlarmaActivada(
      String fecha, String servicio, String hora) async {
    final dbClient = await database;
    // Soporta coincidencia exacta o normalizada (con o sin segundos)
    final horaCorta = hora.length >= 5 ? hora.substring(0, 5) : hora;
    await dbClient.delete(
      'alarmas_activadas',
      where: 'fecha = ? AND servicio = ? AND (hora = ? OR hora LIKE ? OR hora LIKE ?)',
      whereArgs: [fecha, servicio, hora, '$horaCorta%', '$hora%'],
    );
  }

  Future<Map<String, Map<String, String>>> getAlarmasActivadas(String fecha) async {
    final dbClient = await database;
    final res = await dbClient.query(
      'alarmas_activadas',
      where: 'fecha = ?',
      whereArgs: [fecha],
    );

    final ahora = DateTime.now();
    final hoyStr =
        "${ahora.year.toString().padLeft(4, '0')}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";
    final ahoraMin = ahora.hour * 60 + ahora.minute;

    Map<String, Map<String, String>> map = {};
    List<Map<String, dynamic>> sonadasParaBorrar = [];

    for (var r in res) {
      final s = r['servicio']?.toString() ?? '';
      final h = r['hora']?.toString() ?? '';
      final ha = r['hora_alarma']?.toString() ?? '';
      final fdStr = r['fecha_disparo']?.toString() ?? '';

      bool haSonado = false;
      if (fdStr.isNotEmpty) {
        try {
          final fd = DateTime.parse(fdStr);
          if (!ahora.isBefore(fd)) {
            haSonado = true;
          }
        } catch (_) {}
      }

      if (!haSonado) {
        if (fecha.isNotEmpty && fecha.compareTo(hoyStr) < 0) {
          haSonado = true;
        } else if (fecha == hoyStr) {
          final horaEfectiva = ha.isNotEmpty ? ha : h;
          final partes = horaEfectiva.split(':');
          if (partes.length >= 2) {
            final horaInt = int.tryParse(partes[0]) ?? 0;
            final minInt = int.tryParse(partes[1]) ?? 0;
            if (ahoraMin >= (horaInt * 60 + minInt)) {
              haSonado = true;
            }
          }
        }
      }

      if (haSonado) {
        sonadasParaBorrar.add(r);
      } else if (s.isNotEmpty && h.isNotEmpty) {
        map["$s|||$h"] = {
          'hora_alarma': ha,
          'fecha_disparo': fdStr,
        };
      }
    }

    for (var r in sonadasParaBorrar) {
      await dbClient.delete(
        'alarmas_activadas',
        where: 'fecha = ? AND servicio = ? AND hora = ?',
        whereArgs: [r['fecha'], r['servicio'], r['hora']],
      );
    }

    return map;
  }

  /// Devuelve el conjunto de fechas con alarmas activas (pendientes) y purga las que ya han sonado
  Future<Set<String>> getFechasConAlarmasActivas() async {
    final dbClient = await database;
    final res = await dbClient.query('alarmas_activadas');
    if (res.isEmpty) return {};

    final ahora = DateTime.now();
    final hoyStr =
        "${ahora.year.toString().padLeft(4, '0')}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";
    final ahoraMin = ahora.hour * 60 + ahora.minute;

    Set<String> fechasConAlarma = {};
    List<Map<String, dynamic>> sonadasParaBorrar = [];

    for (var r in res) {
      final f = r['fecha']?.toString() ?? '';
      if (f.isEmpty) continue;

      bool haSonado = false;

      // 1. Si tiene fecha_disparo exacta guardada (ISO timestamp)
      final fdStr = r['fecha_disparo']?.toString() ?? '';
      if (fdStr.isNotEmpty) {
        try {
          final fd = DateTime.parse(fdStr);
          if (!ahora.isBefore(fd)) {
            haSonado = true;
          }
        } catch (_) {}
      }

      // 2. Si no tiene fecha_disparo o como comprobación de respaldo:
      if (!haSonado) {
        // Si la fecha del turno es un día anterior a hoy, ya sonó
        if (f.compareTo(hoyStr) < 0) {
          haSonado = true;
        } else if (f == hoyStr) {
          final horaAlarma = r['hora_alarma']?.toString() ?? '';
          final horaServicio = r['hora']?.toString() ?? '';
          final horaEfectiva = horaAlarma.isNotEmpty ? horaAlarma : horaServicio;
          final partes = horaEfectiva.split(':');
          if (partes.length >= 2) {
            final h = int.tryParse(partes[0]) ?? 0;
            final m = int.tryParse(partes[1]) ?? 0;
            final alarmaMin = h * 60 + m;
            if (ahoraMin >= alarmaMin) {
              haSonado = true;
            }
          }
        }
      }

      if (haSonado) {
        sonadasParaBorrar.add(r);
      } else {
        fechasConAlarma.add(f);
      }
    }

    // Purgar de SQLite las alarmas ya sonadas
    for (var r in sonadasParaBorrar) {
      await dbClient.delete(
        'alarmas_activadas',
        where: 'fecha = ? AND servicio = ? AND hora = ?',
        whereArgs: [r['fecha'], r['servicio'], r['hora']],
      );
    }

    return fechasConAlarma;
  }

  // =====================================================
  // 🔥 COPIAS DE SEGURIDAD Y RESTAURACIÓN
  // =====================================================

  /// Genera una copia limpia en el directorio temporal con marca temporal
  Future<String> exportarCopiaSeguridad() async {
    await database; // Asegura que la BD esté abierta y escrita
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      throw Exception("El archivo de base de datos no existe.");
    }

    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    final timestamp = "${now.year.toString().padLeft(4, '0')}-"
        "${now.month.toString().padLeft(2, '0')}-"
        "${now.day.toString().padLeft(2, '0')}_"
        "${now.hour.toString().padLeft(2, '0')}"
        "${now.minute.toString().padLeft(2, '0')}";
    final backupFileName = "korreturnos_copia_$timestamp.db";
    final backupPath = join(tempDir.path, backupFileName);

    await dbFile.copy(backupPath);
    return backupPath;
  }

  /// Restaura una base de datos externa sobre la actual de forma segura
  Future<bool> restaurarDatabaseDesde(String rutaArchivoOrigen) async {
    final nuevoArchivo = File(rutaArchivoOrigen);
    if (!await nuevoArchivo.exists()) {
      throw Exception("El archivo seleccionado no existe.");
    }

    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);
    String? backupPrevioPath;

    try {
      // 1. Cerrar conexión activa a SQLite
      await cerrarDatabase();

      // 2. Crear respaldo preventivo por si el archivo importado estuviera dañado
      if (await dbFile.exists()) {
        final tempDir = await getTemporaryDirectory();
        backupPrevioPath = join(tempDir.path, "datos_backup_seguridad.db");
        await dbFile.copy(backupPrevioPath);
      }

      // 3. Sobrescribir con la nueva base de datos
      await nuevoArchivo.copy(dbPath);

      // 4. Verificar integridad y tablas requeridas
      _db = await openDatabase(dbPath);
      final tables = await _db!.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final nombresTablas = tables.map((t) => t['name']?.toString()).toSet();

      if (!nombresTablas.contains('turnos') ||
          !nombresTablas.contains('registro_diario')) {
        throw Exception(
            "El archivo seleccionado no es una copia válida de Korreturnos.");
      }

      await _asegurarColumnas(_db!);
      return true;
    } catch (e) {
      debugPrint("Error restaurando base de datos: $e");

      // Restaurar el backup preventivo si hubo fallo
      if (backupPrevioPath != null && await File(backupPrevioPath).exists()) {
        try {
          await cerrarDatabase();
          await File(backupPrevioPath).copy(dbPath);
          _db = await openDatabase(dbPath);
        } catch (_) {}
      }
      rethrow;
    }
  }

  // =====================================================
  // 🔹 REGISTRO DIARIO, INCIDENCIAS Y AJUSTE DE TIEMPO
  // =====================================================

  Future<void> insertRegistro(String fecha, String turno, String tipo) async {
    final dbClient = await database;

    // Si ya existía un registro ese día, conservamos sus notas y ajuste de jornada
    final anterior = await getTurnoPorFecha(fecha);

    // Obtenemos los datos actuales del turno para congelar su horario y duración en este día
    final turnoActual = await getTurno(turno, tipo);
    final hasiera = turnoActual?['hasiera']?.toString() ?? '';
    final amaiera = turnoActual?['amaiera']?.toString() ?? '';
    int lanOrduak = (turnoActual?['lan_orduak'] as num?)?.toInt() ?? 0;

    if (lanOrduak <= 0 && hasiera.isNotEmpty && amaiera.isNotEmpty) {
      try {
        final p1 = hasiera.split(':');
        final p2 = amaiera.split(':');
        if (p1.length >= 2 && p2.length >= 2) {
          final min1 =
              (int.tryParse(p1[0]) ?? 0) * 60 + (int.tryParse(p1[1]) ?? 0);
          int min2 =
              (int.tryParse(p2[0]) ?? 0) * 60 + (int.tryParse(p2[1]) ?? 0);
          if (min2 < min1) min2 += 24 * 60;
          lanOrduak = min2 - min1;
        }
      } catch (_) {}
    }

    await dbClient.insert(
      'registro_diario',
      {
        'fecha': fecha,
        'turno': turno,
        'tipo': tipo,
        'hasiera': hasiera,
        'amaiera': amaiera,
        'lan_orduak': lanOrduak,
        'observaciones': anterior?['observaciones'] ?? '',
        'ajuste_minutos': anterior?['ajuste_minutos'] ?? 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> guardarIncidenciaDia(
      String fecha, String observaciones, int ajusteMinutos) async {
    final dbClient = await database;

    await dbClient.update(
      'registro_diario',
      {
        'observaciones': observaciones,
        'ajuste_minutos': ajusteMinutos,
      },
      where: 'fecha = ?',
      whereArgs: [fecha],
    );
  }

  // =====================================================
  // 📎 ADJUNTOS DE INCIDENCIAS (FOTOS Y ARCHIVOS)
  // =====================================================

  Future<Map<String, dynamic>> guardarAdjuntoIncidencia({
    required String fecha,
    required String rutaOrigen,
    required String nombreOriginal,
    required String tipo, // 'imagen' o 'archivo'
  }) async {
    final dbClient = await database;
    final docDir = await getApplicationDocumentsDirectory();
    final adjuntosDir = Directory(join(docDir.path, 'adjuntos'));
    if (!await adjuntosDir.exists()) {
      await adjuntosDir.create(recursive: true);
    }

    final archivoOrigen = File(rutaOrigen);
    final bytes = await archivoOrigen.readAsBytes();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nombreLimpio =
        nombreOriginal.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final rutaDestino =
        join(adjuntosDir.path, '${fecha}_${timestamp}_$nombreLimpio');

    await File(rutaDestino).writeAsBytes(bytes, flush: true);

    final creadoEn = DateTime.now().toIso8601String();
    final id = await dbClient.insert(
      'adjuntos_incidencia',
      {
        'fecha': fecha,
        'nombre': nombreOriginal,
        'tipo': tipo,
        'ruta_local': rutaDestino,
        'datos': bytes,
        'creado_en': creadoEn,
      },
    );

    return {
      'id': id,
      'fecha': fecha,
      'nombre': nombreOriginal,
      'tipo': tipo,
      'ruta_local': rutaDestino,
      'creado_en': creadoEn,
    };
  }

  Future<List<Map<String, dynamic>>> getAdjuntosPorFecha(String fecha) async {
    final dbClient = await database;
    final res = await dbClient.query(
      'adjuntos_incidencia',
      columns: ['id', 'fecha', 'nombre', 'tipo', 'ruta_local', 'creado_en'],
      where: 'fecha = ?',
      whereArgs: [fecha],
      orderBy: 'id ASC',
    );

    final docDir = await getApplicationDocumentsDirectory();
    final adjuntosDir = Directory(join(docDir.path, 'adjuntos'));
    List<Map<String, dynamic>> lista = [];

    for (var row in res) {
      final map = Map<String, dynamic>.from(row);
      String rutaLocal = map['ruta_local']?.toString() ?? '';
      final id = map['id'] as int?;

      // Si el archivo no existe en disco (ej. tras restaurar copia .db), lo reconstruimos desde el BLOB
      if (id != null && (rutaLocal.isEmpty || !await File(rutaLocal).exists())) {
        try {
          if (!await adjuntosDir.exists()) {
            await adjuntosDir.create(recursive: true);
          }
          final blobRes = await dbClient.query(
            'adjuntos_incidencia',
            columns: ['datos'],
            where: 'id = ?',
            whereArgs: [id],
          );
          if (blobRes.isNotEmpty && blobRes.first['datos'] != null) {
            final bytes = blobRes.first['datos'] as Uint8List;
            final nombreLimpio = (map['nombre']?.toString() ?? 'adjunto')
                .replaceAll(RegExp(r'[^\w\.\-]'), '_');
            rutaLocal = join(adjuntosDir.path, '${fecha}_${id}_$nombreLimpio');
            await File(rutaLocal).writeAsBytes(bytes, flush: true);
            await dbClient.update(
              'adjuntos_incidencia',
              {'ruta_local': rutaLocal},
              where: 'id = ?',
              whereArgs: [id],
            );
            map['ruta_local'] = rutaLocal;
          }
        } catch (e) {
          debugPrint("Error reconstruyendo adjunto $id: $e");
        }
      }

      lista.add(map);
    }

    return lista;
  }

  Future<void> eliminarAdjuntoIncidencia(int id) async {
    final dbClient = await database;
    final res = await dbClient.query(
      'adjuntos_incidencia',
      columns: ['ruta_local'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (res.isNotEmpty) {
      final ruta = res.first['ruta_local']?.toString() ?? '';
      if (ruta.isNotEmpty) {
        try {
          final f = File(ruta);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
    }
    await dbClient.delete(
      'adjuntos_incidencia',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Set<String>> getFechasConAdjuntos() async {
    final dbClient = await database;
    try {
      final res = await dbClient.rawQuery(
        'SELECT DISTINCT fecha FROM adjuntos_incidencia WHERE fecha IS NOT NULL',
      );
      return res
          .map((r) => r['fecha']?.toString() ?? '')
          .where((f) => f.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>?> getTurnoPorFecha(String fecha) async {
    final dbClient = await database;

    final res = await dbClient.query(
      'registro_diario',
      where: 'fecha = ?',
      whereArgs: [fecha],
    );

    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String, dynamic>>> getRegistros() async {
    final dbClient = await database;
    return await dbClient.query('registro_diario');
  }

  /// Devuelve todos los registros como un Mapa indexado por fecha (YYYY-MM-DD)
  Future<Map<String, Map<String, dynamic>>> getRegistrosMap() async {
    final list = await getRegistros();
    Map<String, Map<String, dynamic>> map = {};
    for (var row in list) {
      final fecha = row['fecha']?.toString();
      if (fecha != null) {
        map[fecha] = row;
      }
    }
    return map;
  }

  // =====================================================
  // 🔹 TURNOS
  // =====================================================

  Future<List<Map<String, dynamic>>> getTurnos() async {
    final dbClient = await database;
    return await dbClient.query('turnos');
  }

  /// Devuelve todos los turnos como un Mapa indexado por clave "turno-tipo" y "turno"
  Future<Map<String, Map<String, dynamic>>> getTurnosMap() async {
    final list = await getTurnos();
    Map<String, Map<String, dynamic>> map = {};
    for (var row in list) {
      final turno = row['turno']?.toString();
      final tipo = row['tipo']?.toString() ?? '';
      if (turno != null) {
        map["$turno-$tipo"] = row;
        if (!map.containsKey(turno)) {
          map[turno] = row;
        }
      }
    }
    return map;
  }

  /// Busca un turno por su nombre y opcionalmente su tipo (LAB, SDF, etc.)
  Future<Map<String, dynamic>?> getTurno(String turno, [String? tipo]) async {
    final dbClient = await database;

    final res = (tipo != null && tipo.isNotEmpty)
        ? await dbClient.query(
            'turnos',
            where: 'turno = ? AND tipo = ?',
            whereArgs: [turno, tipo],
          )
        : await dbClient.query(
            'turnos',
            where: 'turno = ?',
            whereArgs: [turno],
          );

    return res.isNotEmpty ? res.first : null;
  }

  Future<List<String>> getTurnosUnicos() async {
    final dbClient = await database;

    final res = await dbClient.rawQuery(
      'SELECT DISTINCT turno FROM turnos ORDER BY turno',
    );

    return res.map((e) => e['turno'] as String).toList();
  }

  /// Inserta o actualiza un turno en el catálogo sin alterar los días ya metidos en el calendario
  Future<void> guardarTurno({
    required String turno,
    required String tipo,
    required String hasiera,
    required String amaiera,
    required int lanOrduak,
    int esManual = 1,
    String? turnoAnterior,
    String? tipoAnterior,
  }) async {
    final dbClient = await database;

    // Antes de modificar el turno en el catálogo, nos aseguramos de que cualquier día
    // que ya estuviera metido en registro_diario conserve su horario y duración antiguos.
    final tRef = turnoAnterior ?? turno;
    final tipoRef = tipoAnterior ?? tipo;
    final antiguo = await getTurno(tRef, tipoRef);
    if (antiguo != null) {
      final hAnt = antiguo['hasiera']?.toString() ?? '';
      final aAnt = antiguo['amaiera']?.toString() ?? '';
      final lAnt = (antiguo['lan_orduak'] as num?)?.toInt() ?? 0;

      await dbClient.execute('''
        UPDATE registro_diario
        SET
          hasiera = CASE WHEN hasiera IS NULL OR hasiera = '' THEN ? ELSE hasiera END,
          amaiera = CASE WHEN amaiera IS NULL OR amaiera = '' THEN ? ELSE amaiera END,
          lan_orduak = CASE WHEN lan_orduak IS NULL OR lan_orduak = 0 THEN ? ELSE lan_orduak END
        WHERE turno = ? AND tipo = ?
      ''', [hAnt, aAnt, lAnt, tRef, tipoRef]);
    }

    if (turnoAnterior != null && tipoAnterior != null) {
      if (turnoAnterior != turno || tipoAnterior != tipo) {
        // Solo actualizamos el color y borramos la entrada antigua del catálogo de turnos;
        // NO tocamos registro_diario para que los días ya metidos no cambien.
        await dbClient.update(
          'config_colores',
          {'letra': turno, 'tipo': tipo},
          where: 'letra = ? AND tipo = ?',
          whereArgs: [turnoAnterior, tipoAnterior],
        );
        await dbClient.delete(
          'turnos',
          where: 'turno = ? AND tipo = ?',
          whereArgs: [turnoAnterior, tipoAnterior],
        );
      }
    }

    await dbClient.insert(
      'turnos',
      {
        'turno': turno,
        'tipo': tipo,
        'hasiera': hasiera,
        'amaiera': amaiera,
        'lan_orduak': lanOrduak,
        'gidari_orduak': null,
        'es_manual': esManual,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Elimina un turno si y solo si es manual (protegiendo los turnos oficiales)
  Future<void> deleteTurnoManual(String turno, String tipo) async {
    final dbClient = await database;
    await dbClient.delete(
      'turnos',
      where: 'turno = ? AND tipo = ? AND es_manual = 1',
      whereArgs: [turno, tipo],
    );
  }

  // =====================================================
  // 🔹 SERVICIOS
  // =====================================================

  Future<List<Map<String, dynamic>>> getServiciosPorTurno(
      String turno, String tipo) async {
    final dbClient = await database;

    return await dbClient.query(
      'servicios',
      where: 'turno = ? AND tipo = ?',
      whereArgs: [turno, tipo],
      orderBy: 'orden ASC',
    );
  }

  // =====================================================
  // 🔹 CALENDARIOS
  // =====================================================

  Future<List<Map<String, dynamic>>> getCalendarioOrientativo() async {
    final dbClient = await database;
    return await dbClient.query('calendario_orientativo');
  }

  // =====================================================
  // 🔹 CONFIG SEMANAS
  // =====================================================

  Future<void> guardarSemanas({
    required int semanaReal,
    required int semanaOrientativa,
    required String fechaBase,
  }) async {
    final dbClient = await database;

    await dbClient.insert(
      'config_semanas',
      {
        'id': 1,
        'semana_real_base': semanaReal,
        'semana_orientativa_base': semanaOrientativa,
        'fecha_base': fechaBase,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> obtenerSemanas() async {
    final dbClient = await database;

    final res = await dbClient.query(
      'config_semanas',
      where: 'id = 1',
    );

    return res.isNotEmpty ? res.first : null;
  }

  // =====================================================
  // 🔥 COLORES (TURNO + TIPO)
  // =====================================================

  Future<Map<String, int>> getColoresTurno() async {
    final dbClient = await database;

    final res = await dbClient.query('config_colores');

    Map<String, int> mapa = {};

    for (var row in res) {
      final letra = row['letra']?.toString();
      final tipo = row['tipo']?.toString() ?? '';
      final colorVal = row['color'];

      if (letra != null && colorVal is int) {
        mapa["$letra-$tipo"] = colorVal;
        if (!mapa.containsKey(letra)) {
          mapa[letra] = colorVal;
        }
      }
    }

    return mapa;
  }

  Future<void> guardarColorTurno(String letra, String tipo, int color) async {
    final dbClient = await database;

    await dbClient.insert(
      'config_colores',
      {
        'letra': letra,
        'tipo': tipo,
        'color': color,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteRegistro(String fecha) async {
    final dbClient = await database;

    await dbClient.delete(
      'registro_diario',
      where: 'fecha = ?',
      whereArgs: [fecha],
    );
  }
}
