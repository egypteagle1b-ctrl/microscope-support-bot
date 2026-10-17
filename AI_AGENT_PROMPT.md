# 🤖 Master AI Agent Blueprint: Telegram Educational Bot CMS

> **طريقة الاستخدام مع أي إيجنت (ChatGPT / Claude / Cursor / Copilot):**
> 1. افتح شات جديد مع الذكاء الاصطناعي أو الإيجنت.
> 2. اسحب هذا الملف أو انسخ محتواه بالكامل وضعه في الشات.
> 3. أرسل له الرسالة التالية:
>    *"قم ببناء وتوليد كود هذا المشروع بالكامل استناداً إلى المواصفات والمعمارية الموضحة في هذا الملف."*

---

# System Prompt & Specification

You are an expert Full-Stack Dart and Telegram Bot software architect. Your task is to implement or scaffold the complete production-grade **Educational Telegram Bot with CMS & Web Dashboard** based on the following comprehensive architecture, schemas, and requirements.

---

## 1. Tech Stack & Architecture

- **Platform & Language:** Dart SDK `>=3.0.0 <4.0.0`
- **Telegram Bot Framework:** `televerse: ^1.10.4` (pure Dart, high-performance polling/webhook bot library).
- **Database:** Firebase Realtime Database (RTDB) via native REST API calls (`http: ^1.2.0`), avoiding heavy dependencies. Every request appends `?auth=FIREBASE_SECRET`.
- **Integrated Web Server:** Dart's built-in `HttpServer` bound to `0.0.0.0:$PORT` (default 5000):
  - Serves dynamic CMS dashboard (`web/index.html`) with server-side template replacement of `{{FB_URL}}` and `{{FB_SECRET}}`.
  - `/health` endpoint for uptime monitoring.
  - `/api/upload` endpoint allowing the web dashboard to upload materials (sends file to Telegram backup channel, extracts `file_id`, and saves record to Firebase).
- **Zero-Bandwidth Storage Strategy:**
  - Files are sent to a Telegram Backup Channel / Admin chat.
  - Telegram returns a permanent `file_id`.
  - The bot stores only the `file_id` and metadata in Firebase.
  - When students request files, the bot streams them using `file_id` directly through Telegram's servers.
- **Bilingual Support (Localization):** Arabic (`ar`) and English (`en`) for all user-facing strings with an in-memory cache and Firebase persistence.

---

## 2. Project Directory Tree

```text
telegram-bot/
│
├── bin/
│   └── telegram_bot_cms.dart          # Main entrypoint, HTTP server, bot initialization & text router
│
├── lib/
│   ├── config.dart                    # Central configuration (reads Platform.environment & .env)
│   ├── firebase_db.dart               # Complete Firebase RTDB REST operations
│   ├── strings.dart                   # Bilingual localization dictionary (AR/EN)
│   ├── utils.dart                     # State machines, wizards & 64-byte callback shortener
│   ├── student_handlers.dart          # Student flow: browse tracks, subjects, materials, pagination
│   ├── contributor_handlers.dart      # Contributor wizard: file uploads, subject selection, subscriber notifications
│   ├── admin_handlers.dart            # Admin panel: approve/reject requests, broadcast, analytics, wipe DB
│   └── table_handlers.dart            # Custom student schedules and subject notifications
│
├── web/
│   ├── index.html                     # Web CMS Dashboard with {{FB_URL}} and {{FB_SECRET}} placeholders
│   ├── hr.html                        # HR Evaluation System
│   ├── members_form.html              # Member registration form
│   └── team.html                      # Team showcase page
│
├── .env.example                       # Sample environment config
├── .env                               # Active secrets
├── pubspec.yaml                       # Dart package dependencies
└── Dockerfile                         # Deployment container definition
```

---

## 3. Environment Configuration (`.env`)

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

