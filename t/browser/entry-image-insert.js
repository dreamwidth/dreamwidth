// Native entry image insertion browser test.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

function lineReader(stream, child) {
    let buffer = '', waiting = [], terminal;
    const drain = () => {
        while (waiting.length && buffer.includes('\n')) {
            const line = buffer.slice(0, buffer.indexOf('\n')); buffer = buffer.slice(buffer.indexOf('\n') + 1);
            const waiter = waiting.shift();
            try { waiter.resolve(JSON.parse(line)); } catch (error) { waiter.reject(error); }
        }
        if (terminal) while (waiting.length) waiting.shift().reject(terminal);
    };
    stream.on('data', data => { buffer += data; drain(); });
    child.once('exit', (code, signal) => { terminal = Error(`fixture exited ${code}/${signal}`); drain(); });
    child.once('error', error => { terminal = error; drain(); });
    return () => new Promise((resolve, reject) => { waiting.push({resolve, reject}); drain(); });
}

(async () => {
    let fixture, browser, fixtureDone;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-image-insert-fixture.pl'], {stdio:['pipe','pipe','inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(Error(`fixture ${code}/${signal}`)));
            fixture.once('error', reject);
        }); fixtureDone.catch(() => {});
        const next = lineReader(fixture.stdout, fixture);
        const data = await next();
        const state = async () => { fixture.stdin.write(JSON.stringify({state:1}) + '\n'); return next(); };
        browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable',args:['--no-sandbox']});
        const page = await browser.newPage(), errors = [], failures = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('requestfailed', request => failures.push(request.url()));
        page.on('response', response => { if (response.status() >= 400) failures.push(response.url()); });
        await page.goto('http://127.0.0.1:8080/mobile/login',{waitUntil:'networkidle0'});
        await page.type('[name=user]',data.user); await page.type('[name=password]',data.password);
        await Promise.all([page.waitForNavigation(),page.click('[type=submit]')]);
        const before = await state();
        await page.goto('http://127.0.0.1:8080/entry/new',{waitUntil:'networkidle0'}); const initialURL = page.url(); await page.click('[data-image-insert-open]'); await page.type('#entry-image-url','https://x.invalid/enter.png'); await page.keyboard.press('Enter'); await page.waitForFunction(()=>document.querySelector('[data-image-insert]').hidden); assert.match(await page.$eval('#entry-body',e=>e.value),/enter\.png/); assert.equal(page.url(),initialURL);
        await page.click('[data-image-insert-open]'); await page.focus('[data-image-insert-cancel]'); await page.keyboard.press('Enter'); assert.equal(await page.$eval('[data-image-insert]',e=>e.hidden),true);
        async function insert(path, editor, url, alt) {
            await page.goto('http://127.0.0.1:8080'+path,{waitUntil:'networkidle0'}); await page.select('#editor',editor);
            await page.$eval('#entry-body',e=>{e.value='left RIGHT';e.setSelectionRange(5,10)});
            await page.click('[data-image-insert-open]'); await page.type('#entry-image-url',url); if(alt) await page.type('#entry-image-alt',alt);
            await page.click('[data-image-insert-confirm]'); return page.$eval('#entry-body',e=>e.value);
        }
        for (const editor of ['html_casual1', 'html_raw0', 'markdown0']) {
            const value = await insert('/entry/new', editor, 'https://x.invalid/a.png', 'alt');
            assert.equal(value, 'left <img src="https://x.invalid/a.png" alt="alt">', `${editor} inserts exact markup`);
        }
        const value = await insert(`/entry/${data.user}/${data.id}/edit`,'markdown0','/relative.png','');
        assert.equal(value,'left <img src="/relative.png">');
        await page.goto('http://127.0.0.1:8080/entry/new',{waitUntil:'networkidle0'}); await page.$eval('#entry-body',e=>{e.value='body';e.setSelectionRange(4,4)}); await page.click('[data-image-insert-open]'); await page.type('#entry-image-url','/img/nouserpic.png?x=1&y=2'); await page.type('#entry-image-alt','a"&'); await page.focus('#entry-image-alt'); await page.keyboard.press('Enter'); await page.waitForFunction(()=>document.querySelector('[data-image-insert]').hidden); assert.match(await page.$eval('#entry-body',e=>e.value),/nouserpic\.png\?x=1&amp;y=2.*a&quot;&amp;/);
        await page.select('#editor','rte0'); await page.waitForFunction(()=>window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2); assert.equal(await page.$eval('[data-image-insert-open]',e=>e.hidden),true);
        for (const viewport of [{width:1280,height:800},{width:390,height:844}]) {
            await page.setViewport(viewport); await page.goto('http://127.0.0.1:8080/entry/new',{waitUntil:'networkidle0'}); await page.click('[data-image-insert-open]');
            const visible = await page.$$eval('#entry-image-url,#entry-image-alt,[data-image-insert-confirm],[data-image-insert-cancel]', (els, width, height) => els.every(e => { const r=e.getBoundingClientRect(); return r.left >= 0 && r.right <= width && r.top >= 0 && r.bottom <= height; }), viewport.width, viewport.height);
            assert.equal(visible, true, `image panel controls fit ${viewport.width}px viewport`); await page.screenshot({path:`/tmp/native-image-${viewport.width}.png`,fullPage:true}); await page.click('[data-image-insert-cancel]');
        }
        await page.click('[data-image-insert-open]'); const unchanged=await page.$eval('#entry-body',e=>e.value); await page.click('[data-image-insert-cancel]');
        assert.equal(await page.$eval('#entry-body',e=>e.value),unchanged); assert.equal(await page.$eval('#js-post-entry',e=>e.checkValidity()),true); assert.equal(await page.evaluate(()=>document.activeElement.id),'entry-body');
        const after=await state(); assert.deepEqual(after,before); assert.deepEqual(errors,[]); assert.deepEqual(failures,[]);
        if(process.env.IMAGE_INSERT_INTENTIONAL_FAIL) throw Error('intentional image insertion cleanup');
        console.log('PASS native image new and edit');
    } finally { try { if(browser) await browser.close(); } finally { if(fixture){ fixture.stdin.end(); await fixtureDone; } } }
})().catch(error=>{console.error(error);process.exitCode=1});
