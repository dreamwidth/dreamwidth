// Characterize modern entry draft and preview behavior without publishing.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

(async () => {
    let fixture;
    let fixtureDone;
    let browser;
    const base = 'http://127.0.0.1:8080';
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-draft-preview-fixture.pl'],
            {stdio: ['pipe', 'pipe', 'inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0
                ? resolve()
                : reject(new Error(`entry draft fixture cleanup failed: ${code}/${signal}`)));
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
            fixture.once('exit', (code, signal) =>
                reject(new Error(`entry draft fixture exited before startup: ${code}/${signal}`)));
        });

        browser = await puppeteer.launch({
            executablePath: '/usr/bin/google-chrome-stable',
            args: ['--no-sandbox'],
        });
        const page = await browser.newPage();
        const errors = [];
        const dialogs = [];
        let expectedDialog;
        let expectedDialogAction = 'accept';
        page.on('pageerror', error => errors.push(error.message));
        page.on('dialog', async dialog => {
            const received = `${dialog.type()}: ${dialog.message()}`;
            dialogs.push(received);
            if (received === expectedDialog && expectedDialogAction === 'accept') await dialog.accept();
            else await dialog.dismiss();
        });

        const entryCount = async () => {
            const reply = new Promise((resolve, reject) => {
                fixture.stdout.once('data', data => {
                    try { resolve(JSON.parse(data.toString().trim()).entry_count); }
                    catch (error) { reject(error); }
                });
                fixture.once('error', reject);
            });
            fixture.stdin.write('entry_count\n');
            return reply;
        };
        const rpc = async values => page.evaluate(async values => {
            const response = await fetch('/__rpc_draft', {
                method: values ? 'POST' : 'GET',
                headers: values ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {},
                body: values ? new URLSearchParams(values) : undefined,
            });
            return { status: response.status, json: await response.json() };
        }, values);
        const properties = async () => page.evaluate(async () => {
            const response = await fetch('/__rpc_draft?getProperties=1');
            return response.json();
        });

        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('[name=user]', fixtureData.user);
        await page.type('[name=password]', fixtureData.password);
        await Promise.all([
            page.waitForNavigation({waitUntil: 'networkidle0'}),
            page.click('[type=submit]'),
        ]);

        const entriesBefore = await entryCount();
        const original = { draft: (await rpc()).json.draft, properties: await properties() };
        assert.deepEqual(original, {draft: null, properties: {}}, 'disposable user starts with no saved draft');
        const output = process.argv[2] || '/tmp/entry-draft-preview';
        fs.mkdirSync(output, {recursive: true});

        await page.goto(base + '/entry/new', {waitUntil: 'networkidle0'});
        assert.match(await page.$eval('#editor', e => e.value), /^html_/, 'new entry begins in an HTML editor mode');
        await page.select('#editor', 'html_raw0');
        await page.waitForFunction(() => document.querySelector('#editor').value === 'html_raw0');
        await page.$eval('#id-subject-0', e => { e.value = 'Draft title restore marker'; e.dispatchEvent(new Event('change', {bubbles: true})); });
        await page.$eval('#entry-body', e => {
            e.value = '<p>HTML draft marker <strong>kept</strong></p>';
            e.dispatchEvent(new Event('input', {bubbles: true}));
        });
        await page.evaluate(() => { LJDraft.saveProperties(); LJDraft.saveBody(); });
        await page.waitForFunction(async () => (await (await fetch('/__rpc_draft')).json()).draft.includes('HTML draft marker'));
        let saved = { draft: (await rpc()).json.draft, properties: await properties() };
        assert.match(saved.draft, /HTML draft marker/, 'HTML mode saves body through the real draft RPC');
        assert.equal(saved.properties.subject, 'Draft title restore marker', 'HTML mode saves title property');
        assert.equal(saved.properties.editor, 'html_raw0', 'HTML mode saves editor property');

        await page.select('#editor', 'rte0');
        await page.waitForFunction(() => window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2);
        assert.match(
            await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false)),
            /HTML draft marker/,
            'HTML draft survives switch into the real rich-text editor'
        );
        await page.evaluate(() => {
            const editor = FCKeditorAPI.GetInstance('entry-body');
            editor.SetHTML('<p>RTE draft marker <em>kept</em><script>window.draftPreviewLeak = 1;</script></p>');
            LJDraft.saveProperties();
            LJDraft.saveBody();
        });
        await page.waitForFunction(async () => (await (await fetch('/__rpc_draft')).json()).draft.includes('RTE draft marker'));
        saved = { draft: (await rpc()).json.draft, properties: await properties() };
        assert.match(saved.draft, /RTE draft marker/, 'RTE mode saves serialized body through the real draft RPC');
        assert.equal(saved.properties.editor, 'rte0', 'RTE mode saves editor property');

        expectedDialog = 'confirm: Restore from saved draft entitled Draft title restore marker?';
        await page.reload({waitUntil: 'networkidle0'});
        await page.waitForFunction(() => window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2);
        assert.deepEqual(dialogs, [expectedDialog], 'saved draft restoration presents exactly one subject-bearing confirmation');
        assert.equal(await page.$eval('#id-subject-0', e => e.value), 'Draft title restore marker', 'accepted restore restores title');
        assert.equal(await page.$eval('#editor', e => e.value), 'rte0', 'accepted restore restores rich-text editor mode');
        assert.match(
            await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false)),
            /RTE draft marker/,
            'accepted restore restores rich-text body content'
        );
        await page.screenshot({path: output + '/restored-rte.png', fullPage: true});

        const previewTarget = browser.waitForTarget(target => target.opener() === page.target());
        await page.click('#js-preview-button');
        const preview = await (await previewTarget).page();
        await preview.waitForNavigation({waitUntil: 'networkidle0'}).catch(() => {});
        await preview.waitForSelector('.entry-content, #content');
        const previewHTML = await preview.content();
        fs.writeFileSync(output + '/preview.html', previewHTML);
        assert.match(previewHTML, /This is a preview only/i, 'preview response retains preview-only warning');
        assert.equal(await preview.$eval('#pagetitle', e => e.textContent.trim()), 'Draft title restore marker',
            'preview visibly renders the restored title');
        assert.match(await preview.$eval('.entry-content', e => e.textContent), /RTE draft marker/,
            'preview visibly renders the rich-text body');
        assert.ok(await preview.$eval('.entry-content', e => !e.innerHTML.includes('draftPreviewLeak')),
            'preview cleaning removes unsafe rich-text script content');
        await preview.screenshot({path: output + '/preview.png', fullPage: true});
        await preview.close();

        const entriesAfterPreview = await entryCount();
        assert.equal(entriesAfterPreview, entriesBefore, 'draft and preview flow creates no published entries');

        let heldClear;
        let intercepting = true;
        let releaseHeldClear;
        const clearHeld = new Promise(resolve => { releaseHeldClear = resolve; });
        await page.setRequestInterception(true);
        page.on('request', request => {
            if (!intercepting) return;
            if (request.method() === 'POST' && request.url().endsWith('/__rpc_draft')
                && /(?:^|&)clearProperties=1(?:&|$)/.test(request.postData() || '')) {
                heldClear = request;
                releaseHeldClear();
            } else {
                request.continue();
            }
        });
        expectedDialogAction = 'dismiss';
        await page.reload({waitUntil: 'domcontentloaded'});
        await clearHeld;
        await page.focus('#id-subject-0');
        await page.keyboard.type('Delayed clear subject marker');
        await new Promise(resolve => setTimeout(resolve, 4000));
        assert.ok(heldClear, 'declined restore leaves the real draft-clear request pending');
        const clearResponse = page.waitForResponse(response => response.url().endsWith('/__rpc_draft')
            && response.request().method() === 'POST'
            && /(?:^|&)clearProperties=1(?:&|$)/.test(response.request().postData() || ''));
        await heldClear.continue();
        await clearResponse;
        await page.waitForFunction(() => window.LJDraft
            && JSON.stringify(LJDraft.savedProperties) === JSON.stringify(LJDraft.currentProperties()));
        assert.equal(await page.evaluate(() => document.activeElement?.id), 'id-subject-0',
            'subject remains focused until the clear callback has rebound draft handlers');
        await page.keyboard.press('Tab');
        await page.waitForFunction(async () => {
            const response = await fetch('/__rpc_draft?getProperties=1');
            const properties = await response.json();
            return properties.subject === 'Delayed clear subject marker';
        });
        intercepting = false;
        await page.setRequestInterception(false);
        saved = { draft: (await rpc()).json.draft, properties: await properties() };
        assert.equal(saved.properties.subject, 'Delayed clear subject marker',
            'subject typed during delayed clear persists after the clear succeeds');

        await rpc({clearProperties: 1, clearDraft: 1});
        saved = { draft: (await rpc()).json.draft, properties: await properties() };
        assert.deepEqual(saved, {draft: '', properties: {}}, 'clear removes saved body and all saved properties');
        const dialogsBeforeClearReload = dialogs.length;
        expectedDialog = undefined;
        expectedDialogAction = 'accept';
        await page.goto(base + '/entry/new', {waitUntil: 'networkidle0'});
        assert.equal(dialogs.length, dialogsBeforeClearReload, 'cleared draft does not prompt for restoration');
        assert.equal(await page.$eval('#id-subject-0', e => e.value), '', 'cleared draft reload has an empty title');
        assert.equal(await page.$eval('#entry-body', e => e.value), '', 'cleared draft reload has an empty HTML body');
        assert.deepEqual(errors, [], 'draft and preview flow has no page errors');
        assert.deepEqual(dialogs,
            Array(2).fill('confirm: Restore from saved draft entitled Draft title restore marker?'),
            'accepted and declined restoration dialogs are the only draft prompts');
        console.log('PASS: draft HTML/RTE save, restore, clear, and preview complete without publishing');
    } finally {
        try { if (browser) await browser.close(); }
        finally {
            if (fixture) {
                fixture.stdin.end();
                await fixtureDone;
            }
        }
    }
})().catch(error => { console.error(error); process.exit(1); });
