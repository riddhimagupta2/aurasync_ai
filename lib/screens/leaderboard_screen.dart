import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/s2_helper.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _localRankings = [];
  String _currentSectorName = "Detecting...";

  @override
  void initState() {
    super.initState();
    _loadRegionalRankings();
  }

  Future<void> _loadRegionalRankings() async {
    setState(() => _isLoading = true);
    try {
      String? localS2Token;

      // 1. Gather exact device location coordinates securely
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse) {
            Position pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium,
            );
            localS2Token = S2Helper.generateLevel14Token(
              pos.latitude,
              pos.longitude,
            ).toLowerCase().trim();
          }
        }
      } catch (geoError) {
        debugPrint("Location access bypassed: $geoError");
      }

      // 2. Query verified materials matching our local geographic block token
      var query = _supabase
          .from('waste_items')
          .select('eco_points, s2_cell_id, profiles(display_name)')
          .eq('status', 'COLLECTED');

      if (localS2Token != null) {
        query = query.eq('s2_cell_id', localS2Token);
        final safeToken =
            localS2Token; // Null-safety extraction for the compiler
        setState(() {
          _currentSectorName = safeToken.toUpperCase().replaceAll('S2_14_', '');
        });
      } else {
        setState(() {
          _currentSectorName = "GLOBAL (Location Unavailable)";
        });
      }

      final response = await query;

      // 3. Aggregate points per unique citizen profile row cleanly
      Map<String, int> localAggregation = {};
      for (var row in response) {
        final profileData = row['profiles'];
        String name = profileData != null
            ? profileData['display_name'] ?? "Anonymous"
            : "Anonymous";
        localAggregation[name] =
            (localAggregation[name] ?? 0) + (row['eco_points'] as num).toInt();
      }

      // 4. Sort from highest score value downwards
      var sortedList = localAggregation.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      setState(() {
        _localRankings = sortedList
            .map((e) => {'name': e.key, 'points': e.value})
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Regional Leaderboard Sync Fault: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "Sector Standings",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF00E676).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.gite_outlined, color: Color(0xFF00E676)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "TRACKING SECTOR ZONE: #$_currentSectorName",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _localRankings.isEmpty
                      ? const Center(
                          child: Text(
                            "No collections completed inside this sector block.",
                            style: TextStyle(
                              color: Colors.white30,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _localRankings.length,
                          itemBuilder: (context, index) {
                            final citizen = _localRankings[index];
                            final int rank = index + 1;

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    "#$rank",
                                    style: TextStyle(
                                      color: rank == 1
                                          ? const Color(0xFF00E676)
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      citizen['name'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "${citizen['points']} pts",
                                    style: const TextStyle(
                                      color: Color(0xFF00E676),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
