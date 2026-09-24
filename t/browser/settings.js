// The Settings page's two confirmation dialogs, both JS-only: the
// unsaved-changes guard on tab navigation, and the destructive
// delete-inactive-subscriptions confirm.
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
        await page.goto(base + '/mobile/login', {waitUntil: 'networkidle0'});
        await page.type('[name=user]', fixture.user);
        await page.type('[name=password]', fixture.password);
        await Promise.all([page.waitForNavigation({waitUntil: 'networkidle0'}), page.click('[type=submit]')]);

        await page.goto(base + '/manage/settings/?cat=privacy', {waitUntil: 'networkidle0'});
        const messaging = '[name=LJ__Setting__UserMessaging_usermsg]';
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
        assert.ok(dialogs.some(value => value === `cancel-unsaved:confirm: ${serverConfirm}`),
            'browser uses the server-emitted localized Settings confirmation string without an override');

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
        assert.notEqual(verified.usermsg, 'N', 'cancelled unsaved privacy change never reached the database');

        assert.deepEqual(errors, [], 'settings dialogs have no JavaScript errors');
        assert.equal(dialogs.filter(value => value.startsWith('cancel-unsaved:')).length, 1,
            'the unsaved-change confirmation guards tab navigation');
        assert.equal(dialogs.filter(value => value.startsWith('deleteinactive:')).length, 1, 'one inactive-cleanup confirmation');
        console.log('PASS: unsaved-changes confirm and destructive delete-inactive confirm');
    } finally {
        try { if (browser) await browser.close(); }
        finally { helper.stdin.end(); await done; }
    }
})().catch(error => { console.error(error); process.exit(1); });
