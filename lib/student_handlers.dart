import 'package:televerse/televerse.dart';
import 'firebase_db.dart';
import 'utils.dart';
import 'config.dart';
import 'strings.dart';

final Map<int, String> _activePomodoros = {};
final Map<int, List<Map<String, dynamic>>> _gpaCourses = {};
final Map<int, String> _gpaTempGrade = {};

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

        final favKb = InlineKeyboard().row().add(
          S.get('btn_add_favorite', lang),
          'fav_add:${Utils.shorten(track)}:${Utils.shorten(subject)}:${Utils.shorten(type)}:${Utils.shorten(materialId)}',
        );

        if (fileType == 'link' || fileId.startsWith('http://') || fileId.startsWith('https://')) {
          await ctx.reply('$caption\n\n🔗 $fileId', replyMarkup: favKb);
        } else if (fileId.isEmpty || fileType == 'text' || fileType == 'string') {
          await ctx.reply('📖 *$name*\n\n$caption', parseMode: ParseMode.markdown, replyMarkup: favKb);
        } else if (fileType == 'photo') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithPhoto(inputFile, caption: caption, replyMarkup: favKb);
        } else if (fileType == 'video') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithVideo(inputFile, caption: caption, replyMarkup: favKb);
        } else if (fileType == 'audio') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithAudio(inputFile, caption: caption, replyMarkup: favKb);
        } else if (fileType == 'voice') {
          final inputFile = InputFile.fromFileId(fileId);
          await ctx.replyWithVoice(inputFile, caption: caption, replyMarkup: favKb);
        } else {
          try {
            final inputFile = InputFile.fromFileId(fileId);
            await ctx.replyWithDocument(inputFile, caption: caption, replyMarkup: favKb);
          } catch (e) {
            await ctx.reply('📖 *$name*\n\n$caption\n\n📄 $fileId', replyMarkup: favKb);
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

  // ── Favorite Add Callback ──────────────────────────────────────────────
  bot.callbackQuery(RegExp(r'^fav_add:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    try {
      final parts = data.replaceFirst('fav_add:', '').split(':');
      final track = Utils.lengthen(parts[0]);
      final subject = Utils.lengthen(parts[1]);
      final type = Utils.lengthen(parts[2]);
      final matId = Utils.lengthen(parts[3]);

      final mat = await FirebaseDb.getMaterial(track, subject, type, matId);
      final title = mat?['name']?.toString() ?? matId;
      await FirebaseDb.addFavorite(userId, track, subject, type, matId, title);

      await ctx.answerCallbackQuery(text: '⭐️ تمت الإضافة إلى مفضلاتك بنجاح!', showAlert: true);
    } catch (e) {
      print('[FavAdd] Error: $e');
      await ctx.answerCallbackQuery(text: 'تم الحفظ في المفضلة.');
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

  // ── Student Smart Tools Dashboard [BETA] ────────────────────────────────
  bot.callbackQuery('student_tools_beta', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    final lang = Utils.getUserLanguage(userId);

    final kb = InlineKeyboard()
      .row().add(S.get('btn_my_favorites_beta', lang), 'fav_list')
      .row().add(S.get('btn_pomodoro_beta', lang), 'pomo_menu')
      .row().add(S.get('btn_gpa_calc_beta', lang), 'gpa_menu')
      .row().add(S.get('btn_study_tips_beta', lang), 'study_tips_menu')
      .row().add(S.get('btn_back', lang), 'back:main');

    final text = '✨ *حزمة أدوات الطالب والإنتاجية [BETA 🧪]*\n\n'
        'مرحباً بك! هذه الميزات التجريبية صُممت خصيصاً لمساعدتك على المذاكرة بتركيز وتنظيم وقتك وموادك:\n\n'
        '🔖 *مفضلاتي ومحفوظاتي:* حفظ سريع للمحاضرات والملخصات المهمة للرجوع إليها بضغطة واحدة.\n'
        '⏱ *مؤقت بومودورو:* جلسات تركيز ذكية للمذاكرة مع منبه صوتي عند الانتهاء.\n'
        '📊 *حاسبة المعدل GPA:* حساب فوري لمعدلك الفصلي والتراكمي وتقييمك الأكاديمي.\n'
        '💡 *تقنيات المذاكرة:* ملخصات تطبيقية لأقوى طرق الحفظ والفهم السريع.\n\n'
        '👇 اختر الأداة التي ترغب بها:';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  // ── Favorites List & Delete [BETA] ──────────────────────────────────────
  bot.callbackQuery('fav_list', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    final lang = Utils.getUserLanguage(userId);

    final favs = await FirebaseDb.getFavorites(userId);
    if (favs.isEmpty) {
      final kb = InlineKeyboard().row().add(S.get('btn_back', lang), 'student_tools_beta');
      await ctx.editMessageText(
        '🔖 *قائمة المفضلة فارغة حالياً.*\n\n'
        'عند فتح أي محاضرة أو ملخص، اضغط على زر (⭐️ حفظ في المفضلة) أسفل الرسالة ليتم حفظها هنا للوصول السريع!',
        parseMode: ParseMode.markdown,
        replyMarkup: kb,
      );
      return;
    }

    final kb = InlineKeyboard();
    final buffer = StringBuffer('🔖 *المحاضرات والملخصات المحفوظة:*\n\n');
    int i = 1;
    for (var entry in favs.entries) {
      final val = entry.value;
      if (val is! Map) continue;
      final title = val['title'] ?? 'ملف';
      final subj = val['subject'] ?? '';
      final track = val['track'] ?? '';
      final type = val['type'] ?? '';
      final matId = val['mat_id'] ?? '';
      final favKey = entry.key;

      buffer.writeln('$i. 📌 *[$subj]* $title ($type)');
      kb.row()
        .add('📖 $title', 'mat:${Utils.shorten(track)}:${Utils.shorten(subj)}:${Utils.shorten(type)}:${Utils.shorten(matId)}')
        .add('🗑 حذف', 'fav_del:$favKey');
      i++;
    }
    kb.row().add(S.get('btn_back', lang), 'student_tools_beta');

    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^fav_del:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final favKey = data.replaceFirst('fav_del:', '');
    await ctx.answerCallbackQuery(text: 'تم الحذف من المفضلة.');
    await FirebaseDb.removeFavorite(userId, favKey);

    final favs = await FirebaseDb.getFavorites(userId);
    final lang = Utils.getUserLanguage(userId);
    if (favs.isEmpty) {
      final kb = InlineKeyboard().row().add(S.get('btn_back', lang), 'student_tools_beta');
      await ctx.editMessageText(
        '🔖 *تم حذف جميع العناصر من المفضلة.*',
        parseMode: ParseMode.markdown,
        replyMarkup: kb,
      );
    } else {
      final kb = InlineKeyboard();
      final buffer = StringBuffer('🔖 *المحاضرات والملخصات المحفوظة:*\n\n');
      int i = 1;
      for (var entry in favs.entries) {
        final val = entry.value;
        if (val is! Map) continue;
        final title = val['title'] ?? 'ملف';
        final subj = val['subject'] ?? '';
        final track = val['track'] ?? '';
        final type = val['type'] ?? '';
        final matId = val['mat_id'] ?? '';
        final key = entry.key;

        buffer.writeln('$i. 📌 *[$subj]* $title ($type)');
        kb.row()
          .add('📖 $title', 'mat:${Utils.shorten(track)}:${Utils.shorten(subj)}:${Utils.shorten(type)}:${Utils.shorten(matId)}')
          .add('🗑 حذف', 'fav_del:$key');
        i++;
      }
      kb.row().add(S.get('btn_back', lang), 'student_tools_beta');
      await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
    }
  });

  // ── Pomodoro Focus Timer [BETA] ─────────────────────────────────────────
  bot.callbackQuery('pomo_menu', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    final lang = Utils.getUserLanguage(userId);

    final kb = InlineKeyboard()
      .row().add('🍅 جلسة تركيز قياسية (25 دقيقة)', 'pomo_start:25')
      .row().add('🚀 جلسة تركيز مكثفة (50 دقيقة)', 'pomo_start:50')
      .row().add('⚡ جلسة سريعة تجريبية (1 دقيقة)', 'pomo_start:1')
      .row().add('☕ استراحة قصيرة (5 دقائق)', 'pomo_start:5')
      .row().add(S.get('btn_back', lang), 'student_tools_beta');

    final text = '⏱ *مؤقت المذاكرة والتركيز (Pomodoro) [BETA 🧪]*\n\n'
        'طريقة بومودورو هي تقنية عالمية مثبتة لزيادة التركيز وتجنب التشتت والإرهاق:\n'
        '1️⃣ اختر مدة الجلسة.\n'
        '2️⃣ تخلص من كل المشتتات وابدأ المذاكرة فوراً.\n'
        '3️⃣ سيقوم البوت بإرسال إشعار صوتي لك فور انتهاء الوقت للتوقف وأخذ قسط من الراحة.\n\n'
        'اختر مدة الجلسة لتبدأ الآن:';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^pomo_start:(\d+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final mins = int.parse(ctx.callbackQuery!.data!.split(':')[1]);
    final timerId = DateTime.now().millisecondsSinceEpoch.toString();
    _activePomodoros[userId] = timerId;

    await ctx.answerCallbackQuery(text: '🚀 بدأت الجلسة! ركز جيداً.');

    final kb = InlineKeyboard().row().add('🛑 إلغاء الجلسة', 'pomo_cancel');

    await ctx.editMessageText(
      '⏳ *بدأت جلسة التركيز ($mins دقيقة) [BETA 🧪]*\n\n'
      '📖 _"وَقُل رَّبِّ زِدْنِي عِلْمًا"_\n\n'
      '🎯 *نصائح للجلسة:*\n'
      '• ضع الهاتف في وضع الصامت واغلق وسائل التواصل.\n'
      '• ركز على صفحة أو فكرة واحدة حتى رنين المنبه.\n'
      '• سيصلك إشعار فوري من البوت عند اكتمال الـ $mins دقيقة.\n\n'
      'نحن معك، بالتوفيق يا بطل! 🌟',
      parseMode: ParseMode.markdown,
      replyMarkup: kb,
    );

    Future.delayed(Duration(minutes: mins), () async {
      if (_activePomodoros[userId] == timerId) {
        _activePomodoros.remove(userId);
        try {
          final doneKb = InlineKeyboard()
            .row().add('☕ استراحة 5 دقائق', 'pomo_start:5')
            .row().add('🍅 جلسة تركيز جديدة', 'pomo_menu')
            .row().add('🔙 القائمة الرئيسية', 'back:main');

          await bot.api.sendMessage(
            ChatID(userId),
            '🔔 *انتهت جلسة التركيز ($mins دقيقة)!* 🎉\n\n'
            'أحسنت صنعاً وجهد رائع! أتممت جلسة المذاكرة بنجاح.\n'
            'حان الآن وقت استراحة قصيرة لتجديد نشاطك الذهني ☕',
            parseMode: ParseMode.markdown,
            replyMarkup: doneKb,
          );
        } catch (e) {
          print('[Pomodoro] Error sending completion: $e');
        }
      }
    });
  });

  bot.callbackQuery('pomo_cancel', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    _activePomodoros.remove(userId);
    await ctx.answerCallbackQuery(text: 'تم إلغاء الجلسة.');
    await ctx.editMessageText(
      '🛑 *تم إلغاء جلسة التركيز.*\n\nيمكنك بدء جلسة جديدة في أي وقت تشاء.',
      parseMode: ParseMode.markdown,
      replyMarkup: InlineKeyboard().row().add('⏱ بدء مؤقت جديد', 'pomo_menu').row().add('🔙 رجوع', 'student_tools_beta'),
    );
  });

  // ── GPA Calculator [BETA] ───────────────────────────────────────────────
  bot.callbackQuery('gpa_menu', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    final lang = Utils.getUserLanguage(userId);
    _gpaCourses[userId] ??= <Map<String, dynamic>>[];
    await _showGpaScreen(ctx, userId, lang);
  });

  bot.callbackQuery('gpa_add', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final kb = InlineKeyboard()
      .row().add('A+ (4.0)', 'gpa_gr:A+:4.0').add('A (4.0)', 'gpa_gr:A:4.0').add('A- (3.7)', 'gpa_gr:A-:3.7')
      .row().add('B+ (3.3)', 'gpa_gr:B+:3.3').add('B (3.0)', 'gpa_gr:B:3.0').add('B- (2.7)', 'gpa_gr:B-:2.7')
      .row().add('C+ (2.3)', 'gpa_gr:C+:2.3').add('C (2.0)', 'gpa_gr:C:2.0').add('C- (1.7)', 'gpa_gr:C-:1.7')
      .row().add('D+ (1.3)', 'gpa_gr:D+:1.3').add('D (1.0)', 'gpa_gr:D:1.0').add('F (0.0)', 'gpa_gr:F:0.0')
      .row().add('🔙 إلغاء', 'gpa_menu');

    await ctx.editMessageText('اختر التقدير الذي حصلت عليه في المادة:', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^gpa_gr:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final payload = data.replaceFirst('gpa_gr:', '');
    _gpaTempGrade[userId] = payload;
    await ctx.answerCallbackQuery();

    final gradeName = payload.split(':')[0];
    final kb = InlineKeyboard()
      .row().add('1 ساعة', 'gpa_hr:1').add('2 ساعة', 'gpa_hr:2').add('3 ساعات', 'gpa_hr:3')
      .row().add('4 ساعات', 'gpa_hr:4').add('5 ساعات', 'gpa_hr:5').add('6 ساعات', 'gpa_hr:6')
      .row().add('🔙 إلغاء', 'gpa_menu');

    await ctx.editMessageText('التقدير المختار: *$gradeName*\n\nالآن اختر عدد الساعات المعتمدة لهذه المادة:', parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^gpa_hr:(\d+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final hours = int.parse(data.replaceFirst('gpa_hr:', ''));
    final temp = _gpaTempGrade[userId] ?? 'A:4.0';
    final parts = temp.split(':');
    final grade = parts[0];
    final points = double.tryParse(parts[1]) ?? 4.0;

    _gpaCourses[userId] ??= [];
    _gpaCourses[userId]!.add({
      'grade': grade,
      'points': points,
      'hours': hours,
    });
    _gpaTempGrade.remove(userId);

    await ctx.answerCallbackQuery(text: '✅ تمت إضافة المادة!');
    final lang = Utils.getUserLanguage(userId);
    await _showGpaScreen(ctx, userId, lang);
  });

  bot.callbackQuery('gpa_reset', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    _gpaCourses.remove(userId);
    _gpaTempGrade.remove(userId);
    await ctx.answerCallbackQuery(text: 'تمت إعادة التعيين.');
    final lang = Utils.getUserLanguage(userId);
    await _showGpaScreen(ctx, userId, lang);
  });

  // ── Study Tips & Techniques [BETA] ──────────────────────────────────────
  bot.callbackQuery('study_tips_menu', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    final lang = Utils.getUserLanguage(userId);

    final kb = InlineKeyboard()
      .row().add('🧠 تقنية فاينمان (Feynman)', 'tip_feynman')
      .row().add('🔁 الاسترجاع النشط (Active Recall)', 'tip_recall')
      .row().add('📈 التكرار المتباعد (Spaced Repetition)', 'tip_spaced')
      .row().add('🗺️ الخرائط الذهنية (Mind Maps)', 'tip_maps')
      .row().add(S.get('btn_back', lang), 'student_tools_beta');

    final text = '💡 *أقوى استراتيجيات المذاكرة والحفظ العلمي [BETA 🧪]*\n\n'
        'استراتيجيات علمية مثبتة ومجربة تضاعف سرعة فهمك وقدرتك على استرجاع المعلومات في الامتحانات:\n\n'
        'اضغط على أي استراتيجية لقراءة خطواتها العملية:';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery('tip_feynman', (ctx) async {
    await ctx.answerCallbackQuery();
    final text = '🧠 *تقنية فاينمان (The Feynman Technique) [BETA 🧪]*\n\n'
        'تعتبر من أقوى التقنيات لفهم أعقد النظريات والمعادلات العلمية بسرعة:\n\n'
        '1️⃣ *اختر المفهوم:* حدد الدرس أو المصطلح الذي تود دراسته بدقة.\n'
        '2️⃣ *اشرحه كأنك تشرح لطفل في العاشرة:* اكتب شرحاً مبسطاً بكلماتك البسيطة الخاصة وتجنب المصطلحات المعقدة دون تفكيكها.\n'
        '3️⃣ *حدد نقاط الضعف والفجوات:* اللحظة التي تتعثر فيها في الشرح هي بالضبط النقطة التي تحتاج مراجعتها في المرجع أو التلخيص.\n'
        '4️⃣ *بسط واستخدم التشبيهات:* اربط المفاهيم المجردة بأمثلة حياتية ملموسة.\n\n'
        '🎯 _"إذا لم تستطع شرح فكرة ببساطة، فأنت لم تفهمها بشكل كافٍ."_';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 رجوع للتقنيات', 'study_tips_menu'));
  });

  bot.callbackQuery('tip_recall', (ctx) async {
    await ctx.answerCallbackQuery();
    final text = '🔁 *الاسترجاع النشط (Active Recall) [BETA 🧪]*\n\n'
        'أكبر خطأ يقع فيه الطلاب هو "القراءة السلبية والتظليل بالماركر"، فهو يعطي شعوراً زائفاً بالفهم دون تثبيت في الذاكرة!\n\n'
        '✨ *كيف تطبق الاسترجاع النشط؟*\n'
        '• بعد قراءة صفحة أو فقرة، أغلق الملخص فوراً واسأل نفسك: "ماذا تعلمت للتو؟".\n'
        '• حل أسئلة وامتحانات سابقة قبل المراجعة لتدريب عقلك على البحث في الذاكرة.\n'
        '• حوّل عناوين المحاضرة إلى أسئلة واكتب إجاباتها من ذاكرتك أولاً قبل النظر في الإجابة.\n\n'
        '🎯 _التعلم الحقيقي يحدث عندما يبذل الدماغ جهداً لاسترجاع المعلومة وليس عند إدخالها فقط._';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 رجوع للتقنيات', 'study_tips_menu'));
  });

  bot.callbackQuery('tip_spaced', (ctx) async {
    await ctx.answerCallbackQuery();
    final text = '📈 *التكرار المتباعد (Spaced Repetition) [BETA 🧪]*\n\n'
        'العقل البشري ينسى أكثر من 70% من المعلومات بعد مرور 24 ساعة وفق منحنى النسيان (Forgetting Curve).\n\n'
        '🗓 *جدول المراجعة الأمثل:*\n'
        '• *المراجعة الأولى:* بعد 24 ساعة من المذاكرة (10 دقائق).\n'
        '• *المراجعة الثانية:* بعد 3 أيام (5 دقائق).\n'
        '• *المراجعة الثالثة:* بعد أسبوع.\n'
        '• *المراجعة الرابعة:* بعد شهر.\n\n'
        'بهذه الطريقة تتحول المعلومات من الذاكرة قصيرة المدى إلى الذاكرة الدائمة طويلة المدى تلقائياً!';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 رجوع للتقنيات', 'study_tips_menu'));
  });

  bot.callbackQuery('tip_maps', (ctx) async {
    await ctx.answerCallbackQuery();
    final text = '🗺️ *الخرائط الذهنية والربط البصري [BETA 🧪]*\n\n'
        'الدماغ البشري يعالج الصور والرسوم البيانية أسرع بـ 60,000 مرة من النصوص العادية!\n\n'
        '🎨 *طريقة التطبيق:*\n'
        '• ضع الفكرة الرئيسية أو اسم المادة في المنتصف داخل دائرة.\n'
        '• فرّع منها خطوطاً ملونة لكل قسم أو فصل رئيسي.\n'
        '• استخدم رموزاً وأشكالاً بصرية وكلمات مفتاحية قليلة بدلاً من الجمل الطويلة.\n'
        '• في ليلة الامتحان، خريطة ذهنية واحدة تكفيك لاسترجاع منهج كامل في دقائق!';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 رجوع للتقنيات', 'study_tips_menu'));
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

  // New experimental features labeled [BETA 🧪]
  keyboard.row().add(S.get('btn_smart_search_beta', lang), 'smart_search_beta');
  keyboard.row().add(S.get('btn_student_tools_beta', lang), 'student_tools_beta');

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

Future<void> _showGpaScreen(Context ctx, int userId, String lang, {bool isEdit = true}) async {
  final courses = _gpaCourses[userId] ?? [];
  final buffer = StringBuffer('📊 *حاسبة المعدل التراكمي والفصلي GPA [BETA 🧪]*\n\n');

  if (courses.isEmpty) {
    buffer.writeln('_لم تقم بإضافة أي مواد بعد._\n');
    buffer.writeln('💡 اضغط على زر *(➕ إضافة مادة جديدة)* لإدخال ساعات المادة والتقدير وحساب المعدل تلقائياً.');
  } else {
    buffer.writeln('*المواد المضافة حالياً:*');
    double totalPoints = 0;
    int totalHours = 0;
    for (int i = 0; i < courses.length; i++) {
      final c = courses[i];
      final grade = c['grade'] as String;
      final points = c['points'] as double;
      final hours = c['hours'] as int;
      final coursePoints = points * hours;
      totalPoints += coursePoints;
      totalHours += hours;
      buffer.writeln('${i + 1}. مادة ${i + 1}: *$hours ساعات* | تقدير: *$grade* ($points)');
    }

    final gpa = totalHours > 0 ? (totalPoints / totalHours) : 0.0;
    String rating = '';
    if (gpa >= 3.75) {
      rating = 'ممتاز مع مرتبة الشرف 🏆';
    } else if (gpa >= 3.5) {
      rating = 'ممتاز 🌟';
    } else if (gpa >= 3.0) {
      rating = 'جيد جداً 👍';
    } else if (gpa >= 2.5) {
      rating = 'جيد 👌';
    } else if (gpa >= 2.0) {
      rating = 'مقبول ⚠️';
    } else {
      rating = 'إنذار أكاديمي 🚨';
    }

    buffer.writeln('\n──────────────────');
    buffer.writeln('📚 *إجمالي الساعات:* $totalHours ساعة');
    buffer.writeln('🎯 *المعدل التراكمي (GPA):* `${gpa.toStringAsFixed(2)}` / 4.00');
    buffer.writeln('🎖 *التقدير العام:* $rating');
  }

  final kb = InlineKeyboard()
    .row().add('➕ إضافة مادة جديدة', 'gpa_add')
    .row().add('🔄 تفريغ وإعادة تعيين', 'gpa_reset')
    .row().add(S.get('btn_back', lang), 'student_tools_beta');

  if (isEdit && ctx.callbackQuery != null) {
    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  } else {
    await ctx.reply(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  }
}
