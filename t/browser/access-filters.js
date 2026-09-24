// Run in the devcontainer after bin/dev/screenshot installs headless Chrome.
// Uses an owned disposable fixture; never point this at production.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
const base = 'http://127.0.0.1:8080';
const out = process.env.DW_BROWSER_OUT || '/tmp/access-filters-browser';

(async () => {
    let fixture;
    let fixtureDone;
    let browser;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/access-filters-fixture.pl'],
            {stdio: ['pipe', 'pipe', 'inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error('access fixture cleanup failed: ' + code + '/' + signal)));
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
            fixture.once('exit', code => reject(new Error('access fixture exited before startup: ' + code)));
        });
        fs.mkdirSync(out, {recursive: true});
        browser = await puppeteer.launch({
            executablePath: '/usr/bin/google-chrome-stable',
            args: ['--no-sandbox', '--disable-gpu'],
            defaultViewport: {width: 1280, height: 1000}
        });
        const page = await browser.newPage();
        const errors = [];
        page.on('pageerror', e => errors.push(e.message));
        const go = async () => {
            const res = await page.goto(base + '/manage/circle/editfilters', {waitUntil: 'networkidle0'});
            assert.equal(res.status(), 200);
        };
        const dialogButton = async (label, value) => {
            page.once('dialog', dialog => dialog.accept(value));
            const el = await page.$(`input[type=button][value="${label}"]`)
                || await page.$(`button[data-label="${label}"]`);
            assert.ok(el, `button ${label}`);
            await el.click();
        };
        const groupOptions = () => page.$$eval('[name=list_groups] option', opts => opts.map(o => o.text));

        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('input[name=user]', fixtureData.user);
        await page.type('input[name=password]', fixtureData.password);
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('input[type=submit], button[type=submit]')]);
        await go();

        // "Move Up" reorders the <select> options and recomputes the hidden
        // sort-order fields entirely client-side (see moveGroup/setSortOrders
        // in htdocs/js/access-filters.js); no request happens until Save, so
        // only a real browser can exercise this logic.
        await dialogButton('New', 'First filter');
        await dialogButton('New', 'Second filter');
        assert.deepEqual(await groupOptions(), ['First filter', 'Second filter'],
            'new filters are appended in creation order');
        await page.select('[name=list_groups]', await page.$eval('[name=list_groups] option:last-child', el => el.value));
        await page.click('[data-action=up]');
        assert.deepEqual(await groupOptions(), ['Second filter', 'First filter'],
            'Move Up reorders the option list in the DOM before any save');

        await Promise.all([
            page.waitForNavigation({waitUntil: 'networkidle0'}),
            page.click('form[name=fg] input[type=submit], form[name=fg] button[type=submit]')
        ]);
        assert.match(await page.content(), /Your access filters are now saved/);
        await go();
        assert.deepEqual(await groupOptions(), ['Second filter', 'First filter'],
            'the reordered sort values computed by the client survive a save and reload');

        assert.deepEqual(errors, [], 'no uncaught browser errors');
        console.log('PASS: client-side filter reorder persists across save/reload');
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
