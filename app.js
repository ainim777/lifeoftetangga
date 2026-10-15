Warning: truncated output (original token count: 13079)
Total output lines: 224

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cfg=window.LFT_CONFIG||{};
const $=(s,r=document)=>r.querySelector(s);
const $$=(s,r=document)=>[...r.querySelectorAll(s)];
const money=n=>'Rp '+Number(n||0).toLocaleString('id-ID');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const id=()=>crypto.randomUUID();
let sb,session,profile,store;
let page='dashboard';
let data={customers:[],services:[],transactions:[],items:[],expenses:[],inventory:[],closings:[],traffic:[],orders:[],profiles:[],rewards:[]};
const pageTitles={dashboard:'Dashboard',transaksi:'Transaksi',kiloan:'Pesanan Kiloan',pelanggan:'Pelanggan & Membership',layanan:'Layanan & Harga',stok:'Stok',pengeluaran:'Pengeluaran',kas:'Kas & Pembayaran',tutup:'Tutup Buku',laporan:'Laporan Keuangan',pengguna:'Pengguna & Hak Akses',usaha:'Pengaturan Usaha'};
const paymentMethods=['Tunai','QR Mesin','QR Tetangga'];
const channelLabel={self_service:'Self Service',kiloan_retail:'Kiloan Retail',b2b:'B2B'};

function localDate(value=new Date()){
  const parts=new Intl.DateTimeFormat('en-CA',{timeZone:store?.timezone||cfg.timezone||'Asia/Jakarta',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(value);
  const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));return `${p.year}-${p.month}-${p.day}`;
}
function dateLabel(value){return value?new Intl.DateTimeFormat('id-ID',{timeZone:store?.timezone||cfg.timezone||'Asia/Jakarta',day:'2-digit',month:'short',year:'numeric'}).format(new Date(value)):''}
function toast(message){const t=$('#toast');t.textContent=message;t.classList.remove('hidden');clearTimeout(window._toastTimer);window._toastTimer=setTimeout(()=>t.classList.add('hidden'),3500)}
function showAuth(content){$('#appShell').hidden=true;$('#authScreen').hidden=false;$('#authContent').innerHTML=content}
function loginScreen(message=''){
  showAuth(`<h1>Masuk ke akun usaha</h1><p>Gunakan akun yang sudah diaktifkan sebagai pengguna LifeofTetangga.</p>${message?`<div class="notice">${esc(message)}</div>`:''}<form id="loginForm"><div class="field"><label for="loginEmail">Email</label><input id="loginEmail" type="email" autocomplete="username" required></div><div class="field"><label for="loginPassword">Kata sandi</label><input id="loginPassword" type="password" autocomplete="current-password" required></div><div class="auth-error" id="authError"></div><button class="btn" style="width:100%">Masuk</button></form><p style="font-size:11px">Belum punya akses? Minta pemilik usaha menambahkan akunmu.</p>`);
  $('#loginForm').addEventListener('submit',async e=>{e.preventDefault();const b=$('button',e.currentTarget);b.disabled=true;$('#authError').textContent='';const {error}=await sb.auth.signInWithPassword({email:$('#loginEmail').value.trim(),password:$('#loginPassword').value});b.disabled=false;if(error)$('#authError').textContent='Email atau kata sandi belum cocok. Coba lagi.';});
}
function noProfileScreen(){showAuth(`<h1>Akun belum diaktifkan</h1><p>Login berhasil, tetapi akun ini belum dimasukkan ke daftar pengguna LifeofTetangga.</p><div class="notice">Minta pemilik outlet menambahkan profil akun dengan peran Pemilik atau Kasir. Setelah itu, keluar lalu masuk kembali.</div><button class="btn secondary" id="pendingSignOut">Keluar</button>`);$('#pendingSignOut').onclick=()=>sb.auth.signOut()}
function fatal(message){showAuth(`<h1>Aplikasi belum tersambung</h1><p>${esc(message)}</p><button class="btn secondary" onclick="location.reload()">Coba lagi</button>`)}

