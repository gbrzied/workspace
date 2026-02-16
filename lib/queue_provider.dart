import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'models/client.dart';
import 'package:uuid/uuid.dart';
import 'local_queue_service.dart';
import 'local_rooms_service.dart';
import 'settings_service.dart';
import 'geolocation_service.dart';
import 'connectivity_service.dart';
import 'location_utils.dart';

class QueueProvider extends ChangeNotifier {
  final List<Client> _clients = [];
  List<Client> get clients => _clients;

  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> get rooms => _rooms;

  String? _currentRoomId;
  String? get currentRoomId => _currentRoomId;

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalQueueService _localDb = LocalQueueService();
  final LocalRoomsService _localRoomsDb = LocalRoomsService();
  final SettingsService _settingsDb = SettingsService();
  final GeolocationService _geoService;
  final ConnectivityService? _connectivityService;

  bool _isDemoMode = false;
  bool get isDemoMode => _isDemoMode;

  RealtimeChannel? _subscription;

  // Average walking speed: 1.4 m/s (5 km/h)
  static const double _avgWalkingSpeed = 1.4;
  // Average driving speed: 12 m/s (43 km/h for urban areas)
  static const double _avgDrivingSpeed = 12.0;

  QueueProvider({
    GeolocationService? geoService,
    ConnectivityService? connectivityService,
  })  : _geoService = geoService ?? GeolocationService(),
        _connectivityService = connectivityService {
    initialize();
  }

  Future<void> initialize() async {
    // Check demo mode
    _isDemoMode = await _settingsDb.isDemoMode();
    print('📱 Demo mode: $_isDemoMode');
    
    await fetchWaitingRooms();
    await _loadQueue();
    _setupConnectivityListener();
    print('✅ QueueProvider initialized');
  }

