class ApiConstants {
  // Elige UNA opción según cómo vayas a probar:

  // Opción A — Emulador Android
  //static const String baseUrl = 'http://10.0.2.2:8000';

  // Opción B — Navegador Chrome (más fácil para probar rápido)
  static const String baseUrl = 'http://localhost:8000';

  // Opción C — Dispositivo físico conectado por USB
  // static const String baseUrl = 'http://192.168.X.X:8000';

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String me = '/users/me';
  static const String updateMe = '/users/me';
  static const String driverReg = '/drivers/register';
  static const String driverMe = '/drivers/me';
  static const String driverVehicle = '/drivers/vehicle';
  static const String freights = '/freights';
  static const String payments = '/payments';
  static const String ratings = '/ratings';
}
