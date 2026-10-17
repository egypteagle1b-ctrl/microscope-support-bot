# 🤖 MASTER SPECIFICATION & REPLICATION PROMPT: Educational Telegram Bot with CMS (Dart + Televerse + Firebase)

> **Instructions for the AI Agent:**
> You are an expert Full-Stack Dart and Telegram Bot engineer. Your task is to generate, scaffold, or recreate the complete production-ready **Educational Telegram Bot with CMS & Dashboard** described in this specification. Follow the project architecture, database schemas, state machines, and business logic precisely.

---

## 1. Project Overview & Architecture

- **Language & Runtime:** Dart SDK `>=3.0.0 <4.0.0`
- **Core Framework:** [Televerse](https://pub.dev/packages/televerse) (`^1.10.4`) — Fast and modern Telegram Bot API framework for Dart.
- **Database:** Firebase Realtime Database (RTDB) operated directly via REST API with Secret Key authentication (`http` package), avoiding heavy SDKs.
- **Web Server:** Built-in lightweight `HttpServer` listening on `PORT` (default 5000), serving a responsive web CMS dashboard (`web/index.html`) with server-side credentials injection, `/health` endpoint, and `/api/upload` REST API.
- **Storage Strategy:** Zero-bandwidth overhead! Files sent by contributors/dashboard are forwarded to a Telegram Backup Channel/Admin Chat to obtain a Telegram `file_id`. The metadata and `file_id` are saved in Firebase. Students receive files instantly via `file_id`.
- **Localization:** Bilingual system (Arabic `ar` & English `en`) for all prompts and buttons with caching.

---

## 2. Directory & File Structure

```text
telegram-bot/
├── pubspec.yaml                       # Dependencies: televerse, dotenv, http, googleapis_auth, googleapis
├── .env.example                       # Template for environment variables
├── .env                               # Live environment credentials
├── Dockerfile                         # Container build & deployment file
├── bin/
│   └── telegram_bot_cms.dart          # Entry point, embedded HttpServer, bot initialization & routing
├── lib/
│   ├── config.dart                    # Centralized config reading from Platform.environment and .env
│   ├── firebase_db.dart               # Complete Firebase RTDB REST client & CRUD methods
│   ├── strings.dart                   # Bilingual localization dictionary (AR/EN)
│   ├── utils.dart                     # In-memory wizards, state machine & 64-byte callback shortener
│   ├── student_handlers.dart          # Student flow: browse tracks, subjects, files, pagination, feedback
│   ├── contributor_handlers.dart      # Contributor wizard: file uploads, subject selection, subscriber alerts
│   ├── admin_handlers.dart            # Admin panel: approve/reject requests, broadcast, analytics, wipe DB
│   └── table_handlers.dart            # Custom student schedules and subject notifications
└── web/
    └── index.html                     # Web CMS Dashboard with {{FB_URL}} and {{FB_SECRET}} templates
```

---

## 3. Environment Variables (`.env`)

```env
BOT_TOKEN=123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ
SUPER_ADMIN_ID=123456789
BACKUP_CHANNEL_ID=-1001234567890
FIREBASE_DATABASE_URL=https://your-project-default-rtdb.firebaseio.com/
FIREBASE_SECRET=your_firebase_database_secret
WHATSAPP_SUPPORT_NUMBER=+201234567890
PORT=5000
GOOGLE_DRIVE_FOLDER_ID=optional_folder_id
GOOGLE_SERVICE_ACCOUNT_JSON=optional_service_account_single_line_json
```

---

## 4. Firebase RTDB Schema (JSON Tree)

```json
{
  "users": {
    "<userId>": {
      "joinedAt": "2026-10-17T20:00:00.000Z",
      "language": "ar",
      "tables": {
        "<tableName>": {
          "track": "First Year",
          "subjects": ["Anatomy", "Physiology"],
          "subjects_with_tracks": ["First Year|Anatomy", "First Year|Physiology"]
        }
      }
    }
  },
  "admins": {
    "<userId>": true
  },
  "super_admin": {
    "id": 123456789
  },
  "banned_users": {
    "<userId>": true
  },
  "contributors": {
    "<userId>": {
      "approved": true,
      "name": "Moamen"
    }
  },
  "requests": {
    "<userId>": {
      "timestamp": "2026-10-17T20:00:00.000Z",
      "name": "Student Name",
      "messageIds": { "<adminId>": 1234 }
    }
  },
  "curriculum": {
    "<trackName>": {
      "<subjectName>": {
        "<materialType>": {
          "<materialId>": {
            "title": "Lecture 1 Anatomy",
            "file_id": "BAACAgQAAxkBAAE...",
            "file_type": "document",
            "uploaded_by": 123456789,
            "uploaded_at": "2026-10-17T20:00:00.000Z"
          }
        }
      }
    }
  },
  "contributor_materials": {
    "<userId>": {
      "<materialId>": {
        "track": "<trackName>",
        "subject": "<subjectName>",
        "type": "<materialType>"
      }
    }
  },
  "subject_subscribers": {
    "<subjectName>": {
      "<userId>": true
    }
  },
  "analytics": {
    "top_accessed": {
      "<materialId>": {
        "name": "Lecture 1 Anatomy",
        "count": 42
      }
    }
  },
  "feedbacks": {
    "<feedbackId>": {
      "userId": 123456789,
      "message": "Excellent bot!",
      "timestamp": "2026-10-17T20:00:00.000Z"
    }
  }
}
```

---

## 5. Core Components & Logic Specification

### 5.1. `pubspec.yaml`
```yaml
name: telegram_bot_cms
description: Educational Telegram bot with CMS
version: 1.0.0
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  televerse: ^1.10.4
  dotenv: ^4.2.0
  http: ^1.2.0
  googleapis_auth: ^2.3.4
  googleapis: ^17.0.0
dev_dependencies:
  lints: ^3.0.0
```

### 5.2. `lib/config.dart`
- Load `.env` locally using `DotEnv()..load()`.
- Check `Platform.environment[key]` first (for Docker/Cloud Run/Replit), falling back to `_env[key]`.
- Provide typed getters: `botToken`, `superAdminId`, `backupChannelId`, `firebaseDatabaseUrl`, `firebaseSecret`, `whatsappSupportNumber`, `googleDriveFolderId`, `googleServiceAccountJson`.

### 5.3. `lib/firebase_db.dart`
- Create standard REST client over HTTP using `http.get`, `http.put`, `http.patch`, `http.delete`, `http.post`.
- Format URL as: `$_baseUrl$path.json?auth=$firebaseSecret`.
- Implements:
  - User registration & language preference.
  - Role checks: `isAdmin()`, `isBanned()`, `isContributor()`.
  - Curriculum traversal: `getTracks()`, `getSubjects(track)`, `getMaterialTypes(track, subject)`, `getMaterials(track, subject, type)`.
  - Material mutations: `addMaterial(...)`, `deleteMaterial(...)`, `updateMaterial(...)`.
  - Schedule tables: `saveTable(...)`, `getTables(...)`, `deleteTable(...)`.
  - Subscriber index: `getSubjectSubscribers(subject)`.
  - Analytics logging: `logMaterialAccess(materialId, materialName)`.
  - Contributor request workflow: `addRequest(...)`, `getPendingRequests()`, `removeRequest(...)`.

### 5.4. `lib/utils.dart`
- **Callback Data Shortener:** Telegram has a 64-byte callback limit. When constructing callbacks like `mat_<track>_<subject>_<type>_<id>`, long strings crash the bot. Maintain two in-memory bidirectional maps `_shortToLong` and `_longToShort` with a base-36 counter (`Utils.shorten(data)` & `Utils.expand(data)`).
- **Session State Storage:**
  - `uploadStates`: stores in-progress upload state for contributors/admins: `{ 'step': 'select_track', 'file_id': '...', 'file_type': '...', 'track': '', 'subject': '', 'type': '' }`.
  - `tableCreationStates`: stores custom schedule creation steps for students.
  - `_userModes`: `UserMode.student` or `UserMode.admin`.
  - `_userLanguages`: in-memory language cache (`'ar'` / `'en'`).

### 5.5. `lib/strings.dart`
- Bilingual dictionary mapping keys to Arabic and English strings.
- Example keys: `welcome`, `departments`, `btn_contribute`, `btn_admin_panel`, `btn_student_mode`, `lang_prompt`, `btn_back`, etc.
- Helper `S.get(key, lang, [params])` supporting token interpolation.

### 5.6. `bin/telegram_bot_cms.dart`
- **Web Server (`startDummyServer`):**
  - Handles `/health` returning status 200 JSON.
  - Handles `/` and `/index.html` by serving `web/index.html` and replacing `{{FB_URL}}` with `Config.firebaseDatabaseUrl` and `{{FB_SECRET}}` with `Config.firebaseSecret`.
  - Handles `/api/upload`: Accepts base64 encoded file, sends to Telegram backup channel, gets `fileId`, and creates the record.
- **Bot Setup:**
  - Initialize `Bot(Config.botToken)`.
  - Attach `BanCheck` middleware (blocks banned user IDs).
  - Register modules: `registerStudentHandlers(bot)`, `registerTableHandlers(bot)`, `registerAdminHandlers(bot)`, `registerContributorAndUploadHandlers(bot)`.
  - Centralized `bot.onText`: Single router that delegates text messages to `handleTableText` or `handleUploadText` to avoid listener race conditions.
  - Error catcher ignoring `"message is not modified"` Telegram errors.

### 5.7. `lib/student_handlers.dart`
- `/start` command: Registers user in Firebase, detects language, displays welcome keyboard and inline track buttons.
- Callbacks for Track -> Subject -> Type -> Material List.
- Pagination: 5 files per page with `⬅️ Previous` and `➡️ Next` buttons.
- Clicking a file:
  - Fetches metadata from Firebase.
  - Sends file by `file_id` according to `file_type` (`sendDocument`, `sendVideo`, `sendAudio`, `sendPhoto`).
  - Logs access in `/analytics/top_accessed/<materialId>`.
- "Become Contributor" button: prompts student for name/subject, saves in `/requests`, and notifies all admins with Accept/Reject inline buttons.

### 5.8. `lib/contributor_handlers.dart`
- File upload listener (`bot.onDocument`, `bot.onPhoto`, `bot.onVideo`, `bot.onAudio`).
- Checks if sender is Admin or approved Contributor.
- Forwards/sends file to Backup Channel to capture Telegram `file_id`.
- Initiates step-by-step wizard:
  1. Pick Track (inline keyboard)
  2. Pick Subject (inline keyboard)
  3. Pick Material Type (PDF, Video, Summary, Exams, etc.)
  4. Type Material Title (text input)
  5. Confirm & Save to Firebase RTDB.
- Automatically queries `/subject_subscribers/<subject>` and broadcasts a notification to all subscribed students: *"📢 New material uploaded for [Subject]: [Title]!"*.

### 5.9. `lib/admin_handlers.dart`
- `/admin` command: Restricted to Admins & Super Admin.
- Displays Admin panel:
  - **Pending Requests:** Displays list of contributor applicants with `✅ Accept` / `❌ Reject` buttons. On accept: promotes user in `/contributors`, deletes request, and notifies the applicant.
  - **Broadcast:** Prompts admin for text/photo message and broadcasts it asynchronously to all registered users in `/users`.
  - **Analytics:** Shows total registered users and top accessed materials.
  - **Super Admin Danger Zone:** Wipe curriculum, add/remove admin IDs, transfer ownership.

### 5.10. `lib/table_handlers.dart`
- Allows students to build personalized study tables/schedules.
- Multi-select subjects from their track.
- Adds user to `/subject_subscribers/<subject>/<userId>`.
- Allows viewing, deleting, and updating custom tables.

---

## 6. How to Run & Deploy

```bash
# 1. Fetch dependencies
dart pub get

# 2. Setup .env file
cp .env.example .env
# Edit .env with your BOT_TOKEN and Firebase credentials

# 3. Run the bot
dart run bin/telegram_bot_cms.dart
```

> **Target Agent Execution Rule:**
> When asked to scaffold or clone this bot, generate the complete code for all specified files without omitting handlers, types, or configuration logic.
