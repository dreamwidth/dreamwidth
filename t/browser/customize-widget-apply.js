// t/browser/customize-widget-apply.js
//
// Customize page behaviors that only a real browser can exercise: the theme
// browser's AJAX apply (no page reload), and two widget forms (a generic S2
// property control, and the CodeMirror-backed custom CSS editor) whose
// values live in JS-managed controls rather than plain form fields.
//
// Authors:
//      Mark Smith <mark@dreamwidth.org>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself.  For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    let fixture;
    let fixtureDone;
    let browser;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/customize-fixture.pl'], {stdio: ['pipe', 'pipe', 'inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', code => code ? reject(new Error('fixture cleanup failed: ' + code)) : resolve());
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
            fixture.once('exit', code => reject(new Error('fixture exited before startup: ' + code)));
        });
        browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable',args:['--no-sandbox']});
        const page = await browser.newPage();
        const base = 'http://127.0.0.1:8080';
        const errors = [];
        page.on('pageerror', e => errors.push(e.message));
        await page.goto(base + '/mobile/login',{waitUntil:'networkidle0'});
        await page.type('[name=user]', fixtureData.user);
        await page.type('[name=password]', fixtureData.password);
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}),page.click('[type=submit]')]);

        // Theme browser apply: an AJAX widget RPC updates the selected theme
        // in place, with no navigation.
        await page.goto(base + '/customize/?cat=all&show=all', {waitUntil:'networkidle0'});
        const selectedBefore = await page.$eval('.theme-item.selected h4', el => el.textContent.trim());
        const themeName = await page.$eval('.theme-form', form => form.closest('.theme-item').querySelector('h4').textContent.trim());
        assert.notEqual(themeName, selectedBefore, 'theme browser form chooses a distinct theme');
        const themeRpc = page.waitForResponse(response =>
            response.url().includes('__rpc_widget') && (response.request().postData() || '').includes('ThemeChooser'));
        page.once('dialog', dialog => dialog.accept());
        await page.click('.theme-form .theme_button');
        await themeRpc;
        await page.waitForFunction(name => {
            const selected = document.querySelector('.theme-item.selected h4');
            return selected && selected.textContent.trim() === name;
        }, {}, themeName);
        assert.equal(await page.$eval('.theme-item.selected h4', el => el.textContent.trim()), themeName,
            'theme browser apply refresh marks the selected rendered theme with no page reload');

        // One representative S2 property control: save persists it, reset
        // restores the rendered original, both via a real form submission.
        await page.goto(base + '/customize/options?group=presentation', {waitUntil:'networkidle0'});
        const control = await page.evaluate(() => {
            const element = [...document.querySelectorAll('[name^="Widget[S2PropGroup]_"]')]
                .find(el => !el.disabled && el.tagName === 'SELECT');
            const option = [...element.options].find(o => o.value !== element.value);
            return {name: element.name, before: element.value, after: option.value};
        });
        assert.ok(control, 'presentation group renders a mutable S2 select control');
        await page.select(`[name="${control.name}"]`, control.after);
        await Promise.all([
            page.waitForNavigation({waitUntil:'networkidle0'}),
            page.click('[name="Widget[CustomizeTheme]_save"]'),
        ]);
        assert.equal(await page.$eval(`[name="${control.name}"]`, el => el.value), control.after,
            'S2 property save reloads its actual control value');
        page.once('dialog', dialog => dialog.accept());
        await Promise.all([
            page.waitForNavigation({waitUntil:'networkidle0'}),
            page.click('[name="Widget[CustomizeTheme]_reset"]'),
        ]);
        assert.equal(await page.$eval(`[name="${control.name}"]`, el => el.value), control.before,
            'S2 property reset restores its rendered original control value');

        // Custom CSS lives in a CodeMirror instance, not the backing
        // textarea's DOM value.
        await page.goto(base + '/customize/options?group=customcss', {waitUntil:'networkidle0'});
        const marker = '/* browser custom CSS acceptance */';
        await page.evaluate(value => document.querySelector('.CodeMirror').CodeMirror.setValue(value), marker);
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_save"]')]);
        assert.equal(await page.$eval('.CodeMirror', el => el.CodeMirror.getValue()), marker, 'custom CSS save reloads its CodeMirror value');
        page.once('dialog', dialog => dialog.accept());
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_reset"]')]);
        assert.equal(await page.$eval('.CodeMirror', el => el.CodeMirror.getValue()), '', 'custom CSS reset clears its CodeMirror value');

        assert.deepEqual(errors, [], 'customize widget flows have no JavaScript errors');
        console.log('PASS: theme apply RPC, S2 property save/reset, custom CSS save/reset');
    } finally {
        try { if (browser) await browser.close(); }
        finally {
            if (fixture) {
                fixture.stdin.end();
                await fixtureDone;
            }
        }
    }
})().catch(e=>{console.error(e);process.exit(1);});
