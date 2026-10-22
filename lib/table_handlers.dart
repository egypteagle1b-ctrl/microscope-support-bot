import 'package:televerse/televerse.dart';
import 'firebase_db.dart';
import 'utils.dart';

void registerTableHandlers(Bot bot) {
  bot.hears(RegExp(r'^/table', caseSensitive: false), (ctx) async {
    print('Command /table triggered by user!');
    final userId = ctx.from?.id;
    if (userId == null) {
      print('userId is null!');
      return;
    }
    print('Calling _showTableDashboard for $userId');
    try {
      await _showTableDashboard(ctx, userId);
      print('_showTableDashboard completed successfully');
    } catch (e, stack) {
      print('Error in _showTableDashboard: $e');
      print(stack);
    }
  });

  bot.callbackQuery('table_dash', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.tableCreationStates.remove(userId);
    await _showTableDashboard(ctx, userId, edit: true);
  });

  bot.callbackQuery('add_table', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.tableCreationStates[userId] = {'step': 'name'};
    await ctx.editMessageText('الرجاء إدخال اسم للجدول الجديد:\n(مثلاً: جدول الفصل الدراسي الأول)', replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'table_dash'));
  });

  bot.callbackQuery(RegExp(r'^tab_track:page_(\d+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    await ctx.answerCallbackQuery();
    final page = int.parse(data.split('page_')[1]);
    final tracks = await FirebaseDb.getTracks();
    final keyboard = Utils.paginateKeyboard(tracks, page: page, prefix: 'tab_track:', backData: 'table_dash');
    await ctx.editMessageReplyMarkup(replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^tab_track:(?!page_)(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final trackNameRaw = data.replaceFirst('tab_track:', '');
    final trackName = Utils.lengthen(trackNameRaw);
    await ctx.answerCallbackQuery();

    final state = Utils.tableCreationStates[userId];
    if (state == null) return;
    
    if (!state.containsKey('track')) {
      state['track'] = trackName;
    }
    state['current_track'] = trackName;
    state['step'] = 'subjects';
    if (state['subjects_with_tracks'] == null) {
      state['subjects_with_tracks'] = <String>[];
    }

    await _showSubjectsSelection(ctx, userId, trackName, 0);
  });

  bot.callbackQuery(RegExp(r'^tab_subj:page_(\d+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    await ctx.answerCallbackQuery();
    final state = Utils.tableCreationStates[userId];
    if (state == null) return;
    
    final page = int.parse(data.split('page_')[1]);
    final currentTrack = state['current_track'] as String? ?? state['track'] as String;
    await _showSubjectsSelection(ctx, userId, currentTrack, page);
  });

  bot.callbackQuery(RegExp(r'^tab_subj:(?!page_)(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final subjRaw = data.replaceFirst('tab_subj:', '');
    final subj = Utils.lengthen(subjRaw);
    await ctx.answerCallbackQuery();

    final state = Utils.tableCreationStates[userId];
    if (state == null) return;

    final currentTrack = state['current_track'] as String? ?? state['track'] as String;
    final subjWithTrack = '$currentTrack|$subj';

    List<String> selected = (state['subjects_with_tracks'] as List<String>?) ?? [];
    if (selected.contains(subjWithTrack)) {
      selected.remove(subjWithTrack);
    } else {
      selected.add(subjWithTrack);
    }
    state['subjects_with_tracks'] = selected;

    final page = state['current_page'] ?? 0;
    await _showSubjectsSelection(ctx, userId, currentTrack, page);
  });

  bot.callbackQuery('tab_back_to_tracks', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    
    final state = Utils.tableCreationStates[userId];
    if (state == null) return;
    
    state['step'] = 'track';
    
    final tracks = await FirebaseDb.getTracks();
    final keyboard = Utils.paginateKeyboard(tracks, page: 0, prefix: 'tab_track:', backData: 'table_dash');
    await ctx.editMessageText('اختر الفرقة الدراسية (Track) التي تريد إضافة مواد منها:', replyMarkup: keyboard);
  });

  bot.callbackQuery('tab_done', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    
    final state = Utils.tableCreationStates[userId];
    if (state == null) {
      await ctx.answerCallbackQuery();
      return;
    }
    
    final subjectsWithTracks = (state['subjects_with_tracks'] as List<String>?) ?? [];
    if (subjectsWithTracks.isEmpty) {
      await ctx.answerCallbackQuery(text: 'الرجاء اختيار مادة واحدة على الأقل!', showAlert: true);
      return;
    }

    await ctx.answerCallbackQuery(text: 'جاري الحفظ...');
    final name = state['name'] ?? 'بدون اسم';
    final track = state['track'] ?? '';
    
    await FirebaseDb.saveTable(userId, name, track, subjectsWithTracks);
    Utils.tableCreationStates.remove(userId);
    
    await ctx.editMessageText('تم حفظ الجدول "$name" بنجاح وتم تفعيل الإشعارات للمواد المحددة. ✅');
    await _showTableDashboard(ctx, userId, edit: false);
  });

  bot.callbackQuery('view_tables', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final tables = await FirebaseDb.getTables(userId);
    if (tables.isEmpty) {
      await ctx.editMessageText('لا يوجد جداول محفوظة لديك.', replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'table_dash'));
      return;
    }

    final kb = InlineKeyboard();
    tables.forEach((tableName, data) {
      kb.row().add('📅 $tableName', 'vt:${Utils.shorten(tableName)}');
    });
    kb.row().add('🔙 رجوع', 'table_dash');

    await ctx.editMessageText('اختر الجدول لعرض تفاصيله:', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^vt:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final tableNameRaw = data.replaceFirst('vt:', '');
    final tableName = Utils.lengthen(tableNameRaw);
    await ctx.answerCallbackQuery();

    final tables = await FirebaseDb.getTables(userId);
    if (!tables.containsKey(tableName)) return;

    final track = tables[tableName]['track'] ?? '';
    final subjectsWithTracks = (tables[tableName]['subjects_with_tracks'] as List<dynamic>?)?.cast<String>();
    final subjects = (tables[tableName]['subjects'] as List<dynamic>?)?.cast<String>() ?? [];

    final kb = InlineKeyboard();
    if (subjectsWithTracks != null) {
      for (var s in subjectsWithTracks) {
        if (s.contains('|')) {
          final parts = s.split('|');
          final t = parts[0];
          final sub = parts[1];
          kb.row().add('📚 $sub', 'subj:${Utils.shorten(t)}:${Utils.shorten(sub)}');
        } else {
          kb.row().add('📚 $s', 'subj:${Utils.shorten(track)}:${Utils.shorten(s)}');
        }
      }
    } else {
      for (var s in subjects) {
        kb.row().add('📚 $s', 'subj:${Utils.shorten(track)}:${Utils.shorten(s)}');
      }
    }
    kb.row().add('🗑 مسح الجدول', 'del_table:${Utils.shorten(tableName)}');
    kb.row().add('🔙 رجوع لجداولك', 'view_tables');

    await ctx.editMessageText('جدول: $tableName\nالمواد المسجلة:', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^del_table:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final tableNameRaw = data.replaceFirst('del_table:', '');
    final tableName = Utils.lengthen(tableNameRaw);
    await ctx.answerCallbackQuery(text: 'تم حذف الجدول.');
    
    await FirebaseDb.deleteTable(userId, tableName);
    
    // go back to view tables
    final tables = await FirebaseDb.getTables(userId);
    if (tables.isEmpty) {
      await _showTableDashboard(ctx, userId, edit: true);
    } else {
      final kb = InlineKeyboard();
      tables.forEach((name, data) {
        kb.row().add('📅 $name', 'vt:${Utils.shorten(name)}');
      });
      kb.row().add('🔙 رجوع', 'table_dash');
      await ctx.editMessageText('اختر الجدول لعرض تفاصيله:', replyMarkup: kb);
    }
  });

  bot.callbackQuery('del_all_tables', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery(text: 'تم حذف جميع الجداول.');
    await FirebaseDb.deleteAllTables(userId);
    await _showTableDashboard(ctx, userId, edit: true);
  });

  bot.callbackQuery('tab_recent_updates', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery(text: 'جاري جلب أحدث التحديثات...');

    final tables = await FirebaseDb.getTables(userId);
    if (tables.isEmpty) {
      await ctx.editMessageText(
        'ليس لديك أي جداول مسجلة بعد.\nقم بإنشاء جدول أولاً لاختيار المواد التي تود متابعة تحديثاتها.',
        replyMarkup: InlineKeyboard().row().add('➕ إضافة جدول جديد', 'add_table').row().add('🔙 رجوع', 'table_dash'),
      );
      return;
    }

    final Set<String> userSubjects = {};
    tables.forEach((_, tData) {
      final swt = (tData['subjects_with_tracks'] as List<dynamic>?)?.cast<String>();
      if (swt != null) {
        for (var s in swt) {
          userSubjects.add(s.contains('|') ? s.split('|')[1] : s);
        }
      }
      final subs = (tData['subjects'] as List<dynamic>?)?.cast<String>();
      if (subs != null) {
        userSubjects.addAll(subs);
      }
    });

    final updates = await FirebaseDb.getLatestScheduleUpdates(userSubjects.toList());
    if (updates.isEmpty) {
      await ctx.editMessageText(
        '📌 لا توجد ملفات أو محاضرات جديدة مضافة لموادك المسجلة حتى الآن.',
        replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'table_dash'),
      );
      return;
    }

    final kb = InlineKeyboard();
    final buffer = StringBuffer('📢 *آخر التحديثات للمواد المسجلة في جداولك:*\n\n');
    for (int i = 0; i < updates.length && i < 8; i++) {
      final up = updates[i];
      final title = up['title'] ?? 'ملف';
      final subj = up['subject'] ?? '';
      final track = up['track'] ?? '';
      final type = up['type'] ?? '';
      final id = up['id'] ?? '';
      buffer.writeln('${i + 1}. *[$subj]* $title ($type)');
      kb.row().add(
        '📖 $title ($subj)',
        'mat:${Utils.shorten(track)}:${Utils.shorten(subj)}:${Utils.shorten(type)}:${Utils.shorten(id)}',
      );
    }
    kb.row().add('🔙 رجوع', 'table_dash');

    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery('tab_share', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final tables = await FirebaseDb.getTables(userId);
    if (tables.isEmpty) {
      await ctx.editMessageText(
        'لا يوجد لديك أي جداول حالياً لمشاركتها.',
        replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'table_dash'),
      );
      return;
    }

    final buffer = StringBuffer('📋 *بطاقة المواد الدراسية المسجلة*\n');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    tables.forEach((tName, tData) {
      buffer.writeln('📅 *جدول: $tName*');
      final swt = (tData['subjects_with_tracks'] as List<dynamic>?)?.cast<String>();
      if (swt != null && swt.isNotEmpty) {
        for (var s in swt) {
          final sub = s.contains('|') ? s.split('|')[1] : s;
          buffer.writeln('  ▫️ $sub');
        }
      } else {
        final subs = (tData['subjects'] as List<dynamic>?)?.cast<String>() ?? [];
        for (var s in subs) {
          buffer.writeln('  ▫️ $s');
        }
      }
      buffer.writeln('');
    });
    buffer.writeln('💡 يمكنك متابعة وتعديل جدولك دائماً عبر بوت التيليجرام.');

    final kb = InlineKeyboard().row().add('🔙 رجوع', 'table_dash');
    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  });
}

