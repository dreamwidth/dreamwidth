// Run in the devcontainer after bin/dev/screenshot installs headless Chrome.
// Uses only the seeded development accounts; never point this at production.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
const base = 'http://127.0.0.1:8080';
const out = process.env.DW_BROWSER_OUT || '/tmp/access-filters-browser';

(async () => {
    fs.mkdirSync(out, {recursive: true});
    const browser = await puppeteer.launch({
        executablePath: '/usr/bin/google-chrome-stable',
        args: ['--no-sandbox', '--disable-gpu'],
        defaultViewport: {width: 1280, height: 1000}
    });
    try {
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
        await page.type('input[name=user]', 'test_user');
        await page.type('input[name=password]', 'dreamwidth');
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('input[type=submit], button[type=submit]')]);
        assert.ok((await page.cookies()).some(c => c.name === 'ljmastersession'), 'authenticated');
        await go();
        await shot('empty');
        await dialogButton('New', 'Browser filter');
        const id = await page.$eval('[name=list_groups]', el => el.value);
        assert.ok(id);
        await page.select('[name=list_out]', 'test_friend');
        await button('>> Add');
        assert.ok(await page.$eval('[name=list_in]', el => [...el.options].some(o => o.value === 'test_friend')));
        await shot('populated');
        await page.setViewport({width: 390, height: 844});
        await shot('populated-mobile');
        await page.setViewport({width: 1280, height: 1000});
        await save();
        await shot('saved');
        await go();
        await page.select('[name=list_groups]', id);
        assert.ok(await page.$eval('[name=list_in]', el => [...el.options].some(o => o.value === 'test_friend')), 'membership survives reload');
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
        await page.select('[name=list_in]', 'test_friend');
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
        await go('?authas=test_comm');
        assert.match(await page.content(), /Communities cannot currently use access filters/);
        await shot('community');
        await go('?authas=test_paid');
        assert.equal(await page.$('form[name=fg]'), null, 'unauthorized authas has no editor');
        await shot('unauthorized');
        assert.deepEqual(errors, [], 'no uncaught browser errors');
        console.log('PASS: create, membership, reload, rename, reorder, removal, delete, community, authas');
    } finally {
        await browser.close();
    }
})().catch(e => { console.error(e); process.exit(1); });
