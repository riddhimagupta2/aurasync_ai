import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:geolocator/geolocator.dart'; // NEW: Added for permission gateway
import 'dashboard_screen.dart';
import 'collector_dashboard_screen.dart';

class AuthScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const AuthScreen({super.key, required this.cameras});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _isAdminRole = false;

  // --- HELPER: CLEAN ERROR MESSAGES ---
  String _getReadableErrorMessage(dynamic e) {
    if (e is AuthException) {
      if (e.message.toLowerCase().contains('invalid login credentials')) {
        return "Incorrect email or password. Please try again.";
      }
      return e.message;
    }

    String errorStr = e.toString();
    if (errorStr.contains('Invalid login credentials') ||
        errorStr.contains('invalid_credentials')) {
      return "Incorrect email or password. Please try again.";
    }

    return errorStr.replaceFirst('Exception: ', '');
  }

  // --- LOCATION SECURITY GATEWAY ---
  Future<void> _routeToDashboard() async {
    setState(() => _isLoading = true);

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isLoading = false);
      _showLocationRequirementDialog(
        "Location services are disabled. Please enable GPS to map Swarm sectors.",
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isLoading = false);
        _showLocationRequirementDialog(
          "AuraSync strictly requires location access to log waste correctly.",
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _isLoading = false);
      _showLocationRequirementDialog(
        "Location permissions are permanently denied. Open App Settings to grant access.",
        isPermanent: true,
      );
      return;
    }

    // Proceed to Dashboard ONLY if permissions are granted
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => _isAdminRole
              ? const CollectorDashboardScreen()
              : DashboardScreen(cameras: widget.cameras),
        ),
      );
    }
  }

  // --- UN-DISMISSIBLE LOCATION BLOCKER ---
  void _showLocationRequirementDialog(
    String message, {
    bool isPermanent = false,
  }) {
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
              await GoogleSignIn.instance.signOut();
              if (context.mounted) {
                Navigator.pop(context);
                setState(() => _isLoading = false);
              }
            },
            child: const Text(
              "Cancel Login",
              style: TextStyle(color: Colors.grey),
            ),
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
                _routeToDashboard();
              }
            },
            child: Text(
              isPermanent ? "Open Settings" : "Try Again",
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Native Google Sign-In Flow ---
  Future<void> _handleThirdPartyGoogleAuth() async {
    setState(() => _isLoading = true);
    try {
      const webClientId =
          '568992797364-cbqf1fvsmesir8vqtmp4rfo9h40inj1d.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(serverClientId: webClientId);

      final googleUser = await googleSignIn.authenticate();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return; // User canceled the sign-in flow
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'Missing Google ID Token.';
      }

      final AuthResponse response = await Supabase.instance.client.auth
          .signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);

      if (response.user != null) {
        final googleName =
            response.user!.userMetadata?['full_name'] ??
            response.user!.userMetadata?['name'] ??
            'Eco Neighbor';

        final profileRow = await Supabase.instance.client
            .from('profiles')
            .select('role, trust_score, display_name')
            .eq('id', response.user!.id)
            .limit(1)
            .maybeSingle();

        if (profileRow == null) {
          await Supabase.instance.client.from('profiles').insert({
            'id': response.user!.id,
            'display_name': googleName,
            'role': _isAdminRole ? 'collector_admin' : 'user',
            'trust_score': 100,
          });
        } else {
          final String? currentDisplayName = profileRow['display_name'];
          if (currentDisplayName == null ||
              currentDisplayName == 'Eco Neighbor') {
            await Supabase.instance.client
                .from('profiles')
                .update({'display_name': googleName})
                .eq('id', response.user!.id);
          }
        }

        final verifiedProfile = await Supabase.instance.client
            .from('profiles')
            .select('role, trust_score, phone, address')
            .eq('id', response.user!.id)
            .limit(1)
            .single();

        final String assignedRole = verifiedProfile['role'] ?? 'user';
        final int trustScore = verifiedProfile['trust_score'] ?? 100;
        final String? phone = verifiedProfile['phone'];
        final String? address = verifiedProfile['address'];
        final String expectedRole = _isAdminRole ? 'collector_admin' : 'user';

        if (trustScore <= 0) {
          await Supabase.instance.client.auth.signOut();
          await googleSignIn.signOut();
          throw "Access Terminated. Your profile has been permanently suspended due to repeated fraudulent waste logging violations.";
        }

        if (assignedRole != expectedRole) {
          await Supabase.instance.client.auth.signOut();
          await googleSignIn.signOut();
          throw "Access Denied. Identity parameters do not match requested gateway portal rules.";
        }

        if (mounted) {
          if ((phone == null || phone.isEmpty) ||
              (address == null || address.isEmpty)) {
            setState(() => _isLoading = false);
            _showCompleteProfileDialog(response.user!.id);
            return;
          } else {
            // TRIGGER THE GATEWAY
            await _routeToDashboard();
          }
        }
      }
    } catch (e) {
      if (e.toString().toLowerCase().contains('canceled')) {
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getReadableErrorMessage(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCompleteProfileDialog(String userId) {
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text(
                "Complete Your Profile",
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "To arrange specialized waste pickups, we need your logistics details.",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: _buildInputDecoration(
                        "Phone Number",
                        Icons.phone,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: addressCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _buildInputDecoration(
                        "Full Pickup Address",
                        Icons.home,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    await GoogleSignIn.instance.signOut();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text(
                    "Cancel Login",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (phoneCtrl.text.trim().length < 10 ||
                              addressCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Valid phone and address are required.",
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);
                          try {
                            final existingBannedPhone = await Supabase
                                .instance
                                .client
                                .from('profiles')
                                .select('trust_score')
                                .eq('phone', phoneCtrl.text.trim())
                                .limit(1)
                                .maybeSingle();

                            if (existingBannedPhone != null &&
                                (existingBannedPhone['trust_score'] ?? 100) <=
                                    0) {
                              await Supabase.instance.client.auth.signOut();
                              await GoogleSignIn.instance.signOut();
                              throw "Registration Denied: This mobile number is associated with a suspended account due to policy violations.";
                            }

                            await Supabase.instance.client
                                .from('profiles')
                                .update({
                                  'phone': phoneCtrl.text.trim(),
                                  'address': addressCtrl.text.trim(),
                                })
                                .eq('id', userId);

                            if (context.mounted) {
                              Navigator.pop(context);
                              // TRIGGER THE GATEWAY
                              await _routeToDashboard();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_getReadableErrorMessage(e)),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              if (e.toString().contains("suspended")) {
                                Navigator.pop(context);
                              }
                            }
                          } finally {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.black),
                        )
                      : const Text(
                          "Save & Continue",
                          style: TextStyle(color: Colors.black),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showOtpMockDialog() async {
    final otpController = TextEditingController();
    bool isVerified = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          "Verify Mobile Number",
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "An SMS code has been sent to ${_phoneController.text.trim()}.",
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  color: Colors.white,
                  letterSpacing: 8,
                  fontSize: 24,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: "000000",
                  hintStyle: const TextStyle(color: Colors.white24),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF00E676)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "For prototype demo: Enter any 6 digits.",
                style: TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
            ),
            onPressed: () {
              if (otpController.text.length >= 6) {
                isVerified = true;
                Navigator.pop(context);
              }
            },
            child: const Text(
              "Verify",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (isVerified) {
      await _executeSupabaseSignup();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _executeSupabaseSignup() async {
    final supabase = Supabase.instance.client;
    final targetPhone = _phoneController.text.trim();

    try {
      final existingBannedPhone = await supabase
          .from('profiles')
          .select('trust_score')
          .eq('phone', targetPhone)
          .limit(1)
          .maybeSingle();

      if (existingBannedPhone != null) {
        final int previousScore = existingBannedPhone['trust_score'] ?? 100;
        if (previousScore <= 0) {
          throw "Registration Denied: This mobile number is associated with a suspended account due to policy violations.";
        }
      }

      final AuthResponse res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'display_name': _nameController.text.trim().isEmpty
              ? 'Eco Neighbor'
              : _nameController.text.trim(),
          'phone': targetPhone,
          'address': _addressController.text.trim(),
        },
      );

      if (mounted && res.user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Registration successful! Proceeding to verify account.",
            ),
          ),
        );
        setState(() => _isSignUp = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getReadableErrorMessage(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAuth() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in all security fields."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_isAdminRole && _isSignUp) {
      if (_phoneController.text.trim().length < 10 ||
          _addressController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Valid Phone (>10 digits) and Full Pickup Address are mandatory.",
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (!_isAdminRole && _isSignUp) {
        await _showOtpMockDialog();
      } else {
        final supabase = Supabase.instance.client;
        final AuthResponse response = await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (response.user != null) {
          final profileRow = await supabase
              .from('profiles')
              .select('role, trust_score, phone')
              .eq('id', response.user!.id)
              .limit(1)
              .maybeSingle();

          final String assignedRole = profileRow?['role'] ?? 'user';
          final int trustScore = profileRow?['trust_score'] ?? 100;
          final String? userPhone = profileRow?['phone'];
          final String expectedRole = _isAdminRole ? 'collector_admin' : 'user';

          if (trustScore <= 0) {
            await supabase.auth.signOut();
            throw "Access Terminated. Your profile has been permanently suspended due to repeated fraudulent waste logging violations.";
          }

          if (userPhone != null && userPhone.isNotEmpty) {
            final globalPhoneCheck = await supabase
                .from('profiles')
                .select('trust_score')
                .eq('phone', userPhone)
                .limit(1)
                .maybeSingle();

            if (globalPhoneCheck != null) {
              final int linkedTrustScore =
                  globalPhoneCheck['trust_score'] ?? 100;
              if (linkedTrustScore <= 0) {
                await supabase.auth.signOut();
                throw "Access Denied: The mobile number linked to this account is associated with a suspended profile.";
              }
            }
          }

          if (assignedRole != expectedRole) {
            await supabase.auth.signOut();
            throw "Access Denied. Identity parameters do not match requested gateway portal rules.";
          }

          if (mounted) {
            // TRIGGER THE GATEWAY
            await _routeToDashboard();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getReadableErrorMessage(e)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final TextEditingController resetEmailController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Reset Password",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Enter your registered email address. We will send you a 6-digit OTP code to reset your password.",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: resetEmailController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Email Address",
                        labelStyle: const TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white24),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color(0xFF00E676),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isSending
                      ? null
                      : () async {
                          if (resetEmailController.text.isEmpty) return;

                          setDialogState(() => isSending = true);
                          try {
                            await Supabase.instance.client.auth
                                .resetPasswordForEmail(
                                  resetEmailController.text.trim(),
                                );

                            if (context.mounted) {
                              Navigator.pop(context);
                              _showOTPVerificationDialog(
                                context,
                                resetEmailController.text.trim(),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_getReadableErrorMessage(e)),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          } finally {
                            setDialogState(() => isSending = false);
                          }
                        },
                  child: isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Send OTP",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOTPVerificationDialog(BuildContext context, String email) {
    final TextEditingController otpController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Verify OTP",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Enter the 6-digit code sent to $email.",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: otpController,
                      style: const TextStyle(
                        color: Colors.white,
                        letterSpacing: 8,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        counterText: "",
                        hintText: "000000",
                        hintStyle: const TextStyle(color: Colors.white24),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white24),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color(0xFF00E676),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "New Password",
                        labelStyle: const TextStyle(color: Colors.grey),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white24),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(
                            color: Color(0xFF00E676),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isVerifying
                      ? null
                      : () async {
                          if (otpController.text.length < 6 ||
                              newPasswordController.text.length < 6) {
                            return;
                          }

                          setDialogState(() => isVerifying = true);
                          try {
                            await Supabase.instance.client.auth.verifyOTP(
                              email: email,
                              token: otpController.text.trim(),
                              type: OtpType.recovery,
                            );

                            await Supabase.instance.client.auth.updateUser(
                              UserAttributes(
                                password: newPasswordController.text,
                              ),
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Password updated successfully! You can now log in.",
                                  ),
                                  backgroundColor: Color(0xFF00E676),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_getReadableErrorMessage(e)),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          } finally {
                            setDialogState(() => isVerifying = false);
                          }
                        },
                  child: isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Update Password",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.hub_outlined,
                size: 70,
                color: Color(0xFF00E676),
              ),
              const SizedBox(height: 12),
              const Text(
                "AURASYNC AI",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 35),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(child: _buildRoleTab("Citizen User", false)),
                    Expanded(child: _buildRoleTab("Collector Admin", true)),
                  ],
                ),
              ),
              const SizedBox(height: 35),

              Text(
                _isAdminRole
                    ? "Logistics Portal"
                    : (_isSignUp ? "Create Eco Profile" : "Welcome Back"),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),

              if (!_isAdminRole && _isSignUp) ...[
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration(
                    "Full Name",
                    Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration(
                    "Phone Number",
                    Icons.phone_android,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _addressController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _buildInputDecoration(
                    "Full Pickup Address",
                    Icons.home_work_outlined,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration(
                  "Security Email",
                  Icons.email_outlined,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration(
                  "Account Password",
                  Icons.lock_outline,
                ),
              ),
              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(
                          _isAdminRole
                              ? "AUTHORIZE LOGIN" // <-- Changed text
                              : (_isSignUp ? "REGISTER ACCOUNT" : "SIGN IN"),
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),

              if (!_isSignUp) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgotPasswordDialog(context),
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(color: Color(0xFF00E676), fontSize: 13),
                    ),
                  ),
                ),
              ],

              if (!_isAdminRole) ...[
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? "Already registered? Login directly"
                        : "New platform explorer? Create an account",
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white10)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          "OR",
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white10)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleThirdPartyGoogleAuth,
                  icon: const Icon(
                    Icons.g_mobiledata,
                    color: Colors.white,
                    size: 28,
                  ),
                  label: const Text(
                    "Continue with Google",
                    style: TextStyle(color: Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: const BorderSide(color: Colors.white10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleTab(String label, bool targetRole) {
    final bool active = _isAdminRole == targetRole;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isAdminRole = targetRole;
          if (_isAdminRole) _isSignUp = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00E676) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.black : Colors.white60,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey, size: 20),
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF00E676)),
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
    );
  }
}
