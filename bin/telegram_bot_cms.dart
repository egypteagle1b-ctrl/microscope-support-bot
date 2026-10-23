import 'dart:io';
import 'dart:convert';
import 'package:televerse/televerse.dart';
import 'package:http/http.dart' as http;
import '../lib/config.dart';
import '../lib/student_handlers.dart';
import '../lib/admin_handlers.dart';
import '../lib/contributor_handlers.dart';
import '../lib/table_handlers.dart';
import '../lib/firebase_db.dart';
import '../lib/utils.dart';

Future<void> startDummyServer(Bot bot) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 5000;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Web server listening on all interfaces (0.0.0.0) on port $port');

  await for (final request in server) {
    try {
      await _handleWebRequest(request, bot);
    } catch (e) {
      print('Web server error: $e');
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }
}

Future<void> _handleWebRequest(HttpRequest req, Bot bot) async {
  // CORS — allow dashboard to call Firebase from any origin
  req.response.headers
    ..add('Access-Control-Allow-Origin', '*')
    ..add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..add('Access-Control-Allow-Headers', 'Content-Type')
    ..add('Cache-Control', 'no-cache');

  if (req.method == 'OPTIONS') {
    req.response.statusCode = 204;
    await req.response.close();
    return;
  }

  final path = req.uri.path;

  if (path == '/health') {
    // JSON health endpoint for the status indicator in the dashboard
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"status":"ok","ts":"${DateTime.now().toIso8601String()}"}');

  } else if (path == '/' || path == '/index.html') {
    // Serve admin dashboard, injecting Firebase credentials from config
    final htmlFile = File('web/index.html');
    if (await htmlFile.exists()) {
      String html = await htmlFile.readAsString();
      // Server-side injection so browser gets credentials automatically
      html = html
          .replaceFirst('{{FB_URL}}', Config.firebaseDatabaseUrl)
          .replaceFirst('{{FB_SECRET}}', Config.firebaseSecret);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(html);
    } else {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.text
        ..write('Bot is alive! (web/index.html not found)');
    }

  } else if (path == '/api/upload' && req.method == 'POST') {
    try {
      final content = await utf8.decoder.bind(req).join();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      final track = data['track'] as String;
      final subject = data['subject'] as String;
      final type = data['type'] as String;
      final fileName = data['file_name'] as String;
      final fileBase64 = data['file_base64'] as String;
      
      final bytes = base64Decode(fileBase64.split(',').last);
      
      ChatID chatId = ChatID(Config.superAdminId);
      if (Config.backupChannelId.isNotEmpty && !Config.backupChannelId.contains('your_channel')) {
        chatId = ChatID(int.parse(Config.backupChannelId));
      }

      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
      final isVideo = ext == 'mp4' || ext == 'mkv' || ext == 'mov';
      final isAudio = ext == 'mp3' || ext == 'ogg' || ext == 'm4a' || ext == 'wav' || ext == 'mpga';
      final isPhoto = ext == 'jpg' || ext == 'jpeg' || ext == 'png';
      
      final inputFile = InputFile.fromBytes(bytes, name: fileName);
      String fileId = '';
      String fileType = 'document';

      if (isPhoto) {
        final msg = await bot.api.sendPhoto(chatId, inputFile);
        fileId = msg.photo?.last.fileId ?? '';
        fileType = 'photo';
      } else if (isVideo) {
        final msg = await bot.api.sendVideo(chatId, inputFile);
        fileId = msg.video?.fileId ?? '';
        fileType = 'video';
      } else if (isAudio) {
        final msg = await bot.api.sendAudio(chatId, inputFile);
        fileId = msg.audio?.fileId ?? '';
        fileType = 'audio';
      } else {
        final msg = await bot.api.sendDocument(chatId, inputFile);
        fileId = msg.document?.fileId ?? '';
        fileType = 'document';
      }

      if (fileId.isEmpty) {
        throw Exception('Failed to get fileId from Telegram');
      }

      await FirebaseDb.addMaterial(track, subject, type, {
        'name': fileName,
        'file_id': fileId,
        'file_type': fileType,
        'added_by': 'Admin Panel',
      });

      // Send notifications to subscribers
      final subscribers = await FirebaseDb.getSubjectSubscribers(subject);
      if (subscribers.isNotEmpty) {
        final text = '🔔 إضافة جديدة!\n\nتمت إضافة ملف جديد في مادة: **$subject**\nالنوع: $type\n\nقم بزيارة البوت لتفقدها.';
        Utils.broadcast(bot, subscribers, text);
      }

      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"success":true}');
    } catch (e) {
      req.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false, 'error': e.toString()}));
    }

  } else if (path == '/api/upload_member_photo' && req.method == 'POST') {
    try {
      final content = await utf8.decoder.bind(req).join();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final photoBase64 = data['photo_base64'] as String;
      final fileName = data['file_name'] as String? ?? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final bytes = base64Decode(photoBase64.split(',').last);
      final dir = Directory('web/uploads/members');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('web/uploads/members/$fileName');
      await file.writeAsBytes(bytes);
      
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'url': '/web/uploads/members/$fileName'
        }));
    } catch (e) {
      req.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false, 'error': e.toString()}));
    }

  } else if (path == '/api/backup_member' && req.method == 'POST') {
    try {
      final content = await utf8.decoder.bind(req).join();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      final fileName = data['file_name'] as String;
      final fileBase64 = data['file_base64'] as String;
      
      final bytes = base64Decode(fileBase64.split(',').last);

      if (data.containsKey('photo_base64') && data['photo_base64'] != null) {
        try {
          final pBase64 = data['photo_base64'] as String;
          final pName = data['photo_file_name'] as String? ?? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final pBytes = base64Decode(pBase64.split(',').last);
          final dir = Directory('web/uploads/members');
          if (!await dir.exists()) await dir.create(recursive: true);
          await File('web/uploads/members/$pName').writeAsBytes(pBytes);
        } catch (_) {}
      }

      if (data.containsKey('member_data') && data['member_data'] != null) {
        try {
          final memberData = data['member_data'] as Map<String, dynamic>;
          final id = memberData['id'].toString();
          await FirebaseDb.saveMember(id, memberData);
        } catch (e) {
          print('Error saving member data to Firebase: $e');
        }
      }
      
      ChatID chatId = ChatID(Config.superAdminId);
      if (Config.backupChannelId.isNotEmpty && !Config.backupChannelId.contains('your_channel')) {
        final parsed = int.tryParse(Config.backupChannelId);
        if (parsed != null) chatId = ChatID(parsed);
      }
      
      final inputFile = InputFile.fromBytes(bytes, name: fileName);
      await bot.api.sendDocument(chatId, inputFile);
      
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': true}));
    } catch (e) {
      print('Backup Member Error: $e');
      req.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false, 'error': e.toString()}));
    }

  } else if (path == '/api/broadcast_subject' && req.method == 'POST') {
    try {
      final content = await utf8.decoder.bind(req).join();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final subject = data['subject'] as String;
      final message = data['message'] as String;

      final subscribers = await FirebaseDb.getSubjectSubscribers(subject);
      if (subscribers.isNotEmpty) {
        await Utils.broadcast(bot, subscribers, message);
      }

      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"status":"ok", "count": ${subscribers.length}}');
    } catch (e) {
      req.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'status': 'error', 'error': e.toString()}));
    }

  } else if (path == '/api/feedback' && req.method == 'POST') {
    try {
      final content = await utf8.decoder.bind(req).join();
      final data = jsonDecode(content) as Map<String, dynamic>;

      var name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        final randNum = 1000 + DateTime.now().millisecondsSinceEpoch % 90000;
        name = 'علومنجي #$randNum';
      }
      final ratingNum = (data['rating'] is int) ? data['rating'] as int : int.tryParse('${data['rating']}') ?? 0;
      final ratingStars = ratingNum > 0 ? '$ratingNum/5 ' + ('⭐' * ratingNum) : 'بدون تقييم';
      final message = (data['message'] ?? '').toString().trim();

      if (message.isEmpty) {
        req.response
          ..statusCode = 400
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'success': false, 'error': 'Empty feedback'}));
        await req.response.close();
        return;
      }

      // 1. Save to Firebase Database
      await FirebaseDb.addWebFeedback(
        name: name,
        rating: ratingNum,
        message: message,
      );

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      // 2. Build Telegram notification message
      final notification =
          '🌟 رأي وتقييم جديد من المنصة! 🌟\n\n'
          '👤 المستخدم: $name\n'
          '⭐ التقييم: $ratingStars\n'
          '💬 الرسالة:\n$message\n\n'
          '🕒 التاريخ والوقت: $dateStr\n'
          '🌐 المصدر: منصة الفيدباك (Microscope Feedback)';

      // Send to Super Admin
      if (Config.superAdminId != 0) {
        try {
          await bot.api.sendMessage(
            ChatID(Config.superAdminId),
            notification,
          );
        } catch (e) {
          print('Failed sending feedback alert to Super Admin: $e');
        }
      }

      // Send to other admins
      try {
        final admins = await FirebaseDb.getAdmins();
        for (var adminId in admins) {
          if (adminId != Config.superAdminId) {
            try {
              await bot.api.sendMessage(
                ChatID(adminId),
                notification,
              );
            } catch (_) {}
          }
        }
      } catch (_) {}

      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': true}));
    } catch (e) {
      req.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false, 'error': e.toString()}));
    }

  } else if (path == '/members_form.html' || path == '/members_form') {
    // Serve the Members Data Registration page
    final formFile = File('web/members_form.html');
    if (await formFile.exists()) {
      final html = await formFile.readAsString();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(html);
    } else {
      req.response.statusCode = 404;
      req.response.write('Members form page not found');
    }

  } else if (path == '/team.html' || path == '/team') {
    // Serve the 3D team showcase page
    final teamFile = File('web/team.html');
    if (await teamFile.exists()) {
      String html = await teamFile.readAsString();
      html = html
          .replaceFirst('{{FB_URL}}', Config.firebaseDatabaseUrl)
          .replaceFirst('{{FB_SECRET}}', Config.firebaseSecret);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(html);
    } else {
      req.response.statusCode = 404;
      req.response.write('Team page not found');
    }

  } else if (path == '/hr.html' || path == '/hr') {
    // Serve the HR Evaluation module
    final hrFile = File('web/hr.html');
    if (await hrFile.exists()) {
      String html = await hrFile.readAsString();
      html = html
          .replaceFirst('{{FB_URL}}', Config.firebaseDatabaseUrl)
          .replaceFirst('{{FB_SECRET}}', Config.firebaseSecret);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(html);
    } else {
      req.response.statusCode = 404;
      req.response.write('HR module not found');
    }

  } else if (path == '/mission-admin.html' || path == '/mission-admin') {
    // Serve the Mission Admin Dashboard
    final missionFile = File('web/mission-admin.html');
    if (await missionFile.exists()) {
      final html = await missionFile.readAsString();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(html);
    } else {
      req.response.statusCode = 404;
      req.response.write('Mission admin page not found');
    }

  } else if (path == '/mission-view.html' || path == '/mission-view' || path == '/mission') {
    // Serve the Public Mission View page
    final missionViewFile = File('web/mission-view.html');
    if (await missionViewFile.exists()) {
      final html = await missionViewFile.readAsString();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(html);
    } else {
      req.response.statusCode = 404;
      req.response.write('Mission view page not found');
    }

  } else if (path.startsWith('/web/') || 
             path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') || 
             path.endsWith('.webp') || path.endsWith('.svg') || 
             path.endsWith('.css') || path.endsWith('.js') || path.endsWith('.json') ||
             path.endsWith('.ico') || path.endsWith('.woff') || path.endsWith('.woff2') || path.endsWith('.ttf')) {
    // Serve static images and web assets (including css and js)
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final filePath = cleanPath.startsWith('web/') ? cleanPath : 'web/$cleanPath';
    final file = File(filePath);
    if (await file.exists()) {
      final ext = path.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' 
                 : (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' 
                 : ext == 'svg' ? 'image/svg+xml' 
                 : ext == 'webp' ? 'image/webp'
                 : ext == 'css' ? 'text/css' 
                 : ext == 'js' ? 'application/javascript' 
                 : ext == 'json' ? 'application/json'
                 : ext == 'ico' ? 'image/x-icon'
                 : ext == 'woff' ? 'font/woff'
                 : ext == 'woff2' ? 'font/woff2'
                 : ext == 'ttf' ? 'font/ttf'
                 : 'application/octet-stream';
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.parse(mime);
      if (req.uri.queryParameters.containsKey('download')) {
        req.response.headers.set('Content-Disposition', 'attachment; filename="${file.uri.pathSegments.last}"');
      }
      req.response.add(await file.readAsBytes());
    } else {
      req.response.statusCode = 404;
      req.response.write('Asset not found');
    }

  } else if (path == '/api/register_member' && req.method == 'POST') {
    // ── Registration Form Submissions ───────────────────────────────────────
    // Saves member data to Firebase + sends PDF to Telegram Backup Channel.
    // Note: Google Drive Service Accounts have no personal storage quota —
    //       Telegram backup channel is the reliable alternative.
    try {
      final content = await utf8.decoder.bind(req).join();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final fileName = data['file_name'] as String? ?? 'member_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final fileBase64 = data['file_base64'] as String? ?? '';
      final memberData = data['member_data'] as Map<String, dynamic>?;

      // 1. Save photo to disk (if provided separately)
      if (data.containsKey('photo_base64') && data['photo_base64'] != null) {
        try {
          final pBase64 = data['photo_base64'] as String;
          final pName = data['photo_file_name'] as String? ?? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final pBytes = base64Decode(pBase64.split(',').last);
          final dir = Directory('web/uploads/members');
          if (!await dir.exists()) await dir.create(recursive: true);
          await File('web/uploads/members/$pName').writeAsBytes(pBytes);
        } catch (_) {}
      }

      // 2. Save member data to Firebase (without the raw base64 picture field)
      String? firebaseId;
      if (memberData != null) {
        try {
          final id = memberData['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
          // Strip the raw picture blob — photoUrl is stored instead
          final cleanData = Map<String, dynamic>.from(memberData);
          cleanData.remove('picture');
          await FirebaseDb.saveMember(id, cleanData);
          firebaseId = id;
          print('[register_member] Saved member $id to Firebase');
        } catch (e) {
          print('[register_member] Firebase save error: $e');
        }
      }

      // 3. Send PDF to Telegram Backup Channel
      // (Google Drive Service Accounts have no personal storage quota)
      String? telegramFileId;
      if (fileBase64.isNotEmpty) {
        try {
          final pdfBytes = base64Decode(fileBase64.split(',').last);
          ChatID chatId = ChatID(Config.superAdminId);
          if (Config.backupChannelId.isNotEmpty && !Config.backupChannelId.contains('your_channel')) {
            final parsed = int.tryParse(Config.backupChannelId);
            if (parsed != null) chatId = ChatID(parsed);
          }
          final inputFile = InputFile.fromBytes(pdfBytes, name: fileName);
          final msg = await bot.api.sendDocument(chatId, inputFile);
          telegramFileId = msg.document?.fileId;
          print('[register_member] ✅ PDF sent to Backup Channel. File ID: $telegramFileId');
        } catch (e) {
          print('[register_member] ⚠️ Telegram backup error: $e');
          // Non-fatal — Firebase save already succeeded
        }
      }

      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'firebase_id': firebaseId,
          'telegram_file_id': telegramFileId,
        }));
    } catch (e) {
      print('[register_member] Error: $e');
      req.response
        ..statusCode = 500
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false, 'error': e.toString()}));
    }

  } else {
    req.response.statusCode = 404;
    req.response.write('Not found');
  }

  await req.response.close();
}


