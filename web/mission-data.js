/**
 * MICROSCOPE MISSION — Core Data & Shared Utilities
 * Handles Task Storage, Lifecycle, Timeline Tracking & Notifications
 */

const STORAGE_KEY = 'mm_tasks_data';
const PIN_KEY = 'mm_admin_pin';
const DEFAULT_PIN = '7600319381';

const STATUSES = {
  inactive: { label: 'غير مفعّلة', icon: '⏸️', cls: 'inactive', order: 0 },
  received: { label: 'استُلمت',   icon: '📥', cls: 'received', order: 1 },
  progress: { label: 'قيد التنفيذ', icon: '⚡', cls: 'progress', order: 2 },
  done:     { label: 'مكتملة',    icon: '✅', cls: 'done',     order: 3 }
};

// ── LocalStorage Helpers ──
function loadTasks() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
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
    localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
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
    id: 'tsk_' + Date.now() + '_' + Math.random().toString(36).substr(2, 5),
    title: data.title || 'مهمة جديدة',
    description: data.description || '',
    committees: Array.isArray(data.committees) ? data.committees : [],
    headName: data.headName || '',
    priority: data.priority || 'normal',
    isActive: !!data.isActive,
    status: data.isActive ? 'received' : 'inactive',
    dueDate: data.dueDate || '',
    createdAt: now,
    updatedAt: now,
    timeline: {
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

// ── Official Plan Tasks (Created as Inactive Drafts) ──
const OFFICIAL_PLAN_TASKS = [
  {
    id: 'tsk_p1_interviews',
    title: 'المرحلة الأولى: التقديمات والمقابلات الرسمية (Interviews)',
    description: 'إعلان فتح باب التقديم ومتابعة الاستشارات والاستمارات (Deadline التقديم: الثلاثاء 10/20)، فرز المتقدمين وتحديد مواعيد المقابلات، وإجراء الانترفيوهات من السبت 10/17 إلى الأربعاء 10/21 واختيار المقبولين.',
    committees: ['HR', 'PR'],
    headName: 'مسؤول الموارد البشرية (HR Head)',
    priority: 'high',
    isActive: false,
    status: 'inactive',
    dueDate: '2026-10-21',
    createdAt: '2026-10-12T09:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-12T09:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_p2_onboarding',
    title: 'المرحلة الثانية: التسكين والترحيب بالأعضاء الجدد',
    description: 'إضافة الأعضاء المقبولين إلى لجانهم الرسمية بعد فرز المقابلات، وإرسال رسائل الترحيب الرسمية ودمجهم ضمن قنوات الفريق (الفترة الزمنية من 10/22 إلى 10/24 - Deadline: 10/24).',
    committees: ['HR', 'PR', 'PM'],
    headName: 'إدارة العمليات والـ HR',
    priority: 'high',
    isActive: false,
    status: 'inactive',
    dueDate: '2026-10-24',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_p3_training',
    title: 'المرحلة الثالثة: التأهيل والتدريب الداخلي (Onboarding)',
    description: 'بدء برامج التدريب والتعليم المبدئي للأعضاء الجدد (Members) وعقد اجتماع رسمي (Meeting) لكل لجنة مع أعضائها الجدد خلال الفترة من 10/24 إلى 10/31 (Deadline: 10/31).',
    committees: ['جميع اللجان', 'HR'],
    headName: 'رؤساء اللجان (Heads) & HR',
    priority: 'normal',
    isActive: false,
    status: 'inactive',
    dueDate: '2026-10-31',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_p4_trip',
    title: 'المرحلة الرابعة (أ): تنظيم الرحلة الأولى للفريق',
    description: 'التنسيق والترتيب المبكر بين الأعضاء القدامى لتنظيم الرحلة الأولى للفريق، والتنفيذ في الموعد المحدد لتجنب التعارض مع امتحانات الميدترم (Deadline: 11/5).',
    committees: ['Logistics', 'HR'],
    headName: 'مسؤول اللوجستيك وتنظيم الرحلات',
    priority: 'normal',
    isActive: false,
    status: 'inactive',
    dueDate: '2026-11-05',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_p4_helpdesk',
    title: 'المرحلة الرابعة (ب): فعالية الـ Help Desk والمساعدة الطلابية',
    description: 'فترة التحضير والتجهيز من 11/15 إلى 11/19 (لمدة 5 أيام) وإعداد وتجهيز كافة الأنشطة والفعاليات، وانطلاق الفعالية رسمياً لخدمة الطلاب يوم 11/20.',
    committees: ['IT & Tech', 'PR', 'Logistics'],
    headName: 'فريق الـ Help Desk والتقنية',
    priority: 'high',
    isActive: false,
    status: 'inactive',
    dueDate: '2026-11-20',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_t2_bazaar',
    title: 'خطة الترم الثاني: تنظيم بازار الفريق السنوي (Bazaar)',
    description: 'إعداد وتجهيز بازار مخصص للفريق والأنشطة والمنتجات الطلابية، يشمل حجز المكان، الترويج والتسويق، والتنسيق المسبق مع الرعاة والمشاركين.',
    committees: ['PR', 'Logistics', 'Social Media'],
    headName: 'مسؤول العلاقات العامة واللوجستيك',
    priority: 'normal',
    isActive: false,
    status: 'inactive',
    dueDate: '2027-02-25',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_t2_ramadan_helpdesk',
    title: 'خطة الترم الثاني: هيلب ديسك رمضان (Ramadan Help Desk)',
    description: 'تقديم خدمات الدعم والمساعدة والإرشاد الأكاديمي والطلابي بروح رمضانية وتخصيص نقاط الدعم وقنوات التواصل السريعة للطلاب خلال الشهر المبارك.',
    committees: ['IT & Tech', 'PR', 'HR'],
    headName: 'مسؤول الدعم الفني والـ PR',
    priority: 'normal',
    isActive: false,
    status: 'inactive',
    dueDate: '2027-03-10',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_t2_ramadan_bags',
    title: 'خطة الترم الثاني: شنط رمضان والعمل الخيري (Ramadan Bags)',
    description: 'إعداد وتجهيز شنط رمضان والمواد الغذائية للعمل الخيري، جمع التبرعات، وتنظيم خطة التوزيع الميداني وتوصيلها للأسر الأكثر احتياجاً.',
    committees: ['Charity', 'Logistics'],
    headName: 'لجنة الخيرية (Charity Head)',
    priority: 'high',
    isActive: false,
    status: 'inactive',
    dueDate: '2027-03-05',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_t2_scientific',
    title: 'خطة الترم الثاني: السيشنز والأنشطة العلمية (Scientific Research)',
    description: 'تقديم ورش عمل وسلسلة سيشنز علمية تخصصية ومواصلة أنشطة وأبحاث الفريق، وتأهيل وتدريب الأعضاء لمشاريع ومسابقات البحث العلمي.',
    committees: ['Scientific'],
    headName: 'مسؤول اللجنة العلمية (Scientific Head)',
    priority: 'normal',
    isActive: false,
    status: 'inactive',
    dueDate: '2027-03-20',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_t2_interactive',
    title: 'خطة الترم الثاني: الفعاليات التفاعلية ونشاط الميكروفون المفتوح',
    description: 'تنظيم فعاليات تفاعلية جانبية ونشاط الميكروفون المفتوح لتعزيز التفاعل والروح الإيجابية، مع فتح الباب لاستقبال أي تصورات وأفكار إضافية من الأعضاء.',
    committees: ['Social Media', 'PR'],
    headName: 'مسؤول السوشيال ميديا والتفاعل',
    priority: 'normal',
    isActive: false,
    status: 'inactive',
    dueDate: '2027-03-28',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_gov_evaluation',
    title: 'التطوير والتحسين المؤسسي: نظام تقييم الأداء والمتابعة الأسبوعية',
    description: 'تطبيق نظام دوري لتقييم وتحفيز الأعضاء، توزيع الأدوار والمهام بوضوح، تفعيل قنوات التواصل الرسمية، والالتزام بالديدلاين ومتابعة دورية أسبوعية للمهام والإنتاجية بروح الفريق الواحد.',
    committees: ['HR', 'PM'],
    headName: 'مسؤولو الـ HR وإدارة العمليات',
    priority: 'high',
    isActive: false,
    status: 'inactive',
    dueDate: '2026-11-30',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  },
  {
    id: 'tsk_gov_brainstorming',
    title: 'التطوير والتحسين المؤسسي: تفعيل باركود العصف الذهني واستقبال الاقتراحات (QR Code)',
    description: 'إطلاق باركود (QR Code) تفاعلي لجمع مقترحات وأفكار الأعضاء الجدد والقدامى، عقد جلسات نقاش وأسئلة (Discussion & Q&A) لتوزيع المهام، وتعزيز التعاون بين اللجان لتجنب تضارب المهام.',
    committees: ['IT & Tech', 'PM', 'جميع اللجان'],
    headName: 'لجنة التقنية وإدارة المشاريع',
    priority: 'normal',
    isActive: false,
    status: 'inactive',
    dueDate: '2026-11-15',
    createdAt: '2026-10-20T12:00:00.000Z',
    updatedAt: '2026-10-20T12:00:00.000Z',
    timeline: { created: '2026-10-20T12:00:00.000Z', received: null, progress: null, done: null }
  }
];

// ── Demo Seeding & Automatic Plan Sync ──
function seedDemo() {
  let existing = loadTasks();

  if (!existing || existing.length === 0) {
    saveTasks(OFFICIAL_PLAN_TASKS);
    return;
  }

  // Ensure all official plan tasks exist in storage without overriding user modifications
  let updated = false;
  OFFICIAL_PLAN_TASKS.forEach(planTask => {
    const found = existing.some(t => t.id === planTask.id || t.title === planTask.title);
    if (!found) {
      existing.push(planTask);
      updated = true;
    }
  });

  if (updated) {
    saveTasks(existing);
  }
}

