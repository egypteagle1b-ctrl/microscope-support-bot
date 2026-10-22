import 'package:televerse/televerse.dart';
import 'firebase_db.dart';
import 'utils.dart';
import 'config.dart';
import 'strings.dart';


void registerContributorAndUploadHandlers(Bot bot) {
  // ── /مساهم command ───────────────────────────────────────────────────
  bot.hears(RegExp(r'^/(مساهم|contributor)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    await _showContributorDashboard(ctx, userId, lang, isEdit: false);
  });
}

Future<void> handleUploadText(Context ctx, Bot bot) async {
  final userId = ctx.from?.id;
  if (userId == null) return;

  final state = Utils.uploadStates[userId];
  if (state == null) return;

  final lang = Utils.getUserLanguage(userId);
  final text = ctx.message?.text ?? '';
  if (text.startsWith('/')) return; // ignore commands

  switch (state['action']) {
    // ---- Admin actions ------------------------------------------------
    case 'add_admin_id':
      final targetId = int.tryParse(text);
      if (targetId != null) {
        await FirebaseDb.addAdmin(targetId);
        await ctx.reply(S.get('admin_added', lang, {'id': '$targetId'}));
      } else {
        await ctx.reply(S.get('invalid_id', lang));
      }
      Utils.clearUploadState(userId);
      break;

    case 'broadcast_msg':
      await ctx.reply(S.get('broadcasting', lang));
      final users = await FirebaseDb.getAllUsers();
      Utils.broadcast(bot, users, text);
      Utils.clearUploadState(userId);
      break;

    case 'transfer_owner_id':
      final targetId = int.tryParse(text);
      if (targetId != null) {
        await FirebaseDb.setSuperAdmin(targetId);
        await ctx.reply(
            S.get('transfer_done', lang, {'id': '$targetId'}));
        try {
          final targetLang = Utils.getUserLanguage(targetId);
          await bot.api.sendMessage(
              ChatID(targetId), S.get('transfer_notif', targetLang));
        } catch (_) {}
      } else {
        await ctx.reply(S.get('invalid_id', lang));
      }
      Utils.clearUploadState(userId);
      break;

    // ---- Admin actions ------------------------------------------------
    case 'reply_user_id':
      final targetId = int.tryParse(text);
      if (targetId != null) {
        state['action'] = 'reply_user_msg';
        state['target_id'] = targetId;
        await ctx.reply(S.get('enter_reply_message', lang));
      } else {
        await ctx.reply(S.get('invalid_id', lang));
        Utils.clearUploadState(userId);
      }
      break;

    case 'reply_user_msg':
      final targetId = state['target_id'] as int;
      try {
        final targetLang = Utils.getUserLanguage(targetId);
        await bot.api.sendMessage(
          ChatID(targetId),
          S.get('admin_reply_msg', targetLang, {'msg': text}),
        );
        await ctx.reply(S.get('reply_sent_success', lang));
      } catch (e) {
        await ctx.reply(S.get('reply_sent_failed', lang));
      }
      Utils.clearUploadState(userId);
      break;

    // ---- Contributor request (name only) ---------------------------------
    case 'req_contribute_name':
      final fullName = text.trim().isNotEmpty
          ? text.trim()
          : '${ctx.from?.firstName ?? ''} ${ctx.from?.lastName ?? ''}'.trim();
      Utils.clearUploadState(userId);

      await FirebaseDb.addRequest(userId, name: fullName);
      await ctx.reply(S.get('contribute_request_sent', lang));

      // Notify all admins
      final admins = await FirebaseDb.getAdmins();
      final Map<String, dynamic> msgIds = {};
      for (var adminId in admins) {
        try {
          final adminLang = Utils.getUserLanguage(adminId);
          final keyboard = InlineKeyboard()
            .row()
            .add(S.get('btn_approve', adminLang), 'approve_contrib:$userId')
            .add(S.get('btn_reject', adminLang), 'reject_contrib:$userId');
          final msg = await bot.api.sendMessage(
            ChatID(adminId),
            S.get('admin_contrib_request', adminLang, {
              'id': '$userId',
              'name': fullName.isEmpty ? '$userId' : fullName,
            }),
            replyMarkup: keyboard,
          );
          msgIds[adminId.toString()] = msg.messageId;
        } catch (_) {}
      }
      await FirebaseDb.updateRequestMessageIds(userId, msgIds);
      break;

    // ---- Contact admin ------------------------------------------------
    case 'contact_admin':
      Utils.clearUploadState(userId);
      
      // Save to Firebase
      await FirebaseDb.addFeedback(userId, text);
      
      final admins2 = await FirebaseDb.getAdmins();
      for (var adminId in admins2) {
        try {
          final adminLang = Utils.getUserLanguage(adminId);
          await bot.api.sendMessage(
            ChatID(adminId),
            S.get('new_feedback', adminLang,
                {'id': '$userId', 'msg': text}),
          );
        } catch (_) {}
      }
      await ctx.reply(S.get('contact_admin_sent', lang));
      break;

    // ---- Contributor announcement broadcast --------------------------
    case 'contrib_announce_msg':
      Utils.clearUploadState(userId);
      await ctx.reply(S.get('announce_sending', lang));
      final users2 = await FirebaseDb.getAllUsers();
      Utils.broadcast(bot, users2, text);
      break;

    // ---- Smart Search Beta -------------------------------------------
    case 'smart_search_query':
      Utils.clearUploadState(userId);
      final query = text.trim();
      final results = await FirebaseDb.searchCurriculum(query);
      if (results.isEmpty) {
        final backKb = InlineKeyboard().row().add(S.get('btn_back', lang), 'back:main');
        await ctx.reply(
          S.get('search_no_results', lang, {'query': query}),
          replyMarkup: backKb,
          parseMode: ParseMode.markdown,
        );
        break;
      }

      final kb = InlineKeyboard();
      for (var r in results) {
        final kind = r['kind'];
        if (kind == 'subject') {
          kb.row().add(
            r['title'],
            'subj:${Utils.shorten(r['track'])}:${Utils.shorten(r['subject'])}',
          );
        } else if (kind == 'material') {
          kb.row().add(
            r['title'],
            'mat:${Utils.shorten(r['track'])}:${Utils.shorten(r['subject'])}:${Utils.shorten(r['matType'])}:${Utils.shorten(r['materialId'])}',
          );
        }
      }
      kb.row().add(S.get('btn_back', lang), 'back:main');
      await ctx.reply(
        S.get('search_results_title', lang, {'query': query}),
        replyMarkup: kb,
        parseMode: ParseMode.markdown,
      );
      break;

    // ---- Contributor Quick Add Lecture (by name/text) ----------------
    case 'contrib_quick_add_name':
      state['lecture_name'] = text.trim();
      state['action'] = 'contrib_quick_add_desc';
      await ctx.reply(S.get('quick_add_desc_prompt', lang));
      break;

    case 'contrib_quick_add_desc':
      final qTrack = state['track'] as String? ?? '';
      final qSubject = state['subject'] as String? ?? '';
      final qType = state['type'] as String? ?? 'ملخص';
      final qName = state['lecture_name'] as String? ?? 'محاضرة';
      final desc = text.trim().toLowerCase() == 'تخطي' || text.trim().toLowerCase() == 'skip'
          ? ''
          : text.trim();
      Utils.clearUploadState(userId);

      final isLink = desc.startsWith('http://') || desc.startsWith('https://');
      final fType = isLink ? 'link' : 'text';

      final matId = await FirebaseDb.addMaterial(qTrack, qSubject, qType, {
        'name': qName,
        'file_id': desc.isNotEmpty ? desc : qName,
        'file_type': fType,
        'description': desc,
        'added_by': userId.toString(),
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (matId != null) {
        await FirebaseDb.addContributorMaterialRef(userId, matId, {
          'track': qTrack,
          'subject': qSubject,
          'type': qType,
          'name': qName,
          'file_id': desc.isNotEmpty ? desc : qName,
          'file_type': fType,
        });

        // Notify subscribers
        final subscribers = await FirebaseDb.getSubjectSubscribers(qSubject);
        if (subscribers.isNotEmpty) {
          final notifyText = '🔔 إضافة جديدة!\n\nتمت إضافة: **$qName** في مادة: **$qSubject**\nالنوع: $qType\n\nتفضل بزيارة البوت للاطلاع عليها.';
          Utils.broadcast(bot, subscribers, notifyText);
        }

        final backKb = InlineKeyboard().row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');
        await ctx.reply(
          S.get('quick_add_success', lang, {
            'name': qName,
            'track': qTrack,
            'subject': qSubject,
            'type': qType,
          }),
          replyMarkup: backKb,
        );
      } else {
        await ctx.reply(S.get('upload_failed', lang));
      }
      break;

    // ---- Upload flow: new track / subject typed manually ─────────────
    case 'upload_admin_track':
      state['action'] = 'upload_admin_subject';
      state['track'] = text;
      await ctx.reply(S.get('upload_enter_subject', lang));
      break;

    case 'upload_admin_subject':
      final track = state['track'] as String? ?? '';
      final subject = text;
      state['subject'] = subject;
      state['action'] = 'wait_for_upload_type';

      // Fetch dynamic material types
      final types = await FirebaseDb.getMaterialTypes(track, subject);
      if (types.isEmpty) {
        await ctx.reply(S.get('upload_no_types', lang)); 
        Utils.clearUploadState(userId);
        break;
      }

      final kb = InlineKeyboard();
      for (var t in types) {
        kb.row().add(t, 'up_type:$t');
      }
      await ctx.reply(
        S.get('upload_selected_track', lang, {'track': track}),
        replyMarkup: kb,
      );
      break;

    // ---- Material name: contributor provides a name -----------------
    case 'wait_for_upload_name':
      state['material_name'] = text;
      final type = state['type'] as String? ?? '';
      
      // Move any pending single file into the files list
      final pendingFile = state['pending_file'] as Map<String, dynamic>?;
      final List<Map<String, dynamic>> files = [];
      if (pendingFile != null) {
        files.add(pendingFile);
        state.remove('pending_file');
      }
      state['files'] = files;

      if (type == 'رابط' || type.toLowerCase() == 'link') {
        // Switch to link mode
        state['action'] = 'contrib_upload_link';
        await ctx.reply(S.get('upload_link_prompt', lang));
      } else {
        state['action'] = 'collect_files';
        final doneKb = InlineKeyboard().row()
          .add(S.get('btn_done_uploading', lang), 'contrib_upload_done');

        if (files.isNotEmpty) {
          await ctx.reply(
            S.get('upload_file_received_count', lang, {'count': '${files.length}'}),
            replyMarkup: doneKb,
          );
        } else {
          await ctx.reply(
            S.get('upload_collecting_files', lang),
            replyMarkup: doneKb,
          );
        }
      }
      break;

    // ---- Link upload: user pastes URL --------------------------------
    case 'contrib_upload_link':
      final track2 = (state['track'] as String?) ?? '';
      final subject2 = (state['subject'] as String?) ?? '';
      final type2 = (state['type'] as String?) ?? 'رابط';
      Utils.clearUploadState(userId);

      final url = text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        await ctx.reply(S.get('upload_link_invalid', lang));
        break;
      }

      final linkName = url.length > 60 ? '${url.substring(0, 60)}…' : url;
      final materialName = (state['material_name'] as String?) ?? linkName;
      final materialId = await FirebaseDb.addMaterial(track2, subject2, type2, {
        'name': materialName,
        'file_id': url,
        'file_type': 'link',
        'added_by': userId.toString(),
      });

      if (materialId != null) {
        await FirebaseDb.addContributorMaterialRef(userId, materialId, {
          'track': track2,
          'subject': subject2,
          'type': type2,
          'name': materialName,
          'file_id': url,
          'file_type': 'link'
        });

        // Send notifications to subscribers
        final subscribers = await FirebaseDb.getSubjectSubscribers(subject2);
        if (subscribers.isNotEmpty) {
          final text = '🔔 إضافة جديدة!\n\nتمت إضافة ملف جديد في مادة: **$subject2**\nالنوع: $type2\n\nقم بزيارة البوت لتفقدها.';
          Utils.broadcast(bot, subscribers, text);
        }

        await ctx.reply(S.get('upload_multi_success', lang, {
          'count': '1',
          'subject': subject2,
          'track': track2,
          'type': type2,
        }));
      } else {
        await ctx.reply(S.get('upload_failed', lang));
      }
      break;
  }
}

void registerContributorUploadHandlers(Bot bot) {
  // ── Upload track/subject/type keyboard callbacks ─────────────────────

  bot.callbackQuery(RegExp(r'^up_track:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;

    final state = Utils.uploadStates[userId];
    if (state == null || state['action'] != 'wait_for_upload_track') return;

    final lang = Utils.getUserLanguage(userId);
    final data = ctx.callbackQuery!.data!;
    final track = data.substring('up_track:'.length);
    state['track'] = track;
    state['action'] = 'wait_for_upload_subject';

    final subjects = await FirebaseDb.getSubjects(track);
    if (subjects.isEmpty) {
      await ctx.answerCallbackQuery(
          text: S.get('upload_no_subjects', lang), showAlert: true);
      Utils.clearUploadState(userId);
      return;
    }

    final keyboard = InlineKeyboard();
    for (var s in subjects) {
      keyboard.row().add(s, 'up_subj:$s');
    }

    await ctx.editMessageText(
      S.get('upload_selected_track', lang, {'track': track}),
      replyMarkup: keyboard,
    );
  });

  bot.callbackQuery(RegExp(r'^up_subj:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;

    final state = Utils.uploadStates[userId];
    if (state == null || state['action'] != 'wait_for_upload_subject') return;

    final lang = Utils.getUserLanguage(userId);
    final data = ctx.callbackQuery!.data!;
    final subject = data.substring('up_subj:'.length);
    final track = state['track'] as String? ?? '';
    state['subject'] = subject;
    state['action'] = 'wait_for_upload_type';

    // Fetch dynamic material types
    final types = await FirebaseDb.getMaterialTypes(track, subject);
    if (types.isEmpty) {
      await ctx.answerCallbackQuery(
          text: S.get('upload_no_types', lang), showAlert: true);
      Utils.clearUploadState(userId);
      return;
    }

    final keyboard = InlineKeyboard();
    for (var t in types) {
      keyboard.row().add(t, 'up_type:$t');
    }

    await ctx.editMessageText(
      S.get('upload_selected_subject', lang, {'subject': subject}),
      replyMarkup: keyboard,
    );
  });

  bot.callbackQuery(RegExp(r'^up_type:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;

    final state = Utils.uploadStates[userId];
    if (state == null || state['action'] != 'wait_for_upload_type') return;

    final lang = Utils.getUserLanguage(userId);
    final data = ctx.callbackQuery!.data!;
    final type = data.substring('up_type:'.length);
    state['type'] = type;
    state['action'] = 'wait_for_upload_name';

    await ctx.editMessageText(S.get('upload_enter_name', lang));
  });

  // ── Add Subject button (from contributor dashboard) ───────────────────
  bot.callbackQuery('contrib_add_subject', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final isContributor = await FirebaseDb.isContributor(userId);
    final isAdmin = await FirebaseDb.isAdmin(userId);
    if (!isContributor && !isAdmin) {
      await ctx.answerCallbackQuery(
          text: S.get('no_permission_upload', lang), showAlert: true);
      return;
    }

    Utils.uploadStates[userId] = {
      'action': 'wait_for_upload_track',
    };

    final tracks = await FirebaseDb.getTracks();
    if (tracks.isEmpty) {
      await ctx.answerCallbackQuery(
          text: S.get('upload_no_categories', lang), showAlert: true);
      Utils.clearUploadState(userId);
      return;
    }

    final keyboard = InlineKeyboard();
    for (var t in tracks) {
      keyboard.row().add(t, 'up_track:$t');
    }

    await ctx.editMessageText(
      S.get('contrib_add_subject_prompt', lang),
      replyMarkup: keyboard,
    );
  });

  // ── Done uploading → save all collected files ─────────────────────────
  bot.callbackQuery('contrib_upload_done', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final state = Utils.uploadStates[userId];
    if (state == null || state['action'] != 'collect_files') {
      await ctx.answerCallbackQuery();
      return;
    }

    final track = (state['track'] as String?) ?? '';
    final subject = (state['subject'] as String?) ?? '';
    final type = (state['type'] as String?) ?? '';
    final files = (state['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    await ctx.answerCallbackQuery();

    if (files.isEmpty) {
      await ctx.editMessageText(S.get('upload_no_files', lang));
      Utils.clearUploadState(userId);
      return;
    }

    int savedCount = 0;
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fId = file['fileId'] as String;
      final fType = file['fileType'] as String;
      final materialName = (state['material_name'] as String?) ?? type;
      final autoName = files.length == 1 ? materialName : '$materialName ${i + 1}';

      final backupFileId = await _backupFile(bot, fId, fType);
      final matId = await FirebaseDb.addMaterial(track, subject, type, {
        'name': autoName,
        'file_id': backupFileId ?? fId,
        'file_type': fType,
        'added_by': userId.toString(),
      });

      if (matId != null) {
        await FirebaseDb.addContributorMaterialRef(userId, matId, {
          'track': track,
          'subject': subject,
          'type': type,
          'name': autoName,
          'file_id': backupFileId ?? fId,
          'file_type': fType
        });
        savedCount++;
      }
    }

    // Send notifications to subscribers
    final subscribers = await FirebaseDb.getSubjectSubscribers(subject);
    if (subscribers.isNotEmpty) {
      final text = '🔔 إضافة جديدة!\n\nتمت إضافة ملف جديد في مادة: **$subject**\nالنوع: $type\n\nقم بزيارة البوت لتفقدها.';
      Utils.broadcast(bot, subscribers, text);
    }

    Utils.clearUploadState(userId);
    await ctx.editMessageText(S.get('upload_multi_success', lang, {
      'count': '$savedCount',
      'subject': subject,
      'track': track,
      'type': type,
    }));
  });

  // ── File upload handlers (all types) ─────────────────────────────────

  bot.onDocument((ctx) async {
    final fileId = ctx.message?.document?.fileId;
    if (fileId != null) await _handleUploadFlow(bot, ctx, fileId, 'document');
  });

  bot.onPhoto((ctx) async {
    final fileId = ctx.message?.photo?.last.fileId;
    if (fileId != null) await _handleUploadFlow(bot, ctx, fileId, 'photo');
  });

  bot.onVideo((ctx) async {
    final fileId = ctx.message?.video?.fileId;
    if (fileId != null) await _handleUploadFlow(bot, ctx, fileId, 'video');
  });

  bot.onAudio((ctx) async {
    final fileId = ctx.message?.audio?.fileId;
    if (fileId != null) await _handleUploadFlow(bot, ctx, fileId, 'audio');
  });

  bot.onVoice((ctx) async {
    final fileId = ctx.message?.voice?.fileId;
    if (fileId != null) await _handleUploadFlow(bot, ctx, fileId, 'voice');
  });

  // ── Contributor Dashboard callbacks ──────────────────────────────────

  bot.callbackQuery('contrib_dash', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    await _showContributorDashboard(ctx, userId, lang);
  });

  bot.callbackQuery('contrib_materials', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final materials = await FirebaseDb.getContributorMaterials(userId);
    if (materials.isEmpty) {
      final kb = InlineKeyboard().row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');
      await ctx.editMessageText(S.get('contrib_no_materials', lang), replyMarkup: kb);
      return;
    }

    final tracks = materials.values.map((v) => v['track'] as String).toSet().toList();
    final keyboard = InlineKeyboard();
    for (var t in tracks) {
      keyboard.row().add(t, 'c_mat_track:$t');
    }
    keyboard.row().add('🗑️ مسح جميع موادي', 'c_del_all_mats_confirm');
    keyboard.row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');

    await ctx.editMessageText('📋 موادي:\nاختر المسار:', replyMarkup: keyboard);
  });

  // Bulk Delete: All Materials
  bot.callbackQuery('c_del_all_mats_confirm', (ctx) async {
    final keyboard = InlineKeyboard()
        .row().add('⚠️ نعم، احذف جميع موادي', 'c_del_all_mats_exec')
        .row().add('🔙 تراجع', 'contrib_materials');
    await ctx.editMessageText('هل أنت متأكد من رغبتك في حذف **جميع** المواد التي قمت برفعها؟ لا يمكن التراجع عن هذا الإجراء.', replyMarkup: keyboard, parseMode: ParseMode.markdown);
  });

  bot.callbackQuery('c_del_all_mats_exec', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    await ctx.editMessageText('جاري الحذف...');
    await FirebaseDb.deleteAllContributorMaterials(userId);
    final kb = InlineKeyboard().row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');
    await ctx.editMessageText('✅ تم حذف جميع موادك بنجاح.', replyMarkup: kb);
  });

  // Bulk Delete: Track Materials
  bot.callbackQuery(RegExp(r'^c_del_track_mats_confirm:(.+)'), (ctx) async {
    final track = ctx.callbackQuery!.data!.substring('c_del_track_mats_confirm:'.length);
    final keyboard = InlineKeyboard()
        .row().add('⚠️ نعم، احذف مواد مسار $track', 'c_del_track_mats_exec:$track')
        .row().add('🔙 تراجع', 'c_mat_track:$track');
    await ctx.editMessageText('هل أنت متأكد من رغبتك في حذف جميع موادك في مسار **$track**؟ لا يمكن التراجع عن هذا الإجراء.', replyMarkup: keyboard, parseMode: ParseMode.markdown);
  });

  bot.callbackQuery(RegExp(r'^c_del_track_mats_exec:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final track = ctx.callbackQuery!.data!.substring('c_del_track_mats_exec:'.length);
    if (userId == null) return;
    
    await ctx.editMessageText('جاري الحذف...');
    final materials = await FirebaseDb.getContributorMaterials(userId);
    for (var entry in materials.entries) {
      final matId = entry.key;
      final data = entry.value;
      if (data['track'] == track) {
        final subject = data['subject'] as String? ?? '';
        final type = data['type'] as String? ?? '';
        await FirebaseDb.deleteMaterial(track, subject, type, matId);
        await FirebaseDb.removeContributorMaterialRef(userId, matId);
      }
    }
    
    final keyboard = InlineKeyboard().row().add('🔙 رجوع إلى موادي', 'contrib_materials');
    await ctx.editMessageText('✅ تم حذف جميع مواد مسار $track بنجاح.', replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^c_mat_track:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    
    final track = data.substring('c_mat_track:'.length);
    final materials = await FirebaseDb.getContributorMaterials(userId);
    final subjects = materials.values
        .where((v) => v['track'] == track)
        .map((v) => v['subject'] as String)
        .toSet()
        .toList();

    final keyboard = InlineKeyboard();
    for (var s in subjects) {
      keyboard.row().add(s, 'c_mat_subj:$track:$s');
    }
    keyboard.row().add('🗑️ مسح جميع مواد المسار', 'c_del_track_mats_confirm:$track');
    keyboard.row().add('🔙 رجوع', 'contrib_materials');

    await ctx.editMessageText('📋 موادي - $track:\nاختر المادة:', replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^c_mat_subj:(.*?):(.*)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    
    final parts = data.split(':');
    final track = parts[1];
    final subject = parts[2];
    
    final materials = await FirebaseDb.getContributorMaterials(userId);
    final types = materials.values
        .where((v) => v['track'] == track && v['subject'] == subject)
        .map((v) => v['type'] as String)
        .toSet()
        .toList();

    final keyboard = InlineKeyboard();
    for (var t in types) {
      keyboard.row().add(t, 'c_mat_type:$track:$subject:$t');
    }
    keyboard.row().add('🔙 رجوع', 'c_mat_track:$track');

    await ctx.editMessageText('📋 موادي - $subject:\nاختر النوع:', replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^c_mat_type:(.*?):(.*?):(.*)'), (ctx) async {
    final userId = ctx.from?.id;
    final data = ctx.callbackQuery?.data;
    if (userId == null || data == null) return;
    
    final parts = data.split(':');
    final track = parts[1];
    final subject = parts[2];
    final type = parts[3];
    
    final materials = await FirebaseDb.getContributorMaterials(userId);
    final mats = materials.entries
        .where((e) => e.value['track'] == track && e.value['subject'] == subject && e.value['type'] == type)
        .toList();

    final keyboard = InlineKeyboard();
    for (var e in mats) {
      final matId = e.key;
      final name = e.value['name'] as String? ?? matId;
      keyboard.row().add('$name 🗑️', 'contrib_del_mat:${Utils.shorten(matId)}:${Utils.shorten(track)}:${Utils.shorten(subject)}:${Utils.shorten(type)}');
    }
    keyboard.row().add('🔙 رجوع', 'c_mat_subj:$track:$subject');

    await ctx.editMessageText('📋 موادي - $type:\nاختر الملف لحذفه:', replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^contrib_del_mat:(.*?):(.*?):(.*?):(.*)'), (ctx) async {
    final data = ctx.callbackQuery?.data;
    final userId = ctx.from?.id;
    if (data == null || userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final parts = data.split(':');
    final matId = Utils.lengthen(parts[1]);
    final track = Utils.lengthen(parts[2]);
    final subject = Utils.lengthen(parts[3]);
    final type = Utils.lengthen(parts[4]);

    await FirebaseDb.deleteMaterial(track, subject, type, matId);
    await FirebaseDb.removeContributorMaterialRef(userId, matId);

    await ctx.answerCallbackQuery(text: S.get('material_delete_toast', lang), showAlert: false);

    // Refresh materials list for the current type
    final materials = await FirebaseDb.getContributorMaterials(userId);
    final mats = materials.entries
        .where((e) => e.value['track'] == track && e.value['subject'] == subject && e.value['type'] == type)
        .toList();

    if (mats.isEmpty) {
      // Check if there are other types in the subject
      final types = materials.values
          .where((v) => v['track'] == track && v['subject'] == subject)
          .map((v) => v['type'] as String)
          .toSet()
          .toList();
      
      if (types.isEmpty) {
         // Return to tracks or dashboard depending on if it's fully empty
         if (materials.isEmpty) {
            final kb = InlineKeyboard().row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');
            await ctx.editMessageText(S.get('contrib_no_materials', lang), replyMarkup: kb);
         } else {
            // Jump back to tracks list as a safe fallback
            final tracks = materials.values.map((v) => v['track'] as String).toSet().toList();
            final keyboard = InlineKeyboard();
            for (var t in tracks) {
              keyboard.row().add(t, 'c_mat_track:$t');
            }
            keyboard.row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');
            await ctx.editMessageText('📋 موادي:\nاختر المسار:', replyMarkup: keyboard);
         }
      } else {
          final keyboard = InlineKeyboard();
          for (var t in types) {
            keyboard.row().add(t, 'c_mat_type:$track:$subject:$t');
          }
          keyboard.row().add('🔙 رجوع', 'c_mat_track:$track');
          await ctx.editMessageText('📋 موادي - $subject:\nاختر النوع:', replyMarkup: keyboard);
      }
      return;
    }

    final keyboard = InlineKeyboard();
    for (var e in mats) {
      final id = e.key;
      final name = e.value['name'] as String? ?? id;
      keyboard.row().add('$name 🗑️', 'contrib_del_mat:${Utils.shorten(id)}:${Utils.shorten(track)}:${Utils.shorten(subject)}:${Utils.shorten(type)}');
    }
    keyboard.row().add('🔙 رجوع', 'c_mat_subj:$track:$subject');

    await ctx.editMessageText('📋 موادي - $type:\nاختر الملف لحذفه:', replyMarkup: keyboard);
  });

  // ── Contributor Analytics (NEW FEATURE) ─────────────────────────────
  bot.callbackQuery('contrib_analytics', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    await ctx.answerCallbackQuery();

    final materials = await FirebaseDb.getContributorMaterials(userId);
    if (materials.isEmpty) {
      final backKb = InlineKeyboard().row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');
      await ctx.editMessageText('📊 ليس لديك أي مواد مرفوعة لعرض إحصائياتها بعد.', replyMarkup: backKb);
      return;
    }

    final stats = await FirebaseDb.getStats();
    final topMaterials = stats['topMaterials'] as Map<String, dynamic>? ?? {};

    int totalViews = 0;
    final accessedList = <Map<String, dynamic>>[];

    for (var entry in materials.entries) {
      final matId = entry.key;
      final mData = entry.value as Map<String, dynamic>;
      final mName = mData['name']?.toString() ?? matId;
      int count = 0;
      if (topMaterials.containsKey(matId)) {
        final topEntry = topMaterials[matId];
        if (topEntry is Map && topEntry['count'] != null) {
          count = topEntry['count'] as int;
        }
      }
      totalViews += count;
      if (count > 0) {
        accessedList.add({'name': mName, 'count': count});
      }
    }

    accessedList.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    String msg = '📊 *إحصائيات موادي وتفاعل الطلاب*\n\n';
    msg += '📁 *إجمالي المواد المرفوعة:* ${materials.length} مادة\n';
    msg += '👀 *إجمالي المشاهدات/التحميلات:* $totalViews مشاهدة\n\n';

    if (accessedList.isNotEmpty) {
      msg += '🔥 *المواد الأكثر تفاعلاً:*\n';
      for (var i = 0; i < accessedList.length && i < 5; i++) {
        msg += '${i + 1}. ${accessedList[i]['name']} — ${accessedList[i]['count']} مشاهدة\n';
      }
    } else {
      msg += '✨ لم يتم تسجيل تفاعلات بعد على موادك.';
    }

    final kb = InlineKeyboard().row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');
    await ctx.editMessageText(msg, replyMarkup: kb, parseMode: ParseMode.markdown);
  });

  // ── Contributor Quick Add Lecture (NEW FEATURE) ─────────────────────
  bot.callbackQuery('contrib_quick_add', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final isContributor = await FirebaseDb.isContributor(userId);
    final isAdmin = await FirebaseDb.isAdmin(userId);
    if (!isContributor && !isAdmin) {
      await ctx.answerCallbackQuery(text: S.get('no_permission_upload', lang), showAlert: true);
      return;
    }

    Utils.uploadStates[userId] = {'action': 'wait_for_quick_add_track'};
    final tracks = await FirebaseDb.getTracks();
    if (tracks.isEmpty) {
      await ctx.answerCallbackQuery(text: S.get('upload_no_categories', lang), showAlert: true);
      return;
    }

    final keyboard = InlineKeyboard();
    for (var t in tracks) {
      keyboard.row().add(t, 'qa_track:${Utils.shorten(t)}');
    }
    keyboard.row().add(S.get('btn_back_dashboard', lang), 'contrib_dash');

    await ctx.editMessageText('اختر المسار لإضافة المحاضرة فيه:', replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^qa_track:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final data = ctx.callbackQuery!.data!;
    final track = Utils.lengthen(data.substring('qa_track:'.length));

    final state = Utils.uploadStates[userId];
    if (state == null) return;
    state['track'] = track;
    state['action'] = 'wait_for_quick_add_subject';

    final subjects = await FirebaseDb.getSubjects(track);
    final keyboard = InlineKeyboard();
    for (var s in subjects) {
      keyboard.row().add(s, 'qa_subj:${Utils.shorten(s)}');
    }
    keyboard.row().add('🔙 رجوع', 'contrib_quick_add');

    await ctx.editMessageText('المسار: $track\nاختر المادة:', replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^qa_subj:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final data = ctx.callbackQuery!.data!;
    final subject = Utils.lengthen(data.substring('qa_subj:'.length));

    final state = Utils.uploadStates[userId];
    if (state == null) return;
    final track = state['track'] as String? ?? '';
    state['subject'] = subject;
    state['action'] = 'wait_for_quick_add_type';

    final types = await FirebaseDb.getMaterialTypes(track, subject);
    final keyboard = InlineKeyboard();
    for (var t in types) {
      keyboard.row().add(t, 'qa_type:${Utils.shorten(t)}');
    }
    keyboard.row().add('🔙 رجوع', 'qa_track:${Utils.shorten(track)}');

    await ctx.editMessageText('المادة: $subject\nاختر النوع (ملخص، شرح، فيديو...):', replyMarkup: keyboard);
  });

  bot.callbackQuery(RegExp(r'^qa_type:(.+)'), (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);
    final data = ctx.callbackQuery!.data!;
    final type = Utils.lengthen(data.substring('qa_type:'.length));

    final state = Utils.uploadStates[userId];
    if (state == null) return;
    state['type'] = type;
    state['action'] = 'contrib_quick_add_name';

    await ctx.editMessageText(S.get('quick_add_name_prompt', lang));
  });

  // Contributor announce new lecture
  bot.callbackQuery('contrib_announce', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    Utils.uploadStates[userId] = {'action': 'contrib_announce_msg'};
    await ctx.editMessageText(S.get('announce_prompt', lang));
  });

  // Contributor self-removal: ask confirmation
  bot.callbackQuery('contrib_self_remove', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    final kb = InlineKeyboard()
      .row()
      .add(S.get('btn_confirm_remove', lang), 'contrib_self_remove_confirm')
      .add(S.get('btn_cancel', lang), 'contrib_dash');

    await ctx.editMessageText(
      S.get('contrib_self_remove_confirm', lang),
      replyMarkup: kb,
    );
  });

  // Contributor self-removal: confirmed
  bot.callbackQuery('contrib_self_remove_confirm', (ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final lang = Utils.getUserLanguage(userId);

    await FirebaseDb.removeContributor(userId);
    Utils.setUserMode(userId, UserMode.student);
    Utils.clearUploadState(userId);

    await ctx.editMessageText(S.get('contrib_self_removed', lang));
  });
}

// ── Private: show contributor dashboard ──────────────────────────────────

Future<void> _showContributorDashboard(Context ctx, int userId, String lang,
    {bool isEdit = true}) async {
  final contribData = await FirebaseDb.getContributor(userId);
  if (contribData == null) {
    if (ctx.callbackQuery != null) {
      await ctx.answerCallbackQuery(
          text: S.get('no_permission_upload', lang), showAlert: true);
    } else {
      await ctx.reply(S.get('no_permission_upload', lang));
    }
    return;
  }

  final materials = await FirebaseDb.getContributorMaterials(userId);
  final count = materials.length;

  final kb = InlineKeyboard()
    .row()
    .add(S.get('btn_add_subject', lang), 'contrib_add_subject')
    .add(S.get('btn_quick_add_lecture', lang), 'contrib_quick_add')
    .row()
    .add(S.get('btn_my_materials', lang), 'contrib_materials')
    .add(S.get('btn_contrib_stats', lang), 'contrib_analytics')
    .row()
    .add(S.get('btn_announce', lang), 'contrib_announce')
    .add(S.get('btn_self_remove', lang), 'contrib_self_remove')
    .row()
    .add(S.get('btn_back', lang), 'back:main');

  final msg = S.get('contrib_dashboard_title', lang, {
    'count': '$count',
  });

  if (isEdit && ctx.callbackQuery != null) {
    await ctx.editMessageText(
      msg,
      replyMarkup: kb,
      parseMode: ParseMode.markdown,
    );
  } else {
    await ctx.reply(
      msg,
      replyMarkup: kb,
      parseMode: ParseMode.markdown,
    );
  }
}

// ── Private: handle incoming file (admin or contributor) ─────────────────

Future<void> _handleUploadFlow(
    Bot bot, Context ctx, String fileId, String fileType) async {
  final userId = ctx.from?.id;
  if (userId == null) return;
  final lang = Utils.getUserLanguage(userId);

  final isAdmin = await FirebaseDb.isAdmin(userId);
  final isModeAdmin = Utils.getUserMode(userId) == UserMode.admin;
  final isContributor = await FirebaseDb.isContributor(userId);

  final state = Utils.uploadStates[userId];

  // ── If currently collecting files, just add to the list ─────────────
  if (state != null && state['action'] == 'collect_files') {
    final files = (state['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    files.add({'fileId': fileId, 'fileType': fileType});
    state['files'] = files;

    final doneKb = InlineKeyboard().row()
      .add(S.get('btn_done_uploading', lang), 'contrib_upload_done');
    await ctx.reply(
      S.get('upload_file_received_count', lang, {'count': '${files.length}'}),
      replyMarkup: doneKb,
    );
    return;
  }

  // ── Replace existing file ────────────────────────────────────────────
  if (state != null && state['action'] == 'replace_file') {
    if (!isAdmin) return;

    final backupFileId = await _backupFile(bot, fileId, fileType);
    await FirebaseDb.updateMaterial(
      state['track'], state['subject'], state['type'], state['materialId'],
      {'file_id': backupFileId ?? fileId, 'file_type': fileType},
    );

    await ctx.reply(S.get('file_replaced', lang));
    Utils.clearUploadState(userId);
    return;
  }

  // ── Start a new upload session ────────────────────────────────────────
  if ((isAdmin && isModeAdmin) || isContributor) {
    Utils.uploadStates[userId] = {
      'action': 'wait_for_upload_track',
      'pending_file': {'fileId': fileId, 'fileType': fileType},
    };

    final tracks = await FirebaseDb.getTracks();
    if (tracks.isEmpty) {
      await ctx.reply(S.get('upload_no_categories', lang));
      Utils.clearUploadState(userId);
      return;
    }

    final keyboard = InlineKeyboard();
    for (var t in tracks) {
      keyboard.row().add(t, 'up_track:$t');
    }

    final prompt = (isAdmin && isModeAdmin)
        ? S.get('admin_file_received', lang)
        : S.get('contrib_file_received', lang);
    await ctx.reply(prompt, replyMarkup: keyboard);
  } else {
    await ctx.reply(S.get('no_permission_upload', lang));
  }
}

// ── Private: backup file to channel ──────────────────────────────────────

Future<String?> _backupFile(Bot bot, String fileId, String fileType) async {
  if (Config.backupChannelId.isEmpty ||
      Config.backupChannelId.contains('your_channel')) return fileId;

  try {
    final chatId = ChatID(int.parse(Config.backupChannelId));
    final inputFile = InputFile.fromFileId(fileId);
    if (fileType == 'photo') {
      final msg = await bot.api.sendPhoto(chatId, inputFile);
      return msg.photo?.last.fileId ?? fileId;
    } else if (fileType == 'video') {
      final msg = await bot.api.sendVideo(chatId, inputFile);
      return msg.video?.fileId ?? fileId;
    } else if (fileType == 'audio') {
      final msg = await bot.api.sendAudio(chatId, inputFile);
      return msg.audio?.fileId ?? fileId;
    } else if (fileType == 'voice') {
      final msg = await bot.api.sendVoice(chatId, inputFile);
      return msg.voice?.fileId ?? fileId;
    } else {
      final msg = await bot.api.sendDocument(chatId, inputFile);
      return msg.document?.fileId ?? fileId;
    }
  } catch (e) {
    print('Backup failed: $e');
    return fileId;
  }
}
