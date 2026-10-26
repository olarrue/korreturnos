import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self

    if let controller = window?.rootViewController as? FlutterViewController {
      configurarCanalAlarmas(messenger: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configurarCanalAlarmas(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func configurarCanalAlarmas(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "korreturnos/ios_alarmas",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      let center = UNUserNotificationCenter.current()

      switch call.method {
      case "programarAlarma":
        guard let args = call.arguments as? [String: Any],
              let id = args["id"] as? String,
              let hora = args["hora"] as? Int,
              let minuto = args["minuto"] as? Int,
              let mensaje = args["mensaje"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Argumentos inválidos", details: nil))
          return
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          if let error = error {
            result(FlutterError(code: "AUTH_ERROR", message: error.localizedDescription, details: nil))
            return
          }
          guard granted else {
            result(FlutterError(code: "NOT_GRANTED", message: "Jakinarazpen baimena ukatuta", details: nil))
            return
          }

          let content = UNMutableNotificationContent()
          content.title = "⏰ Korreturnos · Alarma"
          content.body = mensaje
          content.sound = UNNotificationSound.default

          var dateComponents = DateComponents()
          dateComponents.hour = hora
          dateComponents.minute = minuto

          let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
          let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

          center.add(request) { addError in
            if let addError = addError {
              result(FlutterError(code: "ADD_ERROR", message: addError.localizedDescription, details: nil))
            } else {
              result(true)
            }
          }
        }

      case "cancelarAlarma":
        if let args = call.arguments as? [String: Any],
           let id = args["id"] as? String {
          center.removePendingNotificationRequests(withIdentifiers: [id])
          result(true)
        } else {
          result(false)
        }

      case "abrirReloj":
        DispatchQueue.main.async {
          if let url = URL(string: "clock-alarm://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
          }
          result(true)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Mostrar notificación con sonido incluso si la app está abierta en primer plano
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}
