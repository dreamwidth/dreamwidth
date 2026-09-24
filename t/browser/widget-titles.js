// Devcontainer headless regression for the real widget RPC and request state.
// Requires the seeded test_user/test_comm accounts and screenshot dependencies.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable', args:['--no-sandbox']});
    try {
        const page = await browser.newPage();
        const errors = [];
        page.on('pageerror', e => errors.push(e.message));
        const base = 'http://127.0.0.1:8080';
        await page.goto(base + '/mobile/login', {waitUntil:'networkidle0'});
        await page.type('[name=user]', 'test_user');
        await page.type('[name=password]', 'dreamwidth');
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[type=submit]')]);
        for (const query of ['', '?authas=test_comm']) {
            await page.goto(base + '/customize/' + query, {waitUntil:'networkidle0'});
            const widgetClasses = await page.evaluate(() => Object.values(LJWidget.widgets).map(widget => widget.widgetClass));
            assert.ok(widgetClasses.includes('ThemeNav'), 'parent theme-navigation widget initialized');
            assert.ok(widgetClasses.includes('ThemeChooser'), 'nested theme chooser initialized');

            // Foundation owns window.$ for jQuery. The widget callbacks were
            // created with their local DOM helper and must continue to work.
            await page.addScriptTag({url: base + '/js/jquery/jquery-1.8.3.js'});
            assert.equal(await page.evaluate(() => window.$ === window.jQuery), true, 'jQuery owns window.$');

            const original = await page.$eval('#journaltitle', e => e.value);
            for (const title of ['Widget request regression ' + Date.now(), original]) {
                console.log('Saving', query || 'personal', title === original ? 'restore' : 'test value');
                await page.click('#journaltitle_edit');
                await page.$eval('#journaltitle', (el,value) => { el.value = value; }, title);
                let requests = 0;
                const count = request => { if (request.url().includes('__rpc_widget')) requests++; };
                page.on('request', count);
                const response = page.waitForResponse(r => r.url().includes('__rpc_widget'));
                await page.click('#save_btn_journaltitle');
                const res = await response;
                assert.equal(res.status(), 200);
                const body = await res.json();
                await page.waitForNetworkIdle();
                page.off('request', count);
                assert.equal(requests, 1, 'one RPC per save, no stale widget callbacks');
                assert.ok(!body.errors || body.errors.length === 0, JSON.stringify(body.errors));
                await page.reload({waitUntil:'networkidle0'});
                assert.equal(await page.$eval('#journaltitle', e => e.value), title, 'widget save survives reload');
            }
        }

        await page.goto(base + '/customize/options?group=presentation', {waitUntil:'networkidle0'});
        assert.ok(await page.$('[name="Widget[CustomizeTheme]_reset"]'), 'rendered reset control is present');
        const changed = await page.evaluate(() => {
            window.__confirmCalls = 0;
            window.confirm = () => { window.__confirmCalls++; return false; };
            const field = document.querySelector('#customize-form select, #customize-form textarea, #customize-form input[type=checkbox], #customize-form input[type=radio]');
            if (!field) return false;
            field.dispatchEvent(new Event('change', {bubbles: true}));
            return true;
        });
        assert.equal(changed, true, 'customize options has an editable control');
        await page.click('a.customize-nav-group[href*="group=colors"]');
        await new Promise(resolve => setTimeout(resolve, 250));
        assert.ok(page.url().includes('group=presentation'), 'cancelled unsaved-change confirmation keeps the current group');
        await page.click('[name="Widget[CustomizeTheme]_reset"]');
        assert.ok(await page.evaluate(() => window.__confirmCalls >= 2), 'rendered reset control uses the confirmation handler');

        assert.deepEqual(errors, [], 'no widget JS errors');
        console.log('PASS: personal/community widget RPC save, persistence, nested init, and reset wiring');
    } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exit(1); });