## 4. Complete Firebase RTDB Schema

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
      "name": "Contributor Name"
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
      "message": "User feedback message",
      "timestamp": "2026-10-17T20:00:00.000Z"
    }
  }
}
```

---

## 5. Detailed Component Specifications

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
- Load `.env` using `dotenv`.
- Prioritize `Platform.environment[key]` over `.env` (crucial for Docker/cloud environments).
- Provide static getters for all environment variables:
  `botToken`, `superAdminId`, `backupChannelId`, `firebaseDatabaseUrl`, `firebaseSecret`, `whatsappSupportNumber`, `googleDriveFolderId`, `googleServiceAccountJson`.
- Define `enum UserMode { student, admin }`.

### 5.3. `lib/firebase_db.dart`
- Low-level HTTP REST client with 10-second timeout:
  - `_get(String path)`
  - `_put(String path, dynamic data)`
  - `_patch(String path, dynamic data)`
  - `_delete(String path)`
  - `_post(String path, dynamic data)` -> returns generated ID (`res['name']`).
- Authentication URL format: `$_baseUrl$path.json?auth=${Config.firebaseSecret}`.
- Complete operations implemented:
  - **User & Auth:** `registerUser`, `getUserLanguage`, `setUserLanguage`, `isAdmin`, `isBanned`, `addAdmin`, `removeAdmin`, `setSuperAdmin`, `getSuperAdmin`.
  - **Curriculum:** `getTracks`, `getSubjects`, `getMaterialTypes`, `getMaterials`, `addMaterial`, `deleteMaterial`, `updateMaterial`, `getMaterial`.
  - **Contributor Management:** `setContributor`, `getContributor`, `getAllContributors`, `removeContributor`, `isContributor`, `addContributorMaterialRef`, `getContributorMaterials`, `deleteAllContributorMaterials`.
  - **Requests:** `addRequest`, `getPendingRequests`, `removeRequest`, `updateRequestMessageIds`.
  - **Study Tables & Schedule:** `saveTable`, `getTables`, `deleteTable`, `deleteAllTables`, `getSubjectSubscribers`.
  - **Analytics & Maintenance:** `logMaterialAccess`, `getStats`, `getAllUsers`, `wipeCurriculum`, `wipeUsers`.

### 5.4. `lib/utils.dart`
- **Callback Data Shortener:** Telegram enforces a 64-byte limit on `callback_data`. Multi-level menus (e.g., `mat_<track>_<subject>_<type>_<id>`) easily exceed this. Maintain bidirectional maps `_shortToLong` and `_longToShort` using base-36 counters with `shorten(data)` and `expand(data)` methods.
- **In-Memory State Machines:**
  - `uploadStates`: stores in-progress upload state for contributors/admins: `{ 'step': 'select_track', 'file_id': '...', 'file_type': '...', 'track': '', 'subject': '', 'type': '' }`.
  - `tableCreationStates`: stores custom schedule creation steps for students.
  - `_userModes`: tracks whether user is in student or admin mode.
  - `_userLanguages`: in-memory language cache (`'ar'` / `'en'`).

### 5.5. `lib/strings.dart`
- Multi-lingual string repository for Arabic and English with token interpolation:
  `S.get(key, lang, [params])`.
- Covers greetings, buttons, dashboard texts, notifications, error messages, and admin prompts.

### 5.6. `bin/telegram_bot_cms.dart`
- **Built-in Web Server:**
  - `HttpServer.bind(InternetAddress.anyIPv4, port)`
  - `/health`: returns `{"status":"ok"}`.
  - `/` & `/index.html`: serves `web/index.html` with injected credentials:
    `html.replaceFirst('{{FB_URL}}', Config.firebaseDatabaseUrl).replaceFirst('{{FB_SECRET}}', Config.firebaseSecret)`
  - `/api/upload`: handles file uploads from dashboard, posts to backup channel via Telegram Bot API, stores file reference in Firebase.
- **Bot Initialization:**
  - Instantiates `Bot(Config.botToken)`.
  - Attaches `BanCheck` middleware to immediately halt banned users.
  - Registers modules: `registerStudentHandlers`, `registerTableHandlers`, `registerAdminHandlers`, `registerContributorAndUploadHandlers`, `registerContributorUploadHandlers`.
  - **Centralized Text Handler:** Single `bot.onText` listener that dispatches messages to either `handleTableText` or `handleUploadText` to prevent listener collision.
  - Global error handling that safely suppresses harmless `"message is not modified"` exceptions.

### 5.7. `lib/student_handlers.dart`
- `/start` command handler:
  - Registers user in Firebase.
  - Handles language selection (prompt -> inline callback -> cache).
  - Displays main menu: Departments/Tracks, Study Schedule, Contributor Request, Support, Change Language.
- Tracks -> Subjects -> Content Types navigation using inline keyboards.
- Paginated Material List: 5 items per page with navigation arrows (`⬅️` / `➡️`).
- File Delivery: Sends files using Telegram `file_id` based on type (`sendDocument`, `sendVideo`, `sendAudio`, `sendPhoto`), followed by access logging in `/analytics/top_accessed`.
- "Become a Contributor" request flow: records application in Firebase and dispatches interactive requests with `✅ Accept` / `❌ Reject` buttons to all administrators.

### 5.8. `lib/contributor_handlers.dart`
- File upload listener (`onDocument`, `onPhoto`, `onVideo`, `onAudio`).
- Validates permissions (Admin or approved Contributor).
- Uploads/forwards file to Backup Channel to capture Telegram `file_id`.
- Guides user through an interactive wizard:
  1. Select Track
  2. Select Subject
  3. Select Content Type
  4. Enter Title
  5. Save to Firebase.
- Notifies all registered subscribers of that subject via `/subject_subscribers/<subject>`.

### 5.9. `lib/admin_handlers.dart`
- `/admin` command: Restricted to Admins & Super Admin.
- Displays responsive admin dashboard with:
  - **Pending Requests:** Real-time contributor request reviews with instant inline approval/rejection.
  - **Broadcast Engine:** Allows admins to send announcements to all registered users asynchronously.
  - **Analytics:** Displays total users count and top accessed materials.
  - **Super Admin Zone:** Database wipe controls, admin permissions management, and ownership transfer.

### 5.10. `lib/table_handlers.dart`
- Custom student schedule builder:
  - Students choose a track and select multiple subjects.
  - Subscribes students to `/subject_subscribers/<subject>/<userId>`.
  - Students receive automatic notifications whenever new materials are uploaded for their selected subjects.

---

## 6. Execution Command
Build all project files according to the above specifications with clean, robust, and complete Dart code.
