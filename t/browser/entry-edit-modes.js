// Exercise the rendered owned-entry editor modes without publishing.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

(async () => {
    let fixture;
    let fixtureDone;
    let browser;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-edit-modes-fixture.pl'],
            { stdio: ['pipe', 'pipe', 'inherit'] });
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`fixture cleanup failed: ${code}/${signal}`)));
            fixture.once('error', reject);
        });
        fixtureDone.catch(() => {});
        let buffered = '';
        const lines = [];
        const waiting = [];
        const nextLine = label => new Promise((resolve, reject) => {
            const line = lines.shift();
            if (line !== undefined) return resolve(line);
            waiting.push({ resolve, reject, label });
        });
        fixture.stdout.on('data', chunk => {
            buffered += chunk;
            let newline;
            while ((newline = buffered.indexOf('\n')) >= 0) {
                const line = buffered.slice(0, newline);
                buffered = buffered.slice(newline + 1);
                const waiter = waiting.shift();
                if (waiter) waiter.resolve(line); else lines.push(line);
            }
        });
        fixture.stdout.once('error', error => {
            while (waiting.length) waiting.shift().reject(error);
        });
        const jsonLine = async label => {
            const line = await Promise.race([nextLine(label), fixtureDone]);
            try { return JSON.parse(line); }
            catch (error) { throw new Error(`${label}: ${error.message}`); }
        };
        const data = await jsonLine('fixture startup');
        const verify = async index => {
            fixture.stdin.write(JSON.stringify({ index }) + '\n');
            return jsonLine(`fixture entry ${index}`);
        };

        browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome-stable', args: ['--no-sandbox'] });
        const page = await browser.newPage();
        const errors = [];
        const failures = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('requestfailed', request => failures.push(`${request.url()}: ${request.failure()?.errorText}`));
        page.on('response', response => {
            if (response.status() >= 400) failures.push(`${response.status()}: ${response.url()}`);
        });
        const base = 'http://127.0.0.1:8080';
        const output = process.argv[2] || '/tmp/entry-edit-modes';
        fs.mkdirSync(output, { recursive: true });
        await page.goto(base + '/mobile/login', { waitUntil: 'networkidle0' });
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle0' }), page.click('[type=submit]')]);

        const save = async label => {
            const submit = await page.$('[name="action:post"], [name="action:edit"]');
            assert.ok(submit, `${label} has an actual rendered save control`);
            await Promise.all([
                page.waitForNavigation({ waitUntil: 'networkidle0', timeout: 15000 }),
                submit.click(),
            ]);
            assert.match(await page.content(), /success|edited/i, `${label} save reports success`);
        };
        const renderedBody = async mode => {
            if (mode === 'rte0') {
                await page.waitForFunction(() => window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2);
                return page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false));
            }
            return page.$eval('#entry-body', element => element.value);
        };

        for (let index = 0; index < data.cases.length; index++) {
            const item = data.cases[index];
            const mode = item.rendered_editor;
            const url = `${base}/entry/${data.user}/${data.ids[index]}/edit`;
            await page.goto(url, { waitUntil: 'networkidle0' });
            const available = await page.$$eval('#editor option', options => options.map(option => option.value));
            assert.ok(available.includes(mode), `${mode} is a rendered editor choice: ${available.join(', ')}`);
            assert.equal(await page.$eval('#editor', element => element.value), mode,
                `${item.name} initial GET selects its active editor without client forcing`);
            const initial = await renderedBody(mode);
            assert.equal(initial, item.rendered_body,
                `${item.name} initial rendered editor body matches its expected form value`);

            const before = await verify(index);
            assert.equal(before.body, item.stored_body, `${item.name} fixture has exact stored body before saves`);
            assert.equal(before.editor, item.stored_editor, `${item.name} fixture has expected stored editor prop`);
            if (item.legacy) {
                assert.equal(before.editor, '', 'legacy Markdown fixture has no stored editor prop');
                assert.match(before.body, /^!markdown\n/, 'legacy Markdown fixture retains the legacy database marker');
                assert.doesNotMatch(initial, /^!markdown\n/, 'legacy Markdown marker is removed from the rendered textarea');
            }

            await save(`${item.name} no-op`);
            const afterNoop = await verify(index);
            assert.equal(afterNoop.body, initial, `${item.name} no-op save persists the rendered body exactly`);
            assert.equal(afterNoop.editor, mode, `${item.name} no-op save persists the rendered editor exactly`);
            if (process.env.ENTRY_EDIT_MODES_FAIL_AFTER_SAVE && index === 0) {
                throw new Error('intentional editor-mode fixture cleanup probe');
            }

            await page.goto(url, { waitUntil: 'networkidle0' });
            assert.equal(await page.$eval('#editor', element => element.value), mode,
                `${item.name} fresh GET retains the automatically selected editor`);
            assert.equal(await renderedBody(mode), initial,
                `${item.name} fresh GET renders the exact no-op persisted body`);

            let changed;
            if (mode === 'rte0') {
                const input = '<p>Changed rte0 <em>canonical markup</em></p>';
                await page.evaluate(value => FCKeditorAPI.GetInstance('entry-body').SetHTML(value), input);
                changed = await renderedBody(mode);
                assert.equal(changed, input, 'RTE SetHTML has defined canonical bytes before the real save');
            } else {
                changed = `Changed ${mode} exact bytes`;
                await page.$eval('#entry-body', (element, value) => { element.value = value; }, changed);
            }
            await save(`${item.name} changed-content`);
            const afterChange = await verify(index);
            assert.equal(afterChange.body, changed, `${item.name} changed save persists exact body bytes`);
            assert.equal(afterChange.editor, mode, `${item.name} changed save retains exact editor prop`);

            await page.goto(url, { waitUntil: 'networkidle0' });
            assert.equal(await page.$eval('#editor', element => element.value), mode,
                `${item.name} changed fresh GET retains selected mode`);
            assert.equal(await renderedBody(mode), changed,
                `${item.name} changed fresh GET renders exact persisted bytes`);
            await page.screenshot({ path: `${output}/${mode}.png`, fullPage: true });
        }
        assert.deepEqual(errors, [], 'no JavaScript errors during editor mode roundtrips');
        assert.deepEqual(failures, [], 'no failed or HTTP-error resources during editor mode roundtrips');
        console.log('PASS: initial, no-op, changed, and fresh editor-mode roundtrips persist exactly');
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