// ── Google Drive Helpers ─────────────────────────────────────────────────────

/// Uploads [bytes] as a PDF file named [fileName] to the configured Google Drive
/// folder, using a Service Account for authentication.
/// Returns the Drive file ID on success, or null on failure.
Future<String?> uploadToDrive(List<int> bytes, String fileName) async {
  final folderId = Config.googleDriveFolderId;
  final saJson = Config.googleServiceAccountJson;

  print('[Drive] ▶ Starting upload: $fileName → folder: $folderId');

  if (saJson.isEmpty) {
    print('[Drive] ❌ GOOGLE_SERVICE_ACCOUNT_JSON is not set — skipping upload');
    return null;
  }
  if (folderId.isEmpty) {
    print('[Drive] ❌ GOOGLE_DRIVE_FOLDER_ID is not set — skipping upload');
    return null;
  }
  print('[Drive] ✅ Config OK — SA JSON length: ${saJson.length}, folder: $folderId');

  // 1. Get OAuth2 access token
  print('[Drive] 🔑 Requesting OAuth2 access token...');
  final accessToken = await _getGoogleAccessToken(saJson);
  if (accessToken == null) {
    print('[Drive] ❌ Failed to obtain access token — check Service Account JSON and openssl');
    return null;
  }
  print('[Drive] ✅ Access token obtained (length: ${accessToken.length})');

  // 2. Multipart upload to Drive API v3
  //    We use a simple multipart body: metadata part + media part
  const boundary = '-------MicroscopeDriveBoundary7MA4YWxkTrZu0gW';
  final metadata = jsonEncode({
    'name': fileName,
    'mimeType': 'application/pdf',
    'parents': [folderId],
  });

  final metadataPart = '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadata\r\n';
  final mediaPart = '--$boundary\r\n'
      'Content-Type: application/pdf\r\n\r\n';
  final closing = '\r\n--$boundary--';

  final bodyBytes = [
    ...utf8.encode(metadataPart),
    ...utf8.encode(mediaPart),
    ...bytes,
    ...utf8.encode(closing),
  ];

  final uploadUrl = Uri.parse(
    'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
  );

  final response = await http.post(
    uploadUrl,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'multipart/related; boundary="$boundary"',
      'Content-Length': '${bodyBytes.length}',
    },
    body: bodyBytes,
  ).timeout(const Duration(seconds: 60));

  print('[Drive] 📤 Upload response: ${response.statusCode}');
  if (response.statusCode == 200 || response.statusCode == 201) {
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final fileId = result['id'] as String?;
    print('[Drive] ✅ File uploaded successfully! ID: $fileId');
    return fileId;
  } else {
    print('[Drive] ❌ Upload failed ${response.statusCode}: ${response.body}');
    return null;
  }
}

