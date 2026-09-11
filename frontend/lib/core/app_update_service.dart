import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersionName,
    required this.latestVersionCode,
    required this.minimumSupportedVersionCode,
    required this.forceUpdate,
    required this.title,
    required this.message,
    required this.downloadUrl,
    required this.installedVersionCode,
    this.releasedAt,
  });

  final String latestVersionName;
  final int latestVersionCode;
  final int minimumSupportedVersionCode;
  final bool forceUpdate;
  final String title;
  final String message;
  final String downloadUrl;
  final int installedVersionCode;
  final DateTime? releasedAt;

  bool get hasUpdate => latestVersionCode > installedVersionCode;
  bool get isRequired =>
      forceUpdate || installedVersionCode < minimumSupportedVersionCode;

  factory AppUpdateInfo.fromJson(
    Map<String, dynamic> json, {
    required int installedVersionCode,
  }) {
    int asInt(Object? value, [int fallback = 0]) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    final releasedValue = json['released_at']?.toString();
    return AppUpdateInfo(
      latestVersionName: json['latest_version_name']?.toString() ?? 'New',
      latestVersionCode: asInt(json['latest_version_code']),
      minimumSupportedVersionCode:
          asInt(json['minimum_supported_version_code']),
      forceUpdate: json['force_update'] == true,
      title: json['title']?.toString() ?? 'New CATWS Songs Update',
      message: json['message']?.toString() ?? 'A new version is available.',
      downloadUrl: json['download_url']?.toString() ?? '',
      installedVersionCode: installedVersionCode,
      releasedAt:
          releasedValue == null ? null : DateTime.tryParse(releasedValue),
    );
  }
}

class AppUpdateService {
  AppUpdateService(this.api);

  static const _dismissedVersionKey = 'catws.dismissed_update_version_code';
  final ApiClient api;

  Future<AppUpdateInfo?> check() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final installedCode = int.tryParse(packageInfo.buildNumber) ?? 0;
    final info = AppUpdateInfo.fromJson(
      await api.appVersion(),
      installedVersionCode: installedCode,
    );
    if (!info.hasUpdate) return null;

    final preferences = await SharedPreferences.getInstance();
    final dismissedCode = preferences.getInt(_dismissedVersionKey);
    if (!info.isRequired && dismissedCode == info.latestVersionCode)
      return null;
    return info;
  }

  Future<void> dismiss(AppUpdateInfo info) async {
    if (!info.isRequired) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_dismissedVersionKey, info.latestVersionCode);
    }
  }

  Future<bool> openDownload(AppUpdateInfo info) async {
    final uri = Uri.tryParse(info.downloadUrl);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> checkAndShowAppUpdate(
  BuildContext context,
  ApiClient api,
) async {
  final service = AppUpdateService(api);
  try {
    final info = await service.check();
    if (info == null || !context.mounted) return;

    final shouldOpen = await showDialog<bool>(
      context: context,
      barrierDismissible: !info.isRequired,
      builder: (dialogContext) => PopScope(
        canPop: !info.isRequired,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded),
              const SizedBox(width: 10),
              Expanded(child: Text(info.title)),
            ],
          ),
          content: Text(
            '${info.message}\n\nVersion ${info.latestVersionName} is ready to install.',
          ),
          actions: [
            if (!info.isRequired)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Later'),
              ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.download_rounded),
              label: Text(info.isRequired ? 'Update now' : 'Update'),
            ),
          ],
        ),
      ),
    );

    if (shouldOpen != true) {
      await service.dismiss(info);
      return;
    }

    final opened = await service.openDownload(info);
    if (!opened && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update link unavailable'),
          content: const Text(
              'The update link is not valid or could not be opened. Please try again later.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  } catch (_) {
    // Update checks are intentionally best-effort and never block app startup.
  }
}
