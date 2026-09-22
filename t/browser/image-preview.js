// Exercise the image-preview iframe through the real modern entry editor.
// Requires devcontainer seed users and bin/dev/screenshot dependencies.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable', args:['--no-sandbox']});
    try {
        const page = await browser.newPage();
        const errors = [];
        page.on('pageerror', e => errors.push(e.message));
        const base = 'http://127.0.0.1:8080';
        await page.goto(base + '/mobile/login', {waitUntil:'networkidle0'});
        await page.type('[name=user]', 'test_user');
        await page.type('[name=password]', 'dreamwidth');
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[type=submit]')]);
        for (const sourceURL of ['last', 'https://example.invalid/"quoted\\path</script><script>throw new Error(1)</script>']) {
            const callbackURL = '/imguploadrte.bml?' + new URLSearchParams({
                upload_count:'2', su_1:'first', su_2:sourceURL, pp_2:'full', sw_2:'32', sh_2:'24'
            });
            const callbackHTML = await page.evaluate(async url => (await fetch(url)).text(), callbackURL);
            const callbackScript = [...callbackHTML.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(s => s.includes('InObFCK.onUpload'));
            assert.ok(callbackScript, 'legacy upload-return callback retained');
            const calls = [];
            const context = vm.createContext({InObFCK:{onUpload:(...args)=>calls.push(args)}, window:{}});
            context.window.setTimeout = fn => typeof fn === 'function' ? fn() : vm.runInContext(fn, context);
            vm.runInContext(callbackScript, context);
            context.window.onload();
            assert.deepEqual(calls, [[sourceURL, 'full', 32, 24]], 'last upload callback, including escaped URL');
        }
        await page.goto(base + '/entry/new', {waitUntil:'networkidle0'});
        await page.select('#editor', 'rte0');
        await page.waitForFunction(() => window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2);
        await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').Focus());
        await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').Commands.GetCommand('Image').Execute());
        await page.waitForNetworkIdle();
        const dialog = page.frames().find(f => f.url().endsWith('/imguploadrte.bml'));
        const preview = page.frames().find(f => f.url().endsWith('/imgpreview'));
        assert.ok(dialog && preview, 'actual dialog embeds preview');
        await dialog.waitForFunction(() => window.bPreviewInitialized);
        assert.equal(await dialog.evaluate(() => eImgPreview.ownerDocument === document.querySelector('.ImagePreviewArea').contentDocument), true, 'callback passes actual iframe element');
        await dialog.type('#txtUrl', base + '/img/search.gif');
        await dialog.click('#txtAlt');
        await preview.waitForFunction(() => document.querySelector('#imgPreview').naturalWidth > 0);
        await dialog.waitForFunction(() => window.oImageOriginal && oImageOriginal.naturalWidth > 0);
        const natural = await preview.$eval('#imgPreview', e => [e.naturalWidth, e.naturalHeight]);
        await dialog.click('#btnResetSize');
        assert.equal(await dialog.$eval('#txtWidth', e => Number(e.value)), natural[0]);
        assert.equal(await dialog.$eval('#txtHeight', e => Number(e.value)), natural[1]);
        await dialog.$eval('#txtWidth', e => {e.value = '';});
        await dialog.type('#txtWidth', String(natural[0] * 2));
        assert.equal(await dialog.$eval('#txtHeight', e => Number(e.value)), natural[1] * 2, 'aspect-ratio callback');
        await dialog.type('#txtAlt', 'Preview regression');
        await dialog.evaluate(() => UpdatePreview());
        assert.equal(await preview.$eval('#imgPreview', e => e.alt), 'Preview regression');
        const output = process.argv[2] || '/tmp/image-preview';
        fs.mkdirSync(output, {recursive:true});
        await page.screenshot({path:output + '/dialog.png', fullPage:true});
        const shell = page.frames().find(f => f.url().endsWith('/fckdialog.html'));
        await shell.click('#btnOk');
        await page.waitForFunction(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false).includes('Preview regression'));
        const html = await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false));
        assert.match(html, /search\.gif/);
        await page.evaluate(() => {
            const editor = FCKeditorAPI.GetInstance('entry-body');
            editor.Focus();
            const range = editor.EditorDocument.createRange();
            range.selectNode(editor.EditorDocument.querySelector('img'));
            const selection = editor.EditorWindow.getSelection();
            selection.removeAllRanges(); selection.addRange(range);
        });
        await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').Commands.GetCommand('Image').Execute());
        await page.waitForNetworkIdle();
        const edit = page.frames().find(f => f.url().endsWith('/imguploadrte.bml'));
        assert.equal(await edit.$eval('#txtAlt', e => e.value), 'Preview regression', 'existing image loads for editing');
        await edit.$eval('#txtAlt', e => { e.value = 'Edited preview'; });
        await edit.$eval('#txtLnkUrl', (e, value) => {e.value = value;}, base + '/about');
        await edit.evaluate(() => UpdatePreview());
        await page.frames().find(f => f.url().endsWith('/fckdialog.html')).click('#btnOk');
        const edited = await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false));
        assert.match(edited, /Edited preview/);
        assert.match(edited, /href="[^" ]*\/about"/);
        await page.select('#editor', 'html_raw0');
        assert.match(await page.$eval('#entry-body', e => e.value), /Edited preview/, 'image survives HTML switch');
        // Leave the seeded draft empty; this test never submits an entry.
        await page.$eval('#entry-body', e => { e.value = ''; e.dispatchEvent(new Event('input', {bubbles:true})); });
        console.log('Inserted and edited preview image successfully');
        assert.deepEqual(errors, [], 'no image-dialog JS errors');
        console.log('PASS: real editor iframe, callback registration, loading, sizing, alt text, insertion');
    } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exit(1); });
