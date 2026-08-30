import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart'; // REQUIRED FOR LOCALIZATION
import '../services/s2_helper.dart'; // REQUIRED FOR LOCALIZATION

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;

  int _trustScore = 100;
  int _verifiedPoints = 0;

  // NEW: Specifically localized impact variables
  double _localCommunityKg = 0.0;
  bool _hasLocalContribution = false;

  final List<Map<String, dynamic>> _rewards = [
    {
      'title': 'Free Coffee @ GreenBrew',
      'cost': 50,
      'code': 'AURABREW50',
      'icon': Icons.local_cafe,
    },
    {
      'title': '20% Off Transit Pass',
      'cost': 150,
      'code': 'AURATRANSIT20',
      'icon': Icons.directions_bus,
    },
    {
      'title': '\$10 Eco-Store Credit',
      'cost': 300,
      'code': 'AURA10ECO',
      'icon': Icons.shopping_bag,
    },
    {
      'title': '1 Month Spotify Premium',
      'cost': 500,
      'code': 'AURABEATS',
      'icon': Icons.music_note,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Get the Current S2 Cell Context
      String? localToken;
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
          localToken = S2Helper.generateLevel14Token(
            pos.latitude,
            pos.longitude,
          ).toLowerCase().trim();
        }
      }

      // 2. Fetch Profile Identity
      final profileData = await _supabase
          .from('profiles')
          .select('display_name, trust_score')
          .eq('id', user.id)
          .single();

      // 3. Fetch GLOBAL Verified Points (For the marketplace wallet)
      final itemsData = await _supabase
          .from('waste_items')
          .select('eco_points')
          .eq('user_id', user.id)
          .eq('status', 'COLLECTED');

      int calculatedPoints = 0;
      for (var item in itemsData) {
        calculatedPoints += (item['eco_points'] as int? ?? 0);
      }

      // 4. Fetch LOCALIZED Community Impact
      var commQuery = _supabase
          .from('waste_items')
          .select('weight_grams')
          .eq('status', 'COLLECTED');
      if (localToken != null)
        commQuery = commQuery.eq('s2_cell_id', localToken);

      final communityResponse = await commQuery;
      double cGrams = 0;
      for (var item in communityResponse) {
        cGrams += (item['weight_grams'] as num? ?? 0.0).toDouble();
      }

      // 5. CHECK: Has THIS user contributed to THIS specific Swarm?
      var localContQuery = _supabase
          .from('waste_items')
          .select('id')
          .eq('user_id', user.id)
          .eq('status', 'COLLECTED');
      if (localToken != null)
        localContQuery = localContQuery.eq('s2_cell_id', localToken);

      final localContResponse = await localContQuery;
      bool hasLocal = localContResponse
          .isNotEmpty; // TRUE if they have verified logs in this exact cell

      setState(() {
        _nameController.text = profileData['display_name'] ?? "";
        _trustScore = profileData['trust_score'] ?? 100;
        _verifiedPoints = calculatedPoints;
        _localCommunityKg = cGrams / 1000.0;
        _hasLocalContribution = hasLocal;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Profile Load Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isSaving = true);
    final user = _supabase.auth.currentUser;

    try {
      await _supabase
          .from('profiles')
          .update({
            'display_name': _nameController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user!.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile Identity Updated"),
            backgroundColor: Color(0xFF00E676),
          ),
        );
      }
    } catch (e) {
      debugPrint("Update Error: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _redeemReward(Map<String, dynamic> reward) {
    if (_verifiedPoints < reward['cost']) return;

    setState(() {
      _verifiedPoints -= (reward['cost'] as int);
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.only(
            top: 32,
            left: 32,
            right: 32,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF00E676),
                size: 60,
              ),
              const SizedBox(height: 16),
              const Text(
                "REWARD UNLOCKED",
                style: TextStyle(
                  color: Color(0xFF00E676),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reward['title'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 32,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.qr_code_2, color: Colors.black, size: 80),
                    const SizedBox(height: 8),
                    Text(
                      reward['code'],
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Show this code at the partner location to redeem.",
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    "Close",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                        await _supabase.auth.signOut();
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

  Widget _buildBadgesSection() {
    int unlockedTiers = 0;

    if (_localCommunityKg >= 100.0) {
      unlockedTiers = 4;
    } else if (_localCommunityKg >= 60.0) {
      unlockedTiers = 3;
    } else if (_localCommunityKg >= 30.0) {
      unlockedTiers = 2;
    } else if (_localCommunityKg >= 15.0) {
      unlockedTiers = 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Local Sector Milestones Earned",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        // THE ANTI-FREERIDER CHECK
        if (unlockedTiers == 0 || !_hasLocalContribution)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: const Text(
              "No community badges earned in your current sector yet. Scan and verify a drop to unlock trophies here!",
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: List.generate(unlockedTiers, (index) {
                int tierNum = index + 1;
                String targetText = "15kg";
                if (tierNum == 2) targetText = "30kg";
                if (tierNum == 3) targetText = "60kg";
                if (tierNum == 4) targetText = "100kg";

                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.emoji_events,
                        color: Colors.amber,
                        size: 36,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Tier $tierNum",
                        style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$targetText Reached",
                        style: TextStyle(
                          color: Colors.amber.withOpacity(0.7),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "Citizen Profile",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
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
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: "Display Name",
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFF00E676),
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.person_outline,
                                color: Color(0xFF00E676),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _updateProfile,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.black,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      "Update Identity",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      "Account Status",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _trustScore >= 70
                            ? Colors.green.withOpacity(0.05)
                            : Colors.red.withOpacity(0.05),
                        border: Border.all(
                          color: _trustScore >= 70
                              ? Colors.green.withOpacity(0.3)
                              : Colors.red.withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _trustScore >= 70
                                ? Icons.verified_user
                                : Icons.warning_amber_rounded,
                            color: _trustScore >= 70
                                ? const Color(0xFF00E676)
                                : Colors.redAccent,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Community Trust Score: $_trustScore%",
                                  style: TextStyle(
                                    color: _trustScore >= 70
                                        ? const Color(0xFF00E676)
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _trustScore >= 70
                                      ? "Your account is in good standing. Handover verifications are active."
                                      : "Warning: Fraudulent activity detected. Score below 40% limits account capabilities.",
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildBadgesSection(),
                    const SizedBox(height: 32),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Eco-Marketplace",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: Color(0xFF00E676),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "$_verifiedPoints pts",
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                      itemCount: _rewards.length,
                      itemBuilder: (context, index) {
                        final reward = _rewards[index];
                        final bool canAfford =
                            _verifiedPoints >= reward['cost'];

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: canAfford
                                  ? const Color(0xFF00E676).withOpacity(0.4)
                                  : Colors.white10,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                reward['icon'],
                                color: canAfford
                                    ? Colors.white
                                    : Colors.white24,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  reward['title'],
                                  style: TextStyle(
                                    color: canAfford
                                        ? Colors.white
                                        : Colors.white38,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: canAfford
                                    ? () => _redeemReward(reward)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: canAfford
                                      ? const Color(0xFF00E676)
                                      : Colors.grey[900],
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  canAfford
                                      ? "Redeem (${reward['cost']})"
                                      : "Lock (${reward['cost']})",
                                  style: TextStyle(
                                    color: canAfford
                                        ? Colors.black
                                        : Colors.white38,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
