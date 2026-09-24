// t/browser/entry-recovery.js
//
// The subject/body recovery page, exercised as a real browser DOM: a stale
// old-editor POST to /update must land the exact submitted text in the
// textareas' .value, with any markup neutralized rather than executed.
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
const fs = require('node:fs');
const {spawn} = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const output = process.argv[2] || '/tmp/entry-recovery-browser';
    fs.mkdirSync(output, {recursive:true});
    const fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-recovery-fixture.pl'], {stdio:['pipe','pipe','inherit']});
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
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        const base = 'http://127.0.0.1:8080';
        await page.goto(base + '/mobile/login', {waitUntil:'networkidle0'});
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}), page.click('[type=submit]')]);

        // Submits a stale old-editor POST via a real <form>, so the response
        // goes through actual browser HTML parsing (textarea leading-newline
        // handling, entity decoding, script neutralization), then reads the
        // resulting DOM .value back out.
        const postAndRead = async (subject, body) => {
            await page.evaluate((subject, body) => {
                const form = document.createElement('form');
                form.method = 'post';
                form.action = '/update';
                for (const [name, value] of [['subject', subject], ['event', body]]) {
                    const input = document.createElement('input');
                    input.type = 'hidden';
                    input.name = name;
                    input.value = value;
                    form.appendChild(input);
                }
                document.body.appendChild(form);
                form.submit();
            }, subject, body);
            await page.waitForNavigation({waitUntil:'networkidle0'});
            return {
                subject: await page.$eval('#recover-subject', el => el.value),
                body: await page.$eval('#recover-body', el => el.value),
            };
        };

        const leading = await postAndRead('Leading newline subject', '\nfirst line after newline');
        assert.equal(leading.body, '\nfirst line after newline',
            'a body starting with a newline round-trips intact, past the textarea leading-newline quirk');

        const injectionMarker = '</textarea><script>window.__x=1</script>';
        const injected = await postAndRead('Injection subject', injectionMarker);
        assert.equal(injected.body, injectionMarker,
            'the closing-textarea/script sequence comes back as inert text, not markup');
        assert.equal(await page.evaluate(() => window.__x), undefined,
            'the injected script never actually executes');

        const unicode = await postAndRead('Unicode subject é', 'Unicode body é😀 done');
        assert.equal(unicode.subject, 'Unicode subject é', 'a non-astral Unicode subject round-trips');
        assert.equal(unicode.body, 'Unicode body é😀 done',
            'an astral-plane Unicode character (emoji) round-trips in the body');

        const ampersand = await postAndRead('Ampersand subject', 'literal &amp; text');
        assert.equal(ampersand.body, 'literal &amp; text',
            'a literal &amp; sequence round-trips as text, not as a decoded ampersand');

        const placeholder = await postAndRead('Enter a subject', 'placeholder body');
        assert.equal(placeholder.subject, 'Enter a subject',
            'a subject exactly equal to the old placeholder text is shown as submitted, not blanked');

        assert.deepEqual(errors, [], 'recovery page flow has no JavaScript exceptions');
        console.log('PASS: recovery page DOM values for newline/injection/Unicode/ampersand/placeholder');
    } finally {
        try { if (browser) await browser.close(); }
        finally { fixture.stdin.end(); await done; }
    }
})().catch(error => { console.error(error); process.exit(1); });