/// Builds a signed JWT, exchanges it for an OAuth2 access token, and returns it.
/// Implements RFC 7519 / Google Service Account flow without extra packages.
Future<String?> _getGoogleAccessToken(String serviceAccountJson) async {
  try {
    final sa = jsonDecode(serviceAccountJson) as Map<String, dynamic>;
    final clientEmail = sa['client_email'] as String;
    final privateKeyPem = (sa['private_key'] as String)
        .replaceAll('\\n', '\n'); // handle escaped newlines from .env

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final exp = now + 3600;

    final header = base64Url.encode(utf8.encode(jsonEncode({
      'alg': 'RS256',
      'typ': 'JWT',
    }))).replaceAll('=', '');

    final claims = base64Url.encode(utf8.encode(jsonEncode({
      'iss': clientEmail,
      'scope': 'https://www.googleapis.com/auth/drive',
      'aud': 'https://oauth2.googleapis.com/token',
      'iat': now,
      'exp': exp,
    }))).replaceAll('=', '');

    final signingInput = '$header.$claims';

    // Sign using RSA-SHA256
    final signature = _rsaSha256Sign(signingInput, privateKeyPem);
    if (signature == null) return null;

    final jwt = '$signingInput.$signature';

    // Exchange JWT for access token
    final tokenRes = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': jwt,
      },
    ).timeout(const Duration(seconds: 30));

    if (tokenRes.statusCode == 200) {
      final json = jsonDecode(tokenRes.body) as Map<String, dynamic>;
      return json['access_token'] as String?;
    } else {
      print('[Drive] Token exchange failed ${tokenRes.statusCode}: ${tokenRes.body}');
      return null;
    }
  } catch (e) {
    print('[Drive] _getGoogleAccessToken error: $e');
    return null;
  }
}

