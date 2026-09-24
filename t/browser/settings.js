// Browser acceptance for settings saves using disposable test accounts.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

(async () => {
    const helper = spawn('perl', ['t/browser/settings-fixture.pl'], {cwd: process.env.LJHOME, stdio: ['pipe', 'pipe', 'inherit']});
    const done = new Promise((resolve, reject) => {
        helper.once('exit', (code, signal) => code === 0 ? resolve() : reject(new Error(`fixture exit: ${code}/${signal}`)));
        helper.once('error', reject);
    });
    done.catch(() => {});
    let browser;
    try {
        const fixture = await new Promise((resolve, reject) => {
            let output = '';
            helper.stdout.on('data', chunk => {
                output += chunk;
                if (output.includes('\n')) {
                    try { resolve(JSON.parse(output.split('\n')[0])); } catch (error) { reject(error); }
                }
            });
            helper.once('error', reject);
            helper.once('exit', () => reject(new Error('fixture exited before ready')));
        });
        assert.ok(fixture.user && fixture.community, 'fixture creates disposable browser credentials');
        browser = await puppeteer.launch({executablePath: '/usr/bin/google-chrome-stable', args: ['--no-sandbox']});
        const page = await browser.newPage();
        const errors = [], dialogs = [];
        let dialogPhase = '';
        page.on('pageerror', error => errors.push(error.message));
        page.on('dialog', async dialog => {
            dialogs.push(`${dialogPhase}:${dialog.type()}: ${dialog.message()}`);
            if (dialogPhase === 'cancel-unsaved') return dialog.dismiss();
            if (dialogPhase === 'deleteinactive') return dialog.accept();
            throw new Error(`unexpected dialog: ${dialog.type()}: ${dialog.message()}`);
        });
        const base = 'http://127.0.0.1:8080';
        const narrow = {width: 390, height: 844};
        const assertNarrowSettings = async (target, label) => {
            const geometry = await target.evaluate(() => ({
                scrollWidth: document.documentElement.scrollWidth,
                clientWidth: document.documentElement.clientWidth,
            }));
            assert.ok(geometry.scrollWidth <= geometry.clientWidth,
                `${label} settings has no horizontal viewport overflow`);
            const optionWidth = await target.$$eval('#settings_page td[class$="_option"]', cells =>
                Math.max(...cells.map(cell => cell.getBoundingClientRect().width)));
            assert.ok(optionWidth >= 300,
                `${label} settings exposes a full-width usable option column on narrow screens`);
            await target.focus('#settings_nav a');
            const nav = await target.$eval('#settings_nav a', element => {
                const rect = element.getBoundingClientRect();
                return {left: rect.left, right: rect.right, width: rect.width};
            });
            assert.ok(nav.width > 0 && nav.left >= 0 && nav.right <= narrow.width,
                `${label} category tab remains keyboard reachable within the narrow viewport`);
        };
        const heading = async target => target.$eval('#content h1', element => element.textContent.trim());
        const save = async () => Promise.all([
            page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('#settings_save input')
        ]);
        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('[name=user]', fixture.user);
        await page.type('[name=password]', fixture.password);
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('[type=submit]')]);

        await page.setViewport(narrow);
        await page.goto(base + '/manage/settings/?cat=privacy', {waitUntil: 'networkidle0'});
        await assertNarrowSettings(page, 'authenticated');
        assert.match(await heading(page), new RegExp(`Account Settings for ${fixture.user}`, 'i'),
            'authenticated settings heading identifies the effective account');
        await page.screenshot({path: '/tmp/settings-auth-narrow.png', fullPage: true});
        const anonymousContext = await browser.createBrowserContext();
        const anonymous = await anonymousContext.newPage();
        await anonymous.setViewport(narrow);
        await anonymous.goto(base + '/manage/settings/?cat=display', {waitUntil: 'networkidle0'});
        await assertNarrowSettings(anonymous, 'anonymous');
        assert.equal(await heading(anonymous), 'Account Settings', 'anonymous settings retains the legacy heading');
        const disabledTabs = await anonymous.$$eval('#settings_nav .disabled', tabs => tabs.map(tab => ({
            tag: tab.tagName, disabled: tab.getAttribute('aria-disabled'),
        })));
        assert.ok(disabledTabs.length > 0, 'anonymous settings exposes disabled account-only categories');
        assert.ok(disabledTabs.every(tab => tab.tag !== 'A' && tab.disabled === 'true'),
            'anonymous disabled categories are non-links with disabled semantics');
        await anonymous.screenshot({path: '/tmp/settings-anon-narrow.png', fullPage: true});
        await anonymousContext.close();
        await page.setViewport({width: 1280, height: 1000});

        assert.equal(fixture.community_type, 'C', 'fixture community has community type');
        assert.equal(fixture.maintainer, 1, 'fixture maintainer relation is committed');
        await page.goto(base + `/manage/settings/?authas=${fixture.community}&cat=community`, {waitUntil: 'networkidle0'});
        assert.equal(await page.$eval('[name=authas]', element => element.value), fixture.community,
            'maintainer authas selection is retained');
        assert.doesNotMatch(await page.content(), /Invalid authorization|Invalid user/i,
            'maintainer authas request has no permission error');
        const postlevel = '[name=DW__Setting__CommunityPostLevel_communitypostlevel]';
        const moderation = '[name=DW__Setting__CommunityEntryModeration_val]';
        await page.select(postlevel, 'select');
        await page.click(moderation);
        await save();
        await page.reload({waitUntil: 'networkidle0'});
        assert.equal(await page.$eval(postlevel, element => element.value), 'select', 'community post level saves and reloads');
        assert.equal(await page.$eval(moderation, element => element.checked), true, 'community moderation saves and reloads');

        await page.goto(base + '/manage/settings/?cat=privacy', {waitUntil: 'networkidle0'});
        const messaging = '[name=LJ__Setting__UserMessaging_usermsg]';
        await page.select(messaging, 'M');
        await save();
        await page.reload({waitUntil: 'networkidle0'});
        assert.equal(await page.$eval(messaging, element => element.value), 'M', 'privacy setting saves and reloads');
        await page.select(messaging, 'N');
        const unsavedRuntime = await page.evaluate(() => ({ settings: !!window.Settings, changed: window.Settings && Settings.form_changed }));
        assert.equal(unsavedRuntime.settings, true, 'Foundation settings page loads the unsaved-change guard');
        assert.equal(unsavedRuntime.changed, true, 'changing a rendered setting marks the form dirty');
        dialogPhase = 'cancel-unsaved';
        await page.click('#settings_nav a[href*="cat=display"]');
        await page.waitForFunction(() => location.search.includes('cat=privacy'));
        dialogPhase = '';
        assert.match(page.url(), /cat=privacy/, 'cancelled unsaved navigation remains on the edited category');
        assert.equal(await page.$eval(messaging, element => element.value), 'N', 'cancelled navigation retains unsaved input');
        const serverConfirm = await page.evaluate(() => window.SettingsConfirmMsg);
        assert.equal(typeof serverConfirm, 'string', 'server emits a localized confirmation string');
        assert.notEqual(serverConfirm, '', 'server-emitted confirmation string is nonempty');
        dialogPhase = 'cancel-unsaved';
        await page.click('#settings_nav a[href*="cat=display"]');
        await page.waitForFunction(() => location.search.includes('cat=privacy'));
        dialogPhase = '';
        assert.ok(dialogs.some(value => value === `cancel-unsaved:confirm: ${serverConfirm}`),
            'browser uses the server-emitted localized Settings confirmation string without an override');

        await page.goto(base + '/manage/settings/?cat=display', {waitUntil: 'networkidle0'});
        const mobile = '[name=DW__Setting__MobileView_val]';
        const before = await page.$eval(mobile, element => element.checked);
        await page.click(mobile);
        await save();
        await page.reload({waitUntil: 'networkidle0'});
        assert.equal(await page.$eval(mobile, element => element.checked), !before, 'mobile preference saves and reloads');

        await page.goto(base + '/manage/settings/?cat=othersites', {waitUntil: 'networkidle0'});
        const xpostDisable = '[name=DW__Setting__XPostAccounts_xpostdisablecomments]';
        const xpostFooter = '[name=DW__Setting__XPostAccounts_crosspost_footer_text]';
        assert.equal(await page.$eval('#preview_section', element => getComputedStyle(element).display), 'block',
            'Other Sites footer preview initializes under Foundation resources');
        await page.click(xpostDisable);
        await page.click(xpostFooter, {clickCount: 3});
        await page.type(xpostFooter, 'browser footer compatibility');
        await save();
        await page.reload({waitUntil: 'networkidle0'});
        assert.equal(await page.$eval(xpostDisable, element => element.checked), true,
            'Other Sites disable-comments setting saves and reloads');
        assert.equal(await page.$eval(xpostFooter, element => element.value), 'browser footer compatibility',
            'Other Sites footer text saves and reloads');

        await page.goto(base + '/manage/settings/?cat=notifications', {waitUntil: 'networkidle0'});
        const inactiveButton = '[name=deleteinactive]';
        assert.ok(await page.$(inactiveButton), 'notification inactive-cleanup control renders');
        dialogPhase = 'deleteinactive';
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click(inactiveButton)]);
        dialogPhase = '';
        const verified = await new Promise((resolve, reject) => {
            let text = '';
            const timeout = setTimeout(() => reject(new Error('fixture verification timed out')), 10000);
            helper.stdout.on('data', chunk => {
                text += chunk;
                if (!text.includes('\n')) return;
                clearTimeout(timeout);
                try { resolve(JSON.parse(text.split('\n')[0])); } catch (error) { reject(error); }
            });
            helper.once('error', reject);
            helper.once('exit', () => reject(new Error('fixture exited before verification response')));
            helper.stdin.write('verify\n');
        });
        assert.equal(verified.active, 1, 'fresh fixture read retains unrelated active Inbox subscription');
        assert.equal(verified.inactive, 0, 'fresh fixture read confirms browser deleteinactive removed inactive subscription');
        assert.equal(verified.usermsg, 'M', 'cancelled unsaved privacy change is absent from fresh DB state');
        assert.equal(verified.xpost_disable_comments, '1', 'fresh fixture read confirms Other Sites checkbox persistence');
        assert.equal(verified.xpost_footer, 'browser footer compatibility', 'fresh fixture read confirms Other Sites text persistence');
        assert.deepEqual(errors, [], 'settings mutation pages have no JavaScript errors');
        assert.equal(dialogs.filter(value => value.startsWith('cancel-unsaved:')).length, 2,
            'configured unsaved-change confirmations guard tab navigation');
        assert.equal(dialogs.filter(value => value.startsWith('deleteinactive:')).length, 1, 'one inactive-cleanup confirmation');
        if (process.env.SETTINGS_BROWSER_FAIL_AFTER_SAVE) throw new Error('intentional settings cleanup probe');
        console.log('PASS disposable settings community/privacy/mobile saves and notification form');
    } finally {
        try { if (browser) await browser.close(); }
        finally { helper.stdin.end(); await done; }
    }
})().catch(error => { console.error(error); process.exit(1); });