async function loadData(){
  const specs=[
    ['customers',()=>sb.from('customers').select('*').order('name')],
    ['services',()=>sb.from('service_catalog').select('*').eq('active',true).order('category').order('name')],
    ['transactions',()=>sb.from('transactions').select('*').order('created_at',{ascending:false}).limit(1500)],
    ['items',()=>sb.from('transaction_items').select('*').limit(5000)],
    ['expenses',()=>sb.from('expenses').select('*').order('spent_at',{ascending:false}).limit(1500)],
    ['inventory',()=>sb.from('inventory_items').select('*').order('category').order('name')],
    ['closings',()=>sb.from('daily_closings').select('*').order('business_date',{ascending:false}).limit(400)],
    ['traffic',()=>sb.from('daily_traffic').select('*').order('business_date',{ascending:false}).limit(400)],
    ['orders',()=>sb.from('kiloan_orders').select('*').order('created_at',{ascending:false}).limit(1000)],
    ['profiles',()=>sb.from('profiles').select('id,name,role,active').order('name')],
    ['rewards',()=>sb.from('membership_rewards').select('*').order('expires_at')]
  ];
  const results=await Promise.all(specs.map(async([key,fn])=>[key,await fn()]));
  for(const [key,result] of results){if(result.error)throw result.error;data[key]=result.data||[]}
  const s=await sb.from('stores').select('id,name,timezone').eq('id',profile.store_id).single();if(s.error)throw s.error;store=s.data;
}
async function refresh(){try{await loadData();render()}catch(e){toast('Data tidak berhasil dimuat. Periksa koneksi dan akses akun.');console.error(e)}}
async function startApp(current){
  session=current;
  if(!current){loginScreen();return}
  const p=await sb.from('profiles').select('id,store_id,name,role,active').eq('id',current.user.id).maybeSingle();
  if(p.error||!p.data||!p.data.active){noProfileScreen();return}
  profile=p.data;$('#authScreen').hidden=true;$('#appShell').hidden=false;
  $('#userName').textContent=profile.name;$('#userRole').textContent=profile.role==='owner'?'Pemilik':'Kasir';$('#userAvatar').textContent=(profile.name||'L').trim().charAt(0).toUpperCase();
  try{await loadData();$('#storeMeta').textContent=store.name+' · Data tersimpan di Supabase';render()}catch(e){fatal('Koneksi ke tabel usaha belum siap. '+(e.message||''))}
}

function head(kicker,description,actions=''){return `<header class="page-head"><div><div class="eyebrow">${esc(kicker)}</div><h1>${pageTitles[page]}</h1><p>${esc(description)}</p></div><div class="page-actions">${actions}</div></header>`}
function card(content,cls=''){return `<section class="card ${cls}">${content}</section>`}
function noRows(message){return `<div class="empty-state">${esc(message)}</div>`}
function setPage(next){page=next;$$('.nav').forEach(x=>x.classList.toggle('active',x.dataset.page===page));$('#sidebar').classList.remove('mobile-open');$('#drawerShade').classList.add('hidden');render()}
function render(){if(!profile)return;const f=pages[page]||pages.dashboard;$('#view').innerHTML=f();$$('[data-page]').forEach(b=>b.onclick=()=>setPage(b.dataset.page));wireView()}
function wireView(){const q=$('#tableSearch');if(q)q.addEventListener('input',()=>{$$('#dataTable tbody tr').forEach(r=>r.classList.toggle('hidden',!r.innerText.toLowerCase().includes(q.value.toLowerCase())))});const filter=$('#statusFilter');if(filter)filter.onchange=()=>{$$('#dataTable tbody tr').forEach(r=>r.classList.toggle('hidden',!!filter.value&&r.dataset.status!==filter.value))}}
function currentTransactions(){return data.transactions.filter(t=>t.store_id===profile.store_id)}
function currentItems(){return data.items.filter(i=>i.store_id===profile.store_id)}
function todayTransactions(){const d=localDate();return currentTransactions().filter(t=>localDate(t.created_at)===d&&t.status!=='void'&&t.status!=='refunded')}
function todayExpenses(){const d=localDate();return data.expenses.filter(e=>e.store_id===profile.store_id&&localDate(e.spent_at)===d)}
function actualRevenue(tx){return tx.filter(t=>t.status==='paid').reduce((s,t)=>s+Number(t.total),0)}
function grossRevenue(tx){return tx.filter(t=>t.status!=='void'&&t.status!=='refunded').reduce((s,t)=>s+Number(t.subtotal),0)}
function costFor(txIds){const set=new Set(txIds);return currentItems().filter(i=>set.has(i.transaction_id)).reduce((s,i)=>s+Number(i.line_cost||0),0)}
function chartLines(series,width=720,height=230){
  const values=series.flatMap(s=>s.values),max=Math.max(1,...values),min=Math.min(0,...values),x0=55,x1=700,y0=18,y1=height-28;
  const y=v=>y1-(v-min)/(max-min||1)*(y1-y0),x=i=>x0+i*(x1-x0)/Math.max(1,(series[0].values.length-1));
  const lines=series.map(s=>`<polyline fill="none" stroke="${s.color}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" points="${s.values.map((v,i)=>`${x(i)},${y(v)}`).join(' ')}"/>`).join('');
  const grid=[0,.25,.5,.75,1].map(n=>`<line x1="${x0}" y1="${y0+n*(y1-y0)}" x2="${x1}" y2="${y0+n*(y1-y0)}" stroke="#ececf0"/>`).join('');
  const dots=series.map(s=>s.values.map((v,i)=>`<circle cx="${x(i)}" cy="${y(v)}" r="3.5" fill="${s.color}"/>`).join('')).join('');
  return `<svg class="chart" viewBox="0 0 ${width} ${height}" role="img">${grid}${lines}${dots}</svg>`;
}
function legend(series){return `<div class="chart-legend">${series.map(s=>`<span><i class="dot" style="background:${s.color}"></i>${esc(s.label)}</span>`).join('')}</div>`}
function lineChart(series,labels){return `${chartLines(series)}<div class="chart-labels">${labels.map(x=>`<span>${esc(x)}</span>`).join('')}</div>${legend(series)}`}

