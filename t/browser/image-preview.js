// Exercise the image-preview iframe through the real modern entry editor.
// Uses an owned disposable fixture and requires bin/dev/screenshot dependencies.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const vm = require('node:vm');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    let fixture;
    let fixtureDone;
    let browser;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/image-preview-fixture.pl'],
            {stdio: ['pipe', 'pipe', 'inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error('image fixture cleanup failed: ' + code + '/' + signal)));
            fixture.once('error', reject);
        });
        fixtureDone.catch(() => {});
        const fixtureData = await new Promise((resolve, reject) => {
            let output = '';
            fixture.stdout.on('data', data => {
                output += data;
                const newline = output.indexOf('\n');
                if (newline < 0) return;
                try { resolve(JSON.parse(output.slice(0, newline))); }
                catch (error) { reject(error); }
            });
            fixture.once('error', reject);
            fixture.once('exit', code => reject(new Error('image fixture exited before startup: ' + code)));
        });
        browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable', args:['--no-sandbox']});
        const page = await browser.newPage();
        const errors = [];
        const networkErrors = [];
        const imageDialogResponses = [];
        const unexpectedDialogs = [];
        let rejectUnexpectedDialog;
        const unexpectedDialog = new Promise((resolve, reject) => { rejectUnexpectedDialog = reject; });
        // Keep a handler attached after the first failure, while individual UI actions race
        // against this promise and fail promptly.
        unexpectedDialog.catch(() => {});
        const withoutUnexpectedDialog = (step, action) => Promise.race([action(), unexpectedDialog])
            .catch(error => { throw new Error(step + ': ' + error.message); });
        const trace = step => {
            if (process.env.FCK_DIALOG_DEBUG) console.error('[fck-image] ' + step);
        };
        page.on('pageerror', e => errors.push(e.message));
        page.on('dialog', async dialog => {
            const message = dialog.type() + ': ' + dialog.message();
            unexpectedDialogs.push(message);
            console.error('[fck-image] unexpected browser dialog: ' + message);
            // Dismiss only so the runner can tear down; every caller racing this promise
            // rejects with the exact dialog instead of continuing as a pass.
            await dialog.dismiss();
            rejectUnexpectedDialog(new Error('unexpected browser dialog: ' + message));
        });
        page.on('requestfailed', request => networkErrors.push(request.url() + ': ' + request.failure()?.errorText));
        page.on('response', response => {
            if (response.status() >= 400) networkErrors.push(response.status() + ': ' + response.url());
            if (new URL(response.url()).pathname === '/imguploadrte.bml') imageDialogResponses.push(response.url());
        });
        const base = 'http://127.0.0.1:8080';
        const openDialog = async suffix => {
            trace('open ' + suffix + ': wait for shell iframe');
            await page.waitForFunction(() => !!document.querySelector('iframe[src*="fckdialog.html"]'),
                {timeout: 10000});
            trace('open ' + suffix + ': wait for dialog network idle');
            await page.waitForNetworkIdle({idleTime: 200, timeout: 10000});
            const shells = page.frames().filter(frame => frame.url().endsWith('/fckdialog.html'));
            assert.equal(shells.length, 1, 'exactly one current FCK dialog shell exists');
            const shell = shells[0];
            assert.ok(shell, 'FCK dialog shell exists');
            trace('open ' + suffix + ': wait for shell OK');
            await shell.waitForSelector('#btnOk', {timeout: 10000});
            const dialog = page.frames().find(frame => frame.url().endsWith(suffix));
            assert.ok(dialog, 'FCK dialog loads its expected inner document');
            trace('open ' + suffix + ': wait for inner OnLoad and preview');
            await dialog.waitForFunction(
                () => window.bPreviewInitialized && window.oEditor && document.querySelector('#txtUrl'),
                {timeout: 10000}
            );
            trace('open ' + suffix + ': ready');
            return {shell, dialog};
        };
        const acceptDialog = async (shell, predicate, message) => {
            trace(message + ': click OK');
            await shell.waitForSelector('#btnOk', {timeout: 10000});
            await withoutUnexpectedDialog(message + ': click OK', () => shell.click('#btnOk'));
            trace(message + ': wait for shell detach');
            await page.waitForFunction(
                () => !document.querySelector('iframe[src*="fckdialog.html"]'),
                {timeout: 10000}
            );
            trace(message + ': render turns');
            await page.evaluate(() => new Promise(resolve => requestAnimationFrame(
                () => requestAnimationFrame(resolve))));
            trace(message + ': wait for editor update');
            await page.waitForFunction(predicate, {timeout: 10000});
            assert.ok(true, message);
            trace(message + ': complete');
        };
        await page.goto(base + '/mobile/login', {waitUntil:'networkidle0'});
        await page.type('[name=user]', fixtureData.user);
        await page.type('[name=password]', fixtureData.password);
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
        const {shell, dialog} = await openDialog('/imguploadrte.bml');
        const preview = page.frames().find(f => f.url().endsWith('/imgpreview'));
        assert.ok(preview, 'actual dialog embeds preview');
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
        await acceptDialog(shell,
            () => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false).includes('Preview regression'),
            'normal Image confirmation updates the editor after shell detachment');
        if (process.env.IMAGE_PREVIEW_FAIL_AFTER_MUTATION) {
            throw new Error('intentional image fixture cleanup probe');
        }
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
        const {shell: editShell, dialog: edit} = await openDialog('/imguploadrte.bml');
        assert.equal(await edit.$eval('#txtAlt', e => e.value), 'Preview regression', 'existing image loads for editing');
        await edit.$eval('#txtAlt', e => { e.value = 'Edited preview'; });
        await edit.$eval('#txtLnkUrl', (e, value) => {e.value = value;}, base + '/about');
        await edit.evaluate(() => UpdatePreview());
        await acceptDialog(editShell,
            () => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false).includes('Edited preview'),
            'edited normal Image confirmation updates the editor after shell detachment');
        const edited = await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false));
        assert.match(edited, /Edited preview/);
        assert.match(edited, /href="[^" ]*\/about"/);
        await withoutUnexpectedDialog('open ImageButton insertion dialog', () => page.evaluate(() => {
            const editor = FCKeditorAPI.GetInstance('entry-body');
            editor.Focus();
            const image = editor.EditorDocument.querySelector('img');
            const range = editor.EditorDocument.createRange();
            range.setStartAfter(image);
            range.collapse(true);
            const selection = editor.EditorWindow.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            editor.Commands.GetCommand('ImageButton').Execute();
        }));
        const {shell: imageButtonShell, dialog: imageButtonDialog} = await openDialog('/imguploadrte.bml?ImageButton');
        assert.ok(imageButtonDialog, 'actual ImageButton opens the native dialog with its exact query');
        assert.ok(imageDialogResponses.some(url => url.endsWith('/imguploadrte.bml?ImageButton')),
            'ImageButton receives an exact native dialog response');
        await imageButtonDialog.type('#txtUrl', base + '/img/search.gif');
        await imageButtonDialog.type('#txtAlt', 'Image button preview');
        const imageButtonOutput = process.argv[2] || '/tmp/image-preview';
        await page.screenshot({path:imageButtonOutput + '/image-button-dialog.png', fullPage:true});
        await acceptDialog(imageButtonShell,
            () => FCKeditorAPI.GetInstance('entry-body').EditorDocument.querySelector('input[type=image]'),
            'ImageButton insertion updates the editor after shell detachment');
        assert.deepEqual(await page.evaluate(() => {
            const input = FCKeditorAPI.GetInstance('entry-body').EditorDocument.querySelector('input[type=image]');
            return [input.src, input.alt];
        }), [base + '/img/search.gif', 'Image button preview'], 'ImageButton inserts an input-image element');
        await page.evaluate(() => {
            const editor = FCKeditorAPI.GetInstance('entry-body');
            editor.Focus();
            const input = editor.EditorDocument.querySelector('input[type=image]');
            const range = editor.EditorDocument.createRange();
            range.selectNode(input);
            const selection = editor.EditorWindow.getSelection();
            selection.removeAllRanges(); selection.addRange(range);
            editor.Commands.GetCommand('ImageButton').Execute();
        });
        const {shell: editedImageButtonShell, dialog: editedImageButtonDialog} =
            await openDialog('/imguploadrte.bml?ImageButton');
        await editedImageButtonDialog.waitForFunction(() => document.querySelector('#txtAlt').value === 'Image button preview',
            {timeout: 10000});
        assert.equal(await editedImageButtonDialog.$eval('#txtAlt', e => e.value), 'Image button preview',
            'ImageButton editing loads the input-image attributes');
        await editedImageButtonDialog.$eval('#txtAlt', e => { e.value = 'Edited image button'; });
        await acceptDialog(editedImageButtonShell,
            () => FCKeditorAPI.GetInstance('entry-body').EditorDocument.querySelector('input[type=image]').alt === 'Edited image button',
            'ImageButton edit updates the input-image element after shell detachment');
        assert.equal(await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').EditorDocument.querySelector('input[type=image]').alt),
            'Edited image button', 'ImageButton editing updates the input-image element');
        await page.select('#editor', 'html_raw0');
        assert.match(await page.$eval('#entry-body', e => e.value), /Edited preview/, 'image survives HTML switch');
        // Leave the seeded draft empty; this test never submits an entry.
        await page.$eval('#entry-body', e => { e.value = ''; e.dispatchEvent(new Event('input', {bubbles:true})); });
        console.log('Inserted and edited preview image successfully');
        assert.deepEqual(errors, [], 'no image-dialog JS errors');
        assert.deepEqual(networkErrors, [], 'no image-dialog network errors');
        assert.deepEqual(unexpectedDialogs, [], 'ImageButton insertion opens no conversion confirmation');
        console.log('PASS: real editor iframe, callback registration, loading, sizing, alt text, insertion');
    } finally {
        try { if (browser) await browser.close(); }
        finally {
            if (fixture) {
                fixture.stdin.end();
                await fixtureDone;
            }
        }
    }
})().catch(e => { console.error(e); process.exit(1); });
