import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // NEW: dotenv import
import 'dart:io';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'swarm_map_screen.dart';
import '../services/s2_helper.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isProcessing = false;

  // 1. THE DETERMINISTIC HARDCODED MATRIX
  final Map<String, Map<String, dynamic>> _wasteMatrix = {
    "laptop_computer": {
      "name": "Laptop / Desktop",
      "cat": "E-Waste",
      "tox": 6,
      "val": 9,
      "comp": 7,
      "weight_g": 2000.0,
      "sdg": "12",
    },
    "smartphone": {
      "name": "Smartphone / Tablet",
      "cat": "E-Waste",
      "tox": 5,
      "val": 10,
      "comp": 8,
      "weight_g": 200.0,
      "sdg": "12",
    },
    "cables_wires": {
      "name": "Cables & Wires",
      "cat": "E-Waste",
      "tox": 4,
      "val": 4,
      "comp": 3,
      "weight_g": 35.0,
      "sdg": "12",
    },
    "small_peripheral": {
      "name": "Electronic Peripheral",
      "cat": "E-Waste",
      "tox": 4,
      "val": 5,
      "comp": 4,
      "weight_g": 250.0,
      "sdg": "12",
    },
    "lithium_ion_battery": {
      "name": "Lithium-Ion Cell",
      "cat": "Portable Power",
      "tox": 8,
      "val": 8,
      "comp": 9,
      "weight_g": 45.0,
      "sdg": "12",
    },
    "alkaline_battery": {
      "name": "Alkaline / Carbon Cell",
      "cat": "Portable Power",
      "tox": 3,
      "val": 2,
      "comp": 3,
      "weight_g": 25.0,
      "sdg": "12",
    },
    "lead_acid_battery": {
      "name": "Sealed Lead Acid Battery",
      "cat": "Portable Power",
      "tox": 8,
      "val": 6,
      "comp": 6,
      "weight_g": 2500.0,
      "sdg": "12",
    },
    "e_cigarette": {
      "name": "Intact E-Cigarette (Vape)",
      "cat": "Vaping (ENDS)",
      "tox": 10,
      "val": 4,
      "comp": 10,
      "weight_g": 60.0,
      "sdg": "12",
    },
    "medication_pills": {
      "name": "Expired Medication",
      "cat": "Pharmaceuticals",
      "tox": 9,
      "val": 1,
      "comp": 6,
      "weight_g": 10.0,
      "sdg": "3",
    },
    "blister_pack": {
      "name": "Empty Blister Pack",
      "cat": "Pharmaceuticals",
      "tox": 3,
      "val": 2,
      "comp": 9,
      "weight_g": 15.0,
      "sdg": "12",
    },
    "biomedical_sharps": {
      "name": "Biomedical Sharps",
      "cat": "Medical Waste",
      "tox": 9,
      "val": 1,
      "comp": 8,
      "weight_g": 500.0,
      "sdg": "3",
    },
    "cfl_bulb": {
      "name": "Fluorescent Lamp (CFL)",
      "cat": "Mercury Devices",
      "tox": 8,
      "val": 3,
      "comp": 8,
      "weight_g": 80.0,
      "sdg": "12",
    },
    "mercury_thermometer": {
      "name": "Liquid Mercury Thermometer",
      "cat": "Mercury Devices",
      "tox": 10,
      "val": 2,
      "comp": 9,
      "weight_g": 15.0,
      "sdg": "3",
    },
    "smoke_detector": {
      "name": "Ionization Smoke Detector",
      "cat": "Radioactive",
      "tox": 8,
      "val": 2,
      "comp": 7,
      "weight_g": 250.0,
      "sdg": "12",
    },
    "aerosol_can": {
      "name": "Pressurized Aerosol Can",
      "cat": "Chemicals",
      "tox": 7,
      "val": 3,
      "comp": 7,
      "weight_g": 350.0,
      "sdg": "12",
    },
    "agrochemical": {
      "name": "Pesticide / Fertilizer",
      "cat": "Chemicals",
      "tox": 10,
      "val": 1,
      "comp": 8,
      "weight_g": 1000.0,
      "sdg": "6",
    },
    "solvent": {
      "name": "Paint Thinner / Solvent",
      "cat": "Chemicals",
      "tox": 8,
      "val": 4,
      "comp": 6,
      "weight_g": 1000.0,
      "sdg": "6",
    },
    "fire_extinguisher": {
      "name": "Household Fire Extinguisher",
      "cat": "Pressurized Tanks",
      "tox": 5,
      "val": 4,
      "comp": 6,
      "weight_g": 3000.0,
      "sdg": "12",
    },
    "cooking_oil": {
      "name": "Domestic Fats & Oils (FOG)",
      "cat": "Organic Byproducts",
      "tox": 6,
      "val": 8,
      "comp": 4,
      "weight_g": 900.0,
      "sdg": "7",
    },
    "bleach_ammonia": {
      "name": "Bleach / Ammonia Container",
      "cat": "Household Cleaners",
      "tox": 7,
      "val": 2,
      "comp": 4,
      "weight_g": 1000.0,
      "sdg": "12",
    },
    "antifreeze": {
      "name": "Antifreeze",
      "cat": "Automotive Fluids",
      "tox": 9,
      "val": 2,
      "comp": 5,
      "weight_g": 3700.0,
      "sdg": "12",
    },
    "motor_oil": {
      "name": "Used Motor Oil",
      "cat": "Automotive Fluids",
      "tox": 7,
      "val": 7,
      "comp": 5,
      "weight_g": 4000.0,
      "sdg": "12",
    },
    "paint_oil_based": {
      "name": "Oil-Based Paint",
      "cat": "Home Maintenance",
      "tox": 6,
      "val": 3,
      "comp": 6,
      "weight_g": 3500.0,
      "sdg": "12",
    },
    "adhesive_glue": {
      "name": "Industrial Strength Glue",
      "cat": "Home Maintenance",
      "tox": 5,
      "val": 2,
      "comp": 4,
      "weight_g": 150.0,
      "sdg": "12",
    },
    "nail_polish": {
      "name": "Nail Polish / Remover",
      "cat": "Miscellaneous",
      "tox": 4,
      "val": 1,
      "comp": 3,
      "weight_g": 50.0,
      "sdg": "12",
    },
    "pool_chemicals": {
      "name": "Pool Chemicals",
      "cat": "Miscellaneous",
      "tox": 9,
      "val": 1,
      "comp": 6,
      "weight_g": 2000.0,
      "sdg": "12",
    },
  };

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.cameras[0], ResolutionPreset.medium);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services disabled.');
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied) {
        return Future.error('Location permissions denied.');
      }
    }
    return await Geolocator.getCurrentPosition();
  }

  Future<void> _saveToSwarm(Map<String, dynamic> data) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    try {
      Position pos = await _determinePosition();
      String s2Token = S2Helper.generateLevel14Token(
        pos.latitude,
        pos.longitude,
      );

      await supabase.from('waste_items').insert({
        'user_id': user?.id,
        'material_type': "${data['item_name']} (x${data['quantity']})",
        'category': data['category'],
        'analysis_result': data['user_tip'],
        'is_toxic': data['is_toxic'],
        'eco_points': data['total_calculated_points'],
        'weight_grams': data['total_weight_grams'],
        'location_lat': pos.latitude,
        'location_lng': pos.longitude,
        'is_collected': false,
        'status': 'PENDING',
        's2_cell_id': s2Token,
      });
    } catch (e) {
      debugPrint("Supabase Transaction Sync Failure: $e");
    }
  }

  Future<void> _analyzeImage(XFile image) async {
    setState(() => _isProcessing = true);
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];

      // 1. Explicitly check if the key exists before doing anything
      if (apiKey == null || apiKey.trim().isEmpty) {
        throw "GEMINI_API_KEY is missing or empty in your .env file!";
      }

      // 2. FETCH THE DYNAMIC MODEL FROM SUPABASE
      String activeModelString = 'gemini-2.5-flash-lite'; // Fallback default
      try {
        final configResponse = await Supabase.instance.client
            .from('app_settings')
            .select('active_gemini_model')
            .eq('id', 1)
            .maybeSingle();

        if (configResponse != null &&
            configResponse['active_gemini_model'] != null) {
          activeModelString = configResponse['active_gemini_model'] as String;
        }
      } catch (dbError) {
        debugPrint(
          "Failed to fetch model from Supabase, using fallback: $dbError",
        );
      }

      debugPrint("INITIALIZING GEMINI WITH MODEL: $activeModelString");

      // 3. INITIALIZE GEMINI WITH THE DYNAMIC STRING
      final model = GenerativeModel(
        model: activeModelString,
        apiKey: apiKey.trim(),
      );

      final imageBytes = await File(image.path).readAsBytes();

      final prompt = TextPart("""
        Identify the scanned waste item for AuraSync. 

        Your ONLY job is to classify the object into one of these exact keys. 
        If it is a generic cable, charger, mouse, or small tech, YOU MUST USE 'small_peripheral'.
        
        ALLOWED KEYS:
        - laptop_computer, smartphone, small_peripheral
        - lithium_ion_battery, alkaline_battery, lead_acid_battery
        - e_cigarette
        - medication_pills, blister_pack
        - cfl_bulb, mercury_thermometer
        - smoke_detector
        - aerosol_can, agrochemical, solvent, fire_extinguisher, cooking_oil
        - biomedical_sharps
        - bleach_ammonia, antifreeze, motor_oil, paint_oil_based, adhesive_glue, nail_polish, pool_chemicals
        - unknown_hazardous
        - non_hazardous

        Return ONLY a raw JSON markdown object matching this exact structure:
        {
          "item_key": "one_of_the_exact_keys_above",
          "detected_item_name": "Be highly specific (e.g., 'USB-C Cable', 'Duracell AA Battery', 'MacBook Air')",
          "quantity": 1,
          "is_toxic": true/false,
          "estimated_weight_grams": 0.0,
          "user_tip": "One concise safe-handling instruction",
          "eco_insight": "A stark environmental impact fact"
        }
      """);

      final content = [
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)]),
      ];
      final response = await model.generateContent(content);

      if (response.text != null) {
        final cleanJson = response.text!
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        final Map<String, dynamic> rawData = jsonDecode(cleanJson);

        final Map<String, dynamic> processedData = _processDeterministicMath(
          rawData,
        );

        if (mounted) _showImpactCard(processedData);
      }
    } catch (e) {
      debugPrint("Core Analysis Engine Error: $e");
      // This will force a red popup to appear with the exact error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Scan Failed: $e"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Map<String, dynamic> _processDeterministicMath(Map<String, dynamic> rawData) {
    debugPrint("GEMINI RAW OUTPUT: $rawData");

    String generatedKey = (rawData['item_key'] ?? 'non_hazardous')
        .toString()
        .toLowerCase()
        .trim();
    String specificName = (rawData['detected_item_name'] ?? '').toString();
    bool isToxic = rawData['is_toxic'] ?? false;
    final String insightText = (rawData['eco_insight'] ?? '')
        .toString()
        .toLowerCase();

    // 3. FUZZY MATCHING
    String? matchedMatrixKey;

    if (_wasteMatrix.containsKey(generatedKey)) {
      matchedMatrixKey = generatedKey;
    } else {
      for (String matrixKey in _wasteMatrix.keys) {
        if (generatedKey.contains(matrixKey) ||
            matrixKey.contains(generatedKey)) {
          matchedMatrixKey = matrixKey;
          break;
        }
      }
    }

    if (matchedMatrixKey == null) {
      if (insightText.contains('electronic') ||
          insightText.contains('e-waste') ||
          insightText.contains('cable') ||
          generatedKey.contains('cable') ||
          generatedKey.contains('charger')) {
        matchedMatrixKey = "small_peripheral";
      } else if (insightText.contains('battery') ||
          generatedKey.contains('battery')) {
        matchedMatrixKey = "alkaline_battery";
      }
    }

    if (matchedMatrixKey != null) {
      isToxic = true;
    }

    // 4. THE NEW GENEROUS POINT CALCULATION
    final int qty = rawData['quantity'] ?? 1;
    int tox = 0, val = 0, comp = 0;
    double unitWeightGrams = 0.0;
    String name = "General Municipal Waste";
    String category = "Non-Hazardous";
    String sdg = "12";

    if (isToxic) {
      if (matchedMatrixKey != null) {
        tox = _wasteMatrix[matchedMatrixKey]!['tox'];
        val = _wasteMatrix[matchedMatrixKey]!['val'];
        comp = _wasteMatrix[matchedMatrixKey]!['comp'];
        unitWeightGrams = _wasteMatrix[matchedMatrixKey]!['weight_g'];

        String matrixName = _wasteMatrix[matchedMatrixKey]!['name'];
        name = specificName.isNotEmpty ? specificName : matrixName;

        category = _wasteMatrix[matchedMatrixKey]!['cat'];
        sdg = _wasteMatrix[matchedMatrixKey]!['sdg'];
      } else {
        tox = 5;
        val = 5;
        comp = 5;
        unitWeightGrams = (rawData['estimated_weight_grams'] as num? ?? 500.0)
            .toDouble();
        name = specificName.isNotEmpty
            ? specificName
            : "Unknown Hazardous Waste";
        category = "General Hazard";
      }

      // NEW GENEROUS WEIGHT TIERS
      double weightKg = unitWeightGrams / 1000.0;
      double weightMultiplier = 0.5; // Base for Micro items (<100g)

      if (weightKg >= 2.0) {
        weightMultiplier = 3.5; // Large (Laptops, Big Batteries)
      } else if (weightKg >= 0.5) {
        weightMultiplier = 2.0; // Medium (Pesticides, Small appliances)
      } else if (weightKg >= 0.1) {
        weightMultiplier = 1.0; // Small (Phones, Cables, Cans)
      }

      // The Updated Formula
      double basePoints = (tox + val + comp) * weightMultiplier;
      int totalPoints = (basePoints * qty).round();

      // NEW SAFETY FLOOR: A user should NEVER get less than 5 points for recycling hazardous items!
      if (totalPoints < 5) totalPoints = 5;

      rawData['item_name'] = name;
      rawData['category'] = category;
      rawData['sdg_impact'] = sdg;
      rawData['base_point_value'] = (basePoints < 5) ? 5 : basePoints.round();
      rawData['base_weight_grams'] = unitWeightGrams;
      rawData['total_calculated_points'] = totalPoints;
      rawData['total_weight_grams'] = unitWeightGrams * qty;
      rawData['is_toxic'] = true;
    } else {
      rawData['item_name'] = specificName.isNotEmpty
          ? specificName
          : "General Municipal Waste";
      rawData['category'] = "Non-Hazardous";
      rawData['sdg_impact'] = "12";
      rawData['base_point_value'] = 0;
      rawData['base_weight_grams'] = 0.0;
      rawData['total_calculated_points'] = 0;
      rawData['total_weight_grams'] = 0.0;
      rawData['is_toxic'] = false;
    }

    return rawData;
  }

  void _showImpactCard(Map<String, dynamic> data) {
    final bool isToxic = data['is_toxic'] ?? false;
    final int qty = data['quantity'] ?? 1;

    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "${data['item_name']} (x$qty)",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(
                            isToxic
                                ? "+${data['total_calculated_points']} PTS"
                                : "0 PTS",
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          backgroundColor: isToxic
                              ? const Color(0xFF00E676)
                              : Colors.grey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Category: ${data['category']}",
                      style: TextStyle(
                        color: isToxic
                            ? const Color(0xFF00E676)
                            : Colors.amberAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 16),

                    if (isToxic)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Unit Base Value:",
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  "${data['base_point_value']} pts  |  ${data['base_weight_grams']}g",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white10, height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Total Footprint:",
                                  style: const TextStyle(
                                    color: Color(0xFF00E676),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "${data['total_calculated_points']} pts  |  ${data['total_weight_grams']}g",
                                  style: const TextStyle(
                                    color: Color(0xFF00E676),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),
                    const Text(
                      "Environmental Insight:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data['eco_insight'] ?? "",
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (isToxic) ...[
                      const Text(
                        "Safe Household Storage Advice:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data['user_tip'] ?? "",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          "Logistics Target Matrix: SDG ${data['sdg_impact'] ?? '12'}",
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.2),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.amber,
                              size: 18,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "This analysis is informational. General waste lines do not issue active community tracking tags.",
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSubmitting
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "Scan discarded. No ledger entries created.",
                                        ),
                                        backgroundColor: Colors.white24,
                                      ),
                                    );
                                  },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              "Discard Scan",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    if (isToxic) {
                                      setModalState(() => isSubmitting = true);
                                      await _saveToSwarm(data);
                                    }
                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            isToxic
                                                ? "✨ Verified entry uploaded to regional swarm ledger!"
                                                : "Insight logged safely.",
                                          ),
                                          backgroundColor: const Color(
                                            0xFF00E676,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.black,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    isToxic ? "Confirm & Log" : "Done",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00E676)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "Toxin Classifier",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Transform.scale(
            scale: 1.0,
            child: Center(child: CameraPreview(_controller)),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00E676)),
                    SizedBox(height: 16),
                    Text(
                      "Analyzing Composition & Estimating Weight...",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.large(
        backgroundColor: const Color(0xFF00E676),
        onPressed: () async {
          if (!_isProcessing) {
            try {
              final img = await _controller.takePicture();
              await _analyzeImage(img);
            } catch (e) {
              debugPrint("Capture Fault: $e");
            }
          }
        },
        child: const Icon(
          Icons.camera_alt_outlined,
          size: 36,
          color: Colors.black,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