function dashboard(){
  const tx=todayTransactions(),paid=tx.filter(t=>t.status==='paid'),exp=todayExpenses(),expenses=exp.reduce((s,e)=>s+Number(e.amount),0),revenue=grossRevenue(tx),received=paid.reduce((s,t)=>s+Number(t.total),0),cogs=costFor(paid.map(t=>t.id)),profit=received-expenses-cogs;
  const pending=tx.filter(t=>t.status==='unpaid'),pendingValue=pending.reduce((s,t)=>s+Number(t.total),0);
  const low=data.inventory.filter(i=>i.store_id===profile.store_id&&Number(i.quantity)<=Number(i.minimum_quantity));
  const activeOrders=data.orders.filter(o=>o.store_id===profile.store_id&&o.status!=='Diambil');
  const visitorDays=[],visitorLabels=[];for(let back=6;back>=0;back--){const d=new Date();d.setDate(d.getDate()-back);const key=localDate(d);visitorDays.push(data.traffic.find(v=>v.business_date===key)?.visitors||0);visitorLabels.push(new Intl.DateTimeFormat('id-ID',{timeZone:store.timezone,weekday:'short'}).format(d))}
  const transactionDays=visitorLabels.map((_,i)=>{const d=new Date();d.setDate(d.getDate()-(6-i));const key=localDate(d);return currentTransactions().filter(t=>localDate(t.created_at)===key&&t.status!=='void'&&t.status!=='refunded').length});
  const series=[{label:'Pengunjung',color:'#c85a32',values:visitorDays},{label:'Nota transaksi',color:'#d4a373',values:transactionDays}];
  const byChannel=['self_service','kiloan_retail','b2b'].map(c=>{const arr=tx.filter(t=>t.channel===c);return [channelLabel[c],arr.length,arr.reduce((s,t)=>s+Number(t.total),0)]});
  const methodSums=paymentMethods.map(m=>{const income=currentTransactions().filter(t=>t.status==='paid'&&t.payment_method===m).reduce((s,t)=>s+Number(t.total),0),spent=data.expenses.filter(e=>e.store_id===profile.store_id&&e.payment_method===m).reduce((s,e)=>s+Number(e.amount),0);return [m,income-spent]});
  const closing=data.closings.find(c=>c.business_date===localDate());
  const demoCount=data.services.filter(s=>s.price_is_demo).length;
  const actions=`<button class="btn secondary" data-action="visitors">Catat pengunjung</button><button class="btn" data-action="transact">＋ Transaksi Baru</button>`;
  return `${head('Ringkasan usaha · '+dateLabel(new Date()),'Pantau pendapatan, volume layanan, kas tercatat, dan pekerjaan hari ini.',actions)}
  ${demoCount?`<div class="notice" style="margin-bottom:14px">${demoCount} tarif masih bertanda demo. Perbarui di Layanan &amp; Harga sebelum menerima pembayaran nyata.</div>`:''}
  <div class="grid stats">${[['Pendapatan Hari Ini',money(revenue),'Nilai transaksi yang dibuat hari ini.','↗'],['Uang Diterima',money(received),'Pembayaran yang sudah dilunasi hari ini.','✓'],['Pengeluaran Hari Ini',money(expenses),'Pengeluaran yang dicatat hari ini.','↘'],['Laba Sementara',money(profit),'Penerimaan dikurangi biaya tercatat.','≈']].map(x=>card(`<span class="stat-mark">${x[3]}</span><div class="stat-label">${x[0]}</div><div class="stat-value">${x[1]}</div><div class="stat-foot">${x[2]}</div>`)).join('')}</div>
  <div class="grid split">${card(`<h2 class="section-title">Tren pengunjung &amp; transaksi</h2><p class="section-sub">Catatan pengunjung dan nota harian · 7 hari terakhir</p>${lineChart(series,visitorLabels)}<p class="stat-foot">Pengunjung dicatat manual; pengunjung tanpa transaksi tetap masuk hitungan.</p>`)}${card(`<h2 class="section-title">Volume transaksi hari ini</h2><p class="section-sub">Jumlah nota menurut jenis layanan</p><div class="bar-list">${byChannel.map(([name,count])=>`<div class="bar-row"><span>${name}</span><div class="bar-track"><i style="width:${Math.min(100,Math.round(count/Math.max(1,...byChannel.map(x=>x[1]))*100))}%"></i></div><b>${count} nota</b></div>`).join('')}</div><div class="notice" style="margin-top:14px">${pending.length} tagihan belum lunas · ${money(pendingValue)}</div>`)}</div>
  <div class="grid split" style="margin-top:14px">${card(`<h2 class="section-title">Saldo transaksi bersih tercatat</h2><p class="section-sub">Penerimaan dikurangi pengeluaran berdasarkan metode · bukan saldo bank</p><div class="balance">${methodSums.map(([m,n])=>`<div><span>${m}</span><b>${money(n)}</b></div>`).join('')}</div>`)}${card(`<h2 class="section-title">Perlu perhatian</h2><p class="section-sub">Operasional dan tutup hari ini</p><div class="list"><div class="list-row"><span>Pesanan Kiloan belum diambil</span><b>${activeOrders.length}</b></div><div class="list-row"><span>Piutang hari ini</span><b>${money(pendingValue)}</b></div><div class="list-row"><span>Stok di bawah batas</span><b>${low.length} barang</b></div><div class="list-row"><span>Tutup buku</span><span class="tag ${closing?'good':'warn'}">${closing?'Sudah ditutup':'Belum ditutup'}</span></div></div>`)}</div>
  <div class="grid split" style="margin-top:14px">${card(`<h2 class="section-title">Pesanan Kiloan aktif</h2><p class="section-sub">Status cucian yang belum diambil</p>${activeOrders.length?`<div class="list">${activeOrders.slice(0,5).map(o=>{const t=currentTransactions().find(x=>x.id===o.transaction_id),c=data.customers.find(x=>x.id===t?.customer_id);return `<div class="list-row"><span><b>${esc(o.order_no)}</b> · ${esc(c?.name||'Pelanggan')}<small class="muted" style="display:block">${esc(o.status)} · ${esc(o.weight_kg)} kg</small></span><span class="tag warn">${esc(o.status)}</span></div>`}).join('')}</div>`:noRows('Belum ada pesanan Kiloan aktif.')}<button class="btn secondary small" data-page="kiloan">Buka antrean</button>`)}${card(`<h2 class="section-title">Transaksi terakhir hari ini</h2><p class="section-sub">${tx.length} nota · terbaru di atas</p>${tx.length?`<div class="list">${tx.slice(0,5).map(t=>`<div class="list-row"><span><b>${esc(t.invoice_no)}</b><small class="muted" style="display:block">${channelLabel[t.channel]} · ${esc(t.status)}</small></span><b>${money(t.total)}</b></div>`).join('')}</div>`:noRows('Belum ada transaksi hari ini.')}`)}</div>`;
}

