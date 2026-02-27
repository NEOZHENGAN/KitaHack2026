// File: lib/home_page.dart
import 'dart:io' show Platform;
import 'dart:async'; 
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:geocoding/geocoding.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:flutter_dotenv/flutter_dotenv.dart'; 

enum RunState { preRun, running, postRun }

// Run record data model
class RunRecord {
  final String id;
  final double distance; // km
  final int duration; // seconds
  final DateTime date;
  final String location;
  final double pace; // min/km
  final double avgSpeed; // km/h

  RunRecord({
    required this.id,
    required this.distance,
    required this.duration,
    required this.date,
    required this.location,
    required this.pace,
    required this.avgSpeed,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'distance': distance,
      'duration': duration,
      'date': date,
      'location': location,
      'pace': pace,
      'avgSpeed': avgSpeed,
    };
  }

  factory RunRecord.fromMap(Map<String, dynamic> map, String docId) {
    return RunRecord(
      id: docId,
      distance: (map['distance'] as num).toDouble(),
      duration: map['duration'] as int,
      date: (map['date'] as Timestamp).toDate(),
      location: map['location'] as String,
      pace: (map['pace'] as num).toDouble(),
      avgSpeed: (map['avgSpeed'] as num).toDouble(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- Text Controllers ---
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _contactController = TextEditingController(); 
  final TextEditingController _notesController = TextEditingController(); 
  final TextEditingController _newGearController = TextEditingController(); 
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  int _selectedIndex = 0; 
  RunState _currentRunState = RunState.preRun; 
  
  // --- Cloud Data States ---
  List<String> _contactsList = [];
  List<Map<String, String>> _customManuals = []; 
  
  // Run record list
  List<RunRecord> _runRecords = [];
  bool _isLoadingRecords = false;
  
  // Gear Checklist
  List<Map<String, dynamic>> _gearList = [
    {"item": "ID / Driving License", "isChecked": false},
    {"item": "Water / Hydration Pack", "isChecked": false},
    {"item": "Emergency Cash", "isChecked": false},
    {"item": "Personal Meds (e.g. Inhaler)", "isChecked": false},
  ];

  bool _isSendingSOS = false; 
  bool _isSavingContact = false; 
  bool _isSavingNotes = false; 
  
  String _preRunAiResponse = '';
  bool _isLoadingPreRunAI = false;
  String _postRunAiResponse = '';
  bool _isLoadingPostRunAI = false;

  Timer? _runTimer;
  int _secondsElapsed = 0;
  double _distanceMeters = 0.0;
  Position? _lastPosition; 

  String _currentAddress = 'Locating...'; 

  @override
  void initState() {
    super.initState();
    _loadUserData(); 
    _initLocation(); 
    _loadRunRecords(); // Load run records
  }

  @override
  void dispose() {
    _runTimer?.cancel();
    _promptController.dispose();
    _contactController.dispose();
    _notesController.dispose();
    _newGearController.dispose();
    super.dispose();
  }

  // ==========================================
  // Run record functionality
  // ==========================================
  
  // Load run records
  Future<void> _loadRunRecords() async {
    setState(() => _isLoadingRecords = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('run_records')
            .orderBy('date', descending: true)
            .limit(50)
            .get();
        
        setState(() {
          _runRecords = snapshot.docs.map((doc) => RunRecord.fromMap(doc.data(), doc.id)).toList();
        });
        debugPrint('[DEBUG] Loaded ${_runRecords.length} run records');
      }
    } catch (e) {
      debugPrint('[DEBUG] Error loading run records: $e');
    } finally {
      setState(() => _isLoadingRecords = false);
    }
  }

  // Save new run record (no minimum distance limit)
  Future<void> _saveRunRecord() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        double km = _distanceMeters / 1000;
        
        // Save unconditionally (even 0.0km is saved)
        double pace = km > 0 ? _secondsElapsed / 60 / km : 0.0;
        double avgSpeed = km > 0 ? km / (_secondsElapsed / 3600) : 0.0;

        final record = RunRecord(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          distance: km,
          duration: _secondsElapsed,
          date: DateTime.now(),
          location: _currentAddress,
          pace: pace,
          avgSpeed: avgSpeed,
        );

        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('run_records')
            .doc(record.id)
            .set({
          'distance': record.distance,
          'duration': record.duration,
          'date': Timestamp.fromDate(record.date),
          'location': record.location,
          'pace': record.pace,
          'avgSpeed': record.avgSpeed,
        });

        debugPrint('[DEBUG] Run record saved: ${record.distance.toStringAsFixed(2)} km');
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Run recorded: ${record.distance.toStringAsFixed(2)}km in ${_formatTime(_secondsElapsed)}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        
        _loadRunRecords(); // Refresh the list
      }
    } catch (e) {
      debugPrint('[DEBUG] Error saving run record: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving record: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Delete run record
  Future<void> _deleteRunRecord(String recordId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('run_records')
            .doc(recordId)
            .delete();
        _loadRunRecords(); // Refresh the list
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Record deleted'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      debugPrint('[DEBUG] Error deleting record: $e');
    }
  }

  // ==========================================
  // Emergency call & profile management
  // ==========================================
  Future<void> _directCallEmergency() async {
    final Uri phoneUri = Uri.parse('tel:999'); 
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot launch dialer.')));
    }
  }