  Future<void> fetchWaitingRooms() async {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔍 FETCHING WAITING ROOMS');
    print('📱 Demo mode: $_isDemoMode');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Check current demo mode status
    _isDemoMode = await _settingsDb.isDemoMode();
    
    // If demo mode, try local rooms first
    if (_isDemoMode) {
      try {
        final localRooms = await _localRoomsDb.getRooms();
        if (localRooms.isNotEmpty) {
          _rooms = localRooms;
          print('✅ Loaded ${_rooms.length} rooms from local storage (Demo Mode)');
          notifyListeners();
          return;
        } else {
          // Seed demo rooms if none exist
          await _localRoomsDb.seedDemoRooms();
          final seededRooms = await _localRoomsDb.getRooms();
          _rooms = seededRooms;
          print('✅ Seeded and loaded ${_rooms.length} demo rooms');
          notifyListeners();
          return;
        }
      } catch (e) {
        print('⚠️ Error with local rooms, falling back to Supabase: $e');
      }
    }

    // Normal mode - fetch from Supabase
    try {
      print('📡 Making Supabase query...');
      final response = await _supabase.from('waiting_rooms').select();

      print('✅ Query succeeded');
      print('📊 Response type: ${response.runtimeType}');
      print('📊 Response length: ${response is List ? (response as List).length : 'N/A'}');

      if (response is List) {
        print('✅ Response IS a List');

        if (response.isEmpty) {
          print('⚠️ List is EMPTY - no rooms in database');
          _rooms = [];
        } else {
          print('✅ List has ${response.length} items');

          final parsedRooms = <Map<String, dynamic>>[];

          for (int i = 0; i < response.length; i++) {
            final item = response[i];

            try {
              if (item is Map) {
                final room = Map<String, dynamic>.from(item);
                parsedRooms.add(room);
                print('  [Item $i] ✅ Parsed: ${room['name']}');
              }
            } catch (e) {
              print('  [Item $i] ❌ Parse error: $e');
            }
          }

          _rooms = parsedRooms;
          print('✅ Successfully parsed ${_rooms.length} rooms');
        }
      } else {
        print('❌ Response is NOT a List');
        _rooms = [];
      }

      print('📋 Final _rooms count: ${_rooms.length}');
      notifyListeners();

    } catch (e) {
      print('❌ Error fetching rooms: $e');
      // Try fallback to local rooms in demo mode
      if (_isDemoMode) {
        try {
          final localRooms = await _localRoomsDb.getRooms();
          if (localRooms.isNotEmpty) {
            _rooms = localRooms;
            print('⚠️ Using local rooms as fallback');
          }
        } catch (e) {
          print('❌ Fallback also failed: $e');
        }
      }
      _rooms = [];
      notifyListeners();
    }

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  String? _findNearestRoom(double? lat, double? lng) {
    if (lat == null || lng == null || _rooms.isEmpty) {
      print('⚠️ Cannot find nearest room: lat=$lat, lng=$lng, rooms=${_rooms.length}');
      return null;
    }

    double minDistance = double.infinity;
    String? nearestRoomId;

    for (var room in _rooms) {
      final roomLat = room['latitude'] as double;
      final roomLng = room['longitude'] as double;
      final distance = calculateDistance(lat, lng, roomLat, roomLng);

      if (distance < minDistance) {
        minDistance = distance;
        nearestRoomId = room['id'] as String?;
      }
    }

    print('📍 Nearest room: $nearestRoomId (${minDistance.toStringAsFixed(2)} km away)');
    return nearestRoomId;
  }

  Future<void> _loadQueue() async {
    final localClients = await _localDb.getClients();
    _clients
      ..clear()
      ..addAll(localClients.map((map) => Client.fromMap(map)));

    // ✅ Sort by creation time (FIFO) - oldest first
    _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    notifyListeners();
    print('📦 Loaded ${_clients.length} clients from local DB (FIFO sorted)');

    // ✅ NEW: Also fetch all clients from Supabase (all rooms) - skip in demo mode
    if (!_isDemoMode) {
      await _fetchAllClientsFromSupabase();
    }

    await _syncLocalToRemote();
    if (_currentRoomId != null) {
      await _fetchInitialClients(_currentRoomId!);
    }
  }

  // ✅ NEW: Fetch all clients from all rooms in Supabase
  Future<void> _fetchAllClientsFromSupabase() async {
    // Skip in demo mode
    if (_isDemoMode) {
      print('⚠️ Skipping Supabase fetch in demo mode');
      return;
    }
    
    try {
      final data = await _supabase
          .from('clients')
          .select()
          .order('created_at');

      if (data is List && data.isNotEmpty) {
        _clients
          ..clear()
          ..addAll((data as List).map((e) => Client.fromMap(e)));

        // ✅ Keep FIFO order
        _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        notifyListeners();
        print('✅ Fetched ${_clients.length} clients from Supabase (all rooms)');
      }
    } catch (e) {
      print('⚠️ Could not fetch clients from Supabase: $e');
    }
  }

  Future<void> _syncLocalToRemote() async {
    // Skip sync in demo mode
    if (_isDemoMode) {
      print('⚠️ Demo mode - skipping remote sync');
      return;
    }
    
    if (!(_connectivityService?.isOnline ?? true)) {
      print('⚠️ Offline - skipping sync');
      return;
    }

    final unsynced = await _localDb.getUnsyncedClients();
    print('🔄 Syncing ${unsynced.length} unsynced clients');

    for (var client in unsynced) {
      try {
        final remoteClient = Map<String, dynamic>.from(client)
          ..remove('is_synced')
          ..['is_synced'] = true;

        await _supabase.from('clients').upsert(remoteClient, onConflict: 'id');
        await _localDb.markClientAsSynced(client['id'] as String);
        print('✅ Synced client: ${client['name']}');
      } catch (e) {
        print('❌ Sync failed for ${client['id']}: $e');
      }
    }
  }

  Future<void> _fetchInitialClients(String roomId) async {
    // In demo mode, just use local clients
    if (_isDemoMode) {
      print('⚠️ Demo mode - using local clients only');
      return;
    }
    
    try {
      final data = await _supabase
          .from('clients')
          .select()
          .eq('waiting_room_id', roomId)
          .order('created_at'); // ✅ FIFO order

      _clients
        ..clear()
        ..addAll((data as List).map((e) => Client.fromMap(e)));
      notifyListeners();
      print('✅ Fetched ${_clients.length} clients for room $roomId (FIFO)');
    } catch (e) {
      print('❌ Error fetching clients: $e');
    }
  }

  void subscribeToRoom(String roomId) {
    _currentRoomId = roomId;

    // Skip realtime subscription in demo mode
    if (_isDemoMode) {
      print('⚠️ Demo mode - skipping realtime subscription');
      _fetchInitialClients(roomId);
      return;
    }

    if (_subscription != null) {
      _supabase.removeChannel(_subscription!);
      print('🔌 Unsubscribed from previous room');
    }

    _subscription = _supabase
        .channel('public:clients:waiting_room_id=eq.$roomId')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'clients',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'waiting_room_id',
        value: roomId,
      ),
      callback: (payload) async {
        try {
          final newClient = Client.fromMap(payload.newRecord);
          final exists = _clients.any((c) => c.id == newClient.id);

          if (!exists) {
            final localClient = Map<String, dynamic>.from(payload.newRecord)
              ..['is_synced'] = 1;
            await _localDb.insertClientLocally(localClient);
            _clients.add(newClient);
            // ✅ Keep FIFO order - sort by created_at
            _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            notifyListeners();
            print('➕ Client inserted: ${newClient.name}');
          }
        } catch (e) {
          print('❌ Error handling insert: $e');
        }
      },
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'clients',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'waiting_room_id',
        value: roomId,
      ),
      callback: (payload) async {
        try {
          final deletedId = payload.oldRecord['id'] as String;
          _clients.removeWhere((c) => c.id == deletedId);
          notifyListeners();
          print('➖ Client deleted: $deletedId');
        } catch (e) {
          print('❌ Error handling delete: $e');
        }
      },
    )
        .subscribe();

    print('🔌 Subscribed to room: $roomId');
    _fetchInitialClients(roomId);
  }

  Future<void> addClient(String name) async {
    if (name.trim().isEmpty) {
      print('⚠️ Cannot add empty client name');
      return;
    }

    if (_rooms.isEmpty) {
      print('❌ No waiting rooms available');
      return;
    }

    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('➕ ADDING CLIENT: $name');
      print('📱 Demo mode: $_isDemoMode');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      Position? position;
      double? lat;
      double? lng;

      // Only get location in non-demo mode (or if location is available)
      if (!_isDemoMode) {
        print('📍 Requesting geolocation...');
        position = await _geoService.getCurrentPosition();

        if (position != null) {
          lat = position.latitude;
          lng = position.longitude;
          print('✅ Got location: $lat, $lng');
        } else {
          print('⚠️ Location unavailable - will use null');
        }
      } else {
        print('⚠️ Demo mode - skipping geolocation');
      }

      String? nearestRoomId;
      double minDistance = double.infinity;

      if (lat != null && lng != null && _rooms.isNotEmpty) {
        print('🗺️ Calculating nearest room...');
        for (var room in _rooms) {
          final roomLat = room['latitude'] as double;
          final roomLng = room['longitude'] as double;
          final distance = calculateDistance(lat, lng, roomLat, roomLng);

          if (distance < minDistance) {
            minDistance = distance;
            nearestRoomId = room['id'] as String?;
          }
        }
        print('📍 Nearest room: $nearestRoomId (${minDistance.toStringAsFixed(2)} km away)');
      } else {
        nearestRoomId = _rooms.first['id'] as String?;
        print('⚠️ Using first room as fallback: $nearestRoomId');
      }

      if (nearestRoomId == null) {
        print('❌ No valid room found');
        return;
      }

      final newClient = {
        'id': const Uuid().v4(),
        'name': name.trim(),
        'lat': lat,
        'lng': lng,
        'waiting_room_id': nearestRoomId,
        'created_at': DateTime.now().toIso8601String(),
        'is_synced': _isDemoMode ? 1 : 0, // Mark as synced in demo mode
      };

      print('📋 Client data:');
      print('   Name: ${newClient['name']}');
      print('   Location: $lat, $lng');
      print('   Room: $nearestRoomId');

      await _localDb.insertClientLocally(newClient);
      _clients.add(Client.fromMap(newClient));
      // ✅ Keep FIFO order - sort by created_at
      _clients.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();
      print('✅ Client added locally');

      // Only sync to remote in non-demo mode
      if (!_isDemoMode) {
        unawaited(_syncAddClientToRemote(newClient));
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    } catch (e) {
      print('❌ Failed to add client: $e');
      print('   Type: ${e.runtimeType}');
    }
  }

  Future<void> _syncAddClientToRemote(Map<String, dynamic> client) async {
    // Skip in demo mode
    if (_isDemoMode) {
      return;
    }
    
    if (!(_connectivityService?.isOnline ?? true)) {
      print('⚠️ Offline - client will sync later');
      return;
    }

    try {
      final remoteClient = Map<String, dynamic>.from(client)
        ..remove('is_synced')
        ..['is_synced'] = true;

      await _supabase.from('clients').upsert(remoteClient, onConflict: 'id');
      await _localDb.markClientAsSynced(client['id'] as String);
      print('✅ Client synced to remote: ${client['name']}');
    } catch (e) {
      print('❌ Failed to sync client to remote: $e');
    }
  }

  Future<void> removeClient(String id) async {
    try {
      await _localDb.markClientAsSynced(id);
      _clients.removeWhere((c) => c.id == id);
      notifyListeners();
      
      // Only sync to remote in non-demo mode
      if (!_isDemoMode) {
        unawaited(_syncRemoveClientFromRemote(id));
      }
      print('✅ Client removed locally: $id');
    } catch (e) {
      print('❌ Failed to remove client: $e');
    }
  }

  Future<void> _syncRemoveClientFromRemote(String id) async {
    // Skip in demo mode
    if (_isDemoMode) {
      return;
    }
    
    if (!(_connectivityService?.isOnline ?? true)) {
      print('⚠️ Offline - removal will sync later');
      return;
    }

    try {
      await _supabase.from('clients').delete().match({'id': id});
      print('✅ Client removal synced to remote: $id');
    } catch (e) {
      print('❌ Failed to sync client removal: $e');
    }
  }

  Future<void> nextClient() async {
    if (_clients.isEmpty) {
      print('⚠️ Queue is empty!');
      return;
    }

    final firstClient = _clients.first;
    await removeClient(firstClient.id);
    print('✅ Next client: ${firstClient.name}');
  }

  Duration getArrivalTime(double? clientLat, double? clientLng, {bool walkingTime = true}) {
    if (clientLat == null || clientLng == null || _rooms.isEmpty) {
      return Duration.zero;
    }

    final room = _rooms.first;
    final roomLat = room['latitude'] as double;
    final roomLng = room['longitude'] as double;

    // Calculate distance in km
    final distanceKm = calculateDistance(clientLat, clientLng, roomLat, roomLng);
    final distanceMeters = distanceKm * 1000;

    // Calculate time based on speed
    final speed = walkingTime ? _avgWalkingSpeed : _avgDrivingSpeed;
    final seconds = distanceMeters / speed;

    return Duration(seconds: seconds.toInt());
  }

  String formatArrivalTime(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m';
    } else {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '${hours}h ${minutes}m';
    }
  }

  void _setupConnectivityListener() {
    _connectivityService?.addListener(() {
      if (_connectivityService!.isOnline) {
        print('🔌 Internet reconnected — retrying sync');
        _syncLocalToRemote();
      }
    });
  }

  @override
  void dispose() {
    if (_subscription != null) {
      _supabase.removeChannel(_subscription!);
    }
    super.dispose();
  }
}
