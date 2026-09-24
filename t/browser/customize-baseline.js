// Exercise the customize page's theme/layout choosers, custom CSS, every S2
// option-group control type, and linkslist through a real browser.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    let fixture;
    let fixtureDone;
    let browser;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/customize-fixture.pl'], {stdio:['pipe', 'pipe', 'inherit']});
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', code => code ? reject(new Error('fixture cleanup failed: ' + code)) : resolve());
            fixture.once('error', reject);
        });
        const fixtureData = await new Promise((resolve, reject) => {
            let output = '';
            fixture.stdout.on('data', data => {
                output += data;
                const newline = output.indexOf('\n');
                if (newline < 0) return;
                try { resolve(JSON.parse(output.slice(0, newline))); }
                catch (error) { reject(error); }
            });
            fixtureDone.catch(() => {});
            fixture.once('error', reject);
            fixture.once('exit', code => reject(new Error('fixture exited before startup: ' + code)));
        });
        browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable',args:['--no-sandbox']});
        const page = await browser.newPage();
        const base = 'http://127.0.0.1:8080';
        await page.setViewport({width:1280,height:900});
        let errors = [];
        let failures = [];
        const allErrors = [];
        const allFailures = [];
        page.on('pageerror', e => { errors.push(e.message); allErrors.push(e.message); });
        page.on('requestfailed', r => {
            const failure = r.url() + ': ' + (r.failure()?.errorText || 'request failed');
            failures.push(failure); allFailures.push(failure);
        });
        page.on('response', r => {
            if (r.status() >= 400) {
                const failure = r.url() + ': HTTP ' + r.status();
                failures.push(failure); allFailures.push(failure);
            }
        });
        const output = process.argv[2] || '/tmp/customize-baseline';
        fs.mkdirSync(output,{recursive:true});
        await page.goto(base + '/mobile/login',{waitUntil:'networkidle0'});
        await page.type('[name=user]', fixtureData.user);
        await page.type('[name=password]', fixtureData.password);
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}),page.click('[type=submit]')]);
        const states = [['themes','/customize/?cat=all'], ['community','/customize/?authas=' + fixtureData.community]];
        for(const group of ['presentation','colors','fonts','images','text','modules','customcss','display']) {
            states.push([group,'/customize/options?group='+group]);
        }
        const results = [];
        for(const [name,path] of states) {
            errors = [];
            const response = await page.goto(base+path,{waitUntil:'networkidle0'});
            assert.equal(response.status(),200);
            await page.waitForSelector('#journaltitle');
            await page.screenshot({path:output+'/'+name+'.png',fullPage:true});
            const state = {name,path,errors:[...errors],widgets:await page.$$eval('[class*=appwidget]', els=>els.map(e=>e.id).filter(Boolean))};
            results.push(state);
            assert.deepEqual(state.errors, [], name + ' has no JavaScript errors');
        }
        await page.goto(base + '/customize/?cat=all&show=all', {waitUntil:'networkidle0'});
        const selectedBeforeTheme = await page.$eval('.theme-item.selected h4', el => el.textContent.trim());
        const themeChoice = await page.$eval('.theme-form', form => ({
            name: form.closest('.theme-item').querySelector('h4').textContent.trim(),
            themeid: form.elements['Widget[ThemeChooser]_apply_themeid'].value,
            layoutid: form.elements['Widget[ThemeChooser]_apply_layoutid'].value,
            preview: form.closest('.theme-item').querySelector('.theme-preview-link').href,
        }));
        assert.notEqual(themeChoice.name, selectedBeforeTheme, 'theme browser form chooses a distinct theme');
        const previewTarget = browser.waitForTarget(target => target.opener() === page.target());
        const previewLink = await page.evaluateHandle(() =>
            document.querySelector('.theme-form').closest('.theme-item').querySelector('.theme-preview-link'));
        await previewLink.click();
        const previewPage = await (await previewTarget).page();
        await previewPage.waitForFunction(() => /[?&]s2id=\d+/.test(location.href));
        assert.match(previewPage.url(), /[?&]s2id=\d+/, 'theme preview opens its selected preview style');
        await previewPage.close();
        const themeRpc = page.waitForResponse(response =>
            response.url().includes('__rpc_widget') && (response.request().postData() || '').includes('ThemeChooser'));
        page.once('dialog', dialog => dialog.accept());
        await page.click('.theme-form .theme_button');
        await themeRpc;
        await page.waitForFunction(name => {
            const selected = document.querySelector('.theme-item.selected h4');
            return selected && selected.textContent.trim() === name;
        }, {}, themeChoice.name);
        assert.equal(await page.$eval('.theme-item.selected h4', el => el.textContent.trim()), themeChoice.name,
            'theme browser apply refresh marks the selected rendered theme');

        const layoutBefore = await page.$eval('.layout-item.selected .layout-desc', el => el.textContent.trim());
        const layoutChoice = await page.$eval('.layout-form', form => ({
            name: form.closest('.layout-item').querySelector('.layout-desc').textContent.trim(),
            choice: form.elements['Widget[LayoutChooser]_layout_choice'].value,
        }));
        assert.notEqual(layoutChoice.name, layoutBefore, 'layout browser form chooses a distinct layout');
        const layoutRpc = page.waitForResponse(response =>
            response.url().includes('__rpc_widget') && (response.request().postData() || '').includes('LayoutChooser'));
        await page.click('.layout-form .layout-button');
        await layoutRpc;
        await page.waitForFunction(name => {
            const selected = document.querySelector('.layout-item.selected .layout-desc');
            return selected && selected.textContent.trim() === name;
        }, {}, layoutChoice.name);
        assert.equal(await page.$eval('.layout-item.selected .layout-desc', el => el.textContent.trim()), layoutChoice.name,
            'layout browser apply refresh marks the selected rendered layout');

        await page.goto(base + '/customize/options?group=customcss', {waitUntil:'networkidle0'});
        const marker = '/* browser custom CSS acceptance */';
        await page.evaluate(value => document.querySelector('.CodeMirror').CodeMirror.setValue(value), marker);
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_save"]')]);
        assert.equal(await page.$eval('.CodeMirror', el => el.CodeMirror.getValue()), marker, 'custom CSS browser form save reloads its value');
        page.once('dialog', dialog => dialog.accept());
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_reset"]')]);
        assert.equal(await page.$eval('.CodeMirror', el => el.CodeMirror.getValue()), '', 'custom CSS reset restores the seeded value');

        const exercisedControlTypes = new Set();
        assert.ok(await page.$('[name="Widget[S2PropGroup]_custom_css"]'),
            'browser exercises the CodeMirror backing textarea');
        exercisedControlTypes.add('textarea');
        for (const group of ['presentation', 'colors', 'fonts', 'images', 'text', 'modules']) {
            await page.goto(base + '/customize/options?group=' + group, {waitUntil:'networkidle0'});
            const control = await page.evaluate((groupName) => {
                const controls = [...document.querySelectorAll('[name^="Widget[S2PropGroup]_"]')];
                for (const element of controls) {
                    if (element.disabled) continue;
                    if (element.tagName === 'SELECT') {
                        const option = [...element.options].find(option => option.value !== element.value);
                        if (option) return {group: groupName, elementType: 'select', name: element.name, kind: 'value', before: element.value, after: option.value};
                    }
                    if (element.type === 'checkbox') {
                        return {group: groupName, elementType: 'checkbox', name: element.name, kind: 'checked', before: element.checked, after: !element.checked};
                    }
                    if (element.tagName === 'TEXTAREA' || ['text', 'color'].includes(element.type)) {
                        const numeric = element.type === 'text' && element.maxLength > 0
                            && element.maxLength <= 5 && /^\d*$/.test(element.value);
                        const after = (element.type === 'color' || element.classList.contains('coloris')
                            || /color/i.test(element.name)) ? '#123456'
                            : numeric ? (element.value === '1' ? '2' : '1')
                            : 'Browser ' + groupName + ' property';
                        if (after !== element.value) return {group: groupName, elementType: element.tagName === 'TEXTAREA' ? 'textarea' : element.type, name: element.name, kind: 'value', before: element.value, after};
                    }
                }
                return null;
            }, group);
            assert.ok(control, group + ' renders a mutable S2 property control');
            exercisedControlTypes.add(control.elementType);
            await page.evaluate(choice => {
                const element = document.getElementsByName(choice.name)[0];
                if (choice.kind === 'checked') element.checked = choice.after;
                else element.value = choice.after;
                element.dispatchEvent(new Event('change', {bubbles: true}));
            }, control);
            await Promise.all([
                page.waitForNavigation({waitUntil:'networkidle0'}),
                page.click('[name="Widget[CustomizeTheme]_save"]'),
            ]);
            const saved = await page.evaluate(choice => {
                const element = document.getElementsByName(choice.name)[0];
                return choice.kind === 'checked' ? element.checked : element.value;
            }, control);
            assert.deepEqual(saved, control.after, group + ' property save reloads its actual control value: ' + JSON.stringify(control));
            page.once('dialog', dialog => dialog.accept());
            await Promise.all([
                page.waitForNavigation({waitUntil:'networkidle0'}),
                page.click('[name="Widget[CustomizeTheme]_reset"]'),
            ]);
            const reset = await page.evaluate(choice => {
                const element = document.getElementsByName(choice.name)[0];
                return choice.kind === 'checked' ? element.checked : element.value;
            }, control);
            assert.deepEqual(reset, control.before, group + ' reset restores its rendered original control value: ' + JSON.stringify(control));
        }
        async function exerciseExplicitControl(type) {
            for (const group of ['presentation', 'colors', 'fonts', 'images', 'text', 'modules']) {
                await page.goto(base + '/customize/options?group=' + group, {waitUntil:'networkidle0'});
                const control = await page.evaluate((wanted) => {
                    const controls = [...document.querySelectorAll('[name^="Widget[S2PropGroup]_"]')];
                    for (const element of controls) {
                        if (element.disabled) continue;
                        if (wanted === 'select' && element.tagName === 'SELECT') {
                            const option = [...element.options].find(option => option.value !== element.value);
                            if (option) return {name: element.name, kind: 'value', before: element.value, after: option.value};
                        }
                        if (wanted === 'checkbox' && element.type === 'checkbox') {
                            return {name: element.name, kind: 'checked', before: element.checked, after: !element.checked};
                        }
                    }
                    return null;
                }, type);
                if (!control) continue;
                await page.evaluate(choice => {
                    const element = [...document.getElementsByName(choice.name)].find(el => choice.kind !== 'checked' || el.type === 'checkbox');
                    if (choice.kind === 'checked') element.checked = choice.after;
                    else element.value = choice.after;
                }, control);
                await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_save"]')]);
                await page.reload({waitUntil:'networkidle0'});
                const saved = await page.evaluate(choice => {
                    const element = [...document.getElementsByName(choice.name)].find(el => choice.kind !== 'checked' || el.type === 'checkbox');
                    return choice.kind === 'checked' ? element.checked : element.value;
                }, control);
                assert.deepEqual(saved, control.after, type + ' control save reloads its exact state');
                page.once('dialog', dialog => dialog.accept());
                await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_reset"]')]);
                await page.reload({waitUntil:'networkidle0'});
                const reset = await page.evaluate(choice => {
                    const element = [...document.getElementsByName(choice.name)].find(el => choice.kind !== 'checked' || el.type === 'checkbox');
                    return choice.kind === 'checked' ? element.checked : element.value;
                }, control);
                assert.deepEqual(reset, control.before, type + ' control reset restores its exact default state');
                exercisedControlTypes.add(type);
                return;
            }
            assert.fail('fixture renders an enabled S2 ' + type + ' control');
        }
        await exerciseExplicitControl('select');
        await exerciseExplicitControl('checkbox');

        assert.ok(exercisedControlTypes.has('select'), 'browser exercised an S2 select control');
        assert.ok(exercisedControlTypes.has('checkbox'), 'browser exercised an S2 checkbox control');
        assert.ok([...exercisedControlTypes].some(type => ['text', 'color', 'textarea'].includes(type)),
            'browser exercised an S2 text, color, or textarea control');
        const selectedTheme = themeChoice.name;
        const selectedLayout = layoutChoice.name;
        await page.goto(base + '/customize/options?group=linkslist', {waitUntil:'networkidle0'});
        const links = [
            ['1', '20', 'https://example.invalid/browser-second', 'Browser second', 'Browser second hover'],
            ['2', '10', 'https://example.invalid/browser-first', 'Browser first', 'Browser first hover'],
        ];
        for (const [number, order, url, title, hover] of links) {
            await page.$eval('#link_' + number + '_url', (el, value) => el.value = value, url);
            await page.$eval('#link_' + number + '_title', (el, value) => el.value = value, title);
            await page.$eval('#link_' + number + '_hover', (el, value) => el.value = value, hover);
            await page.$eval('[name="Widget[LinksList]_link_' + number + '_ordernum"]', (el, value) => el.value = value, order);
        }
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_save"]')]);
        assert.equal(await page.$eval('#link_1_url', el => el.value), links[1][2], 'lower order reloads first');
        assert.equal(await page.$eval('#link_1_title', el => el.value), links[1][3], 'ordered first link reloads title');
        assert.equal(await page.$eval('#link_1_hover', el => el.value), links[1][4], 'ordered first link reloads hover text');
        assert.equal(await page.$eval('[name="Widget[LinksList]_link_1_ordernum"]', el => el.value), links[1][1], 'ordered first link reloads order');
        assert.equal(await page.$eval('#link_2_url', el => el.value), links[0][2], 'higher order reloads second');
        page.once('dialog', dialog => dialog.accept());
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_reset"]')]);
        assert.equal(await page.$eval('#link_1_title', el => el.value), '', 'linkslist reset clears the rendered link title');
        await page.goto(base + '/customize/', {waitUntil:'networkidle0'});
        assert.equal(await page.$eval('.theme-current h3', el => el.textContent.trim()), selectedTheme, 'linkslist reset preserves selected theme');
        assert.equal(await page.$eval('.layout-item.selected .layout-desc', el => el.textContent.trim()), selectedLayout, 'linkslist reset preserves selected layout');

        await page.goto(base + '/customize/options?group=text', {waitUntil:'networkidle0'});
        assert.ok(await page.$('[name="Widget[CustomTextModule]_module_customtext_title"]'), 'custom text widget renders in the text option group');
        const customTitle = 'Browser custom text';
        await page.$eval('[name="Widget[CustomTextModule]_module_customtext_title"]', (el, value) => el.value = value, customTitle);
        await page.$eval('[name="Widget[CustomTextModule]_module_customtext_content"]', (el, value) => el.value = value, customTitle + ' content');
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_save"]')]);
        assert.equal(await page.$eval('[name="Widget[CustomTextModule]_module_customtext_title"]', el => el.value), customTitle, 'custom text browser form save reloads title');
        page.once('dialog', dialog => dialog.accept());
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[name="Widget[CustomizeTheme]_reset"]')]);
        assert.equal(await page.$eval('[name="Widget[CustomTextModule]_module_customtext_title"]', el => el.value), 'Custom Text', 'custom text reset restores default title');

        if (process.env.CUSTOMIZE_BROWSER_FAIL_AFTER_MUTATION) throw new Error('intentional fixture restoration probe');
        assert.deepEqual(allErrors, [], 'browser mutation flows have no JavaScript errors');
        assert.deepEqual(allFailures, [], 'browser mutation flows have no network failures');
        await page.setViewport({width:390,height:844});
        for (const [name,path] of [['themes-narrow','/customize/?cat=all'], ['linkslist-narrow','/customize/options?group=linkslist']]) {
            errors = []; failures = [];
            const response = await page.goto(base + path, {waitUntil:'networkidle0'});
            assert.equal(response.status(), 200);
            await page.screenshot({path:output+'/'+name+'.png', fullPage:true});
            if (name === 'linkslist-narrow') {
                const widths = await page.$eval('#linkslist-group', group => ({
                    groupClient: group.clientWidth,
                    groupScroll: group.scrollWidth,
                    title: document.querySelector('#link_1_title').getBoundingClientRect().width,
                    hover: document.querySelector('#link_1_hover').getBoundingClientRect().width,
                    titleVisible: (() => {
                        const rect = document.querySelector('#link_1_title').getBoundingClientRect();
                        return Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0));
                    })(),
                }));
                assert.ok(widths.title >= 300 && widths.hover >= 300,
                    'narrow linkslist keeps title and hover inputs usable: ' + JSON.stringify(widths));
                assert.ok(widths.titleVisible >= 100,
                    'narrow linkslist exposes a useful portion of its first text input: ' + JSON.stringify(widths));
                await page.focus('#link_1_title');
                assert.equal(await page.$eval('#link_1_title', el => document.activeElement === el), true,
                    'narrow linkslist text input remains keyboard focusable');
                assert.ok(widths.groupScroll > widths.groupClient,
                    'narrow linkslist scrolls its table rather than shrinking its inputs');
            }
            assert.deepEqual(errors, [], name + ' has no JavaScript errors');
            assert.deepEqual(failures, [], name + ' has no network failures');
        }
        fs.writeFileSync(output+'/results.json',JSON.stringify(results,null,2));
        console.log(JSON.stringify(results,null,2));
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
