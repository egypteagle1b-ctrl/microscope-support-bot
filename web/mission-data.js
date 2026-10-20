/**
 * MICROSCOPE MISSION — Core Data & Shared Utilities
 * Handles Task Storage, Lifecycle, Timeline Tracking, Categories & Notifications
 */

const STORAGE_KEY = 'mm_tasks_data';
const PLAN_VERSION_KEY = 'mm_plan_version_v3';
const CURRENT_PLAN_VERSION = '2026_10_v3';
const PIN_KEY = 'mm_admin_pin';
const DEFAULT_PIN = '7600319381';

const CATEGORIES = {
  timeline: {
    id: 'timeline',
    label: 'الجدول الزمني والمراحل الرئيسية (الترم الأول)',
    shortLabel: 'المراحل الزمنية',
    icon: '📅',
    color: '#00d4ff'
  },
  term2: {
    id: 'term2',
    label: 'خطة الفصل الدراسي الثاني (Term 2)',
    shortLabel: 'خطة الترم الثاني',
    icon: '🎯',
    color: '#38bdf8'
  },
  execution: {
    id: 'execution',
    label: 'آلية التنفيذ والمتابعة (Let\'s Execute!)',
    shortLabel: 'آلية التنفيذ',
    icon: '⚡',
    color: '#f59e0b'
  },
  improvement: {
    id: 'improvement',
    label: 'مقترحات التطوير والتحسين المؤسسي',
    shortLabel: 'التطوير المؤسسي',
    icon: '💡',
    color: '#10b981'
  }
};

const STATUSES = {
  inactive: { label: 'غير مفعّلة', icon: '⏸️', cls: 'inactive', order: 0 },
  received: { label: 'استُلمت',   icon: '📥', cls: 'received', order: 1 },
  progress: { label: 'قيد التنفيذ', icon: '⚡', cls: 'progress', order: 2 },
  done:     { label: 'مكتملة',    icon: '✅', cls: 'done',     order: 3 }
};

// ── LocalStorage Helpers ──
function loadTasks() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY) || localStorage.getItem('mm_tasks');
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    console.error('Error loading tasks:', e);
    return [];
  }
}

function saveTasks(tasks) {
  try {
    const jsonStr = JSON.stringify(tasks);
    localStorage.setItem(STORAGE_KEY, jsonStr);
    localStorage.setItem('mm_tasks', jsonStr); // sync with main portal
    window.dispatchEvent(new CustomEvent('tasksUpdated', { detail: tasks }));
    return true;
  } catch (e) {
    console.error('Error saving tasks:', e);
    return false;
  }
}

function getTask(id) {
  const tasks = loadTasks();
  return tasks.find(t => String(t.id) === String(id)) || null;
}

function createTask(data) {
  const tasks = loadTasks();
  const now = new Date().toISOString();
  const newTask = {
    id: data.id || ('tsk_' + Date.now() + '_' + Math.random().toString(36).substr(2, 5)),
    title: data.title || 'مهمة جديدة',
    description: data.description || '',
    category: data.category || 'timeline',
    timeframe: data.timeframe || '',
    steps: Array.isArray(data.steps) ? data.steps : [],
    committees: Array.isArray(data.committees) ? data.committees : [],
    headName: data.headName || '',
    priority: data.priority || 'normal',
    isActive: !!data.isActive,
    status: data.status || (data.isActive ? 'received' : 'inactive'),
    dueDate: data.dueDate || '',
    createdAt: data.createdAt || now,
    updatedAt: data.updatedAt || now,
    timeline: data.timeline || {
      created: now,
      received: data.isActive ? now : null,
      progress: null,
      done: null
    }
  };
  tasks.unshift(newTask);
  saveTasks(tasks);
  return newTask;
}

function updateTask(id, updates) {
  const tasks = loadTasks();
  const idx = tasks.findIndex(t => String(t.id) === String(id));
  if (idx === -1) return null;

  const now = new Date().toISOString();
  const existing = tasks[idx];
  const updated = {
    ...existing,
    ...updates,
    updatedAt: now
  };

  // Keep timeline in sync if status changes
  if (updates.status && updates.status !== existing.status) {
    if (!updated.timeline) updated.timeline = {};
    updated.timeline[updates.status] = now;
  }

  tasks[idx] = updated;
  saveTasks(tasks);
  return updated;
}

