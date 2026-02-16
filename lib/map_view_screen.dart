import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'queue_provider.dart';
import 'location_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class MapViewScreen extends StatefulWidget {
  final String roomId;

  const MapViewScreen({super.key, required this.roomId});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QueueProvider>();

    final room = provider.rooms.isNotEmpty
        ? provider.rooms.firstWhere(
          (r) => r['id'] == widget.roomId,
      orElse: () => provider.rooms.first,
    )
        : null;

    final roomLat = room?['latitude'] as double?;
    final roomLng = room?['longitude'] as double?;
    final roomName = room?['name'] ?? 'Room';

    return Scaffold(
      appBar: AppBar(
        title: Text('Clients Map - $roomName'),
        backgroundColor: Colors.purple[600],
      ),
      body: Column(
        children: [
          // Map Container with Google Maps Link
          Container(
            height: 300,
            color: Colors.grey[300],
            child: Stack(
              children: [
                // Static map image or placeholder
                Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.map,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        const Text('Room Location Map'),
                        const SizedBox(height: 8),
                        if (roomLat != null && roomLng != null)
                          ElevatedButton.icon(
                            onPressed: () => _openMap(roomLat, roomLng),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open in Google Maps'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (roomLat != null && roomLng != null)
                  Positioned(
                    left: 50,
                    top: 50,
                    child: Column(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 40,
                          color: Colors.red[600],
                        ),
                        Text(
                          roomName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: provider.clients.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text('No clients to display'),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.clients.length,
              itemBuilder: (context, index) {
                final client = provider.clients[index];

                if (client.lat == null || client.lng == null) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(client.name ?? 'Unknown'),
                      subtitle: const Text('📍 Location not available'),
                    ),
                  );
                }

                final walkingDist = _calculateDistance(
                  client.lat!,
                  client.lng!,
                  roomLat ?? 0,
                  roomLng ?? 0,
                );

                // Driving distance is roughly 1.3x walking distance
                final drivingDist = walkingDist * 1.3;

                // Calculate arrival times
                final walkingTime = provider.getArrivalTime(
                  client.lat,
                  client.lng,
                  walkingTime: true,
                );
                final drivingTime = provider.getArrivalTime(
                  client.lat,
                  client.lng,
                  walkingTime: false,
                );

                final walkingTimeStr = provider.formatArrivalTime(walkingTime);
                final drivingTimeStr = provider.formatArrivalTime(drivingTime);

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 1,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      client.name ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          '📍 ${client.lat!.toStringAsFixed(4)}, ${client.lng!.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '🚶 Walk: ${walkingDist.toStringAsFixed(2)} km',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '🚗 Drive: ${drivingDist.toStringAsFixed(2)} km',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.directions),
                      onPressed: () => _openDirections(
                        client.lat!,
                        client.lng!,
                        roomName,
                      ),
                      tooltip: 'Get directions',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _calculateDistance(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    return calculateDistance(lat1, lon1, lat2, lon2);
  }

  void _openMap(double lat, double lng) async {
    final url =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  void _openDirections(double lat, double lng, String destination) async {
    final url =
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&dir_action=navigate';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}