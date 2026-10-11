import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MobileCompanionQrDialog extends StatefulWidget {
  final String rawUrl;

  const MobileCompanionQrDialog({super.key, required this.rawUrl});

  static Future<void> show(BuildContext context, String rawUrl) {
    return showDialog(
      context: context,
      builder: (context) => MobileCompanionQrDialog(rawUrl: rawUrl),
    );
  }

  @override
  State<MobileCompanionQrDialog> createState() => _MobileCompanionQrDialogState();
}

class _MobileCompanionQrDialogState extends State<MobileCompanionQrDialog> {
  List<String> _ipAddresses = [];
  String? _selectedIp;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchNetworkInterfaces();
  }

  Future<void> _fetchNetworkInterfaces() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _ipAddresses = ips;
        _selectedIp = ips.isNotEmpty ? ips.first : null;
        _isLoading = false;
      });
    }
  }

  String _formatMobileUrl() {
    final uri = Uri.tryParse(widget.rawUrl);
    if (uri == null) return widget.rawUrl;

    if (_selectedIp != null && (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      final portPart = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://$_selectedIp$portPart${uri.path}';
    }
    return widget.rawUrl;
  }

  @override
  Widget build(BuildContext context) {
    final mobileUrl = _formatMobileUrl();

    return AlertDialog(
      backgroundColor: const Color(0xFF14161B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.smartphone, size: 20, color: Colors.cyanAccent),
          ),
          const SizedBox(width: 12),
          Text(
            'Mobile Live Preview',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: _isLoading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withValues(alpha: 0.2),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: mobileUrl,
                      version: QrVersions.auto,
                      size: 190.0,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_ipAddresses.length > 1) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedIp,
                      dropdownColor: const Color(0xFF1C1E24),
                      style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Network Adapter',
                        labelStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: _ipAddresses.map((ip) {
                        return DropdownMenuItem(value: ip, child: Text(ip));
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedIp = val);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            mobileUrl,
                            style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white54),
                          tooltip: 'Copy URL',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: mobileUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied URL to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Scan with phone camera while connected to the same Wi-Fi network.',
                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: GoogleFonts.inter(color: Colors.white70)),
        ),
      ],
    );
  }
}
