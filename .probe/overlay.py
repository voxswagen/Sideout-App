import io, re, subprocess, os, shutil
D='/Users/angelopaolodequina/Documents/GitHub/Sideout-App'
s = io.open(D+'/index.html', encoding='utf-8').read()
head = ('<script>window.__E=[];window.addEventListener("error",function(e){'
        'window.__E.push(e.message+" @"+e.lineno);},true);</script>')
tail = r'''<script>window.addEventListener("load",function(){setTimeout(function(){
var o=[];
try{
  Auth.signedIn=function(){return true;};
  Auth.session={access_token:"x"};
  Auth.me={id:"m1",name:"Vox",club:"sideout",role:"owner"};
  Auth.role=function(){return "owner";};
  Auth.isOrganizer=function(){return true;};
  Live.rpc=function(){return Promise.resolve([]);};
  Live.api=function(){return Promise.resolve([]);};
  AuthUI.shown=false;

  /* 1. the bug class that bit twice: an element carrying [hidden] whose
        computed display is not none, i.e. a CSS rule outbidding it. */
  var bad=[].slice.call(document.querySelectorAll("[hidden]")).filter(function(e){
    return getComputedStyle(e).display!=="none";
  }).map(function(e){return (e.id||e.className||e.tagName);});
  o.push("[hidden] but still displayed: "+(bad.join(", ")||"none"));

  /* 2. per screen: anything fixed/absolute, visible, big, outside the live
        screen -- i.e. something laid over the page. */
  var SC=["home","games","board","market","me","chats","session","past",
          "results","groups","player","members","listing","share","comments"];
  SC.forEach(function(n){
    try{ go(n); }catch(e){ o.push(n+": go threw "+e.message); return; }
    var on=document.querySelector(".screen.on");
    var vw=innerWidth, vh=innerHeight;
    var over=[].slice.call(document.querySelectorAll("body *")).filter(function(e){
      var c=getComputedStyle(e);
      if(c.position!=="fixed" && c.position!=="absolute") return false;
      if(c.display==="none"||c.visibility==="hidden"||parseFloat(c.opacity)<0.02) return false;
      if(e.id==="toast") return false;
      var r=e.getBoundingClientRect();
      if(r.width*r.height < 12000) return false;          /* ignore small chrome */
      if(r.bottom<0||r.top>vh||r.right<0||r.left>vw) return false;  /* offscreen */
      if(on && on.contains(e)) return false;              /* part of the screen */
      return true;
    }).map(function(e){
      var r=e.getBoundingClientRect();
      return (e.id||("."+String(e.className).split(" ")[0]))
        +"["+Math.round(r.width)+"x"+Math.round(r.height)+"@"+Math.round(r.top)+"]";
    });
    var sw=document.documentElement.scrollWidth;
    o.push(n+": overlays="+(over.join(" ")||"none")
      +(sw>vw+1?"  H-OVERFLOW scrollW="+sw+" vw="+vw:""));
  });
}catch(e){ o.push("THREW: "+e.message+" @"+(e.stack||"").split("\n")[1]); }
o.push("errors="+((window.__E||[]).join(" | ")||"none"));
var d=document.createElement("div");d.id="xray";d.textContent=o.join(" ;; ");
document.body.appendChild(d);},1600);});</script>'''
io.open(D+'/__ov.html','w',encoding='utf-8').write(
    s.replace('<head>','<head>'+head,1).replace('</body>', tail+'</body>'))
shutil.rmtree('/tmp/cov', ignore_errors=True)
out=b''
try:
    r=subprocess.run(['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '--headless','--disable-gpu','--no-sandbox','--user-data-dir=/tmp/cov',
      '--virtual-time-budget=12000','--window-size=500,860','--dump-dom',
      'file://'+D+'/__ov.html'], capture_output=True, timeout=120)
    out=r.stdout
except subprocess.TimeoutExpired as e:
    out=e.stdout or b''
txt=out.decode('utf-8','replace')
m=re.search(r'<div id="xray">(.*?)</div>', txt, re.S)
print('\n'.join((m.group(1) if m else 'NO XRAY (%d bytes)'%len(txt)).split(' ;; ')))
os.remove(D+'/__ov.html')
