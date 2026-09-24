// Browser accessibility baseline for entry display-date controls.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { spawn } = require('node:child_process');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');

async function readFixture(fixture) {
    return new Promise((resolve, reject) => {
        let buffer = '';
        fixture.stdout.on('data', (chunk) => {
            buffer += chunk;
            const newline = buffer.indexOf('\n');
            if (newline < 0) return;
            try {
                resolve(JSON.parse(buffer.slice(0, newline)));
            } catch (error) {
                reject(error);
            }
        });
        fixture.once('exit', (code, signal) => reject(Error(`fixture startup ${code}/${signal}`)));
    });
}

(async () => {
    let fixture;
    let browser;
    let fixtureDone;
    try {
        fixture = spawn('perl', [process.env.LJHOME + '/t/browser/entry-displaydate-fixture.pl'], {
            stdio: ['pipe', 'pipe', 'inherit'],
        });
        fixtureDone = new Promise((resolve, reject) => {
            fixture.once('exit', (code, signal) => {
                if (code === 0) resolve();
                else reject(Error(`fixture ${code}/${signal}`));
            });
            fixture.once('error', reject);
        });
        fixtureDone.catch(() => {});
        const data = await readFixture(fixture);
        browser = await puppeteer.launch({
            executablePath: '/usr/bin/google-chrome-stable',
            args: ['--no-sandbox'],
        });
        const page = await browser.newPage();
        await page.goto('http://127.0.0.1:8080/mobile/login', { waitUntil: 'networkidle0' });
        await page.type('[name=user]', data.user);
        await page.type('[name=password]', data.password);
        await Promise.all([
            page.waitForNavigation({ waitUntil: 'networkidle0' }),
            page.click('[type=submit]'),
        ]);
        const output = process.argv[2] || '/tmp/entry-displaydate-browser';
        fs.mkdirSync(output, { recursive: true });
        for (const [name, width] of [['desktop', 1280], ['narrow', 375]]) {
            await page.setViewport({ width, height: 800 });
            await page.goto(`http://127.0.0.1:8080/entry/${data.user}/${data.ditemid}/edit`, {
                waitUntil: 'networkidle0',
            });
            for (const [id, label] of [['js-entrytime-date', 'Date'], ['js-entrytime-time', 'Time']]) {
                const got = await page.$eval('#' + id, (element) => element.labels?.[0]?.textContent.trim());
                assert.equal(got, label, `${name} ${id} has accessible ${label} label`);
                await page.$eval('#' + id, (element) => element.scrollIntoView({ block: 'center' }));
                await page.waitForFunction((inputId) => {
                    const element = document.getElementById(inputId);
                    const rect = element?.getBoundingClientRect();
                    return rect && getComputedStyle(element).display !== 'none' && rect.width > 0
                        && rect.height > 0 && rect.bottom > 0 && rect.top < innerHeight;
                }, {}, id);
            }
            await page.screenshot({ path: `${output}/${name}.png`, fullPage: true });
        }
        console.log('PASS: desktop and narrow visible display-date inputs retain accessible names');
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
