// Exercise the native own-entry delete confirmation without deleting the fixture.
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
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-delete-fixture.pl'],
            { stdio: ['pipe', 'pipe', 'inherit'] });
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`fixture cleanup failed: ${code}/${signal}`)));
            fixture.once('error', reject);
        });
        fixtureDone.catch(() => {});
        let buffer = '';
        const lines = [];
        const waiters = [];
        fixture.stdout.on('data', chunk => {
            buffer += chunk;
            let newline;
            while ((newline = buffer.indexOf('\n')) >= 0) {
                const line = buffer.slice(0, newline);
                buffer = buffer.slice(newline + 1);
                const waiter = waiters.shift();
                if (waiter) waiter.resolve(line); else lines.push(line);
            }
        });
        const nextLine = () => new Promise((resolve, reject) => {
            const line = lines.shift();
            if (line !== undefined) return resolve(line);
            waiters.push({ resolve, reject });
        });
        const fixtureJSON = async label => {
            const line = await Promise.race([nextLine(), fixtureDone]);
            try { return JSON.parse(line); }
            catch (error) { throw new Error(`${label}: ${error.message}`); }
        };
        const data = await fixtureJSON('fixture startup');
        const state = async () => {
            fixture.stdin.write(JSON.stringify({ state: true }) + '\n');
            return fixtureJSON('fixture state');
        };

        browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome-stable', args: ['--no-sandbox'] });
        const page = await browser.newPage();
        const errors = [];
        const failures = [];
        const dialogs = [];
        const deletePosts = [];
        let expectedConfirm;
        page.on('pageerror', error => errors.push(error.message));
        page.on('requestfailed', request => failures.push(`${request.url()}: ${request.failure()?.errorText}`));
        page.on('response', response => {
            if (response.status() >= 400) failures.push(`${response.status()}: ${response.url()}`);
        });
        page.on('request', request => {
            if (request.method() === 'POST' && /\/entry\/[^/]+\/\d+\/edit$/.test(new URL(request.url()).pathname)) {
                deletePosts.push(request.url());
            }
        });
        page.on('dialog', async dialog => {
            const received = `${dialog.type()}: ${dialog.message()}`;
            dialogs.push(received);
            if (received === `confirm: ${expectedConfirm}`) await dialog.dismiss();
            else await dialog.dismiss();
        });

        const base = 'http://127.0.0.1:8080';
        const output = process.argv[2] || '/tmp/entry-delete-browser';
        fs.mkdirSync(output, { recursive: true });
        assert.deepEqual(data.state, { target_valid: true, other_valid: true }, 'disposable fixtures start valid');
        await page.goto(base + '/mobile/login', { waitUntil: 'networkidle0' });
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle0' }), page.click('[type=submit]')]);

        const url = `${base}/entry/${data.user}/${data.id}/edit`;
        await page.setViewport({ width: 1280, height: 900 });
        await page.goto(url, { waitUntil: 'networkidle0' });
        assert.ok(await page.$('#js-delete-button'), 'owned edit form renders the delete control');
        expectedConfirm = await page.evaluate(() => postFormInitData.strings.delete_confirm);
        assert.ok(expectedConfirm, 'delete control has a translated confirmation string');
        await page.screenshot({ path: output + '/desktop.png', fullPage: true });
        deletePosts.length = 0;
        await page.click('#js-delete-button');
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        assert.deepEqual(dialogs, [`confirm: ${expectedConfirm}`], 'delete control opens exactly its translated confirmation');
        assert.equal(page.url(), url, 'dismissing confirmation does not navigate away from the edit form');
        assert.deepEqual(deletePosts, [], 'dismissing confirmation performs no delete POST');
        assert.deepEqual(await state(), { target_valid: true, other_valid: true },
            'dismissing confirmation leaves target and unrelated fixtures intact');
        if (process.env.ENTRY_DELETE_BROWSER_FAIL_AFTER_CONFIRM) {
            throw new Error('intentional entry-delete fixture cleanup probe');
        }
        await page.setViewport({ width: 390, height: 844 });
        await page.goto(url, { waitUntil: 'networkidle0' });
        await page.screenshot({ path: output + '/narrow.png', fullPage: true });
        assert.ok(await page.$('#js-delete-button'), 'narrow owned edit form retains delete control');
        assert.deepEqual(errors, [], 'delete confirmation has no JavaScript errors');
        assert.deepEqual(failures, [], 'delete confirmation has no network failures');
        console.log('PASS: native own-entry delete confirmation cancels without mutation');
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
