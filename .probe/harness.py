import io, sys, subprocess, re, os
SRC = '/Users/angelopaolodequina/Documents/GitHub/Sideout-App/index.html'
OUT = '/Users/angelopaolodequina/Documents/GitHub/Sideout-App/__probe.html'
PROBE = """
<script>
(function(){
 var out=[], errs=[], rpcs=[], apis=[];
 var WRITES=/save|archive|_rate|unarchive|restore|delete/i;
 window.addEventListener('error',function(e){ errs.push(e.message); });
 window.addEventListener('unhandledrejection',function(e){
   errs.push('promise: '+(e.reason&&e.reason.message||e.reason)); });
 function dump(){ document.documentElement.innerHTML =
   '<body>PROBE_BEGIN\\n'+out.join('\\n')+'\\nPROBE_END</body>'; }
 window.addEventListener('load', function(){ setTimeout(function(){
  try{
   Live.rpc=function(n){ rpcs.push(n); return Promise.resolve(null); };
   Live.api=function(p,o){ apis.push((o&&o.method||'GET')+' '+String(p).split('?')[0]);
     return Promise.resolve([]); };
   Auth.on=function(){return true;}; Auth.signedIn=function(){return true;};
   Auth.me={role:'owner'}; window.canOrganize=function(){return true;};
   Auth.isOwner=function(){return true;}; Auth.isOrganizer=function(){return true;};
   /* a night loaded, read-only */
   S.mode='gauntlet'; S.active=true; S.round=3; S.target=11; S.timed=false;
   S.title='Wednesday'; S.liveCode='R6YYA'; S.live=true; S.scores=true;
   S.order=[]; S.players={};
   for(var i=0;i<10;i++){ var id='p'+i;
     S.players[id]={id:id,name:'P'+i,level:'int',g:2,w:1,l:1,pf:9,pa:7,sat:0,out:false};
     S.order.push(id); }
   S.courts=[{teams:[['p0','p1'],['p2','p3']],pts:{a:9,b:7},sc:null,win:null},
             {teams:[['p4','p5'],['p6','p7']],pts:{a:11,b:5},sc:{w:11,l:5},win:0}];
   S.queue=['p8','p9']; S.log=[{r:1,c:0,win:['P0','P1'],lose:['P2','P3'],ws:11,ls:5}];

   var KEEP=['home','games','board','market','chats','me','session','past',
             'results','groups','group','player','members','roles','audit',
             'listing','share','comments','auth'];
   out.push('=== kept screens ===');
   KEEP.forEach(function(n){
     var before=errs.length;
     try{ go(n); }catch(e){ errs.push('go('+n+'): '+e.message); }
     var on=document.querySelector('.screen.on');
     var txt=on?(on.innerText||'').trim().length:0;
     var bad=errs.length>before;
     /* Every other screen must actually be display:none. A `display` stated on
        an id-and-class selector outbids `.screen{display:none}`, so a screen
        can be permanently visible underneath whatever is on — which draws two
        screens at once and is invisible to a check that only ever asks what
        `.on` is. #screen-auth.ah did exactly that. */
     var extra=[].slice.call(document.querySelectorAll('.screen')).filter(function(e){
       return e!==on && getComputedStyle(e).display!=='none';
     }).map(function(e){return e.id;});
     if(extra.length) errs.push('go('+n+'): also visible: '+extra.join(','));
     out.push('  '+(n+'            ').slice(0,12)+' -> '
       +(on?on.id:'(none)')+'  text:'+txt
       +(extra.length?'   *** ALSO VISIBLE: '+extra.join(',')+' ***':'')
       +(bad?'   *** ERROR: '+errs.slice(before).join(' / ')+' ***':''));
   });
   out.push('');
   out.push('=== gone screens redirect ===');
   GONE_SCREENS.forEach(function(n){
     var before=errs.length;
     try{ go(n); }catch(e){ errs.push('go('+n+'): '+e.message); }
     var on=document.querySelector('.screen.on');
     out.push('  '+(n+'         ').slice(0,10)+' -> '+(on?on.id:'(none)')
       +(errs.length>before?'  *** '+errs.slice(before).join(' / ')+' ***':''));
   });
   out.push('');
   /* painters that run outside go() */
   out.push('=== painters ===');
   [['paintHome',function(){paintHome();}],
    ['renderAll',function(){renderAll();}],
    ['renderSession',function(){renderSession();}],
    ['syncDocks',function(){syncDocks();}],
    ['syncNav',function(){syncNav(currentScreen());}],
    ['save',function(){save();}],
    ['snapshot',function(){Live.snapshot();}]].forEach(function(p){
     try{ p[1](); out.push('  '+p[0]+'  ok'); }
     catch(e){ out.push('  '+p[0]+'  *** '+e.message+' ***'); errs.push(p[0]+': '+e.message); }
   });
   setTimeout(function(){
     out.push('');
     var bad=rpcs.filter(function(n){return WRITES.test(n);})
       .concat(apis.filter(function(a){return !/^GET/.test(a);}));
     out.push('writes to shared db: '+(bad.length?'*** '+bad.join(' / ')+' ***':'none'));
     out.push('window errors: '+(errs.length?'*** '+errs.length+': '+errs.slice(0,6).join(' | ')+' ***':'none'));
     dump();
   },500);
  }catch(e){ out.push('FATAL '+e.message+' | '+String(e.stack).split('\\n')[1]); dump(); }
 },900); });
})();
</script>
"""
s = io.open(SRC, encoding='utf-8').read()
io.open(OUT,'w',encoding='utf-8').write(s.replace('</body>', PROBE+'</body>'))
r = subprocess.run(['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '--headless','--disable-gpu','--no-sandbox','--virtual-time-budget=16000',
  '--window-size=500,900','--dump-dom','file://'+OUT],
  capture_output=True, text=True)
m = re.search(r'PROBE_BEGIN(.*?)PROBE_END', r.stdout, re.S)
txt = m.group(1) if m else 'NO RESULT\n'+r.stdout[-1500:]
for a,b in [('&quot;','"'),('&#39;',"'"),('&amp;','&'),('&lt;','<'),('&gt;','>')]:
    txt = txt.replace(a,b)
print(txt)
try: os.remove(OUT)
except: pass
