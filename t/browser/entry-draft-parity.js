// Browser parity checks for legacy saved drafts without an editor property.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

function readLine(stream, process, label) {
    return new Promise((resolve, reject) => {
        let buffer = '';
        const onData = (chunk) => {
            buffer += chunk;
            const newline = buffer.indexOf('\n');
            if (newline < 0) return;
            stream.off('data', onData);
            try {
                resolve(JSON.parse(buffer.slice(0, newline)));
            } catch (error) {
                reject(error);
            }
        };
        stream.on('data', onData);
        process.once('exit', (code, signal) => reject(Error(`${label} exited: ${code}/${signal}`)));
        process.once('error', reject);
    });
}

(async () => {
    let fixture;
    let fixtureDone;
    let browser;
    const base = 'http://127.0.0.1:8080';
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-draft-parity-fixture.pl'], {
            stdio: ['pipe', 'pipe', 'inherit'],
        });
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => code === 0 ? resolve() : reject(Error(`fixture ${code}/${signal}`)));
            fixture.once('error', reject);
        });
        fixtureDone.catch(() => {});
        const data = await readLine(fixture.stdout, fixture, 'fixture startup');
        browser = await puppeteer.launch({
            executablePath: '/usr/bin/google-chrome-stable',
            args: ['--no-sandbox'],
        });

        const visit = async (account, accept) => {
            const page = await browser.newPage();
            const dialogs = [];
            page.on('dialog', async (dialog) => {
                dialogs.push(`${dialog.type()}: ${dialog.message()}`);
                if (accept) await dialog.accept();
                else await dialog.dismiss();
            });
            await page.goto(base + '/mobile/login', { waitUntil: 'networkidle0' });
            await page.type('[name=user]', account.user);
            await page.type('[name=password]', account.password);
            await Promise.all([
                page.waitForNavigation({ waitUntil: 'networkidle0' }),
                page.click('[type=submit]'),
            ]);
            await page.goto(base + '/entry/new', { waitUntil: 'networkidle0' });
            return { page, dialogs };
        };

        const preload = await browser.newPage();
        preload.on('dialog', dialog => dialog.accept());
        await preload.goto(base + '/mobile/login', { waitUntil: 'networkidle0' });
        await preload.type('[name=user]', data.preload.user);
        await preload.type('[name=password]', data.preload.password);
        await Promise.all([preload.waitForNavigation({ waitUntil: 'networkidle0' }), preload.click('[type=submit]')]);
        let heldRequest;
        const held = new Promise(resolve => preload.on('request', request => {
            if (request.url().includes('/__draft_preload_delay.gif')) { heldRequest = request; resolve(); }
            else request.continue();
        }));
        await preload.setRequestInterception(true);
        await preload.evaluateOnNewDocument(() => document.addEventListener('DOMContentLoaded', () => {
            const image = document.createElement('img'); image.hidden = true; image.src = '/__draft_preload_delay.gif'; document.body.appendChild(image);
        }));
        await preload.goto(base + '/entry/new', { waitUntil: 'domcontentloaded' });
        await held;
        await preload.$eval('#id-subject-0', element => { element.value = ''; });
        await preload.type('#id-subject-0', 'Typed before window load');
        await preload.keyboard.press('Tab');
        await preload.$eval('#entry-body', element => { element.value = ''; });
        await preload.type('#entry-body', 'Body typed before window load');
        await heldRequest.respond({ status: 200, contentType: 'image/gif', body: Buffer.from('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==', 'base64') });
        await preload.waitForFunction(async () => {
            const draft = await (await fetch('/__rpc_draft')).json();
            const props = await (await fetch('/__rpc_draft?getProperties=1')).json();
            return draft.draft === 'Body typed before window load' && props.subject === 'Typed before window load';
        });
        await preload.close();

        const accepted = await visit(data.accept, true);
        await accepted.page.waitForFunction(() => document.querySelector('#editor')?.value === 'markdown0');
        assert.deepEqual(accepted.dialogs, ['confirm: Restore from saved draft entitled Legacy accept subject?'],
            'legacy draft acceptance asks exactly one restoration confirmation');
        assert.equal(await accepted.page.$eval('#id-subject-0', element => element.value), data.accept.subject,
            'accept restores the saved subject');
        assert.equal(await accepted.page.$eval('#entry-body', element => element.value), data.accept.body,
            'accept restores exact legacy Markdown body bytes');
        assert.equal(await accepted.page.$eval('#editor', element => element.value), 'markdown0',
            'missing saved editor preserves the preferred Markdown selection');
        const acceptSaved = await accepted.page.evaluate(async () => ({
            draft: (await (await fetch('/__rpc_draft')).json()).draft,
            properties: await (await fetch('/__rpc_draft?getProperties=1')).json(),
        }));
        assert.deepEqual(acceptSaved, { draft: data.accept.body, properties: data.accept.props },
            'accept leaves all legacy saved draft fields exact through the draft RPC');
        if (process.env.DRAFT_PARITY_INTENTIONAL_FAIL) {
            throw Error('intentional draft parity cleanup probe');
        }
        await accepted.page.$eval('#id-subject-0', element => { element.value = ''; });
        await accepted.page.type('#id-subject-0', 'Accepted user edit');
        await accepted.page.$eval('#id-subject-0', element => element.blur());
        await accepted.page.select('#prop_picture_keyword', 'draft-parity-icon');
        await accepted.page.$eval('#entry-body', element => { element.value = ''; });
        await accepted.page.type('#entry-body', 'Accepted body edit');
        await accepted.page.waitForFunction(async () => {
            const draft = await (await fetch('/__rpc_draft')).json();
            const props = await (await fetch('/__rpc_draft?getProperties=1')).json();
            return draft.draft === 'Accepted body edit'
                && props.subject === 'Accepted user edit'
                && props.userpic === 'draft-parity-icon';
        });
        await accepted.page.focus('#id-subject-0');
        await accepted.page.keyboard.down('Control');
        await accepted.page.keyboard.press('KeyA');
        await accepted.page.keyboard.up('Control');
        await accepted.page.type('#id-subject-0', data.accept.subject);
        await accepted.page.keyboard.press('Tab');
        await accepted.page.$eval('#entry-body', element => { element.value = ''; });
        await accepted.page.type('#entry-body', 'Accepted body-only revert check');
        await accepted.page.waitForFunction(async (subject) => {
            const draft = await (await fetch('/__rpc_draft')).json();
            const props = await (await fetch('/__rpc_draft?getProperties=1')).json();
            return draft.draft === 'Accepted body-only revert check' && props.subject === subject;
        }, {}, data.accept.subject);
        await accepted.page.close();

        const declined = await visit(data.decline, false);
        await declined.page.waitForFunction(async () => {
            const draft = await (await fetch('/__rpc_draft')).json();
            const props = await (await fetch('/__rpc_draft?getProperties=1')).json();
            return draft.draft === '' && Object.keys(props).length === 0;
        });
        assert.deepEqual(declined.dialogs, ['confirm: Restore from saved draft entitled Legacy decline subject?'],
            'decline asks exactly one restoration confirmation');
        assert.equal(await declined.page.$eval('#id-subject-0', element => element.value), '',
            'decline leaves the entry subject blank');
        assert.equal(await declined.page.$eval('#entry-body', element => element.value), '',
            'decline clears the entry body');
        await declined.page.reload({ waitUntil: 'networkidle0' });
        const declineSaved = await declined.page.evaluate(async () => ({
            draft: (await (await fetch('/__rpc_draft')).json()).draft,
            properties: await (await fetch('/__rpc_draft?getProperties=1')).json(),
        }));
        assert.deepEqual(declineSaved, { draft: '', properties: {} },
            'decline clears the body and every saved draft property through a fresh RPC');
        await declined.page.focus('#id-subject-0');
        await declined.page.type('#id-subject-0', 'Declined user edit');
        await declined.page.$eval('#id-subject-0', element => element.blur());
        await declined.page.select('#prop_picture_keyword', 'draft-parity-icon');
        await declined.page.type('#entry-body', 'Declined body edit');
        await declined.page.waitForFunction(async () => {
            const draft = await (await fetch('/__rpc_draft')).json();
            const props = await (await fetch('/__rpc_draft?getProperties=1')).json();
            return draft.draft === 'Declined body edit'
                && props.subject === 'Declined user edit'
                && props.userpic === 'draft-parity-icon';
        });
        await declined.page.close();
        console.log('PASS: legacy saved-draft accept preserves preferred mode and decline clears exact state');
    } finally {
        try {
            if (browser) await browser.close();
        } finally {
            if (fixture) {
                fixture.stdin.end();
                await fixtureDone;
            }
        }
    }
})().catch((error) => {
    console.error(error);
    process.exit(1);
});