function deleteTask(id) {
  const tasks = loadTasks().filter(t => String(t.id) !== String(id));
  saveTasks(tasks);
  return true;
}

function toggleActive(id, isActive) {
  const task = getTask(id);
  if (!task) return null;
  const now = new Date().toISOString();
  const updates = { isActive: !!isActive };

  if (isActive) {
    if (task.status === 'inactive') {
      updates.status = 'received';
      if (!task.timeline) task.timeline = {};
      task.timeline.received = now;
      updates.timeline = task.timeline;
    }
  } else {
    updates.status = 'inactive';
  }

  return updateTask(id, updates);
}

function advanceStatus(id) {
  const task = getTask(id);
  if (!task || !task.isActive) return null;
  const ord = ['inactive', 'received', 'progress', 'done'];
  const curIdx = ord.indexOf(task.status);
  if (curIdx === -1 || curIdx >= ord.length - 1) return task;

  const nextStatus = ord[curIdx + 1];
  const now = new Date().toISOString();
  const timeline = { ...(task.timeline || {}) };
  timeline[nextStatus] = now;

  return updateTask(id, {
    status: nextStatus,
    timeline
  });
}

function getAdminPin() {
  return localStorage.getItem(PIN_KEY) || DEFAULT_PIN;
}

function setAdminPin(pin) {
  localStorage.setItem(PIN_KEY, String(pin).trim());
}

// ── Rendering & Formatting Helpers ──
function formatDate(isoStr) {
  if (!isoStr) return '—';
  try {
    const d = new Date(isoStr);
    return d.toLocaleDateString('ar-EG', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch (e) {
    return isoStr;
  }
}

function renderBadgeStatus(status) {
  const s = STATUSES[status] || STATUSES.inactive;
  return `<span class="badge badge-status badge-status-${s.cls}">${s.icon} ${s.label}</span>`;
}

function renderCategoryBadge(catId) {
  const cat = CATEGORIES[catId];
  if (!cat) return '';
  return `<span class="badge badge-category badge-category-${cat.id}">${cat.icon} ${cat.shortLabel}</span>`;
}

function renderStepsList(steps) {
  if (!Array.isArray(steps) || steps.length === 0) return '';
  return `
    <div class="task-steps-box">
      <div class="task-steps-header">
        <span class="task-steps-icon">📋</span>
        <span class="task-steps-title">خطوات العمل وتوجيهات التنفيذ:</span>
        <span class="task-steps-count">${steps.length} خطوات</span>
      </div>
      <ul class="task-steps-list">
        ${steps.map((st, i) => `
          <li class="task-step-item">
            <span class="step-num">${i + 1}</span>
            <span class="step-text">${st}</span>
          </li>
        `).join('')}
      </ul>
    </div>
  `;
}

function renderTimeline(task) {
  const steps = [
    { key: 'received', label: 'استُلمت', icon: '📥' },
    { key: 'progress', label: 'قيد التنفيذ', icon: '⚡' },
    { key: 'done',     label: 'مكتملة',   icon: '✅' }
  ];

  const ord = ['inactive', 'received', 'progress', 'done'];
  const curIdx = ord.indexOf(task.status);

  return `
    <div class="timeline-stepper">
      ${steps.map((st, i) => {
        const stepIdx = i + 1; // 1: received, 2: progress, 3: done
        const isCompleted = curIdx >= stepIdx;
        const isCurrent = curIdx === stepIdx;
        const timeVal = task.timeline && task.timeline[st.key] ? formatDate(task.timeline[st.key]) : '';
        return `
          <div class="timeline-step ${isCompleted ? 'completed' : ''} ${isCurrent ? 'current' : ''}">
            <div class="step-dot">${st.icon}</div>
            <div class="step-label">${st.label}</div>
            ${timeVal ? `<div class="step-time">${timeVal}</div>` : ''}
          </div>
          ${i < steps.length - 1 ? `<div class="step-line ${curIdx > stepIdx ? 'active' : ''}"></div>` : ''}
        `;
      }).join('')}
    </div>
  `;
}

// ── Toast Notification ──
function showToast(message, type = 'info') {
  let container = document.getElementById('toastContainer');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toastContainer';
    container.className = 'toast-container';
    document.body.appendChild(container);
  }

  const icons = { success: '✅', error: '❌', info: 'ℹ️', warning: '⚠️' };
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.innerHTML = `
    <span class="toast-icon">${icons[type] || '🔔'}</span>
    <span class="toast-msg">${message}</span>
  `;

  container.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(10px)';
    setTimeout(() => toast.remove(), 300);
  }, 3500);
}

