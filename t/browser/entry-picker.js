// Read-only entry picker browser characterization with disposable accounts.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const output = process.argv[2] || '/tmp/entry-picker-browser';
    fs.mkdirSync(output, {recursive:true});
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
        await page.setViewport({width:1280,height:900});
        const errors = [], failures = [];
        page.on('pageerror', error => errors.push(error.message));
        page.on('requestfailed', req => failures.push(req.url()));
        page.on('response', res => { if (res.status() >= 400) failures.push(res.status() + ' ' + res.url()); });
        const base = 'http://127.0.0.1:8080';
        await page.goto(base + '/mobile/login', {waitUntil:'networkidle0'});
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[type=submit]')]);
        const ids = () => page.$$eval('form input[name=itemid]', inputs => inputs.map(el => Number(el.value)).sort((a,b)=>a-b));
        const sorted = values => [...values].sort((a,b)=>a-b);
        const res = await page.goto(base + '/editjournal.bml', {waitUntil:'networkidle0'});
        assert.equal(res.status(), 200);
        assert.match(await page.title(), /Edit Entries/, 'native picker uses its translated heading');
        assert.ok(await page.$('form.entry-picker'), 'native picker form renders');
        assert.deepEqual(await ids(), sorted(data.ids.slice(1)), 'initial page shows exact newest five');
        await page.screenshot({path:output+'/default.png',fullPage:true});
        await page.$eval('[name=howmany]', el => { el.value = '6'; el.dispatchEvent(new Event('change', {bubbles:true})); });
        assert.equal(await page.$eval('#selecttype-lastn', el => el.checked), true,
            'editing howmany selects the recent-entry mode without a radio click');
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.$eval('[name=howmany]', el => el.form.querySelector('[type=submit]').click())]);
        assert.deepEqual(await ids(), sorted(data.ids), 'edited recent count includes private owner entry');
        const security = await page.$$eval('.entry-picker-security', elements => elements.map(el => el.className));
        assert.ok(security.includes('entry-picker-security entry-picker-security-private'), 'private icon renders');
        assert.ok(security.includes('entry-picker-security entry-picker-security-protected'), 'friends icon renders');
        assert.ok(security.includes('entry-picker-security entry-picker-security-groups'), 'custom-groups icon renders');
        assert.ok(!security.includes('entry-picker-security entry-picker-security-public'), 'public entries have no marker');
        const iconAccessibility = await page.$$eval('.entry-picker-security', elements => elements.map(element => ({
            alt: element.querySelector('img')?.alt,
            title: element.querySelector('img')?.title || '',
            html: element.innerHTML,
        })));
        const expectedSecurityLabels = ['Custom access entry', 'Friends-only entry', 'Private entry'];
        assert.deepEqual(iconAccessibility.map(icon => icon.alt).sort(), expectedSecurityLabels,
            'security icons expose translated, distinct image alt labels');
        assert.deepEqual(iconAccessibility.map(icon => icon.title).sort(), expectedSecurityLabels,
            'security icons expose translated, distinct image title labels');
        assert.ok(iconAccessibility.every(icon => !icon.html.includes('XXX')),
            'security icons never render an invalid image type placeholder');
        await page.screenshot({path:output+'/recent.png',fullPage:true});
        await page.goto(base + '/editjournal', {waitUntil:'networkidle0'});
        for (const [name,value] of Object.entries({year:'1970',month:'1',day:'1'})) {
            await page.$eval('[name='+name+']', (el,value) => { el.value=value; el.dispatchEvent(new Event('change', {bubbles:true})); }, value);
        }
        assert.equal(await page.$eval('#selecttype-day', el => el.checked), true,
            'editing a date field selects day mode without a radio click');
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.$eval('[name=year]', el => el.form.querySelector('[type=submit]').click())]);
        assert.match(await page.$eval('body', el=>el.textContent), /No entries match the criteria/);
        assert.deepEqual(await ids(), []);
        await page.screenshot({path:output+'/empty.png',fullPage:true});
        await page.goto(base + '/editjournal?usejournal=' + data.community, {waitUntil:'networkidle0'});
        assert.deepEqual(await ids(), [data.community_id]);
        const action = await page.$eval('input[name=itemid]', el => el.form.action);
        assert.equal(new URL(action).searchParams.get('usejournal'), data.community);
        await page.screenshot({path:output+'/community.png',fullPage:true});
        await page.setViewport({width:390,height:844});
        await page.goto(base + '/editjournal', {waitUntil:'networkidle0'});
        assert.deepEqual(await ids(), sorted(data.ids.slice(1)));
        await page.screenshot({path:output+'/narrow.png',fullPage:true});
        if (process.env.PICKER_BROWSER_FAIL_AFTER_SELECTION) throw new Error('intentional picker cleanup probe');
        assert.deepEqual(errors, [], 'picker flow has no JavaScript exceptions');
        assert.deepEqual(failures, [], 'picker flow has no failed resources');
        console.log('PASS: picker default/recent/date/community/keyboard/narrow with disposable fixture');
    } finally {
        try { if (browser) await browser.close(); }
        finally { fixture.stdin.end(); await done; }
    }
})().catch(error => { console.error(error); process.exit(1); });
