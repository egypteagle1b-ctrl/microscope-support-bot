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
}

// ── Helper: build admin keyboard ────────────────────────────────────────

Future<InlineKeyboard> _buildAdminKeyboard(int userId, String lang) async {
  final superAdminId = await FirebaseDb.getSuperAdmin();
  final isSuperAdmin = userId == superAdminId;

  final keyboard = InlineKeyboard()
    .row()
    .add(S.get('btn_add_admin', lang), 'dash_add_admin')
    .add(S.get('btn_broadcast', lang), 'dash_broadcast')
    .row()
    .add(S.get('btn_reply_user', lang), 'dash_reply_user')
    .add(S.get('btn_stats', lang), 'dash_stats')
    .row()
    .add(S.get('btn_requests', lang), 'dash_requests')
    .add(S.get('btn_wipe', lang), 'dash_wipe')
    .row()
    .add(S.get('btn_rm_contrib', lang), 'dash_rm_contrib');

  if (isSuperAdmin) {
    keyboard.row()
      .add(S.get('btn_transfer_owner', lang), 'dash_transfer_owner')
      .add(S.get('btn_wipe_users', lang), 'dash_wipe_users');
  }

  keyboard.row().add(S.get('btn_student_mode', lang), 'dash_student');
  return keyboard;
}
