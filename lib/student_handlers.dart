import 'package:televerse/televerse.dart';
import 'firebase_db.dart';
import 'utils.dart';
import 'config.dart';
import 'strings.dart';

void registerStudentHandlers(Bot bot) {
  // ── /start ──────────────────────────────────────────────────────────
  bot.command('start', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;

    await FirebaseDb.registerUser(userId);
    Utils.setUserMode(userId, UserMode.student);
    Utils.clearUploadState(userId);

    // Resolve language: memory cache → Firebase → ask user
    if (!Utils.hasLanguage(userId)) {
      final savedLang = await FirebaseDb.getUserLanguage(userId);
      if (savedLang == 'ar' || savedLang == 'en') {
        Utils.setUserLanguage(userId, savedLang);
      } else {
        // No language set yet — ask the user
        await _sendLanguageSelection(ctx);
        return;
      }
    }

    if (await FirebaseDb.isAdmin(userId)) {
      final lang = Utils.getUserLanguage(userId);
      await ctx.reply(
        '💙',
        replyMarkup: Keyboard()
          .addText(S.get('btn_admin_panel', lang))
          .addText(S.get('btn_student_mode', lang))
          .row()
          .addText(S.get('btn_restart_bot', lang))
          .resized(),
      );
    }

    await _sendMainMenu(bot, ctx, userId);
  });


  // ── Language selection callbacks ─────────────────────────────────────
  bot.callbackQuery('lang_ar', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.setUserLanguage(userId, 'ar');
    await FirebaseDb.setUserLanguage(userId, 'ar');
    await ctx.editMessageText(S.get('lang_set', 'ar'));
    await _sendMainMenuNew(bot, ctx, userId);
  });

  bot.callbackQuery('lang_en', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.setUserLanguage(userId, 'en');
    await FirebaseDb.setUserLanguage(userId, 'en');
    await ctx.editMessageText(S.get('lang_set', 'en'));
    await _sendMainMenuNew(bot, ctx, userId);
  });

  // Change language button — re-shows language selection (editing message)
  bot.callbackQuery('change_lang', (ctx) async {
    await ctx.answerCallbackQuery();
    final kb = InlineKeyboard()
      .row()
      .add('العربية 🇸🇦', 'lang_ar')
      .add('English 🇬🇧', 'lang_en');
    await ctx.editMessageText(S.get('lang_prompt', 'en'), replyMarkup: kb);
  });

  // ── back:main — return to main menu ──────────────────────────
  bot.callbackQuery('back:main', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    await _sendMainMenuNew(bot, ctx, userId, isEdit: true);
  });

  // ── show_departments — show paginated list of tracks ─────────────────
  bot.callbackQuery('show_departments', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    try { await ctx.answerCallbackQuery(text: 'جاري التحميل...'); } catch (_) {}
    final lang = Utils.getUserLanguage(userId);
    final tracks = await FirebaseDb.getTracks();

    InlineKeyboard keyboard;
    if (tracks.isEmpty) {
      keyboard = InlineKeyboard()
        ..row().add(S.get('no_tracks', lang), 'ignore')
        ..row().add('🔙 Back', 'back:main');
    } else {
      keyboard = Utils.paginateKeyboard(tracks, page: 0, prefix: 'track:', backData: 'back:main');
    }

    await ctx.editMessageText(S.get('departments', lang), replyMarkup: keyboard);
  });

  // ── ignore (no-op button) ─────────────────────────────────────────────
  bot.callbackQuery('ignore', (ctx) async {
    final lang = Utils.getUserLanguage(ctx.from?.id ?? 0);
    await ctx.answerCallbackQuery(
        text: S.get('no_tracks', lang), showAlert: false);
  });

  // ── Track Selection ───────────────────────────────────────────────────
  bot.callbackQuery(RegExp(r'^track:(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    final userId = ctx.from?.id;
    if (data == null || userId == null) return;
    try { await ctx.answerCallbackQuery(text: 'جاري التحميل...'); } catch (_) {}

    final trackRaw = data.split(':')[1];
    final lang = Utils.getUserLanguage(userId);
    
    if (trackRaw.startsWith('page_')) {
      final page = int.parse(trackRaw.split('_')[1]);
      final tracks = await FirebaseDb.getTracks();
      final keyboard = Utils.paginateKeyboard(tracks, page: page, prefix: 'track:', backData: 'back:main');
      await ctx.editMessageText(S.get('departments', lang), replyMarkup: keyboard);
      return;
    }

    final track = Utils.lengthen(trackRaw);
    final subjects = await FirebaseDb.getSubjects(track);
    final keyboard = Utils.paginateKeyboard(
      subjects,
      page: 0,
      prefix: 'subj:${Utils.shorten(track)}:',
      backData: 'show_departments',
    );

    await ctx.editMessageText(
      S.get('selected_track', lang, {'track': track}),
      replyMarkup: keyboard,
    );
  });

  // ── Subject Selection ─────────────────────────────────────────────────
  bot.callbackQuery(RegExp(r'^subj:(.*?):(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    final userId = ctx.from?.id;
    if (data == null || userId == null) return;
    try { await ctx.answerCallbackQuery(text: 'جاري التحميل...'); } catch (_) {}

    final parts = data.split(':');
    final track = Utils.lengthen(parts[1]);
    final subjectRaw = parts[2];
    final lang = Utils.getUserLanguage(userId);

    if (subjectRaw.startsWith('page_')) {
      final page = int.parse(subjectRaw.split('_')[1]);
      final subjects = await FirebaseDb.getSubjects(track);
      final keyboard = Utils.paginateKeyboard(subjects, page: page, prefix: 'subj:${Utils.shorten(track)}:', backData: 'show_departments');
      await ctx.editMessageText(S.get('selected_track', lang, {'track': track}), replyMarkup: keyboard);
      return;
    }

    final subject = Utils.lengthen(subjectRaw);
    final types = await FirebaseDb.getMaterialTypes(track, subject);
    final keyboard = Utils.paginateKeyboard(
      types,
      page: 0,
      prefix: 'type:${Utils.shorten(track)}:${Utils.shorten(subject)}:',
      backData: 'track:${Utils.shorten(track)}',
    );

    await ctx.editMessageText(
      S.get('selected_subject', lang, {'subject': subject}),
      replyMarkup: keyboard,
    );
  });

  // ── Material Type Selection ───────────────────────────────────────────
  bot.callbackQuery(RegExp(r'^type:(.*?):(.*?):(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    final userId = ctx.from?.id;
    if (data == null || userId == null) return;
    try { await ctx.answerCallbackQuery(text: 'جاري التحميل...'); } catch (_) {}

    try {
      final parts = data.split(':');
      final track = Utils.lengthen(parts[1]);
      final subject = Utils.lengthen(parts[2]);
      final typeRaw = parts[3];
      final lang = Utils.getUserLanguage(userId);

      if (typeRaw.startsWith('page_')) {
        final page = int.parse(typeRaw.split('_')[1]);
        final types = await FirebaseDb.getMaterialTypes(track, subject);
        final keyboard = Utils.paginateKeyboard(
          types,
          page: page,
          prefix: 'type:${Utils.shorten(track)}:${Utils.shorten(subject)}:',
          backData: 'track:${Utils.shorten(track)}',
        );
        await ctx.editMessageText(S.get('selected_subject', lang, {'subject': subject}), replyMarkup: keyboard);
        return;
      }

      final type = Utils.lengthen(typeRaw);
      final materials = await FirebaseDb.getMaterials(track, subject, type);
      if (materials.isEmpty) {
        final kb = InlineKeyboard().row().add('🔙 Back', 'subj:${Utils.shorten(track)}:${Utils.shorten(subject)}');
        await ctx.editMessageText(
          '${S.get('materials_list', lang, {'type': type})}\n\n${S.get('no_files_found', lang)}',
          replyMarkup: kb,
        );
        return;
      }

      final itemsList = materials.entries.map((e) {
        final name = e.value is Map ? (e.value['name']?.toString() ?? e.key) : e.value.toString();
        return MapEntry(e.key, name);
      }).toList();
      
      final keyboard = Utils.paginateMapKeyboard(
        itemsList,
        page: 0,
        prefix: 'mat:${Utils.shorten(track)}:${Utils.shorten(subject)}:${Utils.shorten(type)}:',
        backData: 'subj:${Utils.shorten(track)}:${Utils.shorten(subject)}',
      );

      await ctx.editMessageText(
        S.get('materials_list', lang, {'type': type}),
        replyMarkup: keyboard,
      );
    } catch (e, stack) {
      print('[TypeCallback] Error: $e\n$stack');
      try {
        await ctx.answerCallbackQuery(text: 'تعذر تحميل المواد، يرجى المحاولة مرة أخرى.', showAlert: true);
      } catch (_) {}
    }
  });

  // ── Material Download ─────────────────────────────────────────────────
  bot.callbackQuery(RegExp(r'^mat:(.*?):(.*?):(.*?):(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    final userId = ctx.from?.id;
    if (data == null || userId == null) return;
    try { await ctx.answerCallbackQuery(text: 'جاري التحميل...'); } catch (_) {}

    try {
      final parts = data.split(':');
      final track = Utils.lengthen(parts[1]);
      final subject = Utils.lengthen(parts[2]);
      final type = Utils.lengthen(parts[3]);
      final materialIdRaw = parts[4];
      final lang = Utils.getUserLanguage(userId);

      if (materialIdRaw.startsWith('page_')) {
        final page = int.parse(materialIdRaw.split('_')[1]);
        final materials = await FirebaseDb.getMaterials(track, subject, type);
        final itemsList = materials.entries.map((e) {
          final name = e.value is Map ? (e.value['name']?.toString() ?? e.key) : e.value.toString();
          return MapEntry(e.key, name);
        }).toList();
        final keyboard = Utils.paginateMapKeyboard(
          itemsList,
          page: page,
          prefix: 'mat:${Utils.shorten(track)}:${Utils.shorten(subject)}:${Utils.shorten(type)}:',
          backData: 'subj:${Utils.shorten(track)}:${Utils.shorten(subject)}',
        );
        await ctx.editMessageText(S.get('materials_list', lang, {'type': type}), replyMarkup: keyboard);
        return;
      }

      final materialId = Utils.lengthen(materialIdRaw);
      final material = await FirebaseDb.getMaterial(track, subject, type, materialId);

      if (material != null) {
        final fileId = material['file_id']?.toString() ?? '';
        final name = material['name']?.toString() ?? materialId;
        final fileType = material['file_type']?.toString() ?? 'document';
        final description = material['description'] as String? ?? '';

        String caption = S.get('here_is_material', lang,
            {'name': name, 'track': track, 'subject': subject, 'type': type});
        if (description.isNotEmpty) caption += '\n\n📝 $description';

        if (fileType == 'link' || fileId.startsWith('http://') || fileId.startsWith('https://')) {
          await ctx.reply('$caption\n\n🔗 $fileId');
        } else if (fileId.isEmpty || fileType == 'text' || fileType == 'string') {
          await ctx.reply('📖 *$name*\n\n$caption', parseMode: ParseMode.markdown);
        } else if (fileType == 'photo') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithPhoto(inputFile, caption: caption);
        } else if (fileType == 'video') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithVideo(inputFile, caption: caption);
        } else if (fileType == 'audio') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithAudio(inputFile, caption: caption);
        } else if (fileType == 'voice') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithVoice(inputFile, caption: caption);
        } else {
          try {
            final inputFile = InputFile.fromFileId(fileId);
            await ctx.replyWithDocument(inputFile, caption: caption);
          } catch (e) {
            await ctx.reply('📖 *$name*\n\n$caption\n\n📄 $fileId');
          }
        }

        await FirebaseDb.logMaterialAccess(materialId, name);
      } else {
        await ctx.answerCallbackQuery(
            text: S.get('material_not_found', lang), showAlert: true);
      }
    } catch (e, stack) {
      print('[MaterialDownload] Error: $e\n$stack');
      try {
        await ctx.answerCallbackQuery(text: 'حدث خطأ أثناء فتح المادة.', showAlert: true);
      } catch (_) {}
    }
  });

  // ── Smart Search Beta callback ──────────────────────────────────────────
  bot.callbackQuery('smart_search_beta', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    await ctx.answerCallbackQuery();
    Utils.uploadStates[userId] = {'action': 'smart_search_query'};
    final kb = InlineKeyboard().row().add(S.get('btn_back', lang), 'back:main');
    await ctx.editMessageText(S.get('search_prompt', lang), replyMarkup: kb);
  });

  // ── Request to Contribute ──────────────────────────────────────────────────
  bot.callbackQuery('req_contribute', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    // If already a contributor, show dashboard button instead of request form
    final isContrib = await FirebaseDb.isContributor(userId);
    if (isContrib) {
      final kb = InlineKeyboard().row()
        .add(S.get('btn_my_dashboard', lang), 'contrib_dash');
      await ctx.reply(S.get('already_contributor_msg', lang), replyMarkup: kb);
      await ctx.answerCallbackQuery();
      return;
    }

    Utils.uploadStates[userId] = {'action': 'req_contribute_name'};
    await ctx.reply(S.get('contribute_name_prompt', lang));
    await ctx.answerCallbackQuery();
  });

  // ── Contact Admin ─────────────────────────────────────────────────────
  bot.callbackQuery('contact_admin', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    Utils.uploadStates[userId] = {'action': 'contact_admin'};
    await ctx.reply(S.get('contact_admin_prompt', lang));
    await ctx.answerCallbackQuery();
  });
}