/// Signs [message] with the RSA private key [pemKey] using SHA-256.
/// Dart's built-in dart:io / dart:convert don't have RSA — we shell out to
/// the system openssl which is available on Linux/Docker (Replit/Cloud Run).
String? _rsaSha256Sign(String message, String pemKey) {
  try {
    // Write key to a temp file
    final tmpDir = Directory.systemTemp;
    final keyFile = File('${tmpDir.path}/sa_key_${DateTime.now().millisecondsSinceEpoch}.pem');
    final msgFile = File('${tmpDir.path}/sa_msg_${DateTime.now().millisecondsSinceEpoch}.txt');
    keyFile.writeAsStringSync(pemKey);
    msgFile.writeAsStringSync(message);

    print('[Drive] 🔐 Running openssl sign...');
    final result = Process.runSync('openssl', [
      'dgst', '-sha256', '-sign', keyFile.path,
      '-out', '${msgFile.path}.sig',
      msgFile.path,
    ]);

    if (result.exitCode != 0) {
      print('[Drive] ❌ openssl sign error (exit ${result.exitCode}): ${result.stderr}');
      keyFile.deleteSync();
      msgFile.deleteSync();
      return null;
    }
    print('[Drive] ✅ openssl signed successfully');

    final sigBytes = File('${msgFile.path}.sig').readAsBytesSync();
    final sig = base64Url.encode(sigBytes).replaceAll('=', '');

    // Cleanup
    keyFile.deleteSync();
    msgFile.deleteSync();
    try { File('${msgFile.path}.sig').deleteSync(); } catch (_) {}

    return sig;
  } catch (e) {
    print('[Drive] _rsaSha256Sign error: $e');
    return null;
  }
}



