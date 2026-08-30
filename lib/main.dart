import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz; // Timezone initialization
import 'package:flutter_dotenv/flutter_dotenv.dart'; // NEW: dotenv import
import 'screens/dashboard_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/collector_dashboard_screen.dart';
import 'services/notification_service.dart';

// Global notification plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezones (Required for zonedSchedule)
  tz.initializeTimeZones();

  // NEW: Load the environment variables from the .env file BEFORE initializing anything else
  await dotenv.load(fileName: ".env");

  // NEW: Fetching Supabase keys securely from the .env file
  final String supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final String supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

  // Initialize Local Notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Request Notification Permissions for Android 13+
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  await NotificationService.init();

  final cameras = await availableCameras();
  runApp(AuraSyncApp(cameras: cameras));
}

class AuraSyncApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const AuraSyncApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AuraSync AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E676),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: RoleRoutingGate(cameras: cameras),
    );
  }
}

/// Dynamic access gate assessing security profiles before delivering user spaces
class RoleRoutingGate extends StatelessWidget {
  final List<CameraDescription> cameras;
  const RoleRoutingGate({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return AuthScreen(cameras: cameras);
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', session.user.id)
          .maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          final String role = snapshot.data!['role'] ?? 'user';
          if (role == 'collector_admin') {
            return const CollectorDashboardScreen();
          }
        }

        return DashboardScreen(cameras: cameras);
      },
    );
  }
}
