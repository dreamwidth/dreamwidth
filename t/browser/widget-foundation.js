// Foundation resource-order regression for legacy widgets.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable', args:['--no-sandbox']});
    try {
        const page = await browser.newPage();
        const errors = [];
        page.on('pageerror', error => errors.push(error.stack || error.message));
        const base = 'http://127.0.0.1:8080';
        await page.goto(base + '/mobile/login', {waitUntil:'networkidle0'});
        await page.type('[name=user]', 'test_user');
        await page.type('[name=password]', 'dreamwidth');
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[type=submit]')]);
        await page.goto(base + '/__test/widget-foundation', {waitUntil:'networkidle0'});
        const state = await page.evaluate(() => ({
            jquery: window.$ === window.jQuery,
            customize: typeof Customize === 'object',
            widgets: Object.values(LJWidget.widgets).map(widget => widget.widgetClass),
            resources: performance.getEntriesByType('resource').map(entry => entry.name),
        }));
        assert.equal(state.jquery, true, 'Foundation keeps jQuery as window.$ before widget setup');
        assert.equal(state.customize, true, 'page_js_obj exists before queued setup executes');
        assert.ok(state.widgets.includes('ThemeNav'), 'parent widget initialized');
        assert.ok(state.widgets.includes('ThemeChooser'), 'nested widget initialized');
        const foundationBundle = state.resources.find(resource => resource.includes('jquery/jquery-1.8.3.js'));
        const widgetBundle = state.resources.find(resource => resource.includes('ljwidget.js'));
        assert.ok(foundationBundle.indexOf('jquery/jquery-1.8.3.js') < foundationBundle.indexOf('6alib/dom.js'), 'jQuery loads before the legacy DOM helper');
        assert.ok(state.resources.indexOf(foundationBundle) < state.resources.indexOf(widgetBundle), 'DOM helper loads before widget runtime');
        assert.ok(widgetBundle.indexOf('customize.js') < widgetBundle.indexOf('ljwidget.js'), 'Customize loads before queued page_js_obj setup');

        const rpc = async action => {
            const classes = [];
            const count = request => {
                if (!request.url().includes('__rpc_widget')) return;
                const params = request.postData() || new URL(request.url()).search.slice(1);
                classes.push(new URLSearchParams(params).get('_widget_class'));
            };
            page.on('request', count);
            const response = page.waitForResponse(result => result.url().includes('__rpc_widget'));
            await action();
            assert.equal((await response).status(), 200);
            await page.waitForNetworkIdle();
            page.off('request', count);
            assert.equal(classes.filter(widget => widget === 'ThemeNav').length, 1, 'one ThemeNav RPC per nested-widget action');
            assert.equal(classes.filter(widget => widget === 'CurrentTheme').length, 1, 'one dependent CurrentTheme refresh per ThemeNav action');
        };
        await page.$eval('#search_box', element => { element.value = 'ciel'; });
        await rpc(() => page.click('#search_btn'));
        assert.ok(await page.$('#show_dropdown_top'), 'ThemeNav refresh replaced nested ThemeChooser markup');
        const showValue = await page.$eval('#show_dropdown_top', element => element.options[1].value);
        await rpc(() => page.select('#show_dropdown_top', showValue));
        assert.ok(await page.$('#show_dropdown_top'), 'refreshed nested ThemeChooser handles a second action');

        const original = await page.$eval('#journaltitle', element => element.value);
        await page.click('#journaltitle_edit');
        await page.$eval('#journaltitle', (element, value) => { element.value = value; }, 'Foundation widget regression ' + Date.now());
        let requests = 0;
        const count = request => { if (request.url().includes('__rpc_widget')) requests++; };
        page.on('request', count);
        const response = page.waitForResponse(result => result.url().includes('__rpc_widget'));
        await page.click('#save_btn_journaltitle');
        assert.equal((await response).status(), 200);
        await page.waitForNetworkIdle();
        page.off('request', count);
        assert.equal(requests, 1, 'one RPC refreshes the Foundation widget');
        await page.reload({waitUntil:'networkidle0'});
        assert.notEqual(await page.$eval('#journaltitle', element => element.value), original, 'title refresh persisted');
        await page.click('#journaltitle_edit');
        await page.$eval('#journaltitle', (element, value) => { element.value = value; }, original);
        const restore = page.waitForResponse(result => result.url().includes('__rpc_widget'));
        await page.click('#save_btn_journaltitle');
        assert.equal((await restore).status(), 200);
        assert.deepEqual(errors, [], 'Foundation fixture has no browser errors');
        console.log('PASS: Foundation resources, nested widgets, and title RPC refresh');
    } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
