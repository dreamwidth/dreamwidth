// Customization subtitle RPC acceptance with disposable accounts.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
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
        const requestFailures = [];
        page.on('pageerror', error => pageErrors.push(error.message));
        page.on('requestfailed', request =>
            requestFailures.push(request.url() + ': ' + (request.failure()?.errorText || 'request failed')));
        page.on('response', response => {
            if (response.status() >= 400) requestFailures.push(response.url() + ': HTTP ' + response.status());
        });
        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('[type=submit]')]);
        for (const query of ['', '?authas=' + data.community]) {
            await page.goto(base + '/customize/' + query, {waitUntil: 'networkidle0'});
            const value = 'Subtitle browser ' + (query || 'personal') + ' ' + Date.now();
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
            assert.equal(await page.$eval('#journalsubtitle', el => el.value), value, 'distinct subtitle survives reload');
        }
        if (process.env.CUSTOMIZE_SUBTITLE_FAIL_AFTER_SAVE) throw new Error('intentional subtitle cleanup probe');

        await page.goto(base + '/customize/?cat=all', {waitUntil: 'networkidle0'});
        const styleBefore = await page.evaluate(() => ({
            theme: document.querySelector('.theme-current h3').textContent.trim(),
            layout: document.querySelector('.theme-current-layout').textContent.trim(),
        }));

        await page.goto(base + '/customize/options?group=display', {waitUntil: 'networkidle0'});
        const displayChoice = await page.evaluate(() => {
            const mood = document.querySelector('#moodtheme_dropdown');
            const alternateMood = [...mood.options].find(option => !option.disabled && option.value !== mood.value);
            const currentNav = document.querySelector('input[name="Widget[NavStripChooser]_control_strip_color"]:checked');
            const alternateNav = [...document.querySelectorAll('input[name="Widget[NavStripChooser]_control_strip_color"]')]
                .find(input => input.value !== currentNav.value);
            return {
                mood: alternateMood && alternateMood.value,
                nav: alternateNav && alternateNav.value,
            };
        });
        assert.ok(displayChoice.mood, 'Display renders an alternate enabled mood theme');
        assert.ok(displayChoice.nav, 'Display renders an alternate nav-strip color');
        const oldMoodDropdown = await page.$('#moodtheme_dropdown');
        assert.ok(oldMoodDropdown, 'Display renders its initial mood selector');
        const moodPreview = page.waitForResponse(response =>
            response.url().includes('__rpc_widget') &&
            (response.request().postData() || '').includes('MoodThemeChooser'));
        await page.select('#moodtheme_dropdown', displayChoice.mood);
        assert.equal((await moodPreview).status(), 200, 'Display mood preview RPC succeeds');
        await page.waitForFunction(old =>
            !old.isConnected || document.querySelector('#moodtheme_dropdown') !== old, {}, oldMoodDropdown);
        await oldMoodDropdown.dispose();
        assert.equal(await page.$eval('#moodtheme_dropdown', select => select.value), displayChoice.mood,
            'Display replacement selector retains the selected mood');
        if (!await page.$eval('#opt_forcemoodtheme', input => input.checked)) await page.click('#opt_forcemoodtheme');
        await page.click('input[name="Widget[NavStripChooser]_control_strip_color"][value="' + displayChoice.nav + '"]');
        assert.equal(await page.$eval('#opt_forcemoodtheme', input => input.checked), true,
            'Display force-mood checkbox is checked before save');
        assert.ok(await page.$eval('#customize-form', form => {
            const data = new FormData(form);
            return data.has('Widget[MoodThemeChooser]_opt_forcemoodtheme');
        }), 'Display form serializes the checked force-mood value');
        await Promise.all([
            page.waitForNavigation({waitUntil: 'networkidle0'}),
            page.click('[name="Widget[CustomizeTheme]_save"]'),
        ]);
        await page.reload({waitUntil: 'networkidle0'});
        assert.equal(await page.$eval('#moodtheme_dropdown', select => select.value), displayChoice.mood,
            'Display mood selection survives save and fresh reload');
        assert.equal(await page.$eval('#opt_forcemoodtheme', input => input.checked), true,
            'Display forced-mood selection survives save and reload');
        assert.equal(await page.$eval('input[name="Widget[NavStripChooser]_control_strip_color"]:checked', input => input.value),
            displayChoice.nav, 'Display nav-strip selection survives save and reload');

        const resetDialog = new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error('Display reset did not open its confirmation')), 5000);
            page.once('dialog', dialog => {
                clearTimeout(timer);
                assert.match(dialog.message(), /reset/i, 'Display reset uses a reset confirmation');
                dialog.accept().then(resolve, reject);
            });
        });
        await Promise.all([
            page.waitForNavigation({waitUntil: 'networkidle0'}),
            resetDialog,
            page.click('[name="Widget[CustomizeTheme]_reset"]'),
        ]);
        await page.reload({waitUntil: 'networkidle0'});
        assert.equal(await page.$eval('#moodtheme_dropdown', select => select.value), '1',
            'Display reset restores mood theme 1 after a fresh reload');
        assert.equal(await page.$eval('#opt_forcemoodtheme', input => input.checked), false,
            'Display reset disables forced mood themes');
        assert.equal(await page.$eval('input[name="Widget[NavStripChooser]_control_strip_color"]:checked', input => input.value), 'dark',
            'Display reset restores the default nav-strip color');
        fs.mkdirSync('/tmp/customize-navigation-display', {recursive: true});
        await page.screenshot({path: '/tmp/customize-navigation-display/display-reset.png', fullPage: true});

        await page.goto(base + '/customize/?cat=all', {waitUntil: 'networkidle0'});
        const styleAfter = await page.evaluate(() => ({
            theme: document.querySelector('.theme-current h3').textContent.trim(),
            layout: document.querySelector('.theme-current-layout').textContent.trim(),
        }));
        assert.deepEqual(styleAfter, styleBefore, 'Display reset preserves the selected theme and layout');
        assert.deepEqual(pageErrors, [], 'subtitle and Display actions have no browser errors');
        assert.deepEqual(requestFailures, [], 'subtitle and Display actions have no failed requests');
        console.log('PASS distinct personal/community subtitle save, one RPC, reload; Display save/reset');
    } finally {
        try { if (browser) await browser.close(); }
        finally { fixture.stdin.end(); await done; }
    }
})().catch(error => { console.error(error); process.exit(1); });
