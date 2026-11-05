/*
 * Frontend-only first pass.
 * When the private backend is ready, replace the demo enqueue in addDownloads()
 * with POST /api/downloads and stream job state from GET /api/downloads/:id.
 */
const state = { view: 'download', kind: 'video', jobs: [], demoMode: true };
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

function showToast(message) {
  const toast = $('#toast');
  toast.textContent = message;
  toast.classList.add('is-visible');
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.remove('is-visible'), 2700);
}

function setView(view) {
  state.view = view;
  $$('.view').forEach((section) => section.classList.toggle('is-visible', section.id === `view-${view}`));
  $$('.nav-pill').forEach((button) => button.classList.toggle('is-active', button.dataset.view === view));
  window.scrollTo({ top: 0, behavior: 'smooth' });
  render();
}

function parseLinks() {
  return $('#links-input').value.split(/\n+/).map((value) => value.trim()).filter(Boolean);
}

function titleFor(url) {
  try { return new URL(url).hostname.replace(/^www\./, ''); } catch { return 'Novo download'; }
}

function formatForJob() {
  return state.kind === 'audio' ? $('#audio-quality-select').value.replace(' ', ' · ') : $('#quality-select').value;
}

function addDownloads() {
  const links = parseLinks();
  if (!links.length) { showToast('Cole pelo menos um link para começar.'); $('#links-input').focus(); return; }
  const invalid = links.find((link) => !/^https?:\/\//i.test(link));
  if (invalid) { showToast('Use links começando com http:// ou https://.'); return; }
  const newJobs = links.map((url, index) => ({ id: crypto.randomUUID?.() ?? `${Date.now()}-${index}`, url, title: titleFor(url), detail: `${state.kind === 'audio' ? 'Áudio' : 'Vídeo'} · ${$('#format-select').value.toUpperCase()} · ${formatForJob()}`, progress: 0, status: 'queued', createdAt: Date.now() }));
  state.jobs = [...newJobs, ...state.jobs];
  $('#links-input').value = '';
  showToast(`${newJobs.length} ${newJobs.length === 1 ? 'item adicionado' : 'itens adicionados'} à fila.`);
  render();
  if (state.demoMode) newJobs.forEach((job, index) => window.setTimeout(() => simulateJob(job.id), index * 850));
  // Production integration point:
  // await fetch('/api/downloads', { method: 'POST', headers: {'content-type':'application/json'}, body: JSON.stringify({links, options}) });
}

function simulateJob(id) {
  const job = state.jobs.find((item) => item.id === id);
  if (!job || job.status === 'done') return;
  job.status = 'active';
  const tick = () => {
    const current = state.jobs.find((item) => item.id === id);
    if (!current) return;
    current.progress = Math.min(100, current.progress + Math.ceil(Math.random() * 16));
    current.status = current.progress >= 100 ? 'done' : 'active';
    render();
    if (current.status !== 'done') window.setTimeout(tick, 650);
  };
  tick();
}

function cancelJob(id) { state.jobs = state.jobs.filter((job) => job.id !== id); showToast('Download removido da fila.'); render(); }

function renderJob(job) {
  const status = job.status === 'done' ? 'Concluído' : job.status === 'active' ? 'Baixando agora' : 'Na fila';
  const action = job.status === 'done' ? '<button class="job-action" data-action="save">Salvar</button>' : `<span class="job-percent">${job.progress}%</span>`;
  return `<article class="job-card"><div class="job-main"><div class="job-title" title="${job.url}">${job.title}</div><div class="job-detail">${job.detail}</div>${job.status !== 'done' ? `<div class="job-progress"><span style="width:${job.progress}%"></span></div>` : ''}</div><div class="job-side">${action}<div class="job-state">${status}</div></div></article>`;
}

function render() {
  const active = state.jobs.filter((job) => job.status === 'active').length;
  const queued = state.jobs.filter((job) => job.status === 'queued').length;
  const done = state.jobs.filter((job) => job.status === 'done').length;
  $('#active-count').textContent = active + queued;
  $('#stat-active').textContent = active;
  $('#stat-queued').textContent = queued;
  $('#stat-done').textContent = done;
  const count = parseLinks().length;
  $('#link-count').textContent = `${count} ${count === 1 ? 'link' : 'links'}`;
  const recent = state.jobs.slice(0, 3);
  $('#recent-list').innerHTML = recent.map(renderJob).join('');
  $('#recent-empty').classList.toggle('is-hidden', recent.length > 0);
  $('#activity-list').innerHTML = state.jobs.map(renderJob).join('');
  $('#activity-empty').classList.toggle('is-hidden', state.jobs.length > 0);
  const completed = state.jobs.filter((job) => job.status === 'done');
  $('#completed-list').innerHTML = completed.map(renderJob).join('');
  $('#completed-empty').classList.toggle('is-hidden', completed.length > 0);
}

$$('[data-view]').forEach((button) => button.addEventListener('click', () => setView(button.dataset.view)));
$$('[data-view-target]').forEach((button) => button.addEventListener('click', () => setView(button.dataset.viewTarget)));
$$('.segment').forEach((button) => button.addEventListener('click', () => {
  state.kind = button.dataset.kind;
  $$('.segment').forEach((item) => item.classList.toggle('is-selected', item === button));
  $('#video-settings').classList.toggle('is-hidden', state.kind !== 'video');
  $('#audio-settings').classList.toggle('is-hidden', state.kind !== 'audio');
  $('#format-select').innerHTML = state.kind === 'audio' ? '<option>MP3</option><option>M4A</option><option>OPUS</option><option>FLAC</option><option>WAV</option>' : '<option value="mp4">MP4</option><option value="webm">WebM</option><option value="mkv">MKV</option><option value="gif">GIF</option>';
}));
$('#download-button').addEventListener('click', addDownloads);
$('#links-input').addEventListener('input', render);
$('#paste-button').addEventListener('click', async () => { try { $('#links-input').value = await navigator.clipboard.readText(); render(); showToast('Links colados.'); } catch { showToast('Permita o acesso à área de transferência ou cole manualmente.'); } });
$('#formats-button').addEventListener('click', () => showToast(parseLinks().length ? 'A consulta de formatos será conectada ao backend.' : 'Cole um link primeiro.'));
document.addEventListener('click', (event) => { if (event.target.matches('[data-action="save"]')) showToast('O download estará disponível aqui quando o backend estiver conectado.'); });
render();