Future<void> handleTableText(Context ctx, Bot bot) async {
  final userId = ctx.from?.id;
  if (userId == null) return;
  final state = Utils.tableCreationStates[userId];
  if (state == null) return;

  final text = ctx.message?.text ?? '';
  if (text.startsWith('/')) return;

  if (state['step'] == 'name') {
    state['name'] = text;
    state['step'] = 'track';
    
    final tracks = await FirebaseDb.getTracks();
    if (tracks.isEmpty) {
      await ctx.reply('لا يوجد فرق دراسية متاحة حالياً.');
      Utils.tableCreationStates.remove(userId);
      return;
    }
    
    final keyboard = Utils.paginateKeyboard(tracks, page: 0, prefix: 'tab_track:', backData: 'table_dash');
    await ctx.reply('تم حفظ الاسم: $text\n\nاختر الفرقة الدراسية (Track) لتبدأ إضافة المواد:', replyMarkup: keyboard);
  }
}

Future<void> _showTableDashboard(Context ctx, int userId, {bool edit = false}) async {
  final kb = InlineKeyboard()
    .row().add('➕ إضافة جدول جديد', 'add_table')
    .row().add('📋 عرض جداولي', 'view_tables')
    .row().add('📢 آخر التحديثات لموادي', 'tab_recent_updates')
    .row().add('📤 مشاركة بطاقة الجداول', 'tab_share')
    .row().add('🗑 مسح جميع الجداول', 'del_all_tables');

  final msg = '📚 إدارة الجداول الدراسية\n\nأهلاً بك! يمكنك هنا إنشاء جدول بالمواد التي تدرسها هذا الترم لمتابعة أحدث المحاضرات والملخصات والوصول السريع إليها.';
  
  if (edit && ctx.callbackQuery != null) {
    await ctx.editMessageText(msg, replyMarkup: kb);
  } else {
    await ctx.reply(msg, replyMarkup: kb);
  }
}

Future<void> _showSubjectsSelection(Context ctx, int userId, String trackName, int page) async {
  final state = Utils.tableCreationStates[userId];
  if (state == null) return;
  state['current_page'] = page;

  final subjects = await FirebaseDb.getSubjects(trackName);
  if (subjects.isEmpty) {
    await ctx.editMessageText('لا توجد مواد في هذه الفرقة.', replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'table_dash'));
    return;
  }

  List<String> selectedWithTracks = (state['subjects_with_tracks'] as List<String>?) ?? [];
  List<String> selectedSubjects = selectedWithTracks
      .where((s) => s.startsWith('$trackName|'))
      .map((s) => s.split('|')[1])
      .toList();

  final kb = Utils.paginateMultiSelectKeyboard(
    subjects,
    selectedSubjects,
    page: page,
    itemsPerPage: 7,
    togglePrefix: 'tab_subj:',
    doneData: 'tab_done',
    backData: 'tab_back_to_tracks',
  );

  await ctx.editMessageText('المواد المتاحة في $trackName:\n(اختر المواد المطلوبة ثم اضغط ✅ Done)', replyMarkup: kb);
}