Future<void> main() async {
  print('Starting Telegram Bot CMS...');

  if (Config.botToken.isEmpty) {
    print('ERROR: BOT_TOKEN is not set in .env');
    return;
  }
  
  if (Config.firebaseDatabaseUrl.isEmpty) {
    print('ERROR: FIREBASE_DATABASE_URL is not set in .env');
    return;
  }

  // Ensure super admin is in database
  if (Config.superAdminId != 0) {
    await FirebaseDb.addAdmin(Config.superAdminId);
    print('Super Admin registered.');
  }

  final bot = Bot(Config.botToken);
  startDummyServer(bot);

  // Error handling
  bot.onError((err) {
    final error = err.error;
    if (error is TelegramException &&
        error.description != null &&
        error.description!.contains('message is not modified')) {
      return; // Ignore this harmless error
    }
    print('Bot Error: $err');
  });

  bot.use(BanCheck());

  // Register Handlers
  registerStudentHandlers(bot);
  registerTableHandlers(bot);
  registerAdminHandlers(bot);
  registerContributorAndUploadHandlers(bot);
  
  // Register generic file upload handlers
  registerContributorUploadHandlers(bot);

  // Centralized Text Handler for state machines to prevent routing conflicts
  bot.onText((ctx) async {
    final userId = ctx.from?.id;
    if (userId == null) return;
    final text = ctx.message?.text ?? '';
    if (text.startsWith('/')) return; // Ignore commands

    if (Utils.tableCreationStates.containsKey(userId)) {
      await handleTableText(ctx, bot);
    } else if (Utils.uploadStates.containsKey(userId)) {
      await handleUploadText(ctx, bot);
    }
  });

  print('Bot is polling...');
  while (true) {
    try {
      await bot.start();
    } catch (e) {
      print('Bot start/poll connection error: $e. Reconnecting in 3 seconds...');
      await Future.delayed(const Duration(seconds: 3));
    }
  }
}

class BanCheck implements Middleware {
  @override
  Future<void> handle(Context ctx, NextFunction next) async {
    final id = ctx.from?.id;
    if (id != null && await FirebaseDb.isBanned(id)) {
      return;
    }
    await next();
  }
}

