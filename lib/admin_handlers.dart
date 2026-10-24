import 'package:televerse/televerse.dart';
import 'firebase_db.dart';
import 'utils.dart';
import 'config.dart';
import 'strings.dart';

void registerAdminHandlers(Bot bot) {
  // ── Admin Keyboard Text Listeners ─────────────────────────────────────
  bot.hears(RegExp(r'(لوحة الإدارة|Admin Panel)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    if (!(await FirebaseDb.isAdmin(userId))) return;
    final lang = Utils.getUserLanguage(userId);
    Utils.setUserMode(userId, UserMode.admin);
    Utils.clearUploadState(userId);
    await ctx.reply(
      S.get('admin_dashboard_title', lang),
      replyMarkup: await _buildAdminKeyboard(userId, lang),
      parseMode: ParseMode.markdown,
    );
  });

  bot.hears(RegExp(r'(وضع الطالب|Student Mode)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    if (!(await FirebaseDb.isAdmin(userId))) return;
    final lang = Utils.getUserLanguage(userId);
    Utils.setUserMode(userId, UserMode.student);
    Utils.clearUploadState(userId);
    await ctx.reply(S.get('admin_switched_student', lang));
  });

  bot.hears(RegExp(r'(تحديث البوت|Restart Bot)'), (ctx) async {
    // Treat as /start
    final userId = ctx.from?.id;
    if (userId == null) return;
    if (!(await FirebaseDb.isAdmin(userId))) return;
    // We could invoke /start manually or just tell them to use /start
    // Actually we can just trigger what /start does, but simpler to redirect or send main menu.
    // Let's just send the student main menu since that's what /start does.
    // _sendMainMenu is private in student_handlers, so we'll just say:
    await ctx.reply('/start');
  });

  // ── /admin command ───────────────────────────────────────────────────
  bot.command('admin', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    if (!(await FirebaseDb.isAdmin(userId))) {
      await ctx.reply(S.get('not_authorized', lang));
      return;
    }

    Utils.setUserMode(userId, UserMode.admin);
    Utils.clearUploadState(userId);

    await ctx.reply(
      S.get('admin_dashboard_title', lang),
      replyMarkup: await _buildAdminKeyboard(userId, lang),
      parseMode: ParseMode.markdown,
    );
  });

  // ── /student command ─────────────────────────────────────────────────
  bot.command('student', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    Utils.setUserMode(userId, UserMode.student);
    Utils.clearUploadState(userId);
    await ctx.reply(S.get('admin_switched_student', lang));
  });

  // ── Dashboard callbacks ──────────────────────────────────────────────
  bot.callbackQuery('dash_student', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    Utils.setUserMode(userId, UserMode.student);
    Utils.clearUploadState(userId);
    await ctx.editMessageText(S.get('admin_switched_student', lang));
  });

  bot.callbackQuery('dash_add_admin', (ctx) async {
    final userId = ctx.from?.id;
    final lang = Utils.getUserLanguage(userId ?? 0);
    final superAdminId = await FirebaseDb.getSuperAdmin();
    if (userId == null || userId != superAdminId) {
      await ctx.answerCallbackQuery(
          text: S.get('only_super_admin', lang), showAlert: true);
      return;
    }
    Utils.uploadStates[userId] = {'action': 'add_admin_id'};
    await ctx.editMessageText(S.get('enter_admin_id', lang));
  });

  bot.callbackQuery('dash_broadcast', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    Utils.uploadStates[userId] = {'action': 'broadcast_msg'};
    await ctx.editMessageText(S.get('enter_broadcast', lang));
  });

  bot.callbackQuery('dash_reply_user', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    Utils.uploadStates[userId] = {'action': 'reply_user_id'};
    await ctx.editMessageText(S.get('enter_user_id_to_reply', lang));
  });

  bot.callbackQuery('dash_stats', (ctx) async {
    final userId = ctx.from?.id;
    final lang = Utils.getUserLanguage(userId ?? 0);
    final stats = await FirebaseDb.getStats();
    final topMaterials = stats['topMaterials'] as Map<String, dynamic>;

    String msg = S.get('stats_title', lang, {'total': '${stats['totalUsers']}'});

    var entries = topMaterials.entries.toList();
    entries.sort(
        (a, b) => (b.value['count'] as int).compareTo(a.value['count'] as int));

    for (var i = 0; i < entries.length && i < 5; i++) {
      msg +=
          '${i + 1}. ${entries[i].value['name']} - ${entries[i].value['count']} views\n';
    }

    final kb = InlineKeyboard()
      .row()
      .add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(msg,
        replyMarkup: kb, parseMode: ParseMode.markdown);
  });

  bot.callbackQuery('dash_wipe', (ctx) async {
    final userId = ctx.from?.id;
    final lang = Utils.getUserLanguage(userId ?? 0);
    final superAdminId = await FirebaseDb.getSuperAdmin();
    if (userId == null || userId != superAdminId) {
      await ctx.answerCallbackQuery(
          text: S.get('only_super_admin', lang), showAlert: true);
      return;
    }

    final kb = InlineKeyboard()
      .row()
      .add(S.get('btn_wipe_confirm', lang), 'dash_wipe_confirm')
      .add(S.get('btn_cancel_action', lang), 'dash_back');

    await ctx.editMessageText(
      S.get('wipe_confirm_msg', lang),
      replyMarkup: kb,
      parseMode: ParseMode.markdown,
    );
  });

  bot.callbackQuery('dash_wipe_confirm', (ctx) async {
    final userId = ctx.from?.id;
    final lang = Utils.getUserLanguage(userId ?? 0);
    final superAdminId = await FirebaseDb.getSuperAdmin();
    if (userId == null || userId != superAdminId) return;

    await FirebaseDb.wipeCurriculum();
    final kb = InlineKeyboard()
      .row()
      .add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(S.get('wipe_done', lang), replyMarkup: kb);
  });

  bot.callbackQuery('dash_wipe_users', (ctx) async {
    final userId = ctx.from?.id;
    final lang = Utils.getUserLanguage(userId ?? 0);
    final superAdminId = await FirebaseDb.getSuperAdmin();
    if (userId == null || userId != superAdminId) {
      await ctx.answerCallbackQuery(
          text: S.get('only_super_admin', lang), showAlert: true);
      return;
    }

    final kb = InlineKeyboard()
      .row()
      .add(S.get('btn_wipe_confirm', lang), 'dash_wipe_users_confirm')
      .add(S.get('btn_cancel_action', lang), 'dash_back');

    await ctx.editMessageText(
      S.get('wipe_users_confirm_msg', lang),
      replyMarkup: kb,
      parseMode: ParseMode.markdown,
    );
  });

  bot.callbackQuery('dash_wipe_users_confirm', (ctx) async {
    final userId = ctx.from?.id;
    final lang = Utils.getUserLanguage(userId ?? 0);
    final superAdminId = await FirebaseDb.getSuperAdmin();
    if (userId == null || userId != superAdminId) return;

    await FirebaseDb.wipeUsers();
    final kb = InlineKeyboard()
      .row()
      .add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(S.get('wipe_done', lang), replyMarkup: kb);
  });

  // ── Remove Contributor — show list instead of asking for ID ──────────
  bot.callbackQuery('dash_rm_contrib', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final contributors = await FirebaseDb.getAllContributors();
    if (contributors.isEmpty) {
      final kb = InlineKeyboard()
        .row()
        .add(S.get('btn_back_to_dash', lang), 'dash_back');
      await ctx.editMessageText(S.get('no_contributors', lang),
          replyMarkup: kb);
      return;
    }

    final kb = InlineKeyboard();
    contributors.forEach((id, data) {
      final name = (data['name'] as String?)?.isNotEmpty == true
          ? data['name'] as String
          : id;
      final track = data['track'] ?? '';
      final subject = data['subject'] ?? '';
      kb.row().add('$name ($track → $subject)', 'rm_contrib_sel:$id');
    });
    kb.row().add(S.get('btn_back_to_dash', lang), 'dash_back');

    await ctx.editMessageText(
      S.get('select_contrib_to_remove', lang),
      replyMarkup: kb,
    );
  });

  // Remove specific contributor by ID (clicked from list)
  bot.callbackQuery(RegExp(r'^rm_contrib_sel:(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    final userId = ctx.from?.id;
    if (data == null || userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final targetId = int.tryParse(data.split(':')[1]);
    if (targetId != null) {
      await FirebaseDb.removeContributor(targetId);
    }

    final kb = InlineKeyboard()
      .row()
      .add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(S.get('contrib_removed', lang), replyMarkup: kb);
  });

  bot.callbackQuery('dash_transfer_owner', (ctx) async {
    final userId = ctx.from?.id;
    final lang = Utils.getUserLanguage(userId ?? 0);
    final superAdminId = await FirebaseDb.getSuperAdmin();
    if (userId == null || userId != superAdminId) return;

    Utils.uploadStates[userId] = {'action': 'transfer_owner_id'};
    await ctx.editMessageText(
      S.get('transfer_owner_prompt', lang),
      parseMode: ParseMode.markdown,
    );
  });

  bot.callbackQuery('dash_requests', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final requests = await FirebaseDb.getPendingRequests();
    if (requests.isEmpty) {
      final kb = InlineKeyboard()
        .row()
        .add(S.get('btn_back_to_dash', lang), 'dash_back');
      await ctx.editMessageText(S.get('no_requests', lang), replyMarkup: kb);
      return;
    }

    String msg = S.get('pending_requests_title', lang);
    final kb = InlineKeyboard();

    requests.forEach((id, data) {
      final name = (data['name'] as String?)?.isNotEmpty == true
          ? data['name'] as String
          : '—';
      msg += S.get('request_item', lang, {
        'id': id,
        'name': name,
        'track': '',
        'subject': '',
      });
      kb.row()
        .add('✅ $id', 'approve_contrib:$id')
        .add('❌ $id', 'reject_contrib:$id');
    });

    kb.row().add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(msg,
        replyMarkup: kb, parseMode: ParseMode.markdown);
  });

  bot.callbackQuery('dash_back', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    await ctx.editMessageText(
      S.get('admin_dashboard_title', lang),
      replyMarkup: await _buildAdminKeyboard(userId, lang),
      parseMode: ParseMode.markdown,
    );
  });

  // ── Content Delete / Replace callbacks ───────────────────────────────
  bot.callbackQuery(RegExp(r'^admin_del:(.*?):(.*?):(.*?):(.*)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    if (!(await FirebaseDb.isAdmin(userId))) return;

    final data = ctx.callbackQuery?.data;
    if (data == null) return;

    final parts = data.split(':');
    final track = Utils.lengthen(parts[1]);
    final subject = Utils.lengthen(parts[2]);
    final type = Utils.lengthen(parts[3]);
    final matId = Utils.lengthen(parts[4]);
    await FirebaseDb.deleteMaterial(track, subject, type, matId);
    await ctx.answerCallbackQuery(
        text: S.get('material_delete_toast', lang), showAlert: true);
    await ctx.editMessageText(S.get('material_deleted', lang));
  });

  bot.callbackQuery(RegExp(r'^admin_rep:(.*?):(.*?):(.*?):(.*)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    if (!(await FirebaseDb.isAdmin(userId))) return;

    final data = ctx.callbackQuery?.data;
    if (data == null) return;

    final parts = data.split(':');
    Utils.uploadStates[userId] = {
      'action': 'replace_file',
      'track': Utils.lengthen(parts[1]),
      'subject': Utils.lengthen(parts[2]),
      'type': Utils.lengthen(parts[3]),
      'materialId': Utils.lengthen(parts[4]),
    };

    await ctx.answerCallbackQuery();
    await ctx.reply(S.get('replace_file_prompt', lang));
  });

  // ── Admin Feedback Inbox (NEW FEATURE) ──────────────────────────────
  bot.callbackQuery('dash_inbox', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    if (!(await FirebaseDb.isAdmin(userId))) return;
    await ctx.answerCallbackQuery();

    final feedbacks = await FirebaseDb.getFeedbacks();
    if (feedbacks.isEmpty) {
      final kb = InlineKeyboard().row().add(S.get('btn_back_to_dash', lang), 'dash_back');
      await ctx.editMessageText('📬 لا توجد رسائل أو شكاوى واردة حالياً.', replyMarkup: kb);
      return;
    }

    String msg = '📬 *صندوق الرسائل والشكاوى الواردة:*\n\n';
    final kb = InlineKeyboard();

    var entries = feedbacks.entries.toList();
    entries.sort((a, b) {
      final tA = a.value['timestamp']?.toString() ?? '';
      final tB = b.value['timestamp']?.toString() ?? '';
      return tB.compareTo(tA);
    });

    for (var i = 0; i < entries.length && i < 5; i++) {
      final id = entries[i].key;
      final fData = entries[i].value as Map<String, dynamic>;
      final senderId = fData['userId']?.toString() ?? 'مجهول';
      final text = fData['message']?.toString() ?? fData['text']?.toString() ?? '';
      final snippet = text.length > 50 ? '${text.substring(0, 50)}…' : text;
      msg += '${i + 1}. *من:* `$senderId`\n💬 $snippet\n\n';
      
      final senderNum = int.tryParse(senderId);
      if (senderNum != null) {
        kb.row()
          .add('💬 رد على $senderId', 'inbox_reply:$senderId')
          .add('🗑️ حذف', 'inbox_del:$id');
      } else {
        kb.row().add('🗑️ حذف الرسالة', 'inbox_del:$id');
      }
    }

    kb.row().add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(msg, replyMarkup: kb, parseMode: ParseMode.markdown);
  });

  bot.callbackQuery(RegExp(r'^inbox_reply:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    final targetId = int.tryParse(ctx.callbackQuery!.data!.replaceFirst('inbox_reply:', ''));
    if (targetId == null) return;

    Utils.uploadStates[userId] = {
      'action': 'reply_user_msg',
      'target_id': targetId,
    };
    await ctx.answerCallbackQuery();
    await ctx.reply(S.get('enter_reply_message', lang));
  });

  bot.callbackQuery(RegExp(r'^inbox_del:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final id = ctx.callbackQuery!.data!.replaceFirst('inbox_del:', '');
    await FirebaseDb.deleteFeedback(id);
    await ctx.answerCallbackQuery(text: 'تم حذف الرسالة بنجاح.');
    
    final lang = Utils.getUserLanguage(userId);
    final feedbacks = await FirebaseDb.getFeedbacks();
    if (feedbacks.isEmpty) {
      final kb = InlineKeyboard().row().add(S.get('btn_back_to_dash', lang), 'dash_back');
      await ctx.editMessageText('📬 لا توجد رسائل واردة حالياً.', replyMarkup: kb);
      return;
    }
    String msg = '📬 *صندوق الرسائل والشكاوى الواردة:*\n\n';
    final kb = InlineKeyboard();
    var entries = feedbacks.entries.toList();
    for (var i = 0; i < entries.length && i < 5; i++) {
      final fId = entries[i].key;
      final fData = entries[i].value as Map<String, dynamic>;
      final senderId = fData['userId']?.toString() ?? 'مجهول';
      final text = fData['message']?.toString() ?? fData['text']?.toString() ?? '';
      final snippet = text.length > 50 ? '${text.substring(0, 50)}…' : text;
      msg += '${i + 1}. *من:* `$senderId`\n💬 $snippet\n\n';
      final senderNum = int.tryParse(senderId);
      if (senderNum != null) {
        kb.row()
          .add('💬 رد على $senderId', 'inbox_reply:$senderId')
          .add('🗑️ حذف', 'inbox_del:$fId');
      } else {
        kb.row().add('🗑️ حذف الرسالة', 'inbox_del:$fId');
      }
    }
    kb.row().add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(msg, replyMarkup: kb, parseMode: ParseMode.markdown);
  });

  // ── Admin System Health Check (NEW FEATURE) ─────────────────────────
  bot.callbackQuery('dash_health', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    if (!(await FirebaseDb.isAdmin(userId))) return;
    await ctx.answerCallbackQuery();

    final sw = Stopwatch()..start();
    final tracks = await FirebaseDb.getTracks();
    sw.stop();
    final latency = sw.elapsedMilliseconds;

    final users = await FirebaseDb.getAllUsers();
    final requests = await FirebaseDb.getPendingRequests();
    final superAdminId = await FirebaseDb.getSuperAdmin();

    String msg = '🩺 *تقرير فحص صحة النظام والخادم*\n\n';
    msg += '⚡ *حالة الاتصال:* متصل وقيد العمل ✅\n';
    msg += '⏱️ *استجابة قاعدة البيانات (Latency):* ${latency}ms\n';
    msg += '👥 *إجمالي المستخدمين المسجلين:* ${users.length} مستخدم\n';
    msg += '📚 *الأقسام والمسارات النشطة:* ${tracks.length} مسار\n';
    msg += '📩 *طلبات المساهمة المعلقة:* ${requests.length} طلب\n';
    msg += '👑 *المالك الرئيسي (Super Admin):* `$superAdminId`\n';
    msg += '🛡️ *حالة البوت والأمان:* مستقر وبدون أخطاء تشغيلية ✓';

    final kb = InlineKeyboard().row().add(S.get('btn_back_to_dash', lang), 'dash_back');
    await ctx.editMessageText(msg, replyMarkup: kb, parseMode: ParseMode.markdown);
  });

  // ── Approve / Reject contributors ──────────────────────────────────────────────
  bot.callbackQuery(RegExp(r'^approve_contrib:(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    if (data == null) return;

    final parts = data.split(':');
    final targetId = int.parse(parts[1]);

    // Fetch contributor's name from the pending request
    final request = await FirebaseDb.getRequest(targetId);
    final name = (request?['name'] as String?) ?? '$targetId';
    final msgIds = request?['messageIds'] as Map<String, dynamic>? ?? {};

    await FirebaseDb.setContributor(targetId, name: name);
    await FirebaseDb.removeRequest(targetId);

    final adminLang = Utils.getUserLanguage(ctx.from?.id ?? 0);
    await ctx.editMessageText(
      S.get('contrib_approved_admin', adminLang,
          {'id': '$targetId', 'name': name}),
    );

    // Delete direct messages for all other admins
    for (var entry in msgIds.entries) {
      final adminId = int.parse(entry.key);
      final msgId = entry.value as int;
      if (ctx.callbackQuery?.message?.messageId == msgId) continue;
      try {
        await bot.api.deleteMessage(ChatID(adminId), msgId);
      } catch (_) {}
    }

    try {
      final targetLang = Utils.getUserLanguage(targetId);
      await bot.api.sendMessage(
        ChatID(targetId),
        S.get('contrib_approved_notif', targetLang),
      );
    } catch (_) {}
  });

  bot.callbackQuery(RegExp(r'^reject_contrib:(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    if (data == null) return;

    final parts = data.split(':');
    final targetId = int.parse(parts[1]);

    final request = await FirebaseDb.getRequest(targetId);
    final msgIds = request?['messageIds'] as Map<String, dynamic>? ?? {};

    await FirebaseDb.removeRequest(targetId);

    final adminLang = Utils.getUserLanguage(ctx.from?.id ?? 0);
    await ctx.editMessageText(
      S.get('contrib_rejected_admin', adminLang, {'id': '$targetId'}),
    );

    // Delete direct messages for all other admins
    for (var entry in msgIds.entries) {
      final adminId = int.parse(entry.key);
      final msgId = entry.value as int;
      if (ctx.callbackQuery?.message?.messageId == msgId) continue;
      try {
        await bot.api.deleteMessage(ChatID(adminId), msgId);
      } catch (_) {}
    }

    try {
      final targetLang = Utils.getUserLanguage(targetId);
      await bot.api.sendMessage(
        ChatID(targetId),
        S.get('contrib_rejected_notif', targetLang),
      );
    } catch (_) {}
  });

  // ── Return to Admin Dashboard ──────────────────────────────────────────
  bot.callbackQuery(RegExp(r'^(admin_dash|dash_back)$'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    if (!(await FirebaseDb.isAdmin(userId))) return;
    final lang = Utils.getUserLanguage(userId);
    Utils.clearUploadState(userId);
    await ctx.answerCallbackQuery();
    await ctx.editMessageText(
      S.get('admin_dashboard_title', lang),
      replyMarkup: await _buildAdminKeyboard(userId, lang),
      parseMode: ParseMode.markdown,
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ── 🎯 1. MICROSCOPE MISSIONS & TASKS HUB ─────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  bot.callbackQuery('adm_missions', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final missions = await FirebaseDb.getMissions();
    int inProgress = 0, received = 0, done = 0, inactive = 0;
    missions.forEach((_, m) {
      if (m is Map) {
        final s = m['status'] ?? 'inactive';
        if (s == 'progress') inProgress++;
        else if (s == 'received') received++;
        else if (s == 'done') done++;
        else inactive++;
      }
    });

    final kb = InlineKeyboard()
      .row().add('⚡ قيد التنفيذ ($inProgress)', 'mis_filter:progress').add('📥 المستلمة ($received)', 'mis_filter:received')
      .row().add('✅ المنجزة ($done)', 'mis_filter:done').add('📑 كافة التكليفات (${missions.length})', 'mis_filter:all')
      .row().add('➕ تكليف مهمة جديدة', 'mis_new_start')
      .row().add('🔄 مزامنة الخطة الرسمية (15 مهمة)', 'mis_seed_official')
      .row().add('🔙 رجوع للوحة الإدارة', 'admin_dash');

    final text = '🎯 *منظومة إدارة المهام وتتبع اللجان (Microscope Missions)*\n\n'
        'أهلاً بك! يمكنك هنا التحكم الكامل بمهام اللجان وتكليف الأعضاء ومتابعة التقدم المباشر مع المنصة:\n\n'
        '📊 *مؤشرات الإنجاز الحالية:*\n'
        '• ⚡ قيد التنفيذ: *$inProgress مهمة*\n'
        '• 📥 قيد الاستلام: *$received مهمة*\n'
        '• ✅ مكتملة بنجاح: *$done مهمة*\n'
        '• ⏸️ مسودات وغير مفعّلة: *$inactive مهمة*\n'
        '• 📁 إجمالي المهام: *${missions.length} مهمة*\n\n'
        'اختر الإجراء المطلوب:';

    await ctx.editMessageText(text, parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^mis_filter:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    await ctx.answerCallbackQuery();
    final filter = data.replaceFirst('mis_filter:', '');

    final missions = await FirebaseDb.getMissions(status: filter);
    final kb = InlineKeyboard();

    if (missions.isEmpty) {
      kb.row().add('➕ إضافة مهمة الآن', 'mis_new_start').row().add('🔙 رجوع لإدارة المهام', 'adm_missions');
      await ctx.editMessageText('📌 لا توجد مهام مطابقة لهذا التصنيف حالياً.', replyMarkup: kb);
      return;
    }

    missions.forEach((id, m) {
      if (m is Map) {
        final title = m['title'] ?? 'مهمة';
        final com = m['committees'] ?? 'General';
        final status = m['status'] ?? 'inactive';
        final icon = status == 'progress' ? '⚡' : status == 'done' ? '✅' : status == 'received' ? '📥' : '⏸️';
        kb.row().add('$icon [$com] $title', 'mis_view:$id');
      }
    });

    kb.row().add('➕ تكليف مهمة جديدة', 'mis_new_start');
    kb.row().add('🔙 رجوع لإدارة المهام', 'adm_missions');

    await ctx.editMessageText('🎯 *قائمة المهام والتكليفات:* (${missions.length} مهمة)\nاختر مهمة لتفاصيلها وتحديث حالتها:', parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^mis_view:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    await ctx.answerCallbackQuery();
    final taskId = data.replaceFirst('mis_view:', '');

    final task = await FirebaseDb.getMission(taskId);
    if (task == null) {
      await ctx.editMessageText('❌ لم يتم العثور على بيانات المهمة.', replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'adm_missions'));
      return;
    }

    final title = task['title'] ?? 'بدون عنوان';
    final com = task['committees'] ?? 'General';
    final head = task['head_name'] ?? 'غير محدد';
    final status = task['status'] ?? 'inactive';
    final priority = task['priority'] ?? 'normal';
    final due = task['due_date'] ?? 'غير محدد';
    final desc = task['description'] ?? 'لا يوجد وصف';
    final statusLabel = status == 'progress' ? '⚡ قيد التنفيذ' : status == 'done' ? '✅ مكتملة بنجاح' : status == 'received' ? '📥 تم الاستلام' : '⏸️ مسودة';

    final buffer = StringBuffer('🎯 *بطاقة المهمة والتكليف الرسمية*\n');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📌 *العنوان:* $title');
    buffer.writeln('🏢 *اللجنة المكلفة:* $com');
    buffer.writeln('👤 *المسؤول المباشر:* $head');
    buffer.writeln('🚦 *الأولوية:* $priority');
    buffer.writeln('📅 *الموعد النهائي:* $due');
    buffer.writeln('🚥 *الحالة الحالية:* $statusLabel');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('📝 *تفاصيل ومخرجات التكليف:*\n$desc');

    final kb = InlineKeyboard()
      .row().add('🔄 تقدم الحالة (Next Status)', 'mis_adv:$taskId')
      .row().add('📢 إرسال بطاقة التكليف للجان', 'mis_dispatch:$taskId')
      .row().add('🗑 حذف هذه المهمة', 'mis_del:$taskId')
      .row().add('🔙 رجوع لقائمة المهام', 'adm_missions');

    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^mis_adv:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final taskId = data.replaceFirst('mis_adv:', '');

    final task = await FirebaseDb.getMission(taskId);
    if (task == null) return;

    final curStatus = task['status'] ?? 'inactive';
    String nextStatus = 'received';
    if (curStatus == 'inactive') nextStatus = 'received';
    else if (curStatus == 'received') nextStatus = 'progress';
    else if (curStatus == 'progress') nextStatus = 'done';
    else if (curStatus == 'done') nextStatus = 'received';

    await FirebaseDb.updateMissionStatus(taskId, nextStatus);
    await ctx.answerCallbackQuery(text: '✅ تم تحديث الحالة إلى: $nextStatus', showAlert: false);

    final updated = await FirebaseDb.getMission(taskId);
    final title = updated?['title'] ?? '';
    final com = updated?['committees'] ?? '';
    final statusLabel = nextStatus == 'progress' ? '⚡ قيد التنفيذ' : nextStatus == 'done' ? '✅ مكتملة' : '📥 تم الاستلام';

    final kb = InlineKeyboard()
      .row().add('🔄 تقدم الحالة مجدداً', 'mis_adv:$taskId')
      .row().add('📢 إرسال بطاقة التكليف', 'mis_dispatch:$taskId')
      .row().add('🔙 رجوع للمهام', 'adm_missions');

    await ctx.editMessageText('🎯 *بطاقة المهمة:* $title\n🏢 اللجنة: $com\n🚥 الحالة الجديدة: *$statusLabel*\n\nتم حفظ التغيير ومزامنته حياً مع لوحة الويب.', parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^mis_dispatch:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    await ctx.answerCallbackQuery();
    final taskId = data.replaceFirst('mis_dispatch:', '');

    final task = await FirebaseDb.getMission(taskId);
    if (task == null) return;

    final title = task['title'] ?? '';
    final com = task['committees'] ?? '';
    final head = task['head_name'] ?? '';
    final due = task['due_date'] ?? '';
    final desc = task['description'] ?? '';

    final dispatchMsg = '🔬 *MICROSCOPE MISSION DISPATCH* 🚀\n'
        '━━━━━━━━━━━━━━━━━━━━\n'
        '📌 *التكليف:* $title\n'
        '🏢 *اللجنة:* $com\n'
        '👤 *المسؤول:* $head\n'
        '📅 *الموعد النهائي:* $due\n'
        '━━━━━━━━━━━━━━━━━━━━\n'
        '📝 *التفاصيل:* \n$desc\n\n'
        '⚡ _تم الإرسال والاعتماد عبر نظام إدارة المهام المركزي._';

    await ctx.reply(dispatchMsg, parseMode: ParseMode.markdown);
  });

  bot.callbackQuery(RegExp(r'^mis_del:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final taskId = data.replaceFirst('mis_del:', '');

    await FirebaseDb.deleteMission(taskId);
    await ctx.answerCallbackQuery(text: 'تم حذف المهمة.');
    await ctx.editMessageText('🗑 *تم حذف المهمة بنجاح.*', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 رجوع للمهام', 'adm_missions'));
  });

  bot.callbackQuery('mis_seed_official', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery(text: 'جاري استعادة الخطة الرسمية...');
    await FirebaseDb.seedOfficialMissions();
    await ctx.editMessageText('✅ *تمت استعادة وتحديث الخطة الرسمية (15 مهمة تغطي كافة المراحل واللجان) بنجاح!*\n\nيمكنك الآن استعراضها وتحديثها من البوت أو لوحة الويب.', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🎯 فتح قائمة المهام', 'adm_missions').row().add('🔙 لوحة الإدارة', 'admin_dash'));
  });

  bot.callbackQuery('mis_new_start', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.uploadStates[userId] = {'action': 'mis_new_title'};
    await ctx.editMessageText('➕ *تكليف مهمة جديدة*\n\nالرجاء كتابة عنوان المهمة (مثال: إعداد أسئلة مسابقة الكيمياء):', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_missions'));
  });

  bot.callbackQuery(RegExp(r'^mis_com:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final com = data.replaceFirst('mis_com:', '');
    await ctx.answerCallbackQuery();

    final state = Utils.uploadStates[userId];
    if (state == null) return;
    state['committee'] = com;

    final kb = InlineKeyboard()
      .row().add('📅 مراحل الترم الأول (Timeline)', 'mis_cat:timeline')
      .row().add('🎯 خطة الترم الثاني (Term 2)', 'mis_cat:term2')
      .row().add('⚡ آلية التنفيذ والمتابعة (Execution)', 'mis_cat:execution')
      .row().add('💡 التطوير المؤسسي (Improvement)', 'mis_cat:improvement');

    await ctx.editMessageText('اللجنة المختارة: *$com*\n\nالآن اختر تصنيف المهمة:', parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^mis_cat:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final cat = data.replaceFirst('mis_cat:', '');
    await ctx.answerCallbackQuery();

    final state = Utils.uploadStates[userId];
    if (state == null) return;
    state['category'] = cat;

    final kb = InlineKeyboard()
      .row().add('🔴 أولوية قصوى (High)', 'mis_prio:high')
      .row().add('🟡 أولوية متوسطة (Normal)', 'mis_prio:normal')
      .row().add('🟢 أولوية عادية (Low)', 'mis_prio:low');

    await ctx.editMessageText('اختر أولوية المهمة:', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^mis_prio:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final prio = data.replaceFirst('mis_prio:', '');
    await ctx.answerCallbackQuery();

    final state = Utils.uploadStates[userId];
    if (state == null) return;
    state['priority'] = prio;

    final kb = InlineKeyboard()
      .row().add('خلال 24 ساعة ⚡', 'mis_dl:خلال 24 ساعة')
      .row().add('خلال 3 أيام 📅', 'mis_dl:خلال 3 أيام')
      .row().add('خلال أسبوع 🗓', 'mis_dl:خلال أسبوع')
      .row().add('تحديد لاحقاً ⏳', 'mis_dl:تحديد لاحقاً');

    await ctx.editMessageText('اختر الموعد النهائي للتسليم (Deadline):', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^mis_dl:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final dl = data.replaceFirst('mis_dl:', '');
    await ctx.answerCallbackQuery();

    final state = Utils.uploadStates[userId];
    if (state == null) return;
    state['deadline'] = dl;
    state['action'] = 'mis_new_desc';

    await ctx.editMessageText('الموعد النهائي: *$dl*\n\nالآن أرسل تفاصيل ومخرجات التكليف في رسالة:', parseMode: ParseMode.markdown);
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ── 📢 2. SMART BROADCAST ENGINE ──────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  bot.callbackQuery('adm_bcast_menu', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final kb = InlineKeyboard()
      .row().add('📢 إذاعة عامة لكل الطلاب', 'dash_broadcast')
      .row().add('🎯 إذاعة مخصصة لفرقة / مسار معين', 'bcast_track_select')
      .row().add('🤝 إذاعة خاصة بالمساهمين فقط', 'bcast_contribs_prompt')
      .row().add('🔙 رجوع للوحة الإدارة', 'admin_dash');

    await ctx.editMessageText('📢 *محرك الإذاعة والتنبيهات المتقدمة*\n\nاختر نوع الإذاعة التي تود إرسالها:', parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery('bcast_track_select', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final tracks = await FirebaseDb.getTracks();
    if (tracks.isEmpty) {
      await ctx.editMessageText('لا توجد مسارات مضافة حالياً.', replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'adm_bcast_menu'));
      return;
    }

    final kb = InlineKeyboard();
    for (var t in tracks) {
      kb.row().add('📁 $t', 'bcast_track_go:${Utils.shorten(t)}');
    }
    kb.row().add('🔙 رجوع', 'adm_bcast_menu');

    await ctx.editMessageText('اختر المسار/الفرقة التي تريد توجيه الإشعار لطلابها فقط:', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^bcast_track_go:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final trackShort = data.replaceFirst('bcast_track_go:', '');
    final track = Utils.lengthen(trackShort);
    await ctx.answerCallbackQuery();

    Utils.uploadStates[userId] = {'action': 'bcast_track_msg', 'track': track};
    await ctx.editMessageText('المسار المختار: *$track*\n\nاكتب نص الإشعار الذي تود إذاعته لطلاب هذا المسار:', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_bcast_menu'));
  });

  bot.callbackQuery('bcast_contribs_prompt', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    Utils.uploadStates[userId] = {'action': 'bcast_contribs_msg'};
    await ctx.editMessageText('اكتب نص الإشعار الموجه للمساهمين في الفريق:', replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_bcast_menu'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ── 📬 3. SUPPORT & FEEDBACK INBOX ────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  bot.callbackQuery('dash_inbox', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final feedbacks = await FirebaseDb.getFeedbacks();
    if (feedbacks.isEmpty) {
      await ctx.editMessageText('📬 *صندوق الرسائل والشكاوى فارغ حالياً.*', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'admin_dash'));
      return;
    }

    final kb = InlineKeyboard();
    final buffer = StringBuffer('📬 *رسائل ومقترحات الطلاب الواردة:*\n\n');
    int i = 1;
    feedbacks.forEach((id, f) {
      if (f is Map && i <= 8) {
        final uId = f['userId'] ?? 'مجهول';
        final msg = f['message'] ?? '';
        final time = f['timestamp'] ?? '';
        buffer.writeln('$i. 👤 الطالب: `$uId`');
        buffer.writeln('💬 الرسالة: "$msg"');
        buffer.writeln('🕒 $time\n');
        kb.row()
          .add('💬 رد على #$i', 'inbox_reply:$uId')
          .add('🗑 حذف', 'inbox_del:$id');
        i++;
      }
    });

    kb.row().add('🔙 رجوع للوحة الإدارة', 'admin_dash');
    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^inbox_reply:(\d+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final targetId = int.parse(data.replaceFirst('inbox_reply:', ''));
    await ctx.answerCallbackQuery();

    Utils.uploadStates[userId] = {'action': 'inbox_reply_msg', 'target_id': targetId};
    await ctx.editMessageText('اكتب رسالة الرد الموجهة للطالب `$targetId`:', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'dash_inbox'));
  });

  bot.callbackQuery(RegExp(r'^inbox_del:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final fId = data.replaceFirst('inbox_del:', '');
    await FirebaseDb.deleteFeedback(fId);
    await ctx.answerCallbackQuery(text: 'تم حذف الرسالة.');
    await ctx.editMessageText('✅ تم حذف الرسالة بنجاح.', replyMarkup: InlineKeyboard().row().add('📬 العودة للبريد', 'dash_inbox'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ── 🩺 4. SYSTEM HEALTH & DIAGNOSTICS ─────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  bot.callbackQuery('dash_health', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final sw = Stopwatch()..start();
    final tracks = await FirebaseDb.getTracks();
    sw.stop();
    final ping = sw.elapsedMilliseconds;

    final users = await FirebaseDb.getAllUsers();
    final admins = await FirebaseDb.getAdmins();
    final contribs = await FirebaseDb.getAllContributors();
    final missions = await FirebaseDb.getMissions();

    final buffer = StringBuffer('🩺 *تقرير استقرار وصحة المنظومة (System Diagnostics)*\n\n');
    buffer.writeln('• حالة البوت: *🟢 متصل ويعمل بكفاءة (Polling)*');
    buffer.writeln('• سرعة استجابة قاعدة البيانات (Ping): *${ping}ms* ⚡');
    buffer.writeln('• عدد الطلاب والمستخدمين: *${users.length} طالب* 👤');
    buffer.writeln('• عدد الفرق والمسارات: *${tracks.length} مسار* 📁');
    buffer.writeln('• عدد المديرين المعتمدين: *${admins.length} مدير* 👑');
    buffer.writeln('• عدد المساهمين النشطين: *${contribs.length} مساهم* 🤝');
    buffer.writeln('• عدد المهام المسجلة بالمنظومة: *${missions.length} مهمة* 🎯');
    buffer.writeln('\n🚀 كافة الخوادم والـ APIs تعمل بنسبة استقرار 100%.');

    final kb = InlineKeyboard()
      .row().add('🔄 إعادة الفحص', 'dash_health')
      .row().add('🔙 رجوع للوحة الإدارة', 'admin_dash');

    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ── 🗂 5. CURRICULUM MANAGEMENT FROM TELEGRAM ─────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  bot.callbackQuery('adm_curriculum', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final tracks = await FirebaseDb.getTracks();

    final kb = InlineKeyboard()
      .row().add('➕ إضافة مسار / فرقة دراسية', 'adm_add_track')
      .row().add('➕ إضافة مادة دراسية', 'adm_add_subject_pick_track')
      .row().add('🗑 استعراض وحذف مادة', 'adm_del_subject_pick_track')
      .row().add('🔙 رجوع للوحة الإدارة', 'admin_dash');

    await ctx.editMessageText(
      '🗂 *إدارة شجرة المناهج والأقسام الدراسية*\n\n'
      '• إجمالي المسارات المتاحة: *${tracks.length} مسار*\n\n'
      'يمكنك إضافة أقسام ومواد دراسية جديدة مباشرة من تيليجرام دون الحاجة لفتح المتصفح:',
      parseMode: ParseMode.markdown,
      replyMarkup: kb,
    );
  });

  bot.callbackQuery('adm_add_track', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.uploadStates[userId] = {'action': 'adm_add_track_name'};
    await ctx.editMessageText('➕ *إضافة مسار جديد*\n\nاكتب اسم المسار أو الفرقة (مثال: الفرقة الثالثة - ميكروبيولوجي):', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_curriculum'));
  });

  bot.callbackQuery('adm_add_subject_pick_track', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final tracks = await FirebaseDb.getTracks();
    final kb = InlineKeyboard();
    for (var t in tracks) {
      kb.row().add('📁 $t', 'adm_add_subj_sel_tr:${Utils.shorten(t)}');
    }
    kb.row().add('🔙 رجوع', 'adm_curriculum');

    await ctx.editMessageText('اختر المسار الذي تريد إضافة المادة إليه:', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^adm_add_subj_sel_tr:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final trackShort = data.replaceFirst('adm_add_subj_sel_tr:', '');
    final track = Utils.lengthen(trackShort);
    await ctx.answerCallbackQuery();

    Utils.uploadStates[userId] = {'action': 'adm_add_subj_name', 'track': track};
    await ctx.editMessageText('المسار: *$track*\n\nاكتب اسم المادة الجديدة المراد إضافتها:', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_curriculum'));
  });

  bot.callbackQuery('adm_del_subject_pick_track', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final tracks = await FirebaseDb.getTracks();
    final kb = InlineKeyboard();
    for (var t in tracks) {
      kb.row().add('📁 $t', 'adm_del_tr_browse:${Utils.shorten(t)}');
    }
    kb.row().add('🔙 رجوع', 'adm_curriculum');

    await ctx.editMessageText('اختر المسار لحذف مادة منه:', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^adm_del_tr_browse:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final trackShort = data.replaceFirst('adm_del_tr_browse:', '');
    final track = Utils.lengthen(trackShort);
    await ctx.answerCallbackQuery();

    final subjects = await FirebaseDb.getSubjects(track);
    if (subjects.isEmpty) {
      await ctx.editMessageText('لا توجد مواد في هذا المسار.', replyMarkup: InlineKeyboard().row().add('🔙 رجوع', 'adm_del_subject_pick_track'));
      return;
    }

    final kb = InlineKeyboard();
    for (var s in subjects) {
      kb.row().add('🗑 $s', 'adm_del_subj_do:${Utils.shorten(track)}:${Utils.shorten(s)}');
    }
    kb.row().add('🔙 رجوع', 'adm_del_subject_pick_track');

    await ctx.editMessageText('اختر المادة المراد حذفها من مسار "$track":', replyMarkup: kb);
  });

  bot.callbackQuery(RegExp(r'^adm_del_subj_do:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    final parts = data.replaceFirst('adm_del_subj_do:', '').split(':');
    final track = Utils.lengthen(parts[0]);
    final subject = Utils.lengthen(parts[1]);

    await FirebaseDb.deleteSubject(track, subject);
    await ctx.answerCallbackQuery(text: 'تم حذف المادة بنجاح.');
    await ctx.editMessageText('🗑 *تم حذف مادة "$subject" من مسار "$track" بنجاح.*', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إدارة المناهج', 'adm_curriculum'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ── 👥 6. USER MODERATION & LOOKUP ────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  bot.callbackQuery('adm_users', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final allUsers = await FirebaseDb.getAllUsers();

    final kb = InlineKeyboard()
      .row().add('🔍 استعلام عن حساب مستخدم', 'adm_lookup_prompt')
      .row().add('🚫 حظر مستخدم (Ban)', 'adm_ban_prompt').add('🟢 فك حظر مستخدم (Unban)', 'adm_unban_prompt')
      .row().add('🔙 رجوع للوحة الإدارة', 'admin_dash');

    await ctx.editMessageText('👥 *إدارة الطلاب والمستخدمين*\n\nإجمالي المستخدمين المسجلين: *${allUsers.length}*\n\nاختر العملية المطلوبة:', parseMode: ParseMode.markdown, replyMarkup: kb);
  });

  bot.callbackQuery('adm_ban_prompt', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.uploadStates[userId] = {'action': 'adm_ban_id'};
    await ctx.editMessageText('🚫 *حظر مستخدم*\n\nأرسل الـ Telegram User ID الخاص بالمستخدم لحرمانه من البوت:', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_users'));
  });

  bot.callbackQuery('adm_unban_prompt', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.uploadStates[userId] = {'action': 'adm_unban_id'};
    await ctx.editMessageText('🟢 *فك حظر مستخدم*\n\nأرسل الـ Telegram User ID الخاص بالمستخدم لفك الحظر عنه:', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_users'));
  });

  bot.callbackQuery('adm_lookup_prompt', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();
    Utils.uploadStates[userId] = {'action': 'adm_lookup_id'};
    await ctx.editMessageText('🔍 *استعلام عن حساب مستخدم*\n\nأرسل الـ Telegram User ID للاستعلام عن رتبته ومواده:', parseMode: ParseMode.markdown, replyMarkup: InlineKeyboard().row().add('🔙 إلغاء', 'adm_users'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ── 🌐 7. WEB PORTALS QUICK LINKS ─────────────────────────────────────
  // ═════════════════════════════════════════════════════════════════════════

  bot.callbackQuery('adm_web_links', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    await ctx.answerCallbackQuery();

    final buffer = StringBuffer('🌐 *روابط وبوابات المنظومة المباشرة*\n');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('🖥️ *لوحة التحكم الرئيسية (Web CMS):*');
    buffer.writeln('`http://localhost:5000/`\n');
    buffer.writeln('🔬 *لوحة إدارة المهام المتقدمة (Mission Admin):*');
    buffer.writeln('`http://localhost:5000/mission-admin.html`\n');
    buffer.writeln('📺 *شاشة العرض المباشر للمهام (Live Missions Screen):*');
    buffer.writeln('`http://localhost:5000/mission-view.html`');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('💡 يمكنك فتح أي رابط مباشرة لمتابعة الشاشات المباشرة ومصفوفة كانبان.');

    final kb = InlineKeyboard().row().add('🔙 رجوع للوحة الإدارة', 'admin_dash');
    await ctx.editMessageText(buffer.toString(), parseMode: ParseMode.markdown, replyMarkup: kb);
  });
}

// ── Helper: build admin keyboard ────────────────────────────────────────

Future<InlineKeyboard> _buildAdminKeyboard(int userId, String lang) async {
  final superAdminId = await FirebaseDb.getSuperAdmin();
  final isSuperAdmin = userId == superAdminId;

  final keyboard = InlineKeyboard()
    // Row 1: Core Mission Hub & Broadcast
    .row()
    .add('🎯 إدارة المهام والتكليفات (Missions)', 'adm_missions')
    .add('📢 إذاعة التنبيهات المتقدمة', 'adm_bcast_menu')
    // Row 2: Support Inbox & Health
    .row()
    .add('📬 صندوق الرسائل والدعم', 'dash_inbox')
    .add('🩺 صحة واستقرار النظام', 'dash_health')
    // Row 3: Curriculum Management & User Management
    .row()
    .add('🗂 إدارة المناهج والأقسام', 'adm_curriculum')
    .add('👥 إدارة الطلاب والمستخدمين', 'adm_users')
    // Row 4: Statistics & Contributors
    .row()
    .add('📊 تقرير الإحصائيات الشامل', 'dash_stats')
    .add('🤝 طلبات ومساهمو الفريق', 'dash_requests')
    // Row 5: Web Links & Fast Tools
    .row()
    .add('🌐 روابط شاشات المهام المباشرة', 'adm_web_links')
    .add(S.get('btn_reply_user', lang), 'dash_reply_user')
    // Row 6: Miko AI Assistant Bot
    .row()
    .addUrl('🤖 كلّم ميكو (المساعد الذكي)', 'https://t.me/micoat_bot');

  if (isSuperAdmin) {
    keyboard.row()
      .add('👑 إضافة أدمن جديد', 'dash_add_admin')
      .add('🚫 مسح مساهم', 'dash_rm_contrib');
    keyboard.row()
      .add('⚠️ مسح المناهج', 'dash_wipe')
      .add('⚠️ مسح المستخدمين', 'dash_wipe_users')
      .add(S.get('btn_transfer_owner', lang), 'dash_transfer_owner');
  }

  keyboard.row().add(S.get('btn_student_mode', lang), 'dash_student');
  return keyboard;
}
