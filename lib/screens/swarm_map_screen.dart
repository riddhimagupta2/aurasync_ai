import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/s2_helper.dart';

class SwarmMapScreen extends StatefulWidget {
  const SwarmMapScreen({super.key});

  @override
  State<SwarmMapScreen> createState() => _SwarmMapScreenState();
}

class _SwarmMapScreenState extends State<SwarmMapScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  GoogleMapController? _mapController;
  LatLng _initialCenter = const LatLng(29.9691, 76.9629);

  Set<Marker> _differentiatedMarkers = {};
  Set<Polygon> _swarmGridPolygons = {};

  String _currentUserSwarmToken = "Calculating...";
  int _localCount = 0;
  int _globalCount = 0;

  @override
  void initState() {
    super.initState();
    _initializeMapMatrix();
  }

  Set<LatLng> _computeS2PolygonCorners(String token) {
    try {
      String cleanToken = token.toLowerCase().trim();

      if (!cleanToken.startsWith("s2_14_")) {
        if (cleanToken.contains('_')) {
          cleanToken = "s2_14_$cleanToken";
        } else {
          return {};
        }
      }

      List<String> parts = cleanToken.replaceAll('s2_14_', '').split('_');
      if (parts.length != 2) return {};

      String latHex = parts[0].replaceAll('n', '-');
      String lngHex = parts[1].replaceAll('n', '-');

      int latIndex = int.parse(latHex, radix: 16);
      int lngIndex = int.parse(lngHex, radix: 16);

      const double latSpacing = 0.0045;
      const double lngSpacing = 0.0052;

      double minLat = latIndex * latSpacing;
      double maxLat = minLat + latSpacing;
      double minLng = lngIndex * lngSpacing;
      double maxLng = minLng + lngSpacing;

      return {
        LatLng(minLat, minLng),
        LatLng(maxLat, minLng),
        LatLng(maxLat, maxLng),
        LatLng(minLat, maxLng),
      };
    } catch (e) {
      debugPrint("S2 Coordinate calculation fault: $e");
      return {};
    }
  }

  String _backwardsCompatibleTokenCheck(Map<String, dynamic> item) {
    if (item['s2_cell_id'] != null &&
        item['s2_cell_id'].toString().isNotEmpty) {
      return item['s2_cell_id'].toString().toLowerCase().trim();
    }
    final double lat = (item['location_lat'] as num? ?? 0.0).toDouble();
    final double lng = (item['location_lng'] as num? ?? 0.0).toDouble();
    return S2Helper.generateLevel14Token(lat, lng).toLowerCase().trim();
  }

  Future<void> _initializeMapMatrix() async {
    setState(() => _isLoading = true);
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      LatLng currentLatLng = LatLng(pos.latitude, pos.longitude);

      String rawUserToken = S2Helper.generateLevel14Token(
        pos.latitude,
        pos.longitude,
      );
      String standardizedUserToken = rawUserToken.toLowerCase().trim();

      // LIVE FILTER: Strictly requests ONLY data that is 'PENDING'. Drops ghost data instantly.
      final List<dynamic> allItems = await _supabase
          .from('waste_items')
          .select('*, profiles(display_name)')
          .eq('status', 'PENDING');

      Set<Marker> computedMarkers = {};
      Set<Polygon> computedPolygons = {};
      Set<String> processedGridTokens = {};

      int localCounter = 0;
      int globalCounter = 0;

      for (var item in allItems) {
        final double lat = (item['location_lat'] as num).toDouble();
        final double lng = (item['location_lng'] as num).toDouble();

        final String itemS2Token = _backwardsCompatibleTokenCheck(item);
        final bool isLocalSwarm =
            (itemS2Token == standardizedUserToken) ||
            (itemS2Token.replaceAll('s2_14_', '') ==
                standardizedUserToken.replaceAll('s2_14_', ''));

        if (isLocalSwarm) {
          localCounter++;
        } else {
          globalCounter++;
        }

        computedMarkers.add(
          Marker(
            markerId: MarkerId("marker_${item['id']}"),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isLocalSwarm
                  ? BitmapDescriptor.hueGreen
                  : BitmapDescriptor.hueCyan,
            ),
            infoWindow: InfoWindow(
              title: isLocalSwarm ? "Local Swarm Drop" : "Global Reach Drop",
              snippet:
                  "${item['material_type']} | Added by: ${item['profiles']?['display_name'] ?? 'Citizen'}",
            ),
          ),
        );

        if (itemS2Token.isNotEmpty &&
            !processedGridTokens.contains(itemS2Token)) {
          processedGridTokens.add(itemS2Token);
          Set<LatLng> boundsCorners = _computeS2PolygonCorners(itemS2Token);

          if (boundsCorners.isNotEmpty) {
            final bool isUserCurrentGridBox =
                itemS2Token == standardizedUserToken ||
                itemS2Token.replaceAll('s2_14_', '') ==
                    standardizedUserToken.replaceAll('s2_14_', '');

            computedPolygons.add(
              Polygon(
                polygonId: PolygonId("poly_$itemS2Token"),
                points: boundsCorners.toList(),
                strokeColor: isUserCurrentGridBox
                    ? const Color(0xFF00E676)
                    : Colors.cyan.withOpacity(0.4),
                strokeWidth: isUserCurrentGridBox ? 3 : 1,
                fillColor: isUserCurrentGridBox
                    ? const Color(0xFF00E676).withOpacity(0.15)
                    : Colors.cyan.withOpacity(0.03),
              ),
            );
          }
        }
      }

      if (!processedGridTokens.contains(standardizedUserToken)) {
        Set<LatLng> userCorners = _computeS2PolygonCorners(
          standardizedUserToken,
        );
        if (userCorners.isNotEmpty) {
          computedPolygons.add(
            Polygon(
              polygonId: PolygonId("poly_user_$standardizedUserToken"),
              points: userCorners.toList(),
              strokeColor: const Color(0xFF00E676),
              strokeWidth: 3,
              fillColor: const Color(0xFF00E676).withOpacity(0.15),
            ),
          );
        }
      }

      setState(() {
        _initialCenter = currentLatLng;
        _currentUserSwarmToken = standardizedUserToken.toUpperCase().replaceAll(
          'S2_14_',
          '',
        );
        _differentiatedMarkers = computedMarkers;
        _swarmGridPolygons = computedPolygons;
        _localCount = localCounter;
        _globalCount = globalCounter;
        _isLoading = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(currentLatLng, 14.5),
      );
    } catch (e) {
      debugPrint("Logistics Interface Synchronization Failure: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Global Swarm Sync",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00E676)),
            onPressed: _initializeMapMatrix,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E676)),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _initialCenter,
                    zoom: 14.5,
                  ),
                  markers: _differentiatedMarkers,
                  polygons: _swarmGridPolygons,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                ),

                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
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
                              "CURRENT SECTOR: #$_currentUserSwarmToken",
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const Icon(
                              Icons.language_outlined,
                              color: Colors.grey,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Geospatial Metric Impact Matrix:",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildLegendIndicator(
                              color: Colors.green,
                              label: "$_localCount Swarm Drops",
                            ),
                            const SizedBox(width: 16),
                            _buildLegendIndicator(
                              color: Colors.cyan,
                              label: "$_globalCount Macro Actions",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegendIndicator({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
