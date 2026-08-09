import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// A global wrapper widget that monitors internet connectivity.
/// When the device loses internet connection, it displays a non-dismissible
/// full-screen blocking overlay over the entire application.
class NetworkGuard extends StatefulWidget {
  final Widget child;

  const NetworkGuard({super.key, required this.child});

  @override
  State<NetworkGuard> createState() => _NetworkGuardState();
}

class _NetworkGuardState extends State<NetworkGuard> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isOffline = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
    try {
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        _verifyConnectivity(results);
      });
    } catch (e) {
      debugPrint('Connectivity stream listener error: $e');
    }
  }

  Future<void> _checkInitialConnection() async {
    try {
      final results = await Connectivity().checkConnectivity();
      await _verifyConnectivity(results);
    } catch (e) {
      debugPrint('Initial connectivity check error: $e');
      // If channel is uninitialized, perform raw DNS ping directly
      await _verifyConnectivity([]);
    }
  }

  /// Verifies active internet reachability by attempting a lightweight DNS lookup.
  Future<void> _verifyConnectivity(List<ConnectivityResult> results) async {
    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      // Before declaring offline, double-check with direct socket lookup
      try {
        final lookup = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        final hasInternet = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
        if (mounted) {
          setState(() => _isOffline = !hasInternet);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isOffline = true);
        }
      }
      return;
    }

    // Perform actual DNS ping to verify active internet throughput
    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final hasInternet = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      if (mounted) {
        setState(() => _isOffline = !hasInternet);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isOffline = true);
      }
    }
  }

  Future<void> _manualRetry() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final results = await Connectivity().checkConnectivity();
      await _verifyConnectivity(results);
    } catch (e) {
      await _verifyConnectivity([]);
    }
    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isOffline)
          PopScope(
            canPop: false,
            child: Material(
              color: Colors.black.withValues(alpha: 0.85),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            size: 64,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'No Internet Connection',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'MTC Sync requires an active internet connection to ensure your data stays synchronized. Please turn on Wi-Fi or Mobile Data to continue using the app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isChecking ? null : _manualRetry,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8CC63F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isChecking
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: Text(
                              _isChecking ? 'Checking Connection...' : 'Retry Connection',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
