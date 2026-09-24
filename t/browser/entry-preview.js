// Exercise the real native entry-preview control without publishing.
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
    const errors = [];
    const networkFailures = [];
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-preview-fixture.pl'],
            {stdio: ['pipe', 'pipe', 'inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0
                ? resolve()
                : reject(new Error(`entry preview fixture cleanup failed: ${code}/${signal}`)));
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
                reject(new Error(`entry preview fixture exited before startup: ${code}/${signal}`)));
        });
        const readFixture = (() => {
            let buffer = '';
            const waiting = [];
            fixture.stdout.on('data', data => {
                buffer += data;
                let newline;
                while ((newline = buffer.indexOf('\n')) >= 0 && waiting.length) {
                    const line = buffer.slice(0, newline);
                    buffer = buffer.slice(newline + 1);
                    const {resolve, reject} = waiting.shift();
                    try { resolve(JSON.parse(line)); }
                    catch (error) { reject(error); }
                }
            });
            return command => new Promise((resolve, reject) => {
                waiting.push({resolve, reject});
                fixture.stdin.write(command + '\n');
            });
        })();

        browser = await puppeteer.launch({
            executablePath: '/usr/bin/google-chrome-stable',
            args: ['--no-sandbox'],
        });
        const track = page => {
            page.on('pageerror', error => errors.push(`${page.url()}: ${error.message}`));
            page.on('response', response => {
                if (response.status() >= 400) networkFailures.push(`${response.status()} ${response.url()}`);
            });
        };
        const page = await browser.newPage();
        track(page);
        const output = process.argv[2] || '/tmp/entry-preview-browser';
        fs.mkdirSync(output, {recursive: true});

        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('[name=user]', fixtureData.user);
        await page.type('[name=password]', fixtureData.password);
        await Promise.all([
            page.waitForNavigation({waitUntil: 'networkidle0'}),
            page.click('[type=submit]'),
        ]);
        const entriesBefore = (await readFixture('entry_count')).entry_count;

        async function sizePopup(preview, width, height) {
            const session = await preview.target().createCDPSession();
            const {windowId} = await session.send('Browser.getWindowForTarget');
            await session.send('Browser.setWindowBounds', {
                windowId,
                bounds: {left: 0, top: 0, width, height, windowState: 'normal'},
            });
            await preview.setViewport({width, height, deviceScaleFactor: 1});
            await preview.waitForFunction(([expectedWidth, expectedHeight]) =>
                innerWidth >= expectedWidth && innerHeight >= expectedHeight
                && document.documentElement.clientWidth > 0 && document.body.getBoundingClientRect().width > 0,
            {}, [width, height]);
        }

        async function openPreview({form, button, path, title, body, prepare, mutate, targetAfterPreview, label}) {
            if (prepare) await prepare();
            const state = await page.$eval(form, element => ({action: element.action, target: element.target}));
            await page.click(`${form} [name=subject]`);
            await page.keyboard.down('Control');
            await page.keyboard.press('A');
            await page.keyboard.up('Control');
            await page.keyboard.type(title);
            await page.click(`${form} textarea[name=event]`);
            await page.keyboard.down('Control');
            await page.keyboard.press('A');
            await page.keyboard.up('Control');
            if (body) await page.keyboard.type(body);
            else await page.keyboard.press('Backspace');
            if (mutate) await mutate();
            const previewTarget = browser.waitForTarget(target => target.opener() === page.target());
            await page.click(button);
            const preview = await (await previewTarget).page();
            track(preview);
            await preview.waitForFunction(expected => location.pathname === expected, {}, path);
            await preview.waitForSelector('body');
            const content = await preview.content();
            fs.writeFileSync(`${output}/${label}.html`, content);
            assert.match(content, /This is a preview only/i, `${label} popup visibly warns that it is preview-only`);
            assert.match(await preview.$eval('body', body => body.textContent), new RegExp(title),
                `${label} popup visibly renders the submitted title`);
            assert.match(await preview.$eval('body', body => body.textContent), new RegExp(body || title),
                `${label} popup visibly renders the submitted content or empty-body title`);
            const restored = await page.$eval(form, element => ({action: element.action, target: element.target}));
            assert.equal(restored.action, state.action, `${label} restores the original form action`);
            assert.equal(restored.target, targetAfterPreview ?? state.target,
                `${label} restores the expected form target`);
            await sizePopup(preview, 1280, 900);
            await preview.screenshot({path: `${output}/${label}-desktop.png`, fullPage: true});
            await sizePopup(preview, 390, 844);
            await preview.screenshot({path: `${output}/${label}-narrow.png`, fullPage: true});
            await preview.close();
        }

        await page.goto(base + '/entry/new', {waitUntil: 'networkidle0'});
        await page.waitForSelector('#js-preview-button');
        const passwordsBefore = await page.$$eval('form input[type=password]', inputs =>
            inputs.map(input => ({name: input.name, disabled: input.disabled})));
        await openPreview({
            form: '#js-post-entry',
            button: '#js-preview-button',
            path: '/entry/preview',
            title: 'Native preview title marker',
            body: 'Native preview body marker',
            mutate: async () => page.$eval('[name=entrytime_date]', input => { input.value = 'not-a-date'; }),
            label: 'native-preview',
        });
        assert.deepEqual(
            await page.$$eval('form input[type=password]', inputs =>
                inputs.map(input => ({name: input.name, disabled: input.disabled}))),
            passwordsBefore,
            'native preview restores every actual password control state'
        );

        const entriesAfter = (await readFixture('entry_count')).entry_count;
        assert.equal(entriesAfter, entriesBefore, 'native preview leaves fresh entry count unchanged');
        if (process.env.ENTRY_PREVIEW_FAIL_AFTER_OPEN) throw new Error('intentional preview cleanup failure');
        assert.deepEqual(errors, [], 'preview controls and popup pages have no JavaScript errors');
        assert.deepEqual(networkFailures, [], 'preview controls and popup pages have no HTTP failures');
        console.log('PASS: real native preview popup renders without publishing');
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
