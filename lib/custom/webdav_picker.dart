import 'dart:convert';

import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

abstract final class CustomWebDavPicker {
  static String _buildDirectory() {
    String directory = Pref.webdavDirectory;
    if (!directory.endsWith('/')) {
      directory += '/';
    }
    return '$directory${Constants.appName}';
  }

  static Future<(webdav.Client, String)?> _connectAndPrepare() async {
    final uri = Pref.webdavUri;
    if (uri.isEmpty) {
      SmartDialog.showToast('请先填写 WebDAV 配置并点击右下角保存');
      return null;
    }
    final directory = _buildDirectory();
    try {
      final client =
          webdav.newClient(
              uri,
              user: Pref.webdavUsername,
              password: Pref.webdavPassword,
            )
            ..setHeaders({'accept-charset': 'utf-8'})
            ..setConnectTimeout(12000)
            ..setReceiveTimeout(12000)
            ..setSendTimeout(12000);
      await client.mkdirAll(directory);
      return (client, directory);
    } catch (e) {
      SmartDialog.showToast('连接 WebDAV 失败，请检查配置: $e');
      return null;
    }
  }

  static Future<List<webdav.File>?> _listBackups(
    webdav.Client client,
    String directory,
  ) async {
    try {
      final list = await client.readDir(directory);
      final files =
          list
              .where(
                (f) =>
                    f.isDir != true &&
                    (f.name?.toLowerCase().endsWith('.json') ?? false),
              )
              .toList()
            ..sort((a, b) {
              final ta = a.mTime ?? a.cTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              final tb = b.mTime ?? b.cTime ?? DateTime.fromMillisecondsSinceEpoch(0);
              return tb.compareTo(ta);
            });
      return files;
    } catch (e) {
      SmartDialog.showToast('读取云端备份列表失败: $e');
      return null;
    }
  }

