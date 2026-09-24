// Exercise the configured native RTE spellcheck submit without persistence.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const net = require('node:net');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

(async () => {
    let fixture;
    let fixtureDone;
    let server;
    let browser;
    const port = 18081;
    const tempDir = fs.mkdtempSync('/tmp/entry-spellcheck-browser-');
    const state = `${tempDir}/checker.json`;
    const output = process.argv[2] || '/tmp/entry-spellcheck-browser';
    let serverDone;
    const portMustBeUnused = () => new Promise((resolve, reject) => {
        const socket = net.connect(port, '127.0.0.1');
        socket.once('connect', () => {
            socket.destroy();
            reject(new Error(`refusing occupied spellcheck browser port ${port}`));
        });
        socket.once('error', error => {
            socket.destroy();
            if (error.code === 'ECONNREFUSED') resolve();
            else reject(error);
        });
    });
    const waitForPort = () => new Promise((resolve, reject) => {
        const deadline = Date.now() + 15000;
        const attempt = () => {
            const socket = net.connect(port, '127.0.0.1');
            socket.once('connect', () => { socket.destroy(); resolve(); });
            socket.once('error', () => {
                socket.destroy();
                if (Date.now() >= deadline) reject(new Error('spellcheck test server did not listen'));
                else setTimeout(attempt, 100);
            });
        };
        attempt();
    });
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-spellcheck-fixture.pl'],
            {stdio: ['pipe', 'pipe', 'inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`fixture cleanup failed: ${code}/${signal}`)));
            fixture.once('error', reject);
        });
        fixtureDone.catch(() => {});
        const data = await new Promise((resolve, reject) => {
            let buffer = '';
            fixture.stdout.on('data', chunk => {
                buffer += chunk;
                const newline = buffer.indexOf('\n');
                if (newline < 0) return;
                try { resolve(JSON.parse(buffer.slice(0, newline))); } catch (error) { reject(error); }
            });
            fixture.once('exit', (code, signal) => reject(new Error(`fixture exited before startup: ${code}/${signal}`)));
        });
        const verify = () => new Promise((resolve, reject) => {
            let buffer = '';
            const onData = chunk => {
                buffer += chunk;
                const newline = buffer.indexOf('\n');
                if (newline < 0) return;
                fixture.stdout.off('data', onData);
                try { resolve(JSON.parse(buffer.slice(0, newline))); } catch (error) { reject(error); }
            };
            fixture.stdout.on('data', onData);
            fixture.stdin.write('verify\n');
        });
        await portMustBeUnused();
        server = spawn('perl', [process.env.LJHOME + '/t/browser/entry-spellcheck-server.pl', String(port), state],
            {stdio: ['ignore', 'ignore', 'pipe']});
        let serverStderr = '';
        server.stderr.on('data', chunk => { serverStderr += chunk; });
        serverDone = new Promise(resolve => {
            server.once('exit', (code, signal) => resolve({code, signal, stderr: serverStderr}));
            server.once('error', error => resolve({error, stderr: serverStderr}));
        });
        const ready = await Promise.race([
            waitForPort().then(() => ({ready: true})),
            serverDone.then(result => ({result})),
        ]);
        if (!ready.ready) {
            throw new Error(`spellcheck test server exited before startup: ${JSON.stringify(ready.result)}`);
        }
        browser = await puppeteer.launch({executablePath: '/usr/bin/google-chrome-stable', args: ['--no-sandbox']});
        const page = await browser.newPage();
        fs.mkdirSync(output, {recursive: true});
        const captureVisible = async (label, selector, width, height) => {
            await page.setViewport({width, height, deviceScaleFactor: 1});
            await page.$eval(selector, element => element.scrollIntoView({block: 'center'}));
            const visible = await page.$eval(selector, element => {
                const rect = element.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0
                    && rect.bottom > 0 && rect.right > 0
                    && rect.top < innerHeight && rect.left < innerWidth;
            });
            assert.ok(visible, `${label} is visible at ${width}px`);
            await page.screenshot({path: `${output}/${label}-${width}.png`, fullPage: true});
        };
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        await page.goto(`http://127.0.0.1:${port}/mobile/login`, {waitUntil: 'networkidle0'});
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('[type=submit]')]);
        await page.goto(`http://127.0.0.1:${port}/entry/${data.user}/${data.ditemid}/edit`, {waitUntil: 'networkidle0'});
        assert.equal(await page.$eval('#editor', el => el.value), 'rte0', 'owned entry renders RTE mode');
        assert.ok(await page.$('[name="action:spellcheck"]'), 'configured native form renders Spell Check control');
        await captureVisible('configured-spellcheck-control', '[name="action:spellcheck"]', 1280, 900);
        await captureVisible('configured-spellcheck-control', '[name="action:spellcheck"]', 390, 844);
        await page.waitForFunction(() => window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2);
        const body = '<p>Browser spellcheck <em>current XHTML</em></p>';
        await page.evaluate(value => FCKeditorAPI.GetInstance('entry-body').SetHTML(value), body);
        await Promise.all([
            page.waitForNavigation({waitUntil: 'networkidle0'}),
            page.click('[name="action:spellcheck"]'),
        ]);
        assert.match(await page.content(), /browser suggestion/, 'spellcheck rerender shows local stub suggestion');
        await captureVisible('spellcheck-result', '#spellcheck-results', 1280, 900);
        await captureVisible('spellcheck-result', '#spellcheck-results', 390, 844);
        assert.equal(await page.$eval('#editor', el => el.value), 'rte0', 'spellcheck rerender retains RTE mode');
        await page.waitForFunction(() => window.FCKeditorAPI && FCKeditorAPI.GetInstance('entry-body')?.Status === 2);
        assert.equal(await page.evaluate(() => FCKeditorAPI.GetInstance('entry-body').GetXHTML(false)), body,
            'spellcheck rerender retains FCK XHTML');
        const checked = JSON.parse(fs.readFileSync(state, 'utf8'));
        assert.equal(checked.checked_body, body.replace(/</g, '&lt;').replace(/>/g, '&gt;'),
            'real submit synchronizes current FCK XHTML before checker invocation');
        const fresh = await verify();
        assert.equal(fresh.subject, 'Stored spellcheck browser subject', 'spellcheck does not persist entry subject');
        assert.equal(fresh.body, '<p>Stored spellcheck browser body</p>', 'spellcheck does not persist entry body');
        assert.equal(fresh.editor, 'rte0', 'spellcheck does not alter stored editor');
        assert.equal(fresh.draft_body, 'Spellcheck draft body', 'spellcheck does not clear draft body');
        assert.equal(fresh.draft_subject, 'Spellcheck draft subject', 'spellcheck does not clear draft properties');
        assert.deepEqual(errors, [], 'RTE spellcheck has no page errors');
        if (process.env.ENTRY_SPELLCHECK_FAIL_AFTER_SUBMIT) throw new Error('intentional spellcheck cleanup failure');
        console.log('PASS: configured RTE spellcheck synchronizes FCK without persistence');
    } finally {
        try { if (browser) await browser.close(); }
        finally {
            try {
                if (server && server.exitCode === null) server.kill('SIGTERM');
                if (serverDone) await serverDone;
            } finally {
                if (fixture) { fixture.stdin.end(); await fixtureDone; }
                fs.rmSync(tempDir, {recursive: true, force: true});
            }
        }
    }
})().catch(error => { console.error(error); process.exit(1); });
