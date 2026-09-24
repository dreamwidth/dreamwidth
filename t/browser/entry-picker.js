// Editing the picker's howmany/date fields auto-selects the matching mode
// radio via a client-side change handler, with no radio click of its own --
// JS-only behavior; the resulting listings themselves are covered by
// t/plack-entry-picker.t.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-picker-fixture.pl'], {stdio:['pipe','pipe','inherit']});
    const done = new Promise((resolve,reject) => {
        fixture.once('exit', (code,signal) => code === 0 ? resolve() : reject(new Error('fixture exit: ' + code + '/' + signal)));
        fixture.once('error', reject);
    });
    done.catch(() => {});
    let browser;
    try {
        const data = await new Promise((resolve,reject) => {
            let text = '';
            fixture.stdout.on('data', chunk => {
                text += chunk.toString();
                if (text.includes('\n')) {
                    try { resolve(JSON.parse(text.split('\n')[0])); } catch (error) { reject(error); }
                }
            });
            fixture.once('error', reject);
            fixture.once('exit', () => reject(new Error('fixture exited before ready')));
        });
        browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable',args:['--no-sandbox']});
        const page = await browser.newPage();
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        const base = 'http://127.0.0.1:8080';
        await page.goto(base + '/mobile/login', {waitUntil:'networkidle0'});
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[type=submit]')]);
        await page.goto(base + '/editjournal', {waitUntil:'networkidle0'});

        await page.$eval('[name=howmany]', el => { el.value = '6'; el.dispatchEvent(new Event('change', {bubbles:true})); });
        assert.equal(await page.$eval('#selecttype-lastn', el => el.checked), true,
            'editing howmany selects the recent-entry mode without a radio click');

        for (const [name,value] of Object.entries({year:'1970',month:'1',day:'1'})) {
            await page.$eval('[name='+name+']', (el,value) => { el.value=value; el.dispatchEvent(new Event('change', {bubbles:true})); }, value);
        }
        assert.equal(await page.$eval('#selecttype-day', el => el.checked), true,
            'editing a date field selects day mode without a radio click');

        assert.deepEqual(errors, [], 'picker flow has no JavaScript exceptions');
        console.log('PASS: editing howmany/date fields auto-selects the matching mode radio');
    } finally {
        try { if (browser) await browser.close(); }
        finally { fixture.stdin.end(); await done; }
    }
})().catch(error => { console.error(error); process.exit(1); });
