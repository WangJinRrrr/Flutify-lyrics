import 'package:flutify_app/l10n/app_locale.dart';
import 'package:flutify_app/l10n/app_localizations.dart';
import 'package:flutify_app/models/app_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppLocale.resolved(const Locale('zh', 'CN')));

  test(
    'catalog pagination and search errors are localized in every locale',
    () async {
      for (final locale in AppLocale.supportedLocales) {
        final strings = await AppLocalizations.delegate.load(locale);
        expect(strings.commonLoadMore, isNotEmpty);
        expect(strings.searchFailedTitle, isNotEmpty);
        expect(strings.searchFailedMessage, isNotEmpty);
        expect(strings.artistNoAlbums, isNotEmpty);
        expect(strings.artistNoSongs, isNotEmpty);
        expect(
          strings.searchFailedTitle,
          isNot(strings.searchNoResultsTitle('query')),
        );
      }
    },
  );

  test(
    'Japanese resolves from system, persists and localizes Spotify',
    () async {
      final locale = basicLocaleListResolution([
        const Locale('ja', 'JP'),
      ], AppLocale.supportedLocales);
      expect(locale.languageCode, 'ja');
      expect(AppLocale.localeFor(AppLanguage.ja), const Locale('ja'));
      final restored = AppPreferences.decode(
        AppPreferences.defaults.copyWith(language: AppLanguage.ja).encode(),
      );
      expect(restored.language, AppLanguage.ja);
      AppLocale.resolved(locale);
      expect(AppLocale.spotifyLanguage, 'ja');
      final strings = await AppLocalizations.delegate.load(locale);
      expect(strings.homeRefresh, 'ホームを更新');
      expect(strings.settingsLanguageJa, '日本語');
      expect(strings.songCount(12), '12 曲');
      expect(strings.settingsCacheMigrated(1, 2, 3), '1 ファイルを移動、2 件使用中、3 件失敗');
    },
  );
  test(
    'system Chinese regions resolve to the right script and Spotify language',
    () async {
      for (final country in ['TW', 'HK', 'MO', 'CN', 'SG']) {
        final locale = basicLocaleListResolution([
          Locale('zh', country),
        ], AppLocale.supportedLocales);
        final traditional = ['TW', 'HK', 'MO'].contains(country);
        expect(locale.scriptCode == 'Hant', traditional);
        AppLocale.resolved(locale);
        expect(AppLocale.spotifyLanguage, traditional ? 'zh-TW' : 'zh-CN');
        final strings = await AppLocalizations.delegate.load(locale);
        expect(strings.settingsLanguageZhHant, '繁體中文');
        expect(strings.settingsLanguageZh, '简体中文');
        expect(
          strings.lyricsTranslationUnavailable,
          traditional ? '暫無對應語言的譯詞' : '暂无对应语言的译词',
        );
      }
      AppLocale.resolved(const Locale('zh', 'CN'));
    },
  );

  test(
    'traditional language persists and old zh preference remains simplified',
    () {
      final prefs = AppPreferences.defaults.copyWith(
        language: AppLanguage.zhHant,
        lyricsExcludedLanguages: ['zh-Hans', 'zh-Hant'],
      );
      final restored = AppPreferences.fromJson(prefs.toJson());
      expect(restored.language, AppLanguage.zhHant);
      expect(restored.lyricsExcludedLanguages, ['zh-Hans', 'zh-Hant']);
      expect(AppLocale.localeFor(AppLanguage.zh)?.scriptCode, 'Hans');
    },
  );
}
