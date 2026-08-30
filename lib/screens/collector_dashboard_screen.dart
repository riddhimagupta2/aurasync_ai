import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CollectorDashboardScreen extends StatefulWidget {
  const CollectorDashboardScreen({super.key});

  @override
  State<CollectorDashboardScreen> createState() =>
      _CollectorDashboardScreenState();
}

class _CollectorDashboardScreenState extends State<CollectorDashboardScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isMapFullscreen = false;

  GoogleMapController? _mapController;
  List<dynamic> _allPendingItems = [];
  Set<Marker> _mapMarkers = {};
  double _globalPendingWeightKg = 0.0;
  final double _logisticsThresholdKg = 4.0;

  String? _selectedSwarmToken;
  Map<String, List<dynamic>> _groupedSwarms = {};

  @override
  void initState() {
    super.initState();
    _loadCollectorMetrics();
  }

  String _getOrComputeS2Token(Map<String, dynamic> item) {
    if (item['s2_cell_id'] != null &&
        item['s2_cell_id'].toString().isNotEmpty) {
      return item['s2_cell_id'].toString();
    }
    final double lat = (item['location_lat'] as num? ?? 0.0).toDouble();
    final double lng = (item['location_lng'] as num? ?? 0.0).toDouble();
    int latIndex = (lat / 0.0045).floor();
    int lngIndex = (lng / 0.0052).floor();
    return "s2_14_${latIndex.toRadixString(16).replaceAll('-', 'n')}_${lngIndex.toRadixString(16).replaceAll('-', 'n')}";
  }

  Future<void> _loadCollectorMetrics() async {
    setState(() => _isLoading = true);
    try {
      final List<dynamic> items = await _supabase
          .from('waste_items')
          .select('*, profiles(display_name, trust_score)')
          .eq('status', 'PENDING');

      double totalWeightGrams = 0;
      Set<Marker> markers = {};
      Map<String, List<dynamic>> swarmsMap = {};

      for (var item in items) {
        totalWeightGrams += (item['weight_grams'] as num? ?? 0.0).toDouble();
        final double lat = (item['location_lat'] as num).toDouble();
        final double lng = (item['location_lng'] as num).toDouble();
        final String profileName =
            item['profiles']?['display_name'] ?? 'Eco Neighbor';

        final String s2Token = _getOrComputeS2Token(item);
        if (!swarmsMap.containsKey(s2Token)) swarmsMap[s2Token] = [];
        swarmsMap[s2Token]!.add(item);

        markers.add(
          Marker(
            markerId: MarkerId(item['id'].toString()),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
            infoWindow: InfoWindow(
              title: "$profileName: ${item['material_type']}",
              snippet: "Weight: ${item['weight_grams']}g",
            ),
          ),
        );
      }

      setState(() {
        _allPendingItems = items;
        _groupedSwarms = swarmsMap;
        _mapMarkers = markers;
        _globalPendingWeightKg = totalWeightGrams / 1000.0;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Collector Matrix Fetch Error: $e");
      setState(() => _isLoading = false);
    }
  }

  double _calculateClusterWeight(List<dynamic> items) {
    double totalGrams = 0;
    for (var item in items) {
      totalGrams += (item['weight_grams'] as num? ?? 0.0).toDouble();
    }
    return totalGrams / 1000.0;
  }

  void _focusCameraOnSector(String token) {
    setState(() => _selectedSwarmToken = token);

    try {
      String cleanToken = token.toLowerCase().replaceAll('s2_14_', '').trim();
      List<String> parts = cleanToken.split('_');
      if (parts.length == 2) {
        int latIndex = int.parse(parts[0].replaceAll('n', '-'), radix: 16);
        int lngIndex = int.parse(parts[1].replaceAll('n', '-'), radix: 16);

        double centerLat = (latIndex * 0.0045) + (0.0045 / 2);
        double centerLng = (lngIndex * 0.0052) + (0.0052 / 2);

        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(centerLat, centerLng), 14.5),
        );
      }
    } catch (e) {
      debugPrint("Camera pan fault: $e");
    }
  }

  void _openBroadcastDialog(String token, double currentWeight) {
    final timeController = TextEditingController(
      text: "Tomorrow between 2:00 PM - 5:00 PM",
    );
    final msgController = TextEditingController(
      text:
          "Swarm truck arriving. Please bring your logged items to the collection spot.",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Broadcast Alert: Swarm #${token.toUpperCase().replaceAll('S2_14_', '')}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.scale, color: Color(0xFF00E676), size: 16),
                const SizedBox(width: 8),
                Text(
                  "Mass gathered: ${currentWeight.toStringAsFixed(2)} kg",
                  style: const TextStyle(
                    color: Color(0xFF00E676),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: timeController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: "Arrival Time",
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msgController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                labelText: "Instructions",
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
            ),
            onPressed: () async {
              try {
                await _supabase.from('swarm_broadcasts').insert({
                  's2_cell_id': token,
                  'scheduled_time': DateTime.now()
                      .add(const Duration(days: 1))
                      .toIso8601String(),
                  'message':
                      "Schedule: ${timeController.text} | Directive: ${msgController.text}",
                });
                if (mounted) {
                  Navigator.pop(context);
                  _showStatusToast(
                    "Notification pushed to local users!",
                    const Color(0xFF00E676),
                  );
                }
              } catch (e) {
                debugPrint("Broadcast Log Error: $e");
              }
            },
            child: const Text(
              "DISPATCH",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UPDATED: Proper Fraud Penalty & Trust Score Enforcement ---
  Future<void> _processFieldHandover(
    Map<String, dynamic> item,
    bool isLegitimateHandover,
  ) async {
    final String itemId = item['id'].toString();
    final String userId = item['user_id']?.toString() ?? "";

    if (userId.isEmpty) {
      _showStatusToast(
        "Error: Core User Reference ID is corrupt or missing.",
        Colors.redAccent,
      );
      return;
    }

    try {
      if (isLegitimateHandover) {
        await _supabase
            .from('waste_items')
            .update({'status': 'COLLECTED', 'is_collected': true})
            .eq('id', itemId);

        final double itemWeight = (item['weight_grams'] as num? ?? 0.0)
            .toDouble();
        final profileData = await _supabase
            .from('profiles')
            .select('total_weight_diverted_g, trust_score')
            .eq('id', userId)
            .maybeSingle();

        double currentWeightDiverted = 0.0;
        int currentTrust = 100;
        if (profileData != null) {
          currentWeightDiverted =
              (profileData['total_weight_diverted_g'] as num? ?? 0.0)
                  .toDouble();
          currentTrust = profileData['trust_score'] as int? ?? 100;
        }

        // Active Trust Score Auto-Recovery Engine
        int healedTrust = currentTrust;
        if (currentTrust < 100) {
          healedTrust = (currentTrust + 5).clamp(0, 100);
        }

        await _supabase
            .from('profiles')
            .update({
              'total_weight_diverted_g': currentWeightDiverted + itemWeight,
              'trust_score': healedTrust,
            })
            .eq('id', userId);

        _showStatusToast(
          "Handover Confirmed. User Trust rating increased.",
          const Color(0xFF00E676),
        );
      } else {
        // FRAUD ENFORCEMENT
        await _supabase
            .from('waste_items')
            .update({'status': 'FRAUD_ALERT', 'is_collected': false})
            .eq('id', itemId);

        final profileData = await _supabase
            .from('profiles')
            .select('trust_score')
            .eq('id', userId)
            .maybeSingle();

        int currentTrust = 100;
        if (profileData != null && profileData['trust_score'] != null) {
          currentTrust = profileData['trust_score'] as int;
        }

        // 1. Deduct 30 points and floor at 0
        int penalizedTrust = currentTrust - 30;
        if (penalizedTrust < 0) {
          penalizedTrust = 0;
        }

        // 2. Push the newly penalized score
        await _supabase
            .from('profiles')
            .update({'trust_score': penalizedTrust})
            .eq('id', userId);

        // 3. Show contextual dynamic toast
        _showStatusToast(
          penalizedTrust == 0
              ? "Fraud verified. User has been permanently suspended (Trust: 0)."
              : "Penalty applied. User trust score dropped to $penalizedTrust.",
          penalizedTrust == 0 ? Colors.redAccent : Colors.orange,
        );
      }

      // Refresh the list to remove the acted-upon item
      await _loadCollectorMetrics();
    } catch (e) {
      debugPrint("Handover Processing Error: $e");
      _showStatusToast("Logistics Processing Fault: $e", Colors.redAccent);
    }
  }

  void _showStatusToast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isLoggingOut = false;

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text(
              "Disconnect Session",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "Are you sure you want to log out of AuraSync?",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              if (!isLoggingOut)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: isLoggingOut
                    ? null
                    : () async {
                        setDialogState(() => isLoggingOut = true);
                        await Supabase.instance.client.auth.signOut();
                        if (mounted) {
                          Navigator.of(
                            context,
                          ).pushNamedAndRemoveUntil('/', (route) => false);
                        }
                      },
                child: isLoggingOut
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "Log Out",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool regionalThresholdMet =
        _globalPendingWeightKg >= _logisticsThresholdKg;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _selectedSwarmToken == null
              ? "Logistics Control Center"
              : "Sector: ${_selectedSwarmToken!.toUpperCase().replaceAll('S2_14_', '')}",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.black,
        leading: _selectedSwarmToken != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => setState(() {
                  _selectedSwarmToken = null;
                  _isMapFullscreen = false;
                }),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Color(0xFF00E676)),
            onPressed: _loadCollectorMetrics,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            )
          : Column(
              children: [
                if (!_isMapFullscreen)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: regionalThresholdMet
                            ? const Color(0xFF00E676)
                            : Colors.amber.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              regionalThresholdMet
                                  ? "REGIONAL ROUTE VIABLE"
                                  : "GATHERING REGIONAL MASS",
                              style: TextStyle(
                                color: regionalThresholdMet
                                    ? const Color(0xFF00E676)
                                    : Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Icon(
                              regionalThresholdMet
                                  ? Icons.local_shipping
                                  : Icons.hourglass_top,
                              color: regionalThresholdMet
                                  ? const Color(0xFF00E676)
                                  : Colors.amber,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "${_globalPendingWeightKg.toStringAsFixed(2)}kg Total Logistics Load",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  flex: _isMapFullscreen ? 10 : 2,
                  child: Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: EdgeInsets.symmetric(
                          horizontal: _isMapFullscreen ? 0 : 16,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            _isMapFullscreen ? 0 : 16,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: GoogleMap(
                          initialCameraPosition: const CameraPosition(
                            target: LatLng(29.9691, 76.9629),
                            zoom: 12.0,
                          ),
                          markers: _mapMarkers,
                          myLocationEnabled: true,
                          zoomControlsEnabled: false,
                          onMapCreated: (controller) =>
                              _mapController = controller,
                        ),
                      ),
                      Positioned(
                        bottom: 24, // Relocated from Top to Bottom Right
                        right: _isMapFullscreen ? 16 : 24,
                        child: FloatingActionButton.small(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                          onPressed: () => setState(
                            () => _isMapFullscreen = !_isMapFullscreen,
                          ),
                          child: Icon(
                            _isMapFullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!_isMapFullscreen) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 16,
                      left: 20,
                      right: 20,
                      bottom: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _selectedSwarmToken == null
                              ? Icons.grid_view_rounded
                              : Icons.person_search_rounded,
                          color: Colors.grey,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedSwarmToken == null
                              ? "ACTIVE S2 NEIGHBORHOOD SWARMS"
                              : "CITIZEN DROP DETAILS IN THIS GRID",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _selectedSwarmToken == null
                        ? _buildSwarmsOverviewGridSystem()
                        : _buildGranularCitizenInspectRows(),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSwarmsOverviewGridSystem() {
    if (_groupedSwarms.isEmpty)
      return const Center(
        child: Text(
          "No active drop requests across regional sectors.",
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    final swarmTokens = _groupedSwarms.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: swarmTokens.length,
      itemBuilder: (context, index) {
        final token = swarmTokens[index];
        final itemsInSwarm = _groupedSwarms[token]!;
        final double swarmWeight = _calculateClusterWeight(itemsInSwarm);
        final bool isSwarmReady = swarmWeight >= _logisticsThresholdKg;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSwarmReady
                  ? const Color(0xFF00E676).withOpacity(0.3)
                  : Colors.white10,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Grid Box: #${token.toUpperCase().replaceAll('S2_14_', '')}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSwarmReady
                          ? Colors.green.withOpacity(0.1)
                          : Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isSwarmReady ? "THRESHOLD MET" : "COLLECTING",
                      style: TextStyle(
                        color: isSwarmReady
                            ? const Color(0xFF00E676)
                            : Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Swarm Weight: ${swarmWeight.toStringAsFixed(2)}kg / $_logisticsThresholdKg kg (${itemsInSwarm.length} items logged)",
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Divider(color: Colors.white10, height: 20),
              Row(
                children: [
                  if (isSwarmReady) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 14),
                        label: const Text(
                          "ALERT TIMINGS",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E676),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () =>
                            _openBroadcastDialog(token, swarmWeight),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      onPressed: () => _focusCameraOnSector(
                        token,
                      ), // Repositions camera context automatically
                      child: const Text(
                        "INSPECT USERS",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGranularCitizenInspectRows() {
    final items = _groupedSwarms[_selectedSwarmToken] ?? [];
    if (items.isEmpty)
      return const Center(
        child: Text(
          "Sector cleared of all verifications.",
          style: TextStyle(color: Colors.white30),
        ),
      );

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final profile = item['profiles'];
        final int trust = profile?['trust_score'] ?? 100;
        final String citizenName = profile?['display_name'] ?? 'Eco Neighbor';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    citizenName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: trust >= 70
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Trust: $trust%",
                      style: TextStyle(
                        color: trust >= 70
                            ? const Color(0xFF00E676)
                            : Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Logged Payload: ${item['material_type']}",
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "Specs: ${item['category']} | Calculated Weight: ${item['weight_grams']}g | Points: ${item['eco_points']} pts",
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const Divider(color: Colors.white10, height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.gpp_bad_outlined, size: 14),
                      label: const Text(
                        "FLAG FRAUD",
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: () => _processFieldHandover(item, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(
                          color: Colors.redAccent,
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 14),
                      label: const Text(
                        "CONFIRM",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _processFieldHandover(item, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
