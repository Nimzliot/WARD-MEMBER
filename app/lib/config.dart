// App configuration.
//
// Either edit the default values below, or pass them at build/run time:
//   flutter run --dart-define-from-file=config.json
// (see config.example.json).
//
// API_BASE_URL — where the Node server is reachable FROM THE PHONE:
//   • Android emulator  → http://10.0.2.2:3000   (10.0.2.2 = your laptop's localhost)
//   • Real phone (same Wi-Fi as laptop) → http://<laptop LAN IP>:3000
//       find the IP with `ipconfig` → "IPv4 Address", e.g. http://192.168.1.23:3000
//       and allow Node through Windows Firewall when prompted
//   • ngrok tunnel → https://<name>.ngrok-free.dev  (works from any network)
//   • Deployed → https://<your-service>.onrender.com
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR-PROJECT-REF.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR-ANON-KEY',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static bool get isConfigured =>
      !supabaseUrl.contains('YOUR-PROJECT-REF') && !supabaseAnonKey.startsWith('YOUR-');
}