// ── Official Plan Tasks (Comprehensive 15 Tasks Covering All Phases) ──
const OFFICIAL_PLAN_TASKS = [
  // ─────────────────────────────────────────────────────────────
  // 1. الجدول الزمني والمراحل الرئيسية (Timeline & Key Phases)
  // ─────────────────────────────────────────────────────────────
  {
    id: 'tsk_p1_interviews',
    category: 'timeline',
    title: 'المرحلة الأولى: التقديمات والمقابلات (Interviews)',
    timeframe: 'من 10/12 إلى 10/21',
    dueDate: '2026-10-21',
    description: 'إعلان فتح باب التقديم ومتابعة الاستشارات والاستمارات (Deadline التقديم: الثلاثاء 10/20)، فرز المتقدمين وتحديد مواعيد المقابلات، وإجراء المقابلات من السبت 10/17 إلى الأربعاء 10/21 واختيار المقبولين.',
    steps: [
      'إعلان فتح باب التقديم ومتابعة الاستشارات والاستمارات (الموعد النهائي للتقديم: الثلاثاء 10/20).',
      'فرز المتقدمين وتحديد مواعيد المقابلات الشخصية وتوزيع اللجان.',
      'إجراء الانترفيوهات من السبت 10/17 إلى الأربعاء 10/21 واختيار المقبولين رسمياً.'
    ],
    committees: ['HR', 'PR', 'Social Media'],
    headName: 'مسؤول الموارد البشرية (HR Head)',
    priority: 'high',
    isActive: true,
    status: 'progress',
    createdAt: '2026-10-12T09:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-12T09:00:00.000Z',
      received: '2026-10-12T10:00:00.000Z',
      progress: '2026-10-17T09:00:00.000Z',
      done: null
    }
  },
  {
    id: 'tsk_p2_onboarding',
    category: 'timeline',
    title: 'المرحلة الثانية: التسكين والترحيب بالأعضاء الجدد',
    timeframe: 'من 10/22 إلى 10/24',
    dueDate: '2026-10-24',
    description: 'إضافة الأعضاء المقبولين إلى لجانهم الرسمية بعد فرز المقابلات، وإرسال رسائل الترحيب الرسمية وتوجيههم ودمجهم ضمن قنوات الفريق.',
    steps: [
      'إضافة الأعضاء المقبولين إلى لجانهم وقنواتهم الرسمية.',
      'إرسال رسائل الترحيب ودمجهم مع الفريق وتهيئتهم لبدء العمل.'
    ],
    committees: ['HR', 'PR', 'PM'],
    headName: 'إدارة العمليات والـ HR',
    priority: 'high',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_p3_training',
    category: 'timeline',
    title: 'المرحلة الثالثة: التأهيل والتدريب الداخلي (Onboarding)',
    timeframe: 'من 10/24 إلى 10/31',
    dueDate: '2026-10-31',
    description: 'بدء التدريب والتعليم المبدئي للأعضاء الجدد (Members) وعقد اجتماع رسمي (Meeting) لكل لجنة مع أعضائها الجدد خلال الفترة من 10/24 إلى 10/31.',
    steps: [
      'بدء التدريب والتعليم المبدئي للأعضاء الجدد (Members) وفق خطة وتخصص كل لجنة.',
      'عقد اجتماع (Meeting) لكل لجنة مع أعضائها الجدد خلال الفترة من 10/24 إلى 10/31.'
    ],
    committees: ['جميع اللجان', 'HR'],
    headName: 'رؤساء اللجان (Heads) & HR',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_p4_trip',
    category: 'timeline',
    title: 'المرحلة الرابعة (أ): تنظيم الرحلة الأولى للفريق',
    timeframe: 'حتى 11/5 (قبل الميدترم)',
    dueDate: '2026-11-05',
    description: 'التنسيق والترتيب المبكر بين الأعضاء القدامى لتنظيم الرحلة الأولى للفريق، والتنفيذ في الموعد المحدد لتجنب التعارض مع امتحانات الميدترم.',
    steps: [
      'التنسيق والترتيب المبكر بين الأعضاء القدامى للرحلة وإعداد البرنامج والأنشطة.',
      'التنفيذ الفعلي في الموعد المحدد (Deadline: 11/5) لتجنب التعارض مع امتحانات الميدترم.'
    ],
    committees: ['Logistics', 'HR'],
    headName: 'مسؤول اللوجستيك وتنظيم الرحلات',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_p4_helpdesk',
    category: 'timeline',
    title: 'المرحلة الرابعة (ب): فعالية الـ Help Desk والمساعدة الطلابية',
    timeframe: 'تحضير: 11/15 إلى 11/19 | انطلاق: 11/20',
    dueDate: '2026-11-20',
    description: 'فترة التحضير والتجهيز من 11/15 إلى 11/19 (لمدة 5 أيام) وإعداد وتجهيز كافة الأنشطة، وانطلاق الفعالية رسمياً لخدمة الطلاب يوم 11/20.',
    steps: [
      'فترة التحضير والتجهيز: من 11/15 إلى 11/19 (لمدة 5 أيام) وإعداد كافة الأنشطة والمطبوعات.',
      'موعد الانطلاق الرسمي: افتتاح وانطلاق الفعالية رسمياً على الأرض لخدمة الطلاب يوم 11/20.'
    ],
    committees: ['IT & Tech', 'PR', 'Logistics'],
    headName: 'فريق الـ Help Desk والتقنية',
    priority: 'high',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },

  // ─────────────────────────────────────────────────────────────
  // 2. خطة الفصل الدراسي الثاني (Plan for Second Term)
  // ─────────────────────────────────────────────────────────────
  {
    id: 'tsk_t2_bazaar',
    category: 'term2',
    title: 'خطة الترم الثاني: تنظيم بازار مخصص للفريق والأنشطة (Bazaar)',
    timeframe: 'بداية الفصل الدراسي الثاني',
    dueDate: '2027-02-28',
    description: 'تنظيم بازار مخصص للفريق والأنشطة والمنتجات الطلابية، يشمل حجز المكان، الترويج والتسويق، والتنسيق المسبق مع الرعاة والمشاركين.',
    steps: [
      'تنظيم بازار مخصص للفريق/الأنشطة وحجز الموقع والتنسيق الميداني.',
      'التواصل مع الرعاة والمشاركين وتجهيز الأجنحة والمعروضات.',
      'الحملة التسويقية والترويجية الشاملة لجذب الطلاب والزوار.'
    ],
    committees: ['PR', 'Logistics', 'Social Media'],
    headName: 'مسؤول العلاقات العامة واللوجستيك',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_t2_ramadan_helpdesk',
    category: 'term2',
    title: 'خطة الترم الثاني: هيلب ديسك رمضان (Ramadan Help Desk)',
    timeframe: 'طوال شهر رمضان المبارك',
    dueDate: '2027-03-10',
    description: 'تقديم خدمات الدعم والمساعدة والإرشاد الأكاديمي والطلابي بروح رمضانية وتخصيص نقاط الدعم وقنوات التواصل السريعة للطلاب.',
    steps: [
      'تخصيص قنوات ونقاط دعم سريع للاستفسارات الأكاديمية خلال شهر رمضان.',
      'تقديم النصائح والإرشادات الأكاديمية ومساندة الطلاب في المذاكرة وتنظيم الوقت.'
    ],
    committees: ['IT & Tech', 'PR', 'HR'],
    headName: 'مسؤول الدعم الفني والعلاقات العامة',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_t2_ramadan_bags',
    category: 'term2',
    title: 'خطة الترم الثاني: شنط رمضان والعمل الخيري (Ramadan Bags)',
    timeframe: 'ما قبل بداية شهر رمضان',
    dueDate: '2027-03-05',
    description: 'إعداد وتجهيز شنط رمضان والمواد الغذائية للعمل الخيري، جمع التبرعات، وتنظيم خطة التوزيع الميداني وتوصيلها للأسر الأكثر احتياجاً.',
    steps: [
      'جمع التبرعات والمساهمات الخيرية وتحديد ميزانية الشنط الغذائية.',
      'شراء وتعبئة المواد الغذائية بالتعاون المشترك بين جميع الأعضاء.',
      'تنفيذ خطة التوزيع الميداني وتوصيل الشنط للأسر المستحقة.'
    ],
    committees: ['Charity', 'Logistics', 'PR'],
    headName: 'لجنة الخيرية (Charity Head)',
    priority: 'high',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_t2_scientific',
    category: 'term2',
    title: 'خطة الترم الثاني: السيشنز والأنشطة العلمية (Scientific Research)',
    timeframe: 'طوال الفصل الدراسي الثاني',
    dueDate: '2027-03-25',
    description: 'تقديم ورش عمل وسلسلة سيشنز علمية تخصصية ومواصلة أنشطة وأبحاث الفريق، وتأهيل وتدريب الأعضاء لمشاريع ومسابقات البحث العلمي.',
    steps: [
      'تقديم سيشنز علمية دورية في المجالات التخصصية والبحثية.',
      'مواصلة أنشطة البحث العلمي وتأهيل الأعضاء لمشاريع ومسابقات الابتكار.',
      'تدريب الأعضاء على المنهجية العلمية والتحليل الإحصائي وكتابة الأوراق البحثية.'
    ],
    committees: ['Scientific'],
    headName: 'مسؤول اللجنة العلمية (Scientific Head)',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_t2_interactive',
    category: 'term2',
    title: 'خطة الترم الثاني: الفعاليات التفاعلية ونشاط الميكروفون المفتوح',
    timeframe: 'خلال فعاليات الترم الثاني',
    dueDate: '2027-03-28',
    description: 'تنظيم فعاليات تفاعلية جانبية ونشاط الميكروفون المفتوح لتعزيز التفاعل والروح الإيجابية، مع فتح الباب لاستقبال أي تصورات وأفكار إضافية من الأعضاء.',
    steps: [
      'تنظيم نشاط الميكروفون والفعاليات الجانبية التفاعلية بالحرم الجامعي.',
      'فتح الباب لاستقبال أي تصورات أو أفكار إضافية ومقترحات من الأعضاء ودراستها للتنفيذ.'
    ],
    committees: ['Social Media', 'PR'],
    headName: 'مسؤول السوشيال ميديا والتفاعل',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },

  // ─────────────────────────────────────────────────────────────
  // 3. آلية التنفيذ والمتابعة (Let's Execute!)
  // ─────────────────────────────────────────────────────────────
  {
    id: 'tsk_exec_guidelines',
    category: 'execution',
    title: 'آلية التنفيذ والمتابعة الميدانية (Let\'s Execute!)',
    timeframe: 'مستمر طوال فترة العمل',
    dueDate: '2026-12-15',
    description: 'من التخطيط إلى التنفيذ: تحويل الأفكار إلى خطوات عملية فورية على الأرض بروح الفريق الواحد، والالتزام الصارم بالديدلاين والتواصل اللحظي المستمر.',
    steps: [
      'الالتزام التام بالمواعيد والديدلاين المحدد لكل مهمة دون أي تأخير.',
      'التواصل المستمر والتعاون اللحظي بين مختلف اللجان لضمان انسيابية العمل.',
      'عقد جلسات مناقشة وأسئلة (Discussion & Q&A) لتبادل الآراء وتوزيع المهام وتلقي الاستفسارات.'
    ],
    committees: ['PM', 'HR', 'جميع اللجان'],
    headName: 'إدارة العمليات والتنفيذ',
    priority: 'high',
    isActive: true,
    status: 'progress',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: '2026-10-20T12:00:00.000Z',
      done: null
    }
  },

  // ─────────────────────────────────────────────────────────────
  // 4. مقترحات التطوير والتحسين المؤسسي (Proposed Improvements)
  // ─────────────────────────────────────────────────────────────
  {
    id: 'tsk_imp_roles',
    category: 'improvement',
    title: 'مقترحات التطوير: تحديد اللجان وتوزيع الأدوار (Committees)',
    timeframe: 'مرحلة إعادة الهيكلة والتوزيع',
    dueDate: '2026-11-10',
    description: 'تحديد اللجان والأدوار: توزيع الأدوار والمهام بوضوح تام على اللجان المختلفة (Committees) لمنع التداخل ورفع كفاءة الإنجاز.',
    steps: [
      'تحديد اللجان والأدوار وتوزيع المهام بوضوح على اللجان المختلفة (Committees).',
      'توصيف مسؤوليات كل عضو ورئيس لجنة بدقة لتفادي أي تضارب مهام.'
    ],
    committees: ['HR', 'PM'],
    headName: 'إدارة الفريق والـ HR',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_imp_channels',
    category: 'improvement',
    title: 'مقترحات التطوير: تفعيل قنوات التواصل وقواعد العمل (Channels)',
    timeframe: 'مستمر ومُعتمد',
    dueDate: '2026-11-12',
    description: 'قنوات التواصل: تفعيل قنوات تواصل رسمية وقواعد عمل واضحة (Channels) لضمان سرعة تداول المعلومات وإخطار الأعضاء بكل المستجدات.',
    steps: [
      'تفعيل قنوات تواصل رسمية وقواعد عمل واضحة (Channels).',
      'إلزام الجميع بالبروتوكولات الرسمية للتواصل وتبادل الملفات.'
    ],
    committees: ['PR', 'IT & Tech', 'HR'],
    headName: 'مسؤول الاتصال المؤسسي',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_imp_evaluation',
    category: 'improvement',
    title: 'مقترحات التطوير: نظام تقييم الأداء والمتابعة الأسبوعية (Evaluation)',
    timeframe: 'متابعة دورية أسبوعية',
    dueDate: '2026-11-30',
    description: 'تقييم الأداء: تطبيق نظام دوري لتقييم وتحفيز الأعضاء (Evaluation)، ومتابعة دورية أسبوعية للمهام والإنتاجية لضمان جودة العمل وتعزيز التعاون بين اللجان لتجنب تضارب المهام.',
    steps: [
      'تطبيق نظام دوري لتقييم وتحفيز الأعضاء (Evaluation).',
      'متابعة دورية أسبوعية للمهام والإنتاجية لضمان جودة العمل.',
      'تعزيز التعاون بين اللجان لتجنب تضارب المهام.'
    ],
    committees: ['HR', 'PM'],
    headName: 'مسؤولو الـ HR وإدارة العمليات',
    priority: 'high',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  },
  {
    id: 'tsk_imp_brainstorming',
    category: 'improvement',
    title: 'مقترحات التطوير: باركود العصف الذهني واستقبال الاقتراحات (Brainstorming QR Code)',
    timeframe: 'من 11/15 فصاعداً',
    dueDate: '2026-11-25',
    description: 'العصف الذهني: استخدام باركود (QR Code) لجمع الاقتراحات والأفكار الجديدة (Brainstorming) وإتاحة فرصة المشاركة الفعالة لجميع الأعضاء في تطوير المنظومة.',
    steps: [
      'استخدام باركود (QR Code) تفاعلي لجمع الاقتراحات والأفكار الجديدة (Brainstorming).',
      'فرز الأفكار ودراستها وتطبيق المبادرات الإيجابية بالتعاون بين اللجان.'
    ],
    committees: ['IT & Tech', 'PM', 'جميع اللجان'],
    headName: 'لجنة التقنية وإدارة المشاريع',
    priority: 'normal',
    isActive: true,
    status: 'received',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: {
      created: '2026-10-20T12:00:00.000Z',
      received: '2026-10-20T12:00:00.000Z',
      progress: null,
      done: null
    }
  }
];