function transactionPage(){
  const tx=currentTransactions().slice(0,30),customers=new Map(data.customers.map(c=>[c.id,c]));
  return `${head('Catat penjualan','Pilih jenis transaksi. Pembayaran dan membership mengikuti data yang tersimpan.',`<button class="btn secondary" data-action="history">Riwayat lengkap</button>`)}
  <div class="choices"><button class="choice" data-action="transact" data-type="Self Service"><em>◉</em><b>Self Service</b><span>Jasa utama mesin, add-on, produk, dan reward membership otomatis.</span></button><button class="choice" data-action="transact" data-type="Kiloan Retail"><em>▤</em><b>Kiloan Retail</b><span>Berat, layanan kiloan, nomor pesanan, pelanggan, dan status cucian.</span></button><button class="choice" data-action="transact" data-type="B2B"><em>▥</em><b>B2B</b><span>Pelanggan bisnis menggunakan layanan Kiloan. Tidak menambah membership.</span></button></div>
  ${card(`<h2 class="section-title">Transaksi terbaru</h2><p class="section-sub">Tagihan belum lunas dapat dibayar dari kolom aksi.</p>${tx.length?`<div class="toolbar"><input id="tableSearch" class="search" placeholder="Cari nota, nama, atau WhatsApp"></div><div class="table-wrap"><table id="dataTable"><thead><tr><th>Nota</th><th>Pelanggan</th><th>Jenis</th><th>Jumlah</th><th>Status</th><th>Aksi</th></tr></thead><tbody>${tx.map(t=>{const c=customers.get(t.customer_id);return `<tr><td><b>${esc(t.invoice_no)}</b><small class="muted" style="display:block">${dateLabel(t.created_at)}</small></td><td>${esc(c?.name||'Pelanggan umum')}<small class="muted" style="display:block">${esc(c?.whatsapp||'')}</small></td><td>${channelLabel[t.channel]}</td><td>${money(t.total)}${t.membership_discount?`<small class="muted" style="display:block">Reward ${money(t.membership_discount)}</small>`:''}</td><td><span class="tag ${t.status==='paid'?'good':t.status==='unpaid'?'warn':'bad'}">${t.status==='paid'?'Lunas':t.status==='unpaid'?'Belum lunas':t.status==='refunded'?'Refund':'Batal'}</span></td><td>${t.status==='unpaid'?`<button class="btn small" data-action="pay" data-id="${t.id}">Terima pembayaran</button>`:'—'}</td></tr>`}).join('')}</tbody></table></div>`:noRows('Belum ada transaksi. Mulai dengan tombol jenis transaksi di atas.')}`)}`;
}