// ── Private helpers ─────────────────────────────────────────────────────

Future<void> _sendLanguageSelection(Context ctx) async {
  final kb = InlineKeyboard()
    .row()
    .add('العربية 🇸🇦', 'lang_ar')
    .add('English 🇬🇧', 'lang_en');
  await ctx.reply(S.get('lang_prompt', 'en'), replyMarkup: kb);
}

/// Sends a new main-menu message (after language was just picked via callback or back).
Future<void> _sendMainMenuNew(Bot bot, Context ctx, int userId, {bool isEdit = false}) async {
  final lang = Utils.getUserLanguage(userId);
  final keyboard = InlineKeyboard();

  keyboard.row().add(S.get('btn_departments', lang), 'show_departments');

  // Schedules / Tables direct button
  keyboard.row().add(S.get('btn_my_tables', lang), 'table_dash');

  // New experimental feature labeled [BETA 🧪]
  keyboard.row().add(S.get('btn_smart_search_beta', lang), 'smart_search_beta');

  final isContrib = await FirebaseDb.isContributor(userId);
  if (isContrib) {
    keyboard.row().add(S.get('btn_my_dashboard', lang), 'contrib_dash');
  }
  keyboard.row().add(S.get('btn_contribute', lang), 'req_contribute');
  keyboard.row().add(S.get('btn_contact_admin', lang), 'contact_admin');
  
  if (Config.whatsappSupportNumber.isNotEmpty) {
    keyboard.row().addUrl(S.get('btn_whatsapp_support', lang), 'https://wa.me/${Config.whatsappSupportNumber}');
  }
  
  keyboard.row().add(S.get('btn_change_lang', lang), 'change_lang');

  if (isEdit) {
    await ctx.editMessageText(S.get('welcome', lang), replyMarkup: keyboard);
  } else {
    await ctx.reply(S.get('welcome', lang), replyMarkup: keyboard);
  }
}

/// Sends a new main-menu message from a /start command.
Future<void> _sendMainMenu(Bot bot, Context ctx, int userId) async {
  await _sendMainMenuNew(bot, ctx, userId, isEdit: false);
}
