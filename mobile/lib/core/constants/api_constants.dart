class ApiConstants {
  // ✅ URL de producción Railway
  static const String baseUrl = 'https://fleteapp-production.up.railway.app';

  // Locales comentadas
  // static const String baseUrl = 'http://10.0.2.2:8000';
  // static const String baseUrl = 'http://localhost:8000';

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