function kiloanPage(){
  const orders=data.orders.filter(o=>o.store_id===profile.store_id),customers=new Map(data.customers.map(c=>[c.id,c]));
  return `${head('Antrean cucian kiloan','Cari nota, nama, WhatsApp, atau ubah status pengerjaan.',`<button class="btn" data-action="transact" data-type="Kiloan Retail">＋ Pesanan Baru</button>`)}<div class="toolbar"><input id="tableSearch" class="search" placeholder="Cari nomor pesanan, nama, atau WhatsApp"><select id="statusFilter" class="search"><option value="">Semua status</option>${['Masuk','Proses','Selesai','Diambil'].map(x=>`<option>${x}</option>`).join('')}</select></div>${card(orders.length?`<div class="table-wrap"><table id="dataTable"><thead><tr><th>No. pesanan</th><t…4079 tokens truncated… id="transactionForm" data-type="${type}"><div class="notice">Pembayaran lunas menyimpan transaksi ke database. Reward akan dihitung otomatis oleh sistem.</div><div class="form-grid" style="margin-top:14px"><div class="field"><label>Nama pelanggan ${isSelf?'(opsional)':' '}</label><input name="customerName" ${isSelf?'':'required'} placeholder="Nama lengkap"></div><div class="field"><label>Nomor WhatsApp ${isSelf?'(opsional)':' '}</label><input name="whatsapp" ${isSelf?'':'required'} placeholder="08xxxxxxxxxx"></div>${!isSelf?`<div class="field"><label>Nomor pesanan</label><input name="invoice" placeholder="Dibuat otomatis jika kosong"></div><div class="field"><label>Berat (kg)</label><input name="weight" type="number" min="0.1" step="0.1" value="1" required></div>`:''}<div class="field wide"><label>${isSelf?'Jasa utama Self Service':'Layanan Kiloan'}</label><select name="mainService" required>${main.map(serviceOption).join('')}</select></div>${isSelf&&extra.length?`<div class="field wide"><label>Add-on dan produk (opsional)</label><div class="checkbox-list">${extra.map(s=>`<label class="check-item"><input type="checkbox" name="extraService" value="${s.id}" data-price="${s.price}" data-demo="${s.price_is_demo}">${esc(s.name)} · ${money(s.price)}${s.price_is_demo?' <span class="demo-label">demo</span>':''}</label>`).join('')}</div></div>`:''}<div class="field"><label>Status pembayaran</label><select name="paymentStatus"><option value="paid">Lunas</option><option value="unpaid">Belum lunas</option></select></div><div class="field"><label>Metode pembayaran</label><select name="paymentMethod">${paymentMethods.map(m=>`<option>${m}</option>`).join('')}</select></div></div><div class="amount-box" style="margin-top:14px"><span>Perkiraan total</span><span id="transactionTotal">${money(Number(main[0]?.price||0))}</span></div><div class="auth-error" id="formError"></div><button class="btn" style="margin-top:14px">Simpan transaksi</button></form>`);
  const f=$('#transactionForm');f.addEventListener('input',updateTransactionTotal);f.addEventListener('change',updateTransactionTotal);f.addEventListener('submit',saveTransaction);
}
function readTransactionLines(form){
  const t=form.dataset.type,isSelf=t==='Self Service',isB2B=t==='B2B',mainService=data.services.find(s=>s.id===form.elements.mainService.value);const qty=isSelf?1:Number(form.elements.weight?.value||1);
  const selected=[mainService,...(isSelf?$$('input[name="extraService"]:checked',form).map(x=>data.services.find(s=>s.id===x.value)):[])].filter(Boolean);
  return selected.map((s,i)=>({service:s,name:s.name,scope:s.category,quantity:i===0?qty:1,unit_price:Number(s.price),unit_cost:Number(s.estimated_unit_cost||0),line_total:Number(s.price)*(i===0?qty:1)}));
}
function updateTransactionTotal(){const f=$('#transactionForm');if(!f)return;const lines=readTransactionLines(f);$('#transactionTotal').textContent=money(lines.reduce((n,l)=>n+l.line_total,0));}
async function findOrCreateCustomer(name,whatsapp,type){if(!whatsapp)return null;const phone=whatsapp.trim();const existing=data.customers.find(c=>c.store_id===profile.store_id&&c.whatsapp===phone);if(existing){const patch={name:name||existing.name,customer_type:type};const u=await sb.from('customers').update(patch).eq('id',existing.id);if(u.error)throw u.error;return existing.id}const r=await sb.from('customers').insert({store_id:profile.store_id,name:name||'Pelanggan',whatsapp:phone,customer_type:type}).select('id').single();if(r.error)throw r.error;return r.data.id}
function makeInvoice(prefix){const d=localDate().replaceAll('-','').slice(2);return `${prefix}-${d}-${String(Date.now()).slice(-6)}`}
async function saveTransaction(e){
  e.preventDefault();const f=e.currentTarget,b=$('button[type="submit"]',f)||$('button',f),error=$('#formError');b.disabled=true;error.textContent='';
  try{
    const type=f.dataset.type,isSelf=type==='Self Service',isB2B=type==='B2B',status=f.elements.paymentStatus.value,lines=readTransactionLines(f);if(!lines.length)throw Error('Pilih minimal satu layanan.');
    if((!isSelf)&&Number(f.elements.weight.value)<=0)throw Error('Berat harus lebih dari nol.');
    const demo=lines.some(l=>l.service.price_is_demo);if(status==='paid'&&demo)throw Error('Harga demo belum boleh dipakai untuk pembayaran nyata. Atur harga layanan dan tandai sebagai aktif dahulu.');
    const customerId=await findOrCreateCustomer(f.elements.customerName.value.trim(),f.elements.whatsapp.value.trim(),isB2B?'b2b':'retail');
    const invoice=(f.elements.invoice?.value||'').trim()||makeInvoice(isSelf?'SS':'KT');
    const subtotal=lines.reduce((s,l)=>s+l.line_total,0);
    const created=await sb.from('transactions').insert({store_id:profile.store_id,invoice_no:invoice,customer_id:customerId,channel:isSelf?'self_service':isB2B?'b2b':'kiloan_retail',status:'unpaid',subtotal,membership_discount:0,total:subtotal,created_by:session.user.id}).select('id').single();if(created.error)throw created.error;
    const txId=created.data.id;
    const itemRows=lines.map(l=>({store_id:profile.store_id,transaction_id:txId,service_id:l.service.id,name:l.name,scope:l.scope,quantity:l.quantity,unit_price:l.unit_price,unit_cost:l.unit_cost,line_total:l.line_total}));
    const itemResult=await sb.from('transaction_items').insert(itemRows);if(itemResult.error){await sb.from('transactions').delete().eq('id',txId);throw itemResult.error}
    if(!isSelf){const order=await sb.from('kiloan_orders').insert({store_id:profile.store_id,transaction_id:txId,order_no:invoice,weight_kg:Number(f.elements.weight.value),status:'Masuk'});if(order.error){await sb.from('transactions').delete().eq('id',txId);throw order.error}}
    if(status==='paid'){
      const paid=await sb.from('transactions').update({status:'paid',payment_method:f.elements.paymentMethod.value}).eq('id',txId).select('membership_discount,total').single();if(paid.error)throw paid.error;
      toast(`Transaksi tersimpan${paid.data.membership_discount?` · reward ${money(paid.data.membership_discount)} otomatis diterapkan`:''}.`);
    }else toast('Tagihan tersimpan sebagai belum lunas.');
    closeModal();await refresh();
  }catch(err){error.textContent=err.message||'Transaksi belum berhasil disimpan.'}finally{b.disabled=false}
}

function openCustomerForm(){modal('Tambah pelanggan',`<form id="customerForm"><div class="form-grid"><div class="field"><label>Nama</label><input name="name" required></div><div class="field"><label>WhatsApp</label><input name="whatsapp" required placeholder="08xxxxxxxxxx"></div><div class="field"><label>Kategori pelanggan</label><select name="customerType"><option value="retail">Retail</option><option value="b2b">B2B</option></select></div></div><button class="btn" style="margin-top:14px">Simpan pelanggan</button></form>`);$('#customerForm').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget;const r=await sb.from('customers').upsert({store_id:profile.store_id,name:f.elements.name.value.trim(),whatsapp:f.elements.whatsapp.value.trim(),customer_type:f.elements.customerType.value},{onConflict:'store_id,whatsapp'});if(r.error)return toast(r.error.message);closeModal();await refresh();toast('Pelanggan tersimpan.')}}
function openExpenseForm(){modal('Catat pengeluaran',`<form id="expenseForm"><div class="form-grid"><div class="field"><label>Kategori</label><select name="category"><option>Operasional</option><option>Utilitas</option><option>Perlengkapan</option><option>Perbaikan</option><option>Lainnya</option></select></div><div class="field"><label>Jumlah (Rp)</label><input name="amount" type="number" min="1" required></div><div class="field"><label>Metode pembayaran</label><select name="paymentMethod">${paymentMethods.map(m=>`<option>${m}</option>`).join('')}</select></div><div class="field"><label>Catatan</label><input name="note" required placeholder="Contoh: tagihan listrik"></div></div><button class="btn" style="margin-top:14px">Simpan pengeluaran</button></form>`);$('#expenseForm').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,r=await sb.from('expenses').insert({store_id:profile.store_id,category:f.elements.category.value,amount:Number(f.elements.amount.value),payment_method:f.elements.paymentMethod.value,note:f.elements.note.value.trim(),created_by:session.user.id});if(r.error)return toast(r.error.message);closeModal();await refresh();toast('Pengeluaran tersimpan.')}}
function openStockForm(){const products=data.inventory.filter(x=>x.category==='product'),ops=data.inventory.filter(x=>x.category==='operational_supply');modal('Tambah / perbarui stok',`<form id="stockForm"><div class="form-grid"><div class="field"><label>Jenis</label><select name="category"><option value="product">Produk untuk dijual</option><option value="operational_supply">Bahan operasional</option></select></div><div class="field"><label>Barang yang ada</label><select name="existing"><option value="">Barang baru…</option>${[...products,...ops].map(x=>`<option value="${x.id}">${esc(x.name)}</option>`).join('')}</select></div><div class="field"><label>Nama barang</label><input name="name" required></div><div class="field"><label>Satuan</label><input name="unit" required placeholder="pcs, kg, liter"></div><div class="field"><label>Jumlah tersedia</label><input name="quantity" type="number" min="0" step="0.001" required></div><div class="field"><label>Batas minimum</label><input name="minimum" type="number" min="0" step="0.001" required></div><div class="field"><label>Biaya per unit (Rp)</label><input name="cost" type="number" min="0" step="1" value="0" required></div></div><button class="btn" style="margin-top:14px" ${profile.role!=='owner'?'disabled':''}>Simpan stok</button></form>`);const f=$('#stockForm');f.elements.existing.onchange=()=>{const item=data.inventory.find(x=>x.id===f.elements.existing.value);if(item){f.elements.category.value=item.category;f.elements.name.value=item.name;f.elements.unit.value=item.unit;f.elements.quantity.value=item.quantity;f.elements.minimum.value=item.minimum_quantity;f.elements.cost.value=item.unit_cost}};f.onsubmit=async e=>{e.preventDefault();if(profile.role!=='owner')return toast('Hanya pemilik yang bisa mengubah stok.');const payload={store_id:profile.store_id,name:f.elements.name.value.trim(),category:f.elements.category.value,unit:f.elements.unit.value.trim(),quantity:Number(f.elements.quantity.value),minimum_quantity:Number(f.elements.minimum.value),unit_cost:Number(f.elements.cost.value),is_demo:false};const r=await sb.from('inventory_items').upsert(payload,{onConflict:'store_id,name,category'});if(r.error)return toast(r.error.message);closeModal();await refresh();toast('Stok diperbarui.')}}
function openServiceForm(service){if(profile.role!=='owner')return toast('Hanya pemilik yang bisa mengubah harga.');modal('Atur harga layanan',`<form id="serviceForm"><p><b>${esc(service.name)}</b></p><div class="form-grid"><div class="field"><label>Harga jual (Rp / ${esc(service.unit)})</label><input name="price" type="number" min="0" step="1" value="${service.price}" required></div><div class="field"><label>Biaya perkiraan per unit</label><input name="cost" type="number" min="0" step="1" value="${service.estimated_unit_cost}" required></div></div><p class="notice" style="margin-top:12px">Menyimpan perubahan akan menandai harga sebagai tarif aktif, bukan demo.</p><button class="btn" style="margin-top:14px">Simpan tarif</button></form>`);$('#serviceForm').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,r=await sb.from('service_catalog').update({price:Number(f.elements.price.value),estimated_unit_cost:Number(f.elements.cost.value),price_is_demo:false}).eq('id',service.id);if(r.error)return toast(r.error.message);closeModal();await refresh();toast('Tarif diperbarui.')}}
function openVisitorForm(){const day=localDate(),v=data.traffic.find(x=>x.business_date===day);modal('Catat jumlah pengunjung',`<form id="visitorForm"><div class="field"><label>Tanggal usaha</label><input name="date" type="date" value="${day}" required></div><div class="field"><label>Jumlah pengunjung hari itu</label><input name="visitors" type="number" min="0" step="1" value="${v?.visitors||0}" required></div><div class="field"><label>Catatan (opsional)</label><input name="note" value="${esc(v?.note||'')}"></div><button class="btn" style="margin-top:14px">Simpan jumlah pengunjung</button></form>`);$('#visitorForm').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,r=await sb.from('daily_traffic').upsert({store_id:profile.store_id,business_date:f.elements.date.value,visitors:Number(f.elements.visitors.value),note:f.elements.note.value||null,created_by:session.user.id},{onConflict:'store_id,business_date'});if(r.error)return toast(r.error.message);closeModal();await refresh();toast('Jumlah pengunjung tersimpan.')}}
async function payTransaction(txId){const methods=paymentMethods.map(m=>`<option>${m}</option>`).join('');modal('Terima pembayaran',`<form id="payForm"><p>Setelah pembayaran dilunasi, sistem menghitung progres membership dan menerapkan reward yang memenuhi syarat.</p><div class="field"><label>Metode pembayaran</label><select name="method">${methods}</select></div><button class="btn" style="margin-top:14px">Tandai lunas</button></form>`);$('#payForm').onsubmit=async e=>{e.preventDefault();const r=await sb.from('transactions').update({status:'paid',payment_method:e.currentTarget.elements.method.value}).eq('id',txId).select('membership_discount').single();if(r.error)return toast(r.error.message);closeModal();await refresh();toast(r.data.membership_discount?`Lunas · reward ${money(r.data.membership_discount)} otomatis dipakai.`:'Pembayaran lunas.')}}
async function updateOrder(orderId,status){const r=await sb.from('kiloan_orders').update({status,picked_up_at:status==='Diambil'?new Date().toISOString():null}).eq('id',orderId);if(r.error)return toast(r.error.message);await refresh();toast('Status pesanan diperbarui.')}
async function saveClosing(e){e.preventDefault();const f=e.currentTarget;const row={store_id:profile.store_id,business_date:localDate(),cash_counted:Number(f.elements.cash.value),qr_machine_counted:Number(f.elements.machine.value),qr_neighbor_counted:Number(f.elements.neighbor.value),note:f.elements.note.value,closed_by:session.user.id,closed_at:new Date().toISOString()};const balance=m=>currentTransactions().filter(t=>t.status==='paid'&&t.payment_method===m&&localDate(t.paid_at||t.created_at)===row.business_date).reduce((s,t)=>s+Number(t.total),0)-todayExpenses().filter(x=>x.payment_method===m).reduce((s,x)=>s+Number(x.amount),0);row.cash_expected=balance('Tunai');row.qr_machine_expected=balance('QR Mesin');row.qr_neighbor_expected=balance('QR Tetangga');const r=await sb.from('daily_closings').upsert(row,{onConflict:'store_id,business_date'});if(r.error)return toast(r.error.message);await refresh();toast('Tutup buku tersimpan.')}
function exportReport(){const rows=[['Bulan','Nota lunas','Pendapatan bersih','Pengeluaran tercatat','Biaya langsung perkiraan','Laba sementara']];const now=new Date();for(let i=5;i>=0;i--){const d=new Date(now.getFullYear(),now.getMonth()-i,1),key=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`,tx=currentTransactions().filter(t=>t.status==='paid'&&localDate(t.paid_at||t.created_at).startsWith(key)),ex=data.expenses.filter(e=>e.store_id===profile.store_id&&localDate(e.spent_at).startsWith(key)),rev=tx.reduce((s,t)=>s+Number(t.total),0),out=ex.reduce((s,e)=>s+Number(e.amount),0),cost=costFor(tx.map(t=>t.id));rows.push([key,tx.length,rev,out,cost,rev-out-cost])}const csv=rows.map(r=>r.join(',')).join('\n'),a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));a.download='lifeoftetangga-laporan.csv';a.click();URL.revokeObjectURL(a.href)}

