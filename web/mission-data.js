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

// ── Demo Seeding ──
function seedDemo() {
  const existing = loadTasks();
  if (existing && existing.length > 0) return;

  const now = new Date();
  const d1 = new Date(now.getTime() - 3600000 * 24).toISOString();
  const d2 = new Date(now.getTime() - 3600000 * 12).toISOString();
  const d3 = new Date(now.getTime() - 3600000 * 2).toISOString();

  const demoTasks = [
    {
      id: 'tsk_demo_1',
      title: 'إطلاق حملة التوعية الطبية ومحتوى السوشيال ميديا',
      description: 'تصميم البوسترات ونشر الفيديوهات التوعوية لفعالية Microscope السنوية عبر المنصات.',
      committees: ['Social Media', 'Design', 'PR'],
      headName: 'د. يوسف الشناوي',
      priority: 'high',
      isActive: true,
      status: 'progress',
      dueDate: new Date(now.getTime() + 86400000 * 3).toISOString().split('T')[0],
      createdAt: d1,
      updatedAt: d3,
      timeline: { created: d1, received: d1, progress: d2, done: null }
    },
    {
      id: 'tsk_demo_2',
      title: 'تجهيز قاعات ورش العمل والمطبوعات الإرشادية',
      description: 'حجز وتجهيز أجهزة العرض وتوزيع المواد العلمية على جميع الطلاب المسجلين بالورشة.',
      committees: ['Logistics', 'Organizing'],
      headName: 'م. أحمد خالد',
      priority: 'normal',
      isActive: true,
      status: 'received',
      dueDate: new Date(now.getTime() + 86400000 * 5).toISOString().split('T')[0],
      createdAt: d2,
      updatedAt: d2,
      timeline: { created: d2, received: d2, progress: null, done: null }
    },
    {
      id: 'tsk_demo_3',
      title: 'أرشفة بيانات المشتركين وتحديث قاعدة البيانات',
      description: 'إدخال استمارات العضوية الجديدة في نظام Firebase والتأكد من مطابقة الأرقام القومية.',
      committees: ['IT & Tech', 'HR'],
      headName: 'مؤمن بهاري',
      priority: 'high',
      isActive: true,
      status: 'done',
      dueDate: new Date(now.getTime() - 86400000).toISOString().split('T')[0],
      createdAt: d1,
      updatedAt: d3,
      timeline: { created: d1, received: d1, progress: d2, done: d3 }
    }
  ];

  saveTasks(demoTasks);
}
