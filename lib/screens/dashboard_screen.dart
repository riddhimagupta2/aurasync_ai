import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:marquee/marquee.dart';
import 'dart:async'; // Required for Streams and Realtime
import 'camera_screen.dart';
import 'swarm_map_screen.dart';
import 'profile_screen.dart';
import 'leaderboard_screen.dart';
import 'auth_screen.dart'; // NEW: Imported to route back on sign out
import '../services/s2_helper.dart';
import 'package:timezone/timezone.dart' as tz;

class DashboardScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const DashboardScreen({super.key, required this.cameras});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isLoading = true;
  String _userName = "Eco Neighbor";
  String? _avatarUrl;
  int _verifiedPts = 0;
  int _pendingPts = 0;
  String _personalKg = "0.00";

  double _globalCommunityKg = 0.0;
  double _localCommunityKg = 0.0;

  List<Map<String, dynamic>> _localLeaders = [];

  // Active broadcast variables
  Map<String, dynamic>? _activeBroadcastAlert;
  RealtimeChannel? _realtimeSubscription;
  String? _currentUserS2Token;

  bool _isBannerExpanded = false;
  bool _isLocationDialogShowing =
      false; // Tracks if the location blocker is open

  List<Map<String, dynamic>> _userPendingScans = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSubscription?.unsubscribe();
    super.dispose();
  }

  // --- APP LIFECYCLE LISTENER ---
  // If user opens app settings to grant location, returning triggers this!
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAllData();
    }
  }

  // --- LOCATION ENFORCEMENT BLOCKER ---
  void _enforceLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationBlocker(
        "Location services are disabled. Please enable GPS to load your local Swarm data.",
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showLocationBlocker(
          "AuraSync strictly requires location access to map waste correctly.",
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showLocationBlocker(
        "Location permissions are permanently denied. Open App Settings to grant access.",
        isPermanent: true,
      );
      return;
    }

    // Try loading again if everything passes!
    _loadAllData();
  }

  void _showLocationBlocker(String message, {bool isPermanent = false}) {
    if (_isLocationDialogShowing) return; // Prevent stacking
    _isLocationDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.redAccent),
            SizedBox(width: 10),
            Text(
              "Location Required",
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AuthScreen(cameras: widget.cameras),
                  ),
                  (route) => false,
                );
              }
            },
            child: const Text("Sign Out", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
            ),
            onPressed: () async {
              if (isPermanent) {
                await Geolocator.openAppSettings();
              } else {
                Navigator.pop(context);
                _enforceLocation();
              }
            },
            child: Text(
              isPermanent ? "Open Settings" : "Retry",
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).then((_) => _isLocationDialogShowing = false);
  }

  // --- BULLETPROOF REALTIME LISTENER ---
  void _setupRealtimeBroadcastListener(String userS2CellId) {
    if (_realtimeSubscription != null) return;

    final supabase = Supabase.instance.client;

    _realtimeSubscription = supabase
        .channel('public:swarm_broadcasts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'swarm_broadcasts',
          callback: (payload) {
            debugPrint(
              "🔥 SUPABASE REALTIME EVENT DETECTED: ${payload.newRecord}",
            );

            final newAlertData = payload.newRecord;
            if (newAlertData.isNotEmpty) {
              final broadcastToken = newAlertData['s2_cell_id']
                  ?.toString()
                  .toLowerCase()
                  .trim();
              final userToken = userS2CellId.toLowerCase().trim();

              if (broadcastToken == userToken) {
                debugPrint("✅ Sector Match! Rendering Banner.");
                if (mounted) {
                  setState(() {
                    _activeBroadcastAlert = newAlertData;
                    _isBannerExpanded = false;
                  });

                  if (newAlertData['scheduled_time'] != null) {
                    DateTime scheduledDate = DateTime.parse(
                      newAlertData['scheduled_time'],
                    );
                    if (scheduledDate.isAfter(DateTime.now())) {
                      _scheduleNotificationChain(scheduledDate);
                    }
                  }
                }
              } else {
                debugPrint(
                  "❌ Ignored. Broadcast was for $broadcastToken, but user is in $userToken",
                );
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _scheduleNotificationChain(DateTime scheduledTime) async {
    await _showNotification(
      1,
      "Swarm Collector Arriving!",
      "The waste collector reaches your sector in 15 minutes. Please have items ready.",
      scheduledTime.subtract(const Duration(minutes: 15)),
    );

    if (scheduledTime.difference(DateTime.now()).inHours > 24) {
      await _showNotification(
        2,
        "Swarm Collection Reminder",
        "Your waste is scheduled for collection in 24 hours.",
        scheduledTime.subtract(const Duration(hours: 24)),
      );
    }

    if (scheduledTime.difference(DateTime.now()).inHours > 48) {
      await _showNotification(
        3,
        "Swarm Collection Scheduled",
        "Your waste is scheduled for collection in 48 hours.",
        scheduledTime.subtract(const Duration(hours: 48)),
      );
    }
  }

  Future<void> _showNotification(
    int id,
    String title,
    String body,
    DateTime date,
  ) async {
    if (date.isBefore(DateTime.now())) return;

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(date, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aura_sync_channel',
          'Swarm Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _expireBroadcast(String broadcastId) async {
    try {
      await Supabase.instance.client
          .from('swarm_broadcasts')
          .update({'status': 'EXPIRED'})
          .eq('id', broadcastId);

      if (mounted) {
        setState(() {
          _activeBroadcastAlert = null;
          _isBannerExpanded = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to auto-expire broadcast: $e");
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // --- STRICT LOCATION ENFORCEMENT CHECK ---
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    LocationPermission permission = await Geolocator.checkPermission();

    if (!serviceEnabled ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _enforceLocation();
      return; // Stops all data loading until GPS is allowed
    } else {
      // If permission was granted and the blocker dialog is open, auto-close it!
      if (_isLocationDialogShowing && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _isLocationDialogShowing = false;
      }
    }
    // -----------------------------------------

    String fetchedName = "Eco Neighbor";
    String? fetchedAvatar;
    double pKg = 0.0;
    double pGrams = 0.0;
    int vPts = 0;
    int pPts = 0;
    double globalKg = 0.0;
    double localKg = 0.0;
    List<Map<String, dynamic>> leaders = [];
    Map<String, dynamic>? alert;
    List<String> pendingS2Tokens = [];
    List<Map<String, dynamic>> pendings = [];

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    String? localToken;
    try {
      // Safe to call because we enforced it above
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      localToken = S2Helper.generateLevel14Token(
        pos.latitude,
        pos.longitude,
      ).toLowerCase().trim();

      _currentUserS2Token = localToken;
    } catch (e) {
      debugPrint("Location Init Error: $e");
    }

    try {
      final profileData = await supabase
          .from('profiles')
          .select('display_name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (profileData != null) {
        fetchedName = profileData['display_name'] ?? "Eco Neighbor";
        fetchedAvatar = profileData['avatar_url'];
      }
    } catch (e) {
      debugPrint("Profile Fetch Error: $e");
    }

    try {
      final userItems = await supabase
          .from('waste_items')
          .select(
            'id, eco_points, status, s2_cell_id, material_type, created_at, category, weight_grams',
          )
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      for (var item in userItems) {
        if (item['status'] == 'COLLECTED') {
          vPts += (item['eco_points'] as num? ?? 0).toInt();
          pGrams += (item['weight_grams'] as num? ?? 0.0).toDouble();
        } else if (item['status'] == 'PENDING') {
          pPts += (item['eco_points'] as num? ?? 0).toInt();
          pendings.add(item);

          if (item['s2_cell_id'] != null) {
            pendingS2Tokens.add(
              item['s2_cell_id'].toString().toLowerCase().trim(),
            );
          }
        }
      }
      pKg = pGrams / 1000.0;
    } catch (e) {
      debugPrint("Points Fetch Error: $e");
    }

    try {
      List<String> tokensToCheck = [];
      if (_currentUserS2Token != null) tokensToCheck.add(_currentUserS2Token!);
      for (var t in pendingS2Tokens) {
        if (!tokensToCheck.contains(t)) tokensToCheck.add(t);
      }

      if (tokensToCheck.isNotEmpty) {
        final broadcasts = await supabase
            .from('swarm_broadcasts')
            .select('*')
            .eq('status', 'ACTIVE_COLLECTION')
            .order('created_at', ascending: false);

        for (var b in broadcasts) {
          String bToken =
              b['s2_cell_id']?.toString().toLowerCase().trim() ?? '';
          if (tokensToCheck.contains(bToken)) {
            if (b['scheduled_time'] != null) {
              if (b['ttl_expiry'] != null) {
                DateTime expiryDate = DateTime.parse(b['ttl_expiry']);
                if (DateTime.now().isAfter(expiryDate)) {
                  _expireBroadcast(b['id'].toString());
                  continue;
                }
              }

              DateTime scheduledDate = DateTime.parse(b['scheduled_time']);
              if (scheduledDate.isAfter(DateTime.now())) {
                _scheduleNotificationChain(scheduledDate);
              }

              alert = b;
              break;
            }
          }
        }
      }

      if (_currentUserS2Token != null) {
        _setupRealtimeBroadcastListener(_currentUserS2Token!);
      }
    } catch (e) {
      debugPrint("Broadcast Fetch Error: $e");
    }

    try {
      final globalResponse = await supabase
          .from('waste_items')
          .select('weight_grams')
          .eq('status', 'COLLECTED');

      double gGrams = 0;
      for (var item in globalResponse) {
        gGrams += (item['weight_grams'] as num? ?? 0.0).toDouble();
      }
      globalKg = gGrams / 1000.0;

      var commQuery = supabase
          .from('waste_items')
          .select('weight_grams')
          .eq('status', 'COLLECTED');
      if (localToken != null) {
        commQuery = commQuery.eq('s2_cell_id', localToken);
      }

      final communityResponse = await commQuery;
      double lGrams = 0;
      for (var item in communityResponse) {
        lGrams += (item['weight_grams'] as num? ?? 0.0).toDouble();
      }
      localKg = lGrams / 1000.0;
    } catch (e) {
      debugPrint("Impact Calculations Fetch Error: $e");
    }

    try {
      var leadQuery = supabase
          .from('waste_items')
          .select('eco_points, s2_cell_id, status, profiles(display_name)');

      if (localToken != null) {
        leadQuery = leadQuery.eq('s2_cell_id', localToken);
      }

      final leadResp = await leadQuery;
      Map<String, int> userTotals = {};

      for (var row in leadResp) {
        if (row['status'] == 'COLLECTED') {
          final pData = row['profiles'];
          String name = pData != null
              ? pData['display_name'] ?? "Anonymous"
              : "Anonymous";
          userTotals[name] =
              (userTotals[name] ?? 0) + (row['eco_points'] as num).toInt();
        }
      }

      var sorted = userTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      leaders = sorted
          .take(3)
          .map((e) => {'name': e.key, 'points': e.value})
          .toList();
    } catch (e) {
      debugPrint("Leaderboard Fetch Error: $e");
    }

    if (mounted) {
      setState(() {
        _userName = fetchedName;
        _avatarUrl = fetchedAvatar;
        _personalKg = pKg.toStringAsFixed(2);
        _verifiedPts = vPts;
        _pendingPts = pPts;
        _globalCommunityKg = globalKg;
        _localCommunityKg = localKg;
        _activeBroadcastAlert = alert;
        _localLeaders = leaders;
        _userPendingScans = pendings;
        _isLoading = false;
        _isBannerExpanded = false;
      });
    }
  }

  Future<void> _cancelPendingScan(String itemId) async {
    try {
      await Supabase.instance.client
          .from('waste_items')
          .delete()
          .eq('id', itemId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Scan successfully removed from ledger history."),
            backgroundColor: Colors.white24,
          ),
        );
      }
      _loadAllData();
    } catch (e) {
      debugPrint("Cancellation Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    String tickerText =
        "🌍 TOTAL ENVIRONMENTAL IMPACT: ${_globalCommunityKg.toStringAsFixed(1)}kg of Specialized Waste Diverted Network-wide! 🚀"
        "        🌱 Be the change: Your next verified item unlocks more Eco-Points! ♻️   ";

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF00E676),
          backgroundColor: Colors.black,
          onRefresh: _loadAllData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 35,
                  width: double.infinity,
                  color: const Color(0xFF00E676).withOpacity(0.1),
                  child: _isLoading
                      ? const Center(
                          child: Text(
                            "Syncing Network Impact...",
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 12,
                            ),
                          ),
                        )
                      : Marquee(
                          text: tickerText,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00E676),
                            fontSize: 13,
                            letterSpacing: 1.2,
                          ),
                          scrollAxis: Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          blankSpace: 50.0,
                          velocity: 40.0,
                          startPadding: 10.0,
                        ),
                ),

                Padding(
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Hello, $_userName!",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                              const Text(
                                "AuraSync HQ",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ProfileScreen(),
                              ),
                            ).then((_) => _loadAllData()),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF00E676),
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey[900],
                                backgroundImage: _avatarUrl != null
                                    ? NetworkImage(_avatarUrl!)
                                    : null,
                                child: _avatarUrl == null
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white70,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      if (_activeBroadcastAlert != null)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isBannerExpanded = !_isBannerExpanded;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              border: Border.all(
                                color: const Color(0xFF00E676),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF00E676,
                                  ).withOpacity(0.15),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.airport_shuttle_rounded,
                                  color: Color(0xFF00E676),
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        "SWARM DISPATCH SCHEDULED",
                                        style: TextStyle(
                                          color: Color(0xFF00E676),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      AnimatedSize(
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: Curves.easeInOut,
                                        alignment: Alignment.topCenter,
                                        child: Text(
                                          _activeBroadcastAlert!['message'] ??
                                              "A collector has been dispatched to your sector.",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            height: 1.4,
                                          ),
                                          maxLines: _isBannerExpanded
                                              ? null
                                              : 3,
                                          overflow: _isBannerExpanded
                                              ? null
                                              : TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _isBannerExpanded
                                            ? "Tap to collapse"
                                            : "Tap to read more",
                                        style: const TextStyle(
                                          color: Color(0xFF00E676),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    setState(() {
                                      _activeBroadcastAlert = null;
                                      _isBannerExpanded = false;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                      _buildImpactCard(),
                      const SizedBox(height: 30),
                      const Text(
                        "Operations",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),

                      Row(
                        children: [
                          _buildActionCard(
                            context,
                            title: "Scan Waste",
                            icon: Icons.qr_code_scanner,
                            color: const Color(0xFF00E676),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    CameraScreen(cameras: widget.cameras),
                              ),
                            ).then((_) => _loadAllData()),
                          ),
                          const SizedBox(width: 15),
                          _buildActionCard(
                            context,
                            title: "Live Swarm Map",
                            icon: Icons.hub_outlined,
                            color: Colors.blueAccent,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SwarmMapScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      _buildPendingScansManager(),
                      _buildLeaderboardPreview(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImpactCard() {
    double activeGoal = 15.0;
    int currentTierWorkingOn = 1;

    if (_localCommunityKg >= 100.0) {
      activeGoal = 200.0;
      currentTierWorkingOn = 5;
    } else if (_localCommunityKg >= 60.0) {
      activeGoal = 100.0;
      currentTierWorkingOn = 4;
    } else if (_localCommunityKg >= 30.0) {
      activeGoal = 60.0;
      currentTierWorkingOn = 3;
    } else if (_localCommunityKg >= 15.0) {
      activeGoal = 30.0;
      currentTierWorkingOn = 2;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF00E676).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "LOCAL SECTOR GOAL: TIER $currentTierWorkingOn",
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  letterSpacing: 1.5,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00E676),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            "${_localCommunityKg.toStringAsFixed(1)}kg / ${activeGoal}kg Diverted",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (_localCommunityKg / activeGoal).clamp(0.0, 1.0),
            backgroundColor: Colors.white10,
            color: const Color(0xFF00E676),
            minHeight: 8,
            borderRadius: BorderRadius.circular(10),
          ),
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.emoji_events,
                  color: Colors.grey.withOpacity(0.5),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Tier $currentTierWorkingOn Locked. Sector needs ${activeGoal}kg total. Your logs in this specific swarm validate your milestone status!",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const Divider(color: Colors.white10),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Verified Points",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "$_verifiedPts",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_pendingPts > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            "(+$_pendingPts pending)",
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "Personal Impact",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    "${_personalKg}kg",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingScansManager() {
    if (_userPendingScans.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Active Ledger (Pending Collection)",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._userPendingScans.map((item) {
          final DateTime createdAt = DateTime.parse(item['created_at']);
          final int hoursOld = DateTime.now().difference(createdAt).inHours;
          final bool canCancel = hoursOld < 24;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['material_type'] ?? "Waste Item",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${item['category']}  |  ${item['weight_grams']}g  |  ${item['eco_points']} pts",
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Logged $hoursOld hours ago",
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canCancel)
                  TextButton.icon(
                    onPressed: () => _cancelPendingScan(item['id'].toString()),
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                    label: const Text(
                      "Cancel Log",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  const Text(
                    "Locked",
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildLeaderboardPreview() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Sector Leaderboard",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LeaderboardScreen(),
                  ),
                ),
                child: const Text(
                  "See All",
                  style: TextStyle(
                    color: Color(0xFF00E676),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                "Syncing localized data...",
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else if (_localLeaders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                "No verified data in your sector yet.",
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          for (int i = 0; i < _localLeaders.length; i++)
            _leaderRow(
              (i + 1).toString(),
              _localLeaders[i]['name'],
              "${_localLeaders[i]['points']} pts",
              isUser: _localLeaders[i]['name'] == _userName,
            ),
        ],
      ),
    );
  }

  Widget _leaderRow(
    String rank,
    String name,
    String pts, {
    bool isUser = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          SizedBox(
            width: 25,
            child: Text(
              rank,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: isUser ? const Color(0xFF00E676) : Colors.white,
                fontWeight: isUser ? FontWeight.bold : FontWeight.w500,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            pts,
            style: const TextStyle(
              color: Color(0xFF00E676),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
