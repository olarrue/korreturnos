class ModoApp {
  /// Si es true, la aplicación se ejecuta en modo Solo Lectura para familiares:
  /// - No se pueden crear, asignar ni borrar turnos.
  /// - No se pueden modificar colores ni calendarios.
  /// - Solo lectura de servicios y notas.
  /// - Botón simplificado para cargar/actualizar la copia enviada por el conductor.
  static bool esFamiliar = false;
}
