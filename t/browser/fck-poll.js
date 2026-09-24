// Exercise the standalone FCK poll dialog through the real modern entry editor.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

(async () => {
    const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome-stable', args: ['--no-sandbox'] });
    const base = 'http://127.0.0.1:8080';
    let originalDraft;
    try {
        const page = await browser.newPage();
        const errors = [];
        const dialogs = [];
        let phase = 'login';
        page.on('pageerror', e => errors.push(`${phase}: ${e.message}\n${e.stack || ''}`));
        page.on('dialog', async dialog => {
            dialogs.push(`${dialog.type()}: ${dialog.message()}`);
            await dialog.dismiss();
        });
        await page.goto(base + '/mobile/login', { waitUntil: 'networkidle0' });
        await page.type('[name=user]', 'test_user');
        await page.type('[name=password]', 'dreamwidth');
        await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle0' }), page.click('[type=submit]')]);
        originalDraft = await page.evaluate(async () => {
            const draft = await (await fetch('/__rpc_draft')).json();
            const properties = await (await fetch('/__rpc_draft?getProperties=1')).json();
            return { draft: draft.draft, properties };
        });
        const fixture = process.env.FCK_POLL_DRAFT_FIXTURE;
        const activeDraft = await page.evaluate(async fixture => {
            if (!fixture) return null;
            const post = async values => fetch('/__rpc_draft', {
                method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams(values),
            });
            await post({ clearProperties: 1, clearDraft: 1 });
            if (fixture === 'subject') {
                await post({ saveSubject: 'Sol draft subject', saveEditor: 'html_casual1', saveTaglist: 'soltag' });
                await post({ saveDraft: 'Sol preserved draft body with <b>markup</b>' });
            }
            const draft = await (await fetch('/__rpc_draft')).json();
            const properties = await (await fetch('/__rpc_draft?getProperties=1')).json();
            return { draft: draft.draft, properties };
        }, fixture) || originalDraft;
        const expectedRestoreDialog = activeDraft.properties.subject
            ? `confirm: Restore from saved draft entitled ${activeDraft.properties.subject}?`
            : 'confirm: Restore from saved draft?';
        await page.goto(base + '/entry/new', { waitUntil: 'networkidle0', timeout: 30000 });
        await page.select('#editor', 'rte0');
        await page.waitForFunction(() => window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2);

        const open = async () => {
            await page.evaluate(() => {
                const editor = FCKeditorAPI.GetInstance('entry-body');
                editor.Focus();
                editor.Commands.GetCommand('LJPollLink').Execute();
            });
            await page.waitForFunction(() => window.frames.length > 0);
            await page.waitForNetworkIdle();
            const dialog = page.frames().find(f => f.url().endsWith('/tools/fck_poll'));
            assert.ok(dialog, 'modern plugin opens the extensionless poll route');
            await dialog.waitForSelector('form[name=poll]');
            return dialog;
        };
        const accept = async expected => {
            const shell = page.frames().find(f => f.url().endsWith('/fckdialog.html'));
            assert.ok(shell, 'FCK dialog shell exists');
            await shell.click('#btnOk');
            await page.waitForFunction(
                () => !document.querySelector('iframe[src*="fckdialog.html"]'),
                { timeout: 10000 }
            );
            await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
            await page.waitForFunction(text => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false).includes(text),
                { timeout: 10000 }, expected);
        };
        const captureDialog = async (name) => {
            await page.screenshot({ path: `${output}/${name}.png`, fullPage: true });
        };
        const setQuestion = async (dialog, number, type, question) => {
            await dialog.select(`select[name=type_${number}]`, type);
            await dialog.click(`input[name=setType_${number}]`);
            await dialog.type(`input[name=question_${number}]`, question);
        };

        const output = process.argv[2] || '/tmp/fck-poll-after';
        fs.mkdirSync(output, { recursive: true });
        let dialog = await open();
        await captureDialog('setup');
        await dialog.evaluate(() => OnDialogTabChange('questions'));
        await setQuestion(dialog, 0, 'radio', 'Radio question');
        await dialog.type('input[name=pq_0_opt_0]', 'One');
        await dialog.type('input[name=pq_0_opt_1]', 'Two');
        await dialog.click('input[value=" Next Question "]');
        await setQuestion(dialog, 1, 'text', 'Text question');
        await dialog.$eval('input[name=pq_1_size]', e => { e.value = '40'; });
        await dialog.$eval('input[name=pq_1_maxlength]', e => { e.value = '120'; });
        assert.match(await dialog.$eval('#QNav', e => e.textContent), /Question 2 of 2/, 'new question updates navigation');
        await dialog.evaluate(() => document.querySelector('#QNav a[href="javascript:switchQuestion(0)"]').click());
        await dialog.waitForFunction(() => /Question 1 of 2/.test(document.querySelector('#QNav').textContent));
        assert.match(await dialog.$eval('#QNav', e => e.textContent), /Question 1 of 2/, 'previous question navigation works');
        await dialog.evaluate(() => switchQuestion(1));
        assert.equal(await dialog.$('input[value*="Remove"]'), null, 'legacy dialog has no question removal control to exercise');
        await captureDialog('questions');
        await accept('Radio question');

        let html = await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false));
        for (const text of ['Radio question', 'Text question']) {
            assert.match(html, new RegExp(text), `inserted ${text}`);
        }

        await page.evaluate(() => {
            const editor = FCKeditorAPI.GetInstance('entry-body');
            editor.Focus();
            const range = editor.EditorDocument.createRange();
            range.selectNode(editor.EditorDocument.querySelector('#poll1'));
            const selection = editor.EditorWindow.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
        });
        dialog = await open();
        await dialog.evaluate(() => OnDialogTabChange('questions'));
        assert.equal(await dialog.$eval('input[name=question_0]', e => e.value), 'Radio question', 'selected poll populates editor');
        await dialog.$eval('input[name=pq_0_opt_0]', e => { e.value = 'Edited first'; });
        await accept('Edited first');
        html = await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false));
        assert.match(html, /Edited first/, 'existing poll edit replaces selected poll');
        phase = 'switching to HTML';
        await page.select('#editor', 'html_raw0');
        await page.waitForFunction(() => document.querySelector('#editor').value === 'html_raw0');
        await page.waitForNetworkIdle({ idleTime: 500, timeout: 10000 });
        phase = 'HTML round trip complete';
        assert.match(await page.$eval('#entry-body', e => e.value), /Edited first/, 'polls survive HTML round trip');
        await page.screenshot({ path: `${output}/html-roundtrip.png`, fullPage: true });
        assert.deepEqual(errors, [], 'no poll dialog JavaScript errors');
        assert.ok(dialogs.every(message => message === expectedRestoreDialog),
            'only the expected saved-draft restoration confirmation was dismissed');
        await page.close();
        console.log('PASS: inserted, edited, and HTML-round-tripped FCK polls without publishing');
    } finally {
        if (originalDraft) {
            const cleanup = await browser.newPage();
            await cleanup.goto(base + '/mobile/', { waitUntil: 'networkidle0' });
            const restoredDraft = await cleanup.evaluate(async original => {
                const post = async values => fetch('/__rpc_draft', {
                    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: new URLSearchParams(values),
                });
                await post({ clearProperties: 1 });
                const propertyNames = {
                    subject: 'saveSubject', editor: 'saveEditor', userpic: 'saveUserpic', taglist: 'saveTaglist',
                    moodid: 'saveMoodID', mood: 'saveMood', location1: 'saveLocation', music: 'saveMusic',
                    adultreason: 'saveAdultReason', commentset: 'saveCommentSet', commentscr: 'saveCommentScr',
                    adultcnt: 'saveAdultCnt',
                };
                const values = {};
                for (const [name, value] of Object.entries(original.properties)) values[propertyNames[name]] = value;
                if (Object.keys(values).length) await post(values);
                await post({ saveDraft: original.draft || '' });
                const draft = await (await fetch('/__rpc_draft')).json();
                const properties = await (await fetch('/__rpc_draft?getProperties=1')).json();
                return { draft: draft.draft, properties };
            }, originalDraft);
            assert.deepEqual(restoredDraft, originalDraft, 'finally restores complete original saved draft state');
            await cleanup.close();
        }
        await browser.close();
    }
})().catch(e => { console.error(e); process.exit(1); });
