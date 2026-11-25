import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:material_ui/material_ui.dart';

abstract final class CustomReplyFilter {
  static const String _keyEnabled = 'customReplyFilterEnabled';
  static const String _keyMinLevel = 'customReplyMinLevel';
  static const String _keyBanUname = 'customReplyBanUname';

  static bool enabled = GStorage.setting.get(_keyEnabled, defaultValue: true);
  static int minLevel = GStorage.setting.get(_keyMinLevel, defaultValue: 0);
  static RegExp? unameRegExp = _compileRegExp(
    GStorage.setting.get(_keyBanUname, defaultValue: ''),
  );

  static RegExp? _compileRegExp(String pattern) {
    if (pattern.isEmpty) return null;
    try {
      return RegExp(pattern, caseSensitive: false);
    } catch (_) {
      return null;
    }
  }

  static bool shouldBlock(ReplyInfo reply) {
    if (!enabled) return false;
    if (minLevel > 0 && reply.member.level.toInt() < minLevel) {
      return true;
    }
    final reg = unameRegExp;
    if (reg != null && reg.hasMatch(reply.member.name)) {
      return true;
    }
    return false;
  }

  static List<SettingsModel> get settings => [
    SwitchModel(
      title: '启用自定义评论过滤',
      subtitle: '控制下方的评论等级过滤与昵称关键词过滤',
      leading: const Icon(Icons.shield_outlined),
      setKey: _keyEnabled,
      defaultVal: true,
      onChanged: (value) => enabled = value,
    ),
    const NormalModel(
      title: '评论最低等级过滤',
      leading: Icon(Icons.military_tech_outlined),
      getSubtitle: _minLevelSubtitle,
      onTap: _showMinLevelDialog,
    ),
    getBanWordModel(
      title: '评论用户名关键词过滤',
      key: _keyBanUname,
      onChanged: (value) {
        unameRegExp = value.pattern.isEmpty ? null : value;
      },
    ),
  ];

  static String _minLevelSubtitle() {
    if (minLevel <= 0) {
      return '不过滤';
    }
    return '过滤 LV$minLevel 以下用户的评论';
  }

  static Future<void> _showMinLevelDialog(
    BuildContext context,
    VoidCallback setState,
  ) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SelectDialog<int>(
        title: '选择评论最低保留等级',
        value: minLevel,
        values: const [
          (0, '不过滤'),
          (1, 'LV1 及以上（过滤 LV0）'),
          (2, 'LV2 及以上（过滤 LV0-1）'),
          (3, 'LV3 及以上（过滤 LV0-2）'),
          (4, 'LV4 及以上（过滤 LV0-3）'),
          (5, 'LV5 及以上（过滤 LV0-4）'),
          (6, '仅保留 LV6'),
        ],
      ),
    );
    if (result != null) {
      minLevel = result;
      await GStorage.setting.put(_keyMinLevel, result);
      setState();
    }
  }
}
