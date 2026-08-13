class ApiConstants {
  // URL de producción Cloud Run. Puedes sobrescribirla con --dart-define=API_BASE_URL=...
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://muvv-api.onrender.com',
  );

  // Locales comentadas
  // static const String baseUrl = 'http://10.0.2.2:8000';
  // static const String baseUrl = 'http://localhost:8000';

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String me = '/users/me';
  static const String updateMe = '/users/me';
  static const String driverReg = '/drivers/register';
  static const String driverMe = '/drivers/me';
  static const String driverVehicle = '/drivers/vehicle';
  static const String freights = '/freights';
  static const String pricingEstimate = '/pricing/estimate';
  static const String payments = '/payments';
  static const String ratings = '/ratings';
  static const String analyticsEvents = '/analytics/events';
}
