class ApiConstants {
  static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator
  // Para dispositivo real: usa tu IP local, ej: 'http://192.168.1.100:8000'
  // Para producción: 'https://tu-dominio.com'

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
