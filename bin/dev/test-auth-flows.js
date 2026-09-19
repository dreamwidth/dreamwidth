// bin/dev/test-auth-flows.js
//
// Browser regression checks and screenshots for login and comment identities.
// Run inside a devcontainer after bin/dev/screenshot has installed Chrome.
//
// Authors:
//      Mark Smith <mark@dreamwidth.org>
//
// Copyright (c) 2026 by Dreamwidth Studios, LLC.
//
// This program is free software; you may redistribute it and/or modify it under
// the same terms as Perl itself. For a copy of the license, please reference
// 'perldoc perlartistic' or 'perldoc perlgpl'.

const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
const { execFileSync } = require('child_process');
const fs = require('fs');
const assert = require('assert/strict');
if (process.env.LJ_IS_DEV_SERVER !== '1') throw new Error('Devcontainer only');
const base = 'http://127.0.0.1:8080';
const out = process.argv[2] || '/tmp/dw-mfa-review';
fs.mkdirSync(out, { recursive: true });
function perl(code, ...args) {
    return execFileSync('perl', ['-e', 'require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; ' + code, ...args], { encoding: 'utf8' }).trim();
}
const fixture = JSON.parse(perl(`
    die 'Dev only' unless $LJ::IS_DEV_SERVER;
    require LJ::Test;
    my %ids;
    for my $name (qw(mfa_reader mfa_bob mfa_mary)) {
        my $u = LJ::load_user($name) || LJ::User->create_personal(
            user => $name, name => $name, email => "$name\\@example.com", password => 'dreamwidth');
        $u->update_self({status => 'A', statusvis => 'V'});
        $u->set_password('dreamwidth');
        $u->set_prop('schemepref', 'tropo');
        $u->kill_all_sessions;
        my $dbh = LJ::get_db_writer();
        $dbh->do('UPDATE password2 SET totp_secret = NULL WHERE userid = ?', undef, $u->id);
        $ids{$name} = $u->id;
    }
    my $u = LJ::load_user('mfa_reader');
    my $entry = $u->t_post_fake_entry(subject => 'A place for Bob and Mary',
        body => 'Development demonstration of posting as another signed-in account.<!-- ' . time() . ' -->', security => 'public');
    $ids{ditemid} = $entry->ditemid;
    print LJ::JSON::to_json(\\%ids);
`));
function code(secret) {
    return perl('require Authen::OATH; require Convert::Base32; print Authen::OATH->new->totp(Convert::Base32::decode_base32($ARGV[0]));', secret);
}
(async () => {
    const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome-stable',
        args: ['--no-sandbox', '--disable-gpu'], defaultViewport: { width: 1280, height: 1000 } });
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    async function goto(path) {
        const response = await page.goto(path.startsWith('http') ? path : base + path, { waitUntil: 'networkidle2' });
        assert(response.status() < 400, 'Page failed: ' + path + ' ' + response.status());
    }
    async function click(selector) {
        await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle2' }), page.click(selector)]);
    }
    async function shot(name) {
        await page.screenshot({ path: out + '/' + name + '.png', fullPage: true });
        console.log('Screenshot: ' + name);
    }
    async function login(user, path = '/login') {
        await goto(path);
        const form = '#protected_login form';
        await page.type(form + ' input[name=user]', user);
        await page.type(form + ' input[name=password]', 'dreamwidth');
        await click(form + ' input[type=submit]');
    }
    async function master() { return (await page.cookies()).find(c => c.name === 'ljmastersession')?.value; }
    try {
        await login('mfa_bob');
        assert(await master(), 'Password login establishes a session');
        await goto('/manage2fa');
        await shot('01-settings-disabled');
        await click('input[name="action:setup"]');
        const secret = await page.$eval('input[name=totp_secret]', el => el.value);
        await shot('02-setup');
        await page.type('input[name=verification_code]', code(secret));
        await page.type('input[name=password]', 'dreamwidth');
        await click('input[name="action:enable"]');
        const recovery = await page.$$eval('code', nodes => nodes.map(n => n.textContent.trim()).filter(s => /^[a-z0-9]{4}-[a-z0-9]{4}$/.test(s)));
        assert.equal(recovery.length, 10, 'Enrollment returns ten recovery codes');
        assert(!(await master()), 'Enrollment revokes browser sessions');
        await shot('03-recovery-codes');
        await login('mfa_bob');
        assert(page.url().endsWith('/login/2fa'), 'Password redirects to MFA');
        assert(!(await master()), 'No session before second factor');
        await shot('04-login-challenge');
        await page.type('#mfa_code', 'not-a-code');
        await click('input[type=submit].button');
        assert(!(await master()), 'Wrong code does not establish session');
        await page.$eval('#mfa_code', el => el.value = '');
        await page.type('#mfa_code', recovery[0]);
        await click('input[type=submit].button');
        assert(await master(), 'Recovery code completes login');
        await goto('/manage2fa');
        await shot('05-settings-enabled');
        await click('input[name="action:disable"]');
        await shot('06-disable');
        await page.deleteCookie(...await page.cookies());
        await login('mfa_reader');
        const browsing = await master();
        const reply = '/~mfa_reader/' + fixture.ditemid + '.html?mode=reply';
        await goto(reply);
        await page.type('textarea[name=body]', 'Bob arrives at the gathering.');
        await click('.comment-add-account');
        await shot('07-add-comment-account');
        await page.type('#protected_login input[name=user]', 'mfa_bob');
        await page.type('#protected_login input[name=password]', 'dreamwidth');
        await click('#protected_login input[type=submit]');
        assert(page.url().endsWith('/login/2fa'), 'Adding MFA account requires factor');
        await page.type('#mfa_code', code(secret));
        await click('input[type=submit].button');
        assert.equal(await master(), browsing, 'Adding comment account preserves browsing session');
        assert.equal(await page.$eval('textarea[name=body]', el => el.value), 'Bob arrives at the gathering.', 'Comment draft survives login');
        assert.equal(await page.$eval('#posting_userid', el => el.value), String(fixture.mfa_bob), 'New account selected for comment');
        await shot('08-comment-post-as');
        await page.type('textarea[name=body]', '\n<!-- Browser test ' + fixture.ditemid + ' -->');
        await click('#submitpost');
        assert.equal(await master(), browsing, 'Posting as Bob preserves browsing session');
        const comment = perl(`require LJ::Comment; my $u = LJ::load_user('mfa_reader');
            my ($poster) = $u->selectrow_array('SELECT posterid FROM talk2 WHERE journalid = ? ORDER BY jtalkid DESC LIMIT 1', undef, $u->id);
            print $poster;`);
        assert.equal(comment, String(fixture.mfa_bob), 'Comment attributed to Bob');
        await login('mfa_mary', '/login?store_only=1&returnto=' + encodeURIComponent(reply));
        assert.equal(await master(), browsing, 'Adding Mary does not change browsing identity');
        await goto('/~mfa_reader/' + fixture.ditemid + '.html');
        assert(await page.$('#qr-posting-account'), 'Quick Reply has account selector');
        await page.evaluate(() => document.querySelector('#qrdiv').style.display = 'block');
        await page.select('#qr-posting-account', String(fixture.mfa_mary));
        await page.type('#qrform textarea[name=body]', 'Mary follows Bob into the room.');
        await shot('09-quick-reply');
        const quickResponse = page.waitForResponse(r => r.url().includes('/talkpost_do') && r.request().method() === 'POST');
        await page.type('#qrform textarea[name=body]', '\n<!-- Browser test ' + fixture.ditemid + ' -->');
        await page.click('#qrform #submitpost');
        await quickResponse;
        assert.equal(perl(`my $u = LJ::load_user('mfa_reader'); my ($poster) = $u->selectrow_array('SELECT posterid FROM talk2 WHERE journalid = ? ORDER BY jtalkid DESC LIMIT 1', undef, $u->id); print $poster;`), String(fixture.mfa_mary), 'Quick Reply attributed to Mary');
        assert.equal(await master(), browsing, 'Quick Reply preserves browsing identity');

        await goto('/entry/new');
        await shot('10-entry-editor');
        assert.equal(await page.$$eval('input[type=password]', els => els.filter(e => e.name === 'password' && !e.closest('.lj_login_form')).length), 0, 'Entry editor has no inline login');
        const accountsResult = await page.evaluate(async () => {
            const token = document.querySelector('[name=lj_form_auth]').value;
            const valid = await fetch('/rpc/comment-accounts', { method: 'POST', body: new URLSearchParams({lj_form_auth: token}) });
            const invalid = await fetch('/rpc/comment-accounts', { method: 'POST', body: new URLSearchParams({lj_form_auth: 'bad'}) });
            return { accounts: await valid.json(), invalidStatus: invalid.status };
        });
        assert.equal(accountsResult.accounts.accounts.length, 2, 'Account endpoint returns stored identities');
        assert.equal(accountsResult.invalidStatus, 403, 'Account endpoint requires CSRF token');
        const apiKey = perl("require DW::API::Key; print DW::API::Key->get_one(LJ::load_user('mfa_reader'))->hash;");
        // Use the HTTP client so a 401 does not open Chrome's native auth dialog.
        const readFeed = credential => fetch(base + '/~mfa_reader/data/rss?auth=digest', {
            headers: {Authorization: 'Basic ' + Buffer.from('mfa_reader:' + credential).toString('base64')},
            signal: AbortSignal.timeout(15000)
        });
        const feedAuth = [(await readFeed('dreamwidth')).status, (await readFeed(apiKey)).status];
        assert.deepEqual(feedAuth, [401, 200], 'RSS requires an API key instead of the password');
        const oldToken = await page.$eval('#js-post-entry [name=lj_form_auth]', el => el.value);
        await page.evaluate(async ({token, userid}) => {
            await fetch('/switchaccount', {method:'POST', body: new URLSearchParams({lj_form_auth:token, userid})});
        }, {token:oldToken, userid:fixture.mfa_mary});
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle2'}), page.evaluate(token => {
            const form = document.createElement('form');
            form.method = 'POST'; form.action = '/entry/new';
            for (const [name, value] of Object.entries({lj_form_auth:token, poster_remote:'mfa_reader', event:'Keep this draft with the original account.', 'action:post':'1'})) {
                const input = document.createElement('input'); input.name=name; input.value=value; form.appendChild(input);
            }
            document.body.appendChild(form); form.submit();
        }, oldToken)]);
        assert((await page.content()).includes('Your active account changed'), 'Changed entry identity rejected');
        assert.equal(await page.$eval('[name=event]', el => el.value), 'Keep this draft with the original account.', 'Entry draft preserved after account change');
        assert.equal(await page.$eval('[name=poster_remote]', el => el.value), 'mfa_reader', 'Original entry identity retained on retry');
        await shot('13-entry-account-changed');
        await goto('/changepassword');
        await shot('12-password-change');
        await page.setViewport({ width: 390, height: 844 });
        await goto('/login?store_only=1');
        await shot('11-mobile-login');
        assert.equal(errors.length, 0, 'No browser JavaScript errors: ' + errors.join('; '));
        console.log('PASS: enrollment, MFA, recovery, comment draft round trip, stored account posting, Quick Reply, entry editor');
    } catch (error) {
        await page.screenshot({ path: out + '/failure.png', fullPage: true });
        fs.writeFileSync(out + '/failure.html', await page.content());
        throw error;
    } finally {
        await browser.close();
    }
})().catch(error => { console.error(error); process.exit(1); });
