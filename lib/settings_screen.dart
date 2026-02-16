import 'package:flutter/material.dart';
import 'settings_service.dart';
import 'local_rooms_service.dart';
import 'queue_provider.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  final LocalRoomsService _roomsService = LocalRoomsService();
  
  bool _isDemoMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final demoMode = await _settings.isDemoMode();
    setState(() {
      _isDemoMode = demoMode;
      _isLoading = false;
    });
  }

  Future<void> _toggleDemoMode(bool value) async {
    setState(() => _isDemoMode = value);
    await _settings.setDemoMode(value);
    
    if (value) {
      // Enable demo mode - seed demo rooms
      await _roomsService.seedDemoRooms();
      print('✅ Demo mode enabled - rooms seeded');
      
      // Refresh the queue provider to load demo rooms
      if (mounted) {
        final provider = context.read<QueueProvider>();
        await provider.fetchWaitingRooms();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo mode enabled - demo rooms loaded'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      // Disable demo mode - clear demo rooms
      await _roomsService.clearRooms();
      print('✅ Demo mode disabled - rooms cleared');
      
      // Refresh the queue provider
      if (mounted) {
        final provider = context.read<QueueProvider>();
        await provider.fetchWaitingRooms();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demo mode disabled - switched to Supabase'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),
                
                // Demo Mode Section
                _buildSectionHeader('Simulation'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Demo Mode'),
                        subtitle: const Text(
                          'Use local demo data instead of Supabase',
                        ),
                        value: _isDemoMode,
                        onChanged: _toggleDemoMode,
                        secondary: Icon(
                          _isDemoMode ? Icons.science : Icons.science_outlined,
                          color: _isDemoMode ? Colors.purple : Colors.grey,
                        ),
                      ),
                      if (_isDemoMode) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.info_outline, color: Colors.blue),
                          title: const Text('Demo Rooms'),
                          subtitle: const Text('5 pre-configured locations available'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showDemoRoomsInfo(),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.refresh, color: Colors.orange),
                          title: const Text('Reset Demo Data'),
                          subtitle: const Text('Re-seed demo rooms'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _resetDemoData(),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Data Source Section
                _buildSectionHeader('Data Source'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          _isDemoMode ? Icons.storage : Icons.cloud,
                          color: _isDemoMode ? Colors.purple : Colors.blue,
                        ),
                        title: Text(_isDemoMode ? 'Local Storage' : 'Supabase'),
                        subtitle: Text(
                          _isDemoMode 
                              ? 'Using demo rooms from local database'
                              : 'Connected to Supabase cloud',
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // About Section
                _buildSectionHeader('About'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Waiting Room Manager'),
                        subtitle: Text('Version 1.0.0'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.code),
                        title: const Text('Demo Mode'),
                        subtitle: const Text(
                          'Enable demo mode to test the app without Supabase connection',
                        ),
                        onTap: () => _showDemoModeHelp(),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  void _showDemoRoomsInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demo Rooms'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The following demo rooms are available:'),
            SizedBox(height: 12),
            Text('🏢 Downtown Clinic'),
            Text('✈️ Airport Terminal A'),
            Text('🛒 Shopping Mall Center'),
            Text('🎓 University Campus'),
            Text('🏥 Central Hospital'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _resetDemoData() async {
    await _roomsService.clearRooms();
    await _roomsService.seedDemoRooms();
    
    if (mounted) {
      final provider = context.read<QueueProvider>();
      await provider.fetchWaitingRooms();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo data reset successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showDemoModeHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demo Mode'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Demo Mode allows you to test the app without connecting to Supabase:',
            ),
            SizedBox(height: 12),
            Text('• Uses local SQLite database'),
            Text('• Pre-loaded with 5 demo rooms'),
            Text('• Clients are stored locally only'),
            Text('• Works completely offline'),
            SizedBox(height: 12),
            Text(
              'Perfect for testing, demos, and simulations!',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}
