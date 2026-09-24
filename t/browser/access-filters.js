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
        page.on('pageerror', e => { errors.push(e.message); console.error('Browser error:', e.message); });
        page.on('response', res => { if (res.status() >= 400) console.error('HTTP', res.status(), res.url()); });
        const shot = name => page.screenshot({path: `${out}/${name}.png`, fullPage: true});
        const go = async (query = '') => {
            const res = await page.goto(base + '/manage/circle/editfilters' + query, {waitUntil: 'networkidle0'});
            assert.equal(res.status(), 200);
        };
        const button = async label => {
            const el = await page.$(`input[type=button][value="${label}"]`)
                || await page.$(`button[data-label="${label}"]`);
            assert.ok(el, `button ${label}`);
            await el.click();
        };
        const dialogButton = async (label, value) => {
            page.once('dialog', dialog => value === null ? dialog.dismiss() : dialog.accept(value));
            await button(label);
        };
        const save = async () => {
            await Promise.all([
                page.waitForNavigation({waitUntil: 'networkidle0'}),
                page.click('form[name=fg] input[type=submit], form[name=fg] button[type=submit]')
            ]);
            assert.match(await page.content(), /Your access filters are now saved/);
        };
        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('input[name=user]', fixtureData.user);
        await page.type('input[name=password]', fixtureData.password);
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('input[type=submit], button[type=submit]')]);
        assert.ok((await page.cookies()).some(c => c.name === 'ljmastersession'), 'authenticated');
        await go();
        await shot('empty');
        await dialogButton('New', 'Browser filter');
        const id = await page.$eval('[name=list_groups]', el => el.value);
        assert.ok(id);
        await page.select('[name=list_out]', fixtureData.friend);
        await button('>> Add');
        assert.ok(await page.$eval('[name=list_in]', (el, friend) => [...el.options].some(o => o.value === friend), fixtureData.friend));
        await shot('populated');
        await page.setViewport({width: 390, height: 844});
        await shot('populated-mobile');
        await page.setViewport({width: 1280, height: 1000});
        await save();
        if (process.env.ACCESS_FILTERS_FAIL_AFTER_SAVE) throw new Error('intentional access fixture cleanup probe');
        await shot('saved');
        await go();
        await page.select('[name=list_groups]', id);
        assert.ok(await page.$eval('[name=list_in]', (el, friend) => [...el.options].some(o => o.value === friend), fixtureData.friend), 'membership survives reload');
        await dialogButton('Rename', 'Renamed browser filter');
        await dialogButton('New', 'Second browser filter');
        const second = await page.$eval('[name=list_groups]', el => el.value);
        await button('Move Up');
        await save();
        await go();
        const ordered = await page.$$eval('[name=list_groups] option', opts => opts.map(o => ({value:o.value,text:o.text})));
        assert.equal(ordered[0].value, second, 'reorder survives reload');
        assert.equal(ordered.find(o => o.value === id).text, 'Renamed browser filter', 'rename survives reload');
        await page.select('[name=list_groups]', id);
        await page.select('[name=list_in]', fixtureData.friend);
        await button('<< Remove');
        await save();
        await go();
        await page.select('[name=list_groups]', id);
        assert.equal(await page.$eval('[name=list_in]', el => el.options.length), 0, 'removal survives reload');
        await dialogButton('Delete', '');
        await page.select('[name=list_groups]', second);
        await dialogButton('Delete', '');
        await save();
        await go();
        assert.equal(await page.$eval('[name=list_groups]', el => el.options.length), 0, 'deletion survives reload');
        await go('?authas=' + fixtureData.community);
        assert.match(await page.content(), /Communities cannot currently use access filters/);
        await shot('community');
        await go('?authas=' + fixtureData.outsider);
        assert.equal(await page.$('form[name=fg]'), null, 'unauthorized authas has no editor');
        await shot('unauthorized');
        assert.deepEqual(errors, [], 'no uncaught browser errors');
        console.log('PASS: create, membership, reload, rename, reorder, removal, delete, community, authas');
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
