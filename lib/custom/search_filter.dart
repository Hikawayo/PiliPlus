import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:material_ui/material_ui.dart';

abstract final class CustomSearchFilter {
  static const String _keyDedup = 'customSearchDedup';
  static const String _keyRelevanceMode = 'customSearchRelevanceMode';

  static bool dedupEnabled = GStorage.setting.get(
    _keyDedup,
    defaultValue: true,
  );

  /// 0 = 关闭, 1 = 标准相关（推荐）, 2 = 严格相关
  static int relevanceMode = GStorage.setting.get(
    _keyRelevanceMode,
    defaultValue: 1,
  );

  static final RegExp _splitRegExp = RegExp(
    r'[\s,，。！？!?、;；:：/\\|()（）\[\]【】《》<>""“”‘’+-]+',
  );
  static final RegExp _tokenPartRegExp = RegExp(
    r'[a-z0-9]+|[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+',
  );
  static final RegExp _asciiWordRegExp = RegExp(r'^[a-z0-9]+$');
  static final RegExp _whitespaceRegExp = RegExp(r'\s+');

  static const Set<String> _stopWords = {
    '看',
    '的',
    '了',
    '是',
    '在',
    '和',
    '与',
    '也',
    '都',
    '就',
    '把',
    '被',
    '给',
    '让',
    '到',
    '去',
    '来',
    '啊',
    '呢',
    '吧',
    '吗',
    '哦',
    '嗯',
    '呀',
    '这',
    '那',
    '个',
    '有',
    '没',
    '不',
    '很',
    '太',
    '最',
    '超',
    '好',
    '大',
    '小',
    '新',
    '旧',
    '全',
    '第',
    '一',
    '二',
    '三',
    'a',
    'an',
    'the',
    'of',
    'to',
    'in',
    'on',
    'for',
    'and',
    'or',
  };

  static void filterVideos({
    required String keyword,
    required List<SearchVideoItemModel> dataList,
    required Set<String> seenKeys,
  }) {
    if (!dedupEnabled && relevanceMode == 0) {
      return;
    }

    final trimmed = keyword.trim();
    final skipRelevance =
        relevanceMode == 0 ||
        trimmed.isEmpty ||
        IdUtils.avRegexExact.hasMatch(trimmed) ||
        IdUtils.bvRegexExact.hasMatch(trimmed);

    final coreTokens = skipRelevance ? const <String>[] : _extractCoreTokens(trimmed);

    dataList.removeWhere((item) {
      if (dedupEnabled) {
        final key = _videoKey(item);
        if (key != null && !seenKeys.add(key)) {
          return true;
        }
      }
      if (!skipRelevance && coreTokens.isNotEmpty) {
        return !_isRelevant(item, coreTokens, strict: relevanceMode >= 2);
      }
      return false;
    });
  }

  static String? _videoKey(SearchVideoItemModel item) {
    final bvid = item.bvid;
    if (bvid != null && bvid.isNotEmpty) {
      return 'bv:$bvid';
    }
    final aid = item.aid ?? item.id;
    if (aid != null) {
      return 'av:$aid';
    }
    final url = item.arcurl;
    if (url != null && url.isNotEmpty) {
      return 'url:$url';
    }
    return null;
  }

  static List<String> _extractCoreTokens(String keyword) {
    final lower = keyword.toLowerCase();
    final rawTokens = <String>[];
    for (final segment in lower.split(_splitRegExp)) {
      if (segment.isEmpty) continue;
      final parts = _tokenPartRegExp
          .allMatches(segment)
          .map((m) => m.group(0)!)
          .toList();
      if (parts.isEmpty) {
        rawTokens.add(segment);
      } else {
        rawTokens.addAll(parts);
      }
    }
    if (rawTokens.isEmpty) return const [];

    final filtered = rawTokens
        .where((t) => !_stopWords.contains(t))
        .toSet()
        .toList();
    return filtered.isNotEmpty ? filtered : rawTokens.toSet().toList();
  }

  static bool _isRelevant(
    SearchVideoItemModel item,
    List<String> coreTokens, {
    required bool strict,
  }) {
    final title = item.title.toLowerCase();
    final author = (item.owner.name ?? '').toLowerCase();
    final desc = (item.desc ?? '').toLowerCase();

    final primaryText = '$title $author';
    final fullText = strict ? primaryText : '$primaryText $desc';
    final compactText = fullText.replaceAll(_whitespaceRegExp, '');

    if (strict) {
      return coreTokens.every(
        (token) => _matchToken(token, fullText, compactText),
      );
    }

    for (final token in coreTokens) {
      if (_matchToken(token, fullText, compactText)) {
        return true;
      }
    }

    final titleList = item.titleList;
    if (titleList != null) {
      for (final seg in titleList) {
        if (!seg.isEm) continue;
        final emText = seg.text.trim().toLowerCase();
        if (emText.isEmpty || _stopWords.contains(emText)) continue;
        if (emText.length >= 2) {
          return true;
        }
      }
    }

    return false;
  }

  static bool _matchToken(String token, String fullText, String compactText) {
    if (fullText.contains(token)) {
      return true;
    }
    if (_asciiWordRegExp.hasMatch(token) && token.length >= 4) {
      return compactText.contains(token);
    }
    return false;
  }

  static List<SettingsModel> get settings => [
    SwitchModel(
      title: '搜索结果自动去重',
      subtitle: '过滤综合/视频搜索翻页时重复出现的视频',
      leading: const Icon(Icons.filter_none_outlined),
      setKey: _keyDedup,
      defaultVal: true,
      onChanged: (value) => dedupEnabled = value,
    ),
    const NormalModel(
      title: '搜索结果相关性过滤',
      leading: Icon(Icons.manage_search_outlined),
      getSubtitle: _relevanceSubtitle,
      onTap: _showRelevanceDialog,
    ),
  ];

  static String _relevanceSubtitle() {
    return switch (relevanceMode) {
      0 => '关闭（保留原版搜索与个性化推荐）',
      2 => '严格相关（标题/UP主须命中全部核心词）',
      _ => '标准相关（过滤无核心词命中的个性化推荐）',
    };
  }

  static Future<void> _showRelevanceDialog(
    BuildContext context,
    VoidCallback setState,
  ) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => SelectDialog<int>(
        title: '搜索结果相关性过滤',
        value: relevanceMode,
        values: const [
          (0, '关闭（按原版接口显示）'),
          (1, '标准相关（推荐：过滤不相关个性化塞入）'),
          (2, '严格相关（标题/UP主须包含全部核心词）'),
        ],
      ),
    );
    if (result != null) {
      relevanceMode = result;
      await GStorage.setting.put(_keyRelevanceMode, result);
      setState();
    }
  }
}
