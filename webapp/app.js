/* Same-origin API: Vercel forwards /api to Render. */
const API_BASE = (window.YTDLP_API_BASE || window.location.origin).replace(/\/$/, '');
const state = { view:'download', kind:'video', jobs:[], authenticated:false, collection:null, selected:new Set() };
const $ = (s) => document.querySelector(s), $$ = (s) => [...document.querySelectorAll(s)];
const esc = (v) => String(v ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function showToast(message) { $('#toast').textContent=message; $('#toast').classList.add('is-visible'); clearTimeout(showToast.timer); showToast.timer=setTimeout(()=>$('#toast').classList.remove('is-visible'),3500); }
function setView(view) { state.view=view; $$('.view').forEach(s=>s.classList.toggle('is-visible',s.id==='view-'+view)); $$('.nav-pill').forEach(b=>{b.classList.toggle('is-active',b.dataset.view===view); b.setAttribute('aria-current',b.dataset.view===view?'page':'false');}); window.scrollTo({top:0,behavior:'smooth'}); render(); }
async function api(path,payload) {
  let response; try { response=await fetch(API_BASE+path,{credentials:'include',...(payload===undefined?{}:{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload)})}); } catch { throw Error('Não foi possível conectar ao servidor. Tente novamente em instantes.'); }
  if(!response.ok) { if(response.status===401) {state.authenticated=false; $('#login-overlay').classList.remove('is-hidden');} const body=await response.json().catch(()=>({})); throw Error(typeof body.detail==='string'?body.detail:'Não foi possível concluir. Tente novamente.'); } return response.json();
}
function parseLinks() { return $('#links-input').value.split(/\n+/).map(v=>v.trim()).filter(Boolean); }
function normalizeJob(j) { return {...j,title:j.title||'Download',detail:j.detail||'Download',progress:Math.max(0,Math.min(100,Number(j.progress)||0))}; }
async function addDownloads() {
  const links=parseLinks(); if(!links.length){showToast('Cole pelo menos um link.');return;} if(links.length>5){showToast('Adicione até 5 links por vez.');return;} if(links.some(l=>!/^https?:\/\//i.test(l))){showToast('Use links começando com http:// ou https://.');return;}
  $('#download-button').disabled=true; try {const payload=await api('/api/downloads',{links,options:{kind:state.kind,container:$('#format-select').value.toLowerCase(),quality:$('#quality-select').value.split(' ')[0]}});state.jobs=[...payload.jobs.map(normalizeJob),...state.jobs];$('#links-input').value='';showToast('Downloads adicionados à fila.');render();pollRealJobs();} catch(e){showToast(e.message);} finally{$('#download-button').disabled=false;}
}
function renderJob(j) {
 const status=({done:'Concluído',active:'Baixando agora',error:'Falhou',cancelled:'Cancelado',queued:'Na fila'})[j.status]||'Na fila';
 const action=j.status==='done'?'<a class="job-action" href="'+API_BASE+'/api/downloads/'+encodeURIComponent(j.id)+'/file">Salvar</a>':'<span class="job-percent">'+Math.round(j.progress)+'%</span>';
 return '<article class="job-card"><div class="job-main"><div class="job-title" title="'+esc(j.url)+'">'+esc(j.title)+'</div><div class="job-detail">'+esc(j.detail)+'</div>'+(['active','queued'].includes(j.status)?'<div class="job-progress"><span style="width:'+j.progress+'%"></span></div>':'')+(j.error?'<div class="job-detail">'+esc(j.error)+'</div>':'')+'</div><div class="job-side">'+action+'<div class="job-state">'+status+'</div></div></article>';
}
function render() {
 const active=state.jobs.filter(j=>j.status==='active').length,queued=state.jobs.filter(j=>j.status==='queued').length,done=state.jobs.filter(j=>j.status==='done');
 $('#active-count').textContent=active+queued;$('#stat-active').textContent=active;$('#stat-queued').textContent=queued;$('#stat-done').textContent=done.length;const n=parseLinks().length;$('#link-count').textContent=n+(n===1?' link':' links');
 for(const [name,jobs] of [['recent',state.jobs.slice(0,3)],['activity',state.jobs],['completed',done]]) {$('[id="'+name+'-list"]').innerHTML=jobs.map(renderJob).join('');$('[id="'+name+'-empty"]').classList.toggle('is-hidden',jobs.length>0);}
}
async function pollRealJobs() {clearTimeout(pollRealJobs.timer);if(!state.authenticated)return;try{state.jobs=(await api('/api/downloads')).map(normalizeJob);render();}catch(e){showToast(e.message);}if(state.authenticated&&state.jobs.some(j=>['queued','active'].includes(j.status)))pollRealJobs.timer=setTimeout(pollRealJobs,1800);}
async function login() {const b=$('#login-form button');b.disabled=true;$('#login-error').textContent='Conectando… O servidor pode levar um momento para iniciar.';try{await api('/api/auth/login',{password:$('#login-password').value});state.authenticated=true;$('#login-password').value='';$('#login-error').textContent='';$('#login-overlay').classList.add('is-hidden');await pollRealJobs();}catch(e){$('#login-error').textContent=e.message;}finally{b.disabled=false;}}
async function initBackend() {try{state.authenticated=(await api('/api/auth/session')).authenticated;}catch(e){showToast(e.message);}if(state.authenticated)await pollRealJobs();else $('#login-overlay').classList.remove('is-hidden');}
function renderSelection() {const n=state.selected.size;$('#stories-selection').textContent=n?n+(n===1?' selecionado':' selecionados'):'Nenhum selecionado';$('#stories-download').disabled=!n;$('#stories-select-all').textContent=n===Math.min(50,state.collection.stories.length)?'Desmarcar todos':'Selecionar todos';$$('.story-checkbox').forEach(i=>{i.checked=state.selected.has(i.value);});}
async function listStories(event) {
 event.preventDefault();$('#instagram-list').disabled=true;$('#instagram-list').textContent='Consultando…';$('#instagram-message').textContent='Buscando os Stories disponíveis…';$('#instagram-results').classList.add('is-hidden');state.collection=null;state.selected.clear();
 try {const c=await api('/api/instagram/stories',{username:$('#instagram-profile').value});state.collection=c;$('#instagram-message').textContent=c.stories.length?'Escolha os Stories abaixo. Esta lista fica disponível por 10 minutos.':'Este perfil não tem Stories disponíveis agora.';if(!c.stories.length)return;$('#stories-title').textContent='@'+c.username;$('#stories-count').textContent=c.stories.length+' Stories disponíveis';
 $('#stories-grid').innerHTML=c.stories.map((s,index)=>{const time=s.timestamp?new Date(s.timestamp*1000).toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}):'';return '<label class="story-card"><input class="story-checkbox" type="checkbox" value="'+esc(s.id)+'" aria-label="Selecionar Story '+(index+1)+'" /><div class="story-preview"><img src="'+API_BASE+'/api/instagram/collections/'+encodeURIComponent(c.collectionId)+'/stories/'+encodeURIComponent(s.id)+'/thumbnail" alt="Prévia do Story '+(index+1)+'" loading="lazy" /><span class="story-kind">'+(s.kind==='video'?'Vídeo':'Foto')+'</span></div><span class="story-caption">Story '+(index+1)+'<small>'+esc(time)+'</small></span></label>';}).join('');$('#instagram-results').classList.remove('is-hidden');renderSelection();
 }catch(e){$('#instagram-message').textContent=e.message;}finally{$('#instagram-list').disabled=false;$('#instagram-list').textContent='Listar Stories';}
}
async function downloadStories() {if(!state.collection||!state.selected.size)return;$('#stories-download').disabled=true;try{const p=await api('/api/instagram/downloads',{collectionId:state.collection.collectionId,storyIds:[...state.selected]});state.jobs=[...p.jobs.map(normalizeJob),...state.jobs];state.selected.clear();renderSelection();setView('activity');pollRealJobs();showToast('Seleção adicionada à fila. Ao concluir, toque em Salvar.');}catch(e){showToast(e.message);renderSelection();}}
$$('[data-view]').forEach(b=>b.addEventListener('click',()=>setView(b.dataset.view)));
$$('[data-view-target]').forEach(b=>b.addEventListener('click',()=>setView(b.dataset.viewTarget)));
$$('.segment').forEach(b=>b.addEventListener('click',()=>{state.kind=b.dataset.kind;$$('.segment').forEach(i=>i.classList.toggle('is-selected',i===b));$('#video-settings').classList.toggle('is-hidden',state.kind!=='video');$('#audio-settings').classList.toggle('is-hidden',state.kind!=='audio');$('#format-select').innerHTML=(state.kind==='audio'?['mp3','m4a','opus','flac','wav']:['mp4','webm','mkv','gif']).map(v=>'<option value="'+v+'">'+v.toUpperCase()+'</option>').join('');}));
$('#download-button').addEventListener('click',addDownloads);$('#links-input').addEventListener('input',render);
$('#login-form').addEventListener('submit',e=>{e.preventDefault();login();});
$('#paste-button').addEventListener('click',async()=>{try{$('#links-input').value=await navigator.clipboard.readText();render();}catch{showToast('Cole os links manualmente no campo.');}});
$('#formats-button').addEventListener('click',()=>showToast('Escolha o formato e a qualidade em Como salvar.'));
$('#instagram-form').addEventListener('submit',listStories);
$('#stories-grid').addEventListener('change',e=>{if(!e.target.matches('.story-checkbox'))return;if(e.target.checked&&state.selected.size>=50){e.target.checked=false;showToast('Selecione até 50 Stories por download.');return;}if(e.target.checked)state.selected.add(e.target.value);else state.selected.delete(e.target.value);renderSelection();});
$('#stories-select-all').addEventListener('click',()=>{if(!state.collection)return;state.selected=state.selected.size===Math.min(50,state.collection.stories.length)?new Set():new Set(state.collection.stories.slice(0,50).map(s=>s.id));renderSelection();});
$('#stories-download').addEventListener('click',downloadStories);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)pollRealJobs();});
render();initBackend();
