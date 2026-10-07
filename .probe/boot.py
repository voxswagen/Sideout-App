import io, re, subprocess, os, shutil, sys
D='/Users/angelopaolodequina/Documents/GitHub/Sideout-App'
s = io.open(D+'/index.html', encoding='utf-8').read()
head = ('<script>window.__E=[];window.addEventListener("error",function(e){'
        'window.__E.push(e.message+" @"+e.lineno+":"+e.colno);},true);</script>')
tail = ('<script>window.addEventListener("load",function(){setTimeout(function(){'
        'var o=[];o.push("errors="+((window.__E||[]).join(" // ")||"none"));'
        'var on=document.querySelector(".screen.on");o.push("screen="+(on?on.id:"NONE"));'
        'o.push("bodyText="+(document.body.innerText||"").trim().length);'
        'o.push("tabbar="+((document.getElementById("tabbar")||{}).hidden));'
        'var d=document.createElement("div");d.id="xray";d.textContent=o.join(" ;; ");'
        'document.body.appendChild(d);},1500);});</script>')
io.open(D+'/__probe.html','w',encoding='utf-8').write(
    s.replace('<head>', '<head>'+head, 1).replace('</body>', tail+'</body>'))
shutil.rmtree('/tmp/cpb', ignore_errors=True)
out = b''
try:
    r = subprocess.run(['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '--headless','--disable-gpu','--no-sandbox','--user-data-dir=/tmp/cpb',
      '--virtual-time-budget=8000','--window-size=500,900','--dump-dom',
      'file://'+D+'/__probe.html'], capture_output=True, timeout=45)
    out = r.stdout
except subprocess.TimeoutExpired as e:
    out = e.stdout or b''
txt = out.decode('utf-8', 'replace')
m = re.search(r'<div id="xray">(.*?)</div>', txt, re.S)
print('\n'.join((m.group(1) if m else 'NO XRAY (dump %d bytes)' % len(txt)).split(' ;; ')))
os.remove(D+'/__probe.html')
