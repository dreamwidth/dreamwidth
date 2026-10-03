// Customization subtitle RPC acceptance with a disposable account.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const fixture = spawn('perl', [process.env.LJHOME + '/t/browser/customize-fixture.pl'], {stdio: ['pipe', 'pipe', 'inherit']});
    const done = new Promise((resolve, reject) => {
        fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error('fixture cleanup failed: ' + code + '/' + signal)));
        fixture.once('error', reject);
    });
    done.catch(() => {});
    let browser;
    try {
        const data = await new Promise((resolve, reject) => {
            let text = '';
            fixture.stdout.on('data', chunk => {
                text += chunk;
                if (!text.includes('\n')) return;
                try { resolve(JSON.parse(text.split('\n')[0])); } catch (error) { reject(error); }
            });
            fixture.once('error', reject);
            fixture.once('exit', code => reject(new Error('fixture exited before startup: ' + code)));
        });
        browser = await puppeteer.launch({executablePath: '/usr/bin/google-chrome-stable', args: ['--no-sandbox']});
        const page = await browser.newPage();
        const base = 'http://127.0.0.1:8080';
        const pageErrors = [];
        page.on('pageerror', error => pageErrors.push(error.message));
        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('[type=submit]')]);

        await page.goto(base + '/customize/', {waitUntil: 'networkidle0'});
        const value = 'Subtitle browser ' + Date.now();
        await page.click('#journalsubtitle_edit');
        await page.$eval('#journalsubtitle', (el, value) => { el.value = value; }, value);
        let rpc = 0;
        const count = request => { if (request.url().includes('__rpc_widget')) rpc++; };
        page.on('request', count);
        const response = page.waitForResponse(r => r.url().includes('__rpc_widget'));
        await page.click('#save_btn_journalsubtitle');
        assert.equal((await response).status(), 200, 'subtitle RPC succeeds');
        await page.waitForNetworkIdle();
        page.off('request', count);
        assert.equal(rpc, 1, 'exactly one subtitle widget RPC');
        await page.reload({waitUntil: 'networkidle0'});
        assert.equal(await page.$eval('#journalsubtitle', el => el.value), value, 'subtitle survives reload');

        assert.deepEqual(pageErrors, [], 'subtitle save has no browser errors');
        console.log('PASS: subtitle save via a single widget RPC, survives reload');
    } finally {
        try { if (browser) await browser.close(); }
        finally { fixture.stdin.end(); await done; }
    }
})().catch(error => { console.error(error); process.exit(1); });
