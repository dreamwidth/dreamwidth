// Browser baseline for retained legacy URL image insertion.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

(async () => {
    let fixture, fixtureDone, browser;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/imgupload-legacy-fixture.pl'],
            { stdio: ['pipe', 'pipe', 'inherit'] });
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(Error(`fixture ${code}/${signal}`)));
            fixture.once('error', reject);
        });
        fixtureDone.catch(() => {});
        let buffered = '';
        const fixtureData = await new Promise((resolve, reject) => {
            fixture.stdout.on('data', data => {
                buffered += data;
                const newline = buffered.indexOf('\n');
                if (newline >= 0) try { resolve(JSON.parse(buffered.slice(0, newline))); } catch (error) { reject(error); }
            });
            fixture.once('exit', (code, signal) => reject(Error(`fixture startup ${code}/${signal}`)));
            fixture.once('error', reject);
        });
        const state = () => new Promise((resolve, reject) => {
            fixture.stdout.once('data', data => { try { resolve(JSON.parse(data)); } catch (error) { reject(error); } });
            fixture.once('error', reject); fixture.stdin.write(JSON.stringify({ state: 1 }) + '\n');
        });
        browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome-stable', args: ['--no-sandbox'] });
        const errors = [];
        const output = process.argv[2] || '/tmp/imgupload-legacy-browser';
        fs.mkdirSync(output, { recursive: true });
        const before = await state();
        for (const [name, viewport] of [['desktop', { width: 1280, height: 800 }], ['narrow', { width: 390, height: 844 }]]) {
            const page = await browser.newPage();
            let phase = `${name}: create`;
            page.on('pageerror', error => errors.push(`${phase}: ${error.stack || error.message}`));
            await page.setViewport(viewport);
            phase = `${name}: login`;
            await page.goto('http://127.0.0.1:8080/mobile/login', { waitUntil: 'networkidle0' });
            await page.type('[name=user]', fixtureData.user); await page.type('[name=password]', fixtureData.password);
            await Promise.all([page.waitForNavigation(), page.click('[type=submit]')]);
            phase = `${name}: load legacy editor`;
            await page.goto('http://127.0.0.1:8080/update.bml', { waitUntil: 'networkidle0' });
            const parentURL = page.url();
            phase = `${name}: open dialog`; await page.evaluate(() => InOb.handleInsertImage());
            await page.waitForFunction(() => document.querySelector('#popupsIframe')?.contentDocument?.getElementById('fromurlentry'));
            const frame = await (await page.$('#popupsIframe')).contentFrame();
            for (const selector of ['#fromurlentry', '#alttext', '#btnNext', '#close']) assert.ok(await frame.$(selector), `${name} dialog exposes ${selector}`);
            await page.screenshot({ path: `${output}/${name}-dialog.png`, fullPage: true });
            await new Promise(resolve => setTimeout(resolve, 650));
            phase = `${name}: submit URL insertion`;
            await frame.type('#fromurlentry', `https://example.invalid/${name}.png`); await frame.type('#alttext', `${name} alt`); await frame.click('#btnNext');
            await page.waitForFunction(() => !document.querySelector('#popupsIframe'));
            assert.equal(page.url(), parentURL, `${name} insertion closes without parent navigation`);
            assert.match(await page.$eval('[name=event]', e => e.value), new RegExp(`<img src="https://example\.invalid/${name}\.png" alt='${name} alt' />`));
            await page.close();
        }
        assert.deepEqual(await state(), before, 'URL insertion leaves fresh entry state unchanged');
        assert.deepEqual(errors, [], 'legacy dialog has no page errors');
        if (process.env.IMGUPLOAD_INTENTIONAL_FAIL) throw Error('intentional image dialog cleanup probe');
        console.log('PASS: legacy image URL dialog inserts without navigation');
    } finally { try { if (browser) await browser.close(); } finally { if (fixture) { fixture.stdin.end(); await fixtureDone; } } }
})().catch(error => { console.error(error); process.exitCode = 1; });