document.addEventListener('click',async e=>{
  const b=e.target.closest('[data-action]');if(!b)return;const a=b.dataset.action;
  if(a==='transact')openTransaction(b.dataset.type||'Self Service');
  else if(a==='history')setPage('transaksi');
  else if(a==='customer')openCustomerForm();
  else if(a==='expense')openExpenseForm();
  else if(a==='stock')openStockForm();
  else if(a==='visitors')openVisitorForm();
  else if(a==='pay')payTransaction(b.dataset.id);
  else if(a==='edit-service')openServiceForm(data.services.find(s=>s.id===b.dataset.id));
  else if(a==='close-modal')closeModal();
  else if(a==='modal-backdrop'&&e.target===b)closeModal();
  else if(a==='export-report')exportReport();
});
document.addEventListener('change',e=>{const o=e.target.closest('[data-action="order-status"]');if(o)updateOrder(o.dataset.id,o.value)});
document.addEventListener('submit',e=>{if(e.target.id==='closingForm')saveClosing(e)},{capture:true});
document.addEventListener('submit',async e=>{if(e.target.id==='storeForm'){e.preventDefault();if(profile.role!=='owner')return toast('Hanya pemilik yang dapat mengubah pengaturan.');const f=e.target,r=await sb.from('stores').update({name:f.elements.name.value.trim(),timezone:f.elements.timezone.value}).eq('id',store.id);if(r.error)return toast(r.error.message);await refresh();toast('Pengaturan usaha tersimpan.')}},{capture:true});
$('#menuToggle').onclick=()=>{const aside=$('#sidebar');aside.classList.toggle('mobile-open');$('#drawerShade').classList.toggle('hidden')};$('#drawerShade').onclick=()=>{$('#sidebar').classList.remove('mobile-open');$('#drawerShade').classList.add('hidden')};$('#signOut').onclick=()=>sb.auth.signOut();

try{
  if(!cfg.supabaseUrl||!cfg.publishableKey||!cfg.storeId)throw Error('Konfigurasi Supabase belum lengkap.');
  sb=createClient(cfg.supabaseUrl,cfg.publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
  const {data:{session:current},error}=await sb.auth.getSession();if(error)throw error;
  await startApp(current);
  sb.auth.onAuthStateChange((_event,next)=>{startApp(next)});
}catch(e){fatal('Koneksi Supabase belum bisa dimulai. '+(e.message||''))}