  static String _platformLabel(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('desktop') ||
        lower.contains('windows') ||
        lower.contains('macos') ||
        lower.contains('linux') ||
        lower.contains('_pc')) {
      return 'PC';
    }
    if (lower.contains('pad') || lower.contains('tablet')) {
      return 'PAD';
    }
    if (lower.contains('phone') ||
        lower.contains('android') ||
        lower.contains('ios')) {
      return 'PHONE';
    }
    return '其他';
  }

  static String _currentPlatformLabel() {
    return switch (DeviceUtils.platformName) {
      'desktop' => 'PC',
      'pad' => 'PAD',
      _ => 'PHONE',
    };
  }

  static String _formatTime(DateTime? dt) {
    if (dt == null) return '未知时间';
    final local = dt.toLocal();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${p2(local.month)}-${p2(local.day)} '
        '${p2(local.hour)}:${p2(local.minute)}';
  }

  static String _formatSize(int? bytes) {
    if (bytes == null || bytes < 0) return '未知大小';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  static String _defaultNewFileName() {
    final now = DateTime.now();
    String p2(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${p2(now.month)}${p2(now.day)}_${p2(now.hour)}${p2(now.minute)}${p2(now.second)}';
    return 'piliplus_settings_${DeviceUtils.platformName}_$stamp.json';
  }

  static Future<bool> _confirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmText,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  static Future<String?> _promptNewFileName(BuildContext context) async {
    String fileName = _defaultNewFileName();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建备份文件'),
        content: TextFormField(
          autofocus: true,
          initialValue: fileName,
          onChanged: (v) => fileName = v.trim(),
          decoration: const InputDecoration(
            labelText: '文件名（自动补全 .json）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final cleaned = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
              if (cleaned.isEmpty) {
                SmartDialog.showToast('文件名不能为空');
                return;
              }
              final finalName = cleaned.toLowerCase().endsWith('.json')
                  ? cleaned
                  : '$cleaned.json';
              Navigator.of(ctx).pop(finalName);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  static Future<void> backup(BuildContext context) async {
    SmartDialog.showLoading(msg: '正在读取云端列表...');
    final conn = await _connectAndPrepare();
    if (conn == null) {
      SmartDialog.dismiss();
      return;
    }
    final (client, directory) = conn;
    final files = await _listBackups(client, directory);
    SmartDialog.dismiss();
    if (files == null || !context.mounted) return;

    final currentTag = _currentPlatformLabel();
    const createNewToken = '__CREATE_NEW__';

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('选择要备份的目标（当前: $currentTag）'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('新建备份文件'),
                subtitle: const Text('不覆盖旧文件，单独保存一份新备份'),
                onTap: () => Navigator.of(ctx).pop(createNewToken),
              ),
              if (files.isNotEmpty) const Divider(),
              for (final f in files)
                Builder(
                  builder: (itemCtx) {
                    final name = f.name ?? '';
                    final tag = _platformLabel(name);
                    final isCross = tag != currentTag;
                    final meta =
                        '[$tag${isCross ? '·跨平台' : ''}]  ${_formatTime(f.mTime ?? f.cTime)}  ·  ${_formatSize(f.size)}';
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(name),
                      subtitle: Text(meta),
                      onTap: () => Navigator.of(ctx).pop(name),
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selected == null || !context.mounted) return;

    String targetName;
    if (selected == createNewToken) {
      final newName = await _promptNewFileName(context);
      if (newName == null || !context.mounted) return;
      targetName = newName;
    } else {
      targetName = selected;
      final tag = _platformLabel(targetName);
      final crossHint = tag != currentTag
          ? '\n注意：目标文件标记为 [$tag]，与当前设备 [$currentTag] 不同，确认跨平台覆盖吗？'
          : '';
      final ok = await _confirmDialog(
        context,
        title: '确认覆盖备份',
        content: '即将用当前设备设置覆盖云端文件：\n$targetName$crossHint',
        confirmText: '确认覆盖',
      );
      if (!ok) return;
    }

    try {
      SmartDialog.showLoading(msg: '正在备份...');
      final data = GStorage.exportAllSettings();
      final remotePath = '$directory/$targetName';
      try {
        await client.remove(remotePath);
      } catch (_) {}
      await client.write(remotePath, utf8.encode(data));
      SmartDialog.dismiss();
      SmartDialog.showToast('备份成功: $targetName');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('备份失败: $e');
    }
  }

  static Future<void> restore(BuildContext context) async {
    SmartDialog.showLoading(msg: '正在读取云端列表...');
    final conn = await _connectAndPrepare();
    if (conn == null) {
      SmartDialog.dismiss();
      return;
    }
    final (client, directory) = conn;
    final files = await _listBackups(client, directory);
    SmartDialog.dismiss();
    if (files == null || !context.mounted) return;

    if (files.isEmpty) {
      SmartDialog.showToast('云端目录 $directory 中没有找到任何 .json 备份文件');
      return;
    }

    final currentTag = _currentPlatformLabel();

    final selected = await showDialog<webdav.File>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('选择要恢复的备份（当前: $currentTag）'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in files)
                Builder(
                  builder: (itemCtx) {
                    final name = f.name ?? '';
                    final tag = _platformLabel(name);
                    final isCross = tag != currentTag;
                    final meta =
                        '[$tag${isCross ? '·跨平台' : ''}]  ${_formatTime(f.mTime ?? f.cTime)}  ·  ${_formatSize(f.size)}';
                    return ListTile(
                      leading: const Icon(Icons.restore),
                      title: Text(name),
                      subtitle: Text(meta),
                      onTap: () => Navigator.of(ctx).pop(f),
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selected == null || selected.name == null || !context.mounted) return;

    final targetName = selected.name!;
    final tag = _platformLabel(targetName);
    if (tag != currentTag) {
      final ok = await _confirmDialog(
        context,
        title: '跨平台恢复确认',
        content: '所选备份 [$tag] ($targetName) 与当前设备 [$currentTag] 平台不同，确认要恢复吗？',
        confirmText: '仍要恢复',
      );
      if (!ok) return;
    }

    try {
      SmartDialog.showLoading(msg: '正在恢复...');
      final remotePath = '$directory/$targetName';
      final bytes = await client.read(remotePath);
      await GStorage.importAllSettings(utf8.decode(bytes));
      await Future.wait([
        GStorage.setting.flush(),
        GStorage.video.flush(),
      ]);
      SmartDialog.dismiss();
      SmartDialog.showToast('恢复成功: $targetName（请重启应用生效）');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('恢复失败: $e');
    }
  }
}