// ── Demo Seeding & Automatic Plan Sync ──
function seedDemo(forceReset = false) {
  let existing = loadTasks();
  const storedVersion = localStorage.getItem(PLAN_VERSION_KEY);

  if (forceReset || !existing || existing.length === 0 || storedVersion !== CURRENT_PLAN_VERSION) {
    const officialIds = new Set(OFFICIAL_PLAN_TASKS.map(t => t.id));
    const userCustomTasks = (existing || []).filter(t => !officialIds.has(t.id));

    // Merge official plan tasks while keeping status if user had toggled it
    const mergedOfficial = OFFICIAL_PLAN_TASKS.map(officialTask => {
      const found = (existing || []).find(t => t.id === officialTask.id);
      if (found && !forceReset) {
        return {
          ...officialTask,
          isActive: found.isActive !== undefined ? found.isActive : officialTask.isActive,
          status: found.status || officialTask.status,
          timeline: found.timeline || officialTask.timeline
        };
      }
      return { ...officialTask };
    });

    const finalTasks = [...mergedOfficial, ...userCustomTasks];
    saveTasks(finalTasks);
    localStorage.setItem(PLAN_VERSION_KEY, CURRENT_PLAN_VERSION);
    return finalTasks;
  }

  // Ensure all official tasks exist
  let updated = false;
  OFFICIAL_PLAN_TASKS.forEach(planTask => {
    const found = existing.some(t => t.id === planTask.id);
    if (!found) {
      existing.push({ ...planTask });
      updated = true;
    }
  });

  if (updated) {
    saveTasks(existing);
  }
  return existing;
}