  Future<void> _showEditNameDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    final TextEditingController nameController = TextEditingController(text: user?.displayName ?? '');
    bool isUpdating = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Edit Username', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              content: TextField(
                controller: nameController,
                decoration: InputDecoration(hintText: 'Enter new name...', filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                  onPressed: isUpdating ? null : () async {
                    if (nameController.text.trim().isNotEmpty) {
                      setDialogState(() => isUpdating = true);
                      try {
                        await user?.updateDisplayName(nameController.text.trim());
                        await user?.reload(); 
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username updated successfully!'), backgroundColor: Colors.green));
                        }
                      } catch (e) { debugPrint('[DEBUG] Error updating name: $e'); } 
                      finally { setDialogState(() => isUpdating = false); }
                    }
                  },
                  child: isUpdating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  // ==========================================
  // Reverse geocoding (live address)
  // ==========================================
  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        if (mounted) setState(() => _lastPosition = pos); 
        await _updateAddress(pos);
      } else { setState(() => _currentAddress = 'Location permission denied'); }
    } catch (e) { debugPrint('[DEBUG] Init Location Error: $e'); }
  }

  Future<void> _updateAddress(Position pos) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String street = place.street ?? '';
        String locality = place.locality ?? place.subLocality ?? '';
        if (street.contains('+')) street = place.subLocality ?? ''; 
        String addressText = [street, locality].where((e) => e.isNotEmpty).join(', ');
        if (addressText.isEmpty) addressText = 'Unknown Street';
        if (mounted) setState(() => _currentAddress = addressText);
      }
    } catch (e) { debugPrint('[DEBUG] Geocoding Error: $e'); }
  }

  // ==========================================
  // Firebase data sync logic (global)
  // ==========================================
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          if (doc.data()!.containsKey('emergency_contacts')) _contactsList = List<String>.from(doc.data()!['emergency_contacts']);
          if (doc.data()!.containsKey('custom_manuals')) {
            _customManuals = List<Map<String, dynamic>>.from(doc.data()!['custom_manuals']).map((e) => {"title": e["title"].toString(), "content": e["content"].toString()}).toList();
          }
          if (doc.data()!.containsKey('gear_list')) _gearList = List<Map<String, dynamic>>.from(doc.data()!['gear_list']);
          if (doc.data()!.containsKey('runner_notes')) _notesController.text = doc.data()!['runner_notes'].toString();
        });
      }
    }
  }

  Future<void> _addContact() async {
    final phone = _contactController.text.trim();
    if (phone.isEmpty || _contactsList.contains(phone)) return;
    setState(() { _isSavingContact = true; _contactsList.add(phone); });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await _firestore.collection('users').doc(user.uid).set({'emergency_contacts': _contactsList}, SetOptions(merge: true));
      _contactController.clear(); FocusScope.of(context).unfocus(); 
    } finally { setState(() => _isSavingContact = false); }
  }

  Future<void> _removeContact(String phone) async {
    setState(() => _contactsList.remove(phone));
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await _firestore.collection('users').doc(user.uid).set({'emergency_contacts': _contactsList}, SetOptions(merge: true));
    } catch (e) { debugPrint('[DEBUG] Error removing contact: $e'); }
  }

  Future<void> _saveCustomManualsToFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await _firestore.collection('users').doc(user.uid).set({'custom_manuals': _customManuals}, SetOptions(merge: true));
    } catch (e) { debugPrint('[DEBUG] Error saving manual: $e'); }
  }

  Future<void> _syncGearListToFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) await _firestore.collection('users').doc(user.uid).set({'gear_list': _gearList}, SetOptions(merge: true));
    } catch (e) { debugPrint('[DEBUG] Error syncing gear: $e'); }
  }

  Future<void> _saveNotesToFirebase() async {
    setState(() => _isSavingNotes = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({'runner_notes': _notesController.text}, SetOptions(merge: true));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notes saved to cloud!'), backgroundColor: Colors.green));
      }
      FocusScope.of(context).unfocus(); 
    } catch (e) { debugPrint('[DEBUG] Error saving notes: $e'); } 
    finally { setState(() => _isSavingNotes = false); }
  }

  // ==========================================
  // AI intelligence core
  // ==========================================
  Future<void> _assessPreRunRisk() async {
    final userInput = _promptController.text;
    if (userInput.trim().isEmpty) return; 
    final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    setState(() { _isLoadingPreRunAI = true; _preRunAiResponse = ''; });
    try {
      final String contextStr = "Address: $_currentAddress. User describes environment as: '$userInput'.";
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final prompt = 'You are a running safety expert. Based on $contextStr, infer potential weather/safety risks. Provide exactly 3 short actionable safety warnings for this run. Keep it very concise.';
      final response = await model.generateContent([Content.text(prompt)]);
      setState(() => _preRunAiResponse = response.text ?? 'No response.');
    } catch (e) {
      debugPrint('[DEBUG] Gemini API Request Failed: $e');
      setState(() => _preRunAiResponse = "💡 Cannot connect with Gemini.\n\nShowing Safety Guidelines:\n• Low Visibility: Wear high-visibility reflective gear.\n• Slippery Surfaces: Shorten your stride to prevent falls.\n• Personal Security: Stay in well-lit areas and share live location."); 
    } finally { setState(() => _isLoadingPreRunAI = false); }
  }

  Future<void> _analyzePostRun() async {
    final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    setState(() { _isLoadingPostRunAI = true; _postRunAiResponse = ''; });
    try {
      double km = _distanceMeters / 1000; int mins = _secondsElapsed ~/ 60;
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final prompt = 'The runner just completed a run. Distance: ${km.toStringAsFixed(3)} km. Time: $mins minutes. Provide 2 short, encouraging recovery tips and 1 safety tip for their next run. Keep it very concise.';
      final response = await model.generateContent([Content.text(prompt)]);
      setState(() => _postRunAiResponse = response.text ?? 'Great run!');
    } catch (e) {
      debugPrint('[DEBUG] Gemini API Request Failed: $e');
      setState(() => _postRunAiResponse = "💡 Cannot connect with Gemini.\n\nShowing Recovery Guidelines:\n• Hydrate immediately to replenish lost fluids.\n• Stretch your legs to prevent muscle cramps.\n• Rest well before your next session.");
    } finally { setState(() => _isLoadingPostRunAI = false); }
  }

  // ==========================================
  // Hardware tracker engine (ultra-sensitive)
  // ==========================================
  void _startRun() async {
    _runTimer?.cancel(); 
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    Position startPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _updateAddress(startPos);
    if (!mounted) return;
    
    setState(() { _currentRunState = RunState.running; _secondsElapsed = 0; _distanceMeters = 0.0; _lastPosition = startPos; });
    
    _runTimer?.cancel(); 
    _runTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_currentRunState != RunState.running) { timer.cancel(); return; }
      setState(() => _secondsElapsed++);
      
      // Quick refresh rate (every 2 seconds)
      if (_secondsElapsed % 2 == 0) {
        try {
          Position currentPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          if (_lastPosition != null && _currentRunState == RunState.running) {
            double dist = Geolocator.distanceBetween(_lastPosition!.latitude, _lastPosition!.longitude, currentPos.latitude, currentPos.longitude);
            
            // Ultra-sensitive tracking: Updates for movement > 0.5 meters
            if (dist > 0.5) { 
              setState(() { _distanceMeters += dist; _lastPosition = currentPos; }); 
              _updateAddress(currentPos); 
              debugPrint('[DEBUG] Distance: ${(_distanceMeters/1000).toStringAsFixed(3)} km');
            }
          }
        } catch (e) { debugPrint('[DEBUG] Running GPS Error: $e'); }
      }
    });
  }

  void _stopRun() {
    _runTimer?.cancel(); _runTimer = null; 
    setState(() { _currentRunState = RunState.postRun; }); 
    _analyzePostRun();
    _saveRunRecord(); // Save record unconditionally
  }

  void _resetRun() {
    setState(() { _currentRunState = RunState.preRun; _secondsElapsed = 0; _distanceMeters = 0.0; _preRunAiResponse = ''; _postRunAiResponse = ''; _promptController.clear(); });
  }

  // ==========================================
  // Universal SOS broadcaster
  // ==========================================
  Future<void> _triggerSOS() async {
    setState(() => _isSendingSOS = true);
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final user = FirebaseAuth.instance.currentUser;
      await user?.reload(); 
      final updatedUser = FirebaseAuth.instance.currentUser;
      
      String userName = "A runner";
      if (updatedUser != null) {
        if (updatedUser.displayName != null && updatedUser.displayName!.isNotEmpty) userName = updatedUser.displayName!;
        else if (updatedUser.email != null) userName = updatedUser.email!.split('@')[0];
      }

      await _firestore.collection('sos_logs').add({
        'user_name': userName, 'user_email': updatedUser?.email ?? 'Unknown', 
        'timestamp': FieldValue.serverTimestamp(), 'location': GeoPoint(pos.latitude, pos.longitude), 
        'address_context': _currentAddress, 'status': 'EMERGENCY_ACTIVE',
      });

      debugPrint('[DEBUG] SOS logged to Firestore');

      String targetPhones = '999'; 
      if (_contactsList.isNotEmpty) targetPhones = _contactsList.join(Platform.isIOS ? ',' : ';');
      final String mapsUrl = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
      final Uri smsUri = Uri.parse('sms:$targetPhones?body=${Uri.encodeComponent("EMERGENCY! $userName needs help near $_currentAddress. Live GPS: $mapsUrl")}');
      
      if (await canLaunchUrl(smsUri)) await launchUrl(smsUri);
    } finally { setState(() => _isSendingSOS = false); }
  }

  // ==========================================
  // Helper methods
  // ==========================================
  String _formatTime(int seconds) {
    int m = seconds ~/ 60; int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _calculatePace() {
    if (_distanceMeters < 100) return '--:--'; 
    double kmRan = _distanceMeters / 1000;
    double minPerKm = _secondsElapsed / 60 / kmRan;
    int mins = minPerKm.toInt();
    int secs = ((minPerKm - mins) * 60).toInt();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  // ==========================================
  // Premium UI components
  // ==========================================
  Widget _buildIOSCard({required Widget child}) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))]),
      child: child,
    );
  }

  Widget _buildLocationCapsule() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.my_location_rounded, color: Color(0xFFFF3B30), size: 20), 
            const SizedBox(width: 10),
            Expanded(child: Text(_currentAddress, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  // Simplified run record card (prevent overflow)
  Widget _buildRunRecordCard(RunRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          // Left: distance and time
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.distance.toStringAsFixed(2)} km',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87),
                ),
                Text(
                  _formatTime(record.duration),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          // Middle: date
          Expanded(
            flex: 2,
            child: Text(
              record.date.toString().split(' ')[0],
              style: const TextStyle(fontSize: 11, color: Colors.black45),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Delete button
          SizedBox(
            width: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
              onPressed: () => _deleteRunRecord(record.id),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------
  // TAB 1: Preparation (Gear & Notes)
  // ------------------------------------------
  Widget _buildPrepTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Pre-Run Checklist', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.black87)),
          const SizedBox(height: 8),
          const Text('Gear up before you stride out.', style: TextStyle(fontSize: 15, color: Colors.black54)),
          const SizedBox(height: 24),

          _buildIOSCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [Icon(Icons.inventory_2_rounded, color: Colors.deepOrangeAccent, size: 22), SizedBox(width: 8), Text('Essential Gear', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87))]),
                const SizedBox(height: 12),
                
                ..._gearList.asMap().entries.map((entry) {
                  int idx = entry.key; Map<String, dynamic> item = entry.value;
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero, activeColor: const Color(0xFFFF3B30), controlAffinity: ListTileControlAffinity.leading,
                    title: Text(item['item'], style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: item['isChecked'] ? Colors.black38 : Colors.black87, decoration: item['isChecked'] ? TextDecoration.lineThrough : null)),
                    value: item['isChecked'],
                    onChanged: (bool? val) { setState(() => _gearList[idx]['isChecked'] = val ?? false); _syncGearListToFirebase(); },
                    secondary: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22), onPressed: () { setState(() => _gearList.removeAt(idx)); _syncGearListToFirebase(); }),
                  );
                }),
                
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _newGearController, decoration: InputDecoration(hintText: 'Add custom item...', filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)))),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () {
                        final text = _newGearController.text.trim();
                        if (text.isEmpty) return; 
                        bool exists = _gearList.any((e) => e['item'].toString().toLowerCase() == text.toLowerCase());
                        if (exists) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item already exists!'), backgroundColor: Colors.orange)); return; }
                        setState(() { _gearList.add({"item": text, "isChecked": false}); _newGearController.clear(); });
                        _syncGearListToFirebase();
                      },
                      child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.add, color: Colors.white, size: 22)),
                    )
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildIOSCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(children: [Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 24), SizedBox(width: 8), Text('Runner\'s Scratchpad', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87))]),
                const SizedBox(height: 16),
                TextField(controller: _notesController, maxLines: 5, decoration: InputDecoration(hintText: 'Jot down locker codes, route changes, or specific medical conditions here...', hintStyle: const TextStyle(height: 1.5), filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _isSavingNotes ? null : _saveNotesToFirebase, icon: _isSavingNotes ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.cloud_upload_rounded, size: 18), label: const Text('Save Notes to Cloud', style: TextStyle(fontWeight: FontWeight.w700)), style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0))
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ------------------------------------------
  // TAB 2: Run Tracker (AI & SOS & Records) - Fixed RenderFlex overflow
  // ------------------------------------------
  Widget _buildRunTrackerTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), 
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Column(
        children: [
          _buildLocationCapsule(), 

          if (_currentRunState == RunState.preRun) ...[
            _buildIOSCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [Icon(Icons.psychology_rounded, color: Colors.blueAccent, size: 22), SizedBox(width: 8), Text('Pre-Run AI Scanner', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))]),
                  const SizedBox(height: 16),
                  TextField(controller: _promptController, decoration: InputDecoration(hintText: 'Environment (e.g. raining, dark)', filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)), maxLines: 2),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _isLoadingPreRunAI ? null : _assessPreRunRisk, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isLoadingPreRunAI ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Scan Environment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  if (_preRunAiResponse.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.2))), child: Text(_preRunAiResponse, style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5, fontWeight: FontWeight.w500))),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 30),
            GestureDetector(
              onTap: _startRun,
              child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]), child: const Center(child: Text('START RUN', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)))),
            ),
            // Only show Run History card if records exist to avoid blank space
            if (_runRecords.isNotEmpty) ...[
              const SizedBox(height: 30),
              _buildIOSCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.history_rounded, color: Colors.purple, size: 22),
                            SizedBox(width: 8),
                            Text('Run History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.black87)),
                          ],
                        ),
                        TextButton(
                          onPressed: _loadRunRecords,
                          child: const Text('Refresh', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Only show latest 3 records
                    SingleChildScrollView(
                      child: Column(
                        children: [
                          ..._runRecords.take(3).map((record) => _buildRunRecordCard(record)),
                          if (_runRecords.length > 3)
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    builder: (context) => Container(
                                      height: MediaQuery.of(context).size.height * 0.8,
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('All Run Records', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 16),
                                          Expanded(
                                            child: ListView.builder(
                                              itemCount: _runRecords.length,
                                              itemBuilder: (context, index) => _buildRunRecordCard(_runRecords[index]),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('View All Records', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 30),
            // Fix: SOS Broadcast List overflow issue
            _buildIOSCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SOS Broadcast List', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _contactController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Add phone...',
                            filled: true,
                            fillColor: const Color(0xFFF2F2F7),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _isSavingContact ? null : _addContact,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 24),
                        ),
                      )
                    ],
                  ),
                  if (_contactsList.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    // Key fix: Use SingleChildScrollView + Row instead of Wrap
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _contactsList
                            .map(
                              (phone) => Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Chip(
                                  label: Text(
                                    phone,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  backgroundColor: const Color(0xFFE5E5EA),
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  deleteIcon: const Icon(
                                    Icons.cancel,
                                    size: 18,
                                    color: Colors.black45,
                                  ),
                                  onDeleted: () => _removeContact(phone),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ] else if (_currentRunState == RunState.running) ...[
            _buildIOSCard(
              child: Column(
                children: [
                  const Text('ACTIVE RUN', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 20),
                  Text(
                    _formatTime(_secondsElapsed),
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Text('TIME', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            (_distanceMeters / 1000).toStringAsFixed(3),
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
                          ),
                          const Text('KM', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            _calculatePace(),
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
                          ),
                          const Text('MIN/KM', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_currentAddress',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _stopRun,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    'FINISH RUN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ),
          ] else if (_currentRunState == RunState.postRun) ...[
            _buildIOSCard(
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 60), const SizedBox(height: 10),
                  const Text('Run Completed!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)), const Divider(height: 40),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [Column(children: [Text((_distanceMeters / 1000).toStringAsFixed(3), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), const Text('KM', style: TextStyle(color: Colors.black45))]), Column(children: [Text(_formatTime(_secondsElapsed), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), const Text('TIME', style: TextStyle(color: Colors.black45))])]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildIOSCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [Icon(Icons.auto_awesome, color: Colors.deepPurple), SizedBox(width: 8), Text('AI Post-Run Analysis', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))]),
                  const SizedBox(height: 16),
                  if (_isLoadingPostRunAI) const Center(child: CircularProgressIndicator()) else Text(_postRunAiResponse, style: const TextStyle(fontSize: 15, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(onPressed: _resetRun, style: ElevatedButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Back to Home', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
          ],

          const SizedBox(height: 40),
          GestureDetector(
            onTap: _isSendingSOS ? null : _triggerSOS,
            child: Container(height: 180, width: 180, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF3B30), Color(0xFFD32F2F)], begin: Alignment.topLeft, end: Alignment.bottomRight), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFFF3B30).withOpacity(0.4), blurRadius: 30, spreadRadius: 8, offset: const Offset(0, 10))]), child: Center(child: _isSendingSOS ? const CircularProgressIndicator(color: Colors.white) : const Text('SOS', style: TextStyle(color: Colors.white, fontSize: 54, fontWeight: FontWeight.w800, letterSpacing: 2)))),
          ),
          const SizedBox(height: 20),
          const Text('Press to broadcast GPS to your list', style: TextStyle(color: Colors.black45, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 80), 
        ],
      ),
    );
  }

  // ------------------------------------------
  // TAB 3: First Aid Knowledge 
  // ------------------------------------------
  Future<void> _showAddCustomManualDialog() async {
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController contentCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Custom Manual', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: InputDecoration(hintText: 'Condition (e.g. Asthma)', filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
              const SizedBox(height: 12),
              TextField(controller: contentCtrl, maxLines: 4, decoration: InputDecoration(hintText: 'Steps to take...', filled: true, fillColor: const Color(0xFFF2F2F7), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0), onPressed: () { if (titleCtrl.text.trim().isNotEmpty && contentCtrl.text.trim().isNotEmpty) { setState(() { _customManuals.add({"title": titleCtrl.text.trim(), "content": contentCtrl.text.trim()}); }); _saveCustomManualsToFirebase(); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom manual added!'), backgroundColor: Colors.green)); } }, child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700))),
          ],
        );
      }
    );
  }

  Widget _buildFirstAidTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Emergency Manual', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black87)), SizedBox(height: 4)]),
              IconButton(onPressed: _showAddCustomManualDialog, icon: const Icon(Icons.add_circle_rounded, color: Colors.blueAccent, size: 36), tooltip: 'Add Personal Plan')
            ],
          ),
          const SizedBox(height: 24),

          if (_customManuals.isNotEmpty) ...[
            const Text('Personal Emergency Manual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.blueAccent, letterSpacing: 0.5)), const SizedBox(height: 12),
            ..._customManuals.asMap().entries.map((entry) { int idx = entry.key; Map<String, String> manual = entry.value; return Padding(padding: const EdgeInsets.only(bottom: 16.0), child: _buildFirstAidCard(title: manual['title'] ?? 'Custom Plan', icon: Icons.favorite_rounded, color: Colors.blueAccent, content: manual['content'] ?? '', onDelete: () { setState(() => _customManuals.removeAt(idx)); _saveCustomManualsToFirebase(); })); }),
            const Divider(height: 40),
          ],

          const Text('General First Aid', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black45, letterSpacing: 0.5)), const SizedBox(height: 12),
          _buildFirstAidCard(title: 'Heat Stroke / Exhaustion', icon: Icons.wb_sunny_rounded, color: Colors.orange, content: '1. Move the person to a cool, shaded area.\n2. Loosen tight clothing.\n3. Apply cool, wet cloths to the skin (neck, armpits).\n4. If conscious, give small sips of water.\n5. Call emergency if they lose consciousness.'), const SizedBox(height: 16),
          _buildFirstAidCard(title: 'Sprains & Strains (R.I.C.E)', icon: Icons.accessible_forward_rounded, color: Colors.teal, content: '• REST: Stop running immediately.\n• ICE: Apply ice packs for 15-20 mins.\n• COMPRESSION: Wrap with a bandage firmly.\n• ELEVATION: Keep the injured limb raised above heart level.'), const SizedBox(height: 16),
          _buildFirstAidCard(title: 'Severe Bleeding', icon: Icons.bloodtype_rounded, color: Colors.redAccent, content: '1. Apply direct pressure to the wound using a clean cloth or shirt.\n2. Maintain pressure continuously.\n3. Elevate the bleeding area if possible.\n4. Do not remove the cloth if soaked, add another layer on top.'), const SizedBox(height: 16),
          _buildFirstAidCard(title: 'Unconscious / CPR', icon: Icons.monitor_heart_rounded, color: Colors.red.shade800, content: '1. Check responsiveness (tap and shout).\n2. If no breathing, call 999 immediately.\n3. Start CPR: Place hands in center of chest.\n4. Push hard and fast (100-120 compressions/min, 2 inches deep).'),
          const SizedBox(height: 80), 
        ],
      ),
    );
  }

  Widget _buildFirstAidCard({required String title, required IconData icon, required Color color, required String content, VoidCallback? onDelete}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))]),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent), 
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          children: [
            Container(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20), alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(content, style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.6)),
                  if (onDelete != null) ...[const SizedBox(height: 16), Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20), label: const Text('Remove', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600))))]
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Main Scaffold with bottom navigation
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [_buildPrepTab(), _buildRunTrackerTab(), _buildFirstAidTab()];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeStride', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5)), 
        centerTitle: true, backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0, 
        actions: [IconButton(icon: const Icon(Icons.call_rounded, color: Color(0xFFFF3B30)), tooltip: 'Call 999', onPressed: _directCallEmergency), IconButton(icon: const Icon(Icons.manage_accounts_rounded, color: Colors.black87), onPressed: _showEditNameDialog), IconButton(icon: const Icon(Icons.exit_to_app_rounded, color: Colors.black54), onPressed: () => FirebaseAuth.instance.signOut())],
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]),
        child: BottomNavigationBar(
          backgroundColor: Colors.white, elevation: 0, currentIndex: _selectedIndex, onTap: (index) => setState(() => _selectedIndex = index), selectedItemColor: const Color(0xFFFF3B30), unselectedItemColor: Colors.black38, selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12), unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          items: const [BottomNavigationBarItem(icon: Icon(Icons.backpack_rounded), label: 'Prep'), BottomNavigationBarItem(icon: Icon(Icons.directions_run_rounded), label: 'Tracker'), BottomNavigationBarItem(icon: Icon(Icons.medical_services_rounded), label: 'First Aid')],
        ),
      ),
    );
  }
}