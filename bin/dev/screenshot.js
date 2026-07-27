// bin/dev/screenshot.js
//
// Capture a full-page screenshot of a local dev-server URL with headless
// Chrome. Invoked by bin/dev/screenshot (which installs the deps and handles
// login); not normally run directly.
//
// Args: <path> <outfile> <WxH> [ljmastersession] [ljloggedin]

const puppeteer = require("/opt/dw-screenshot/node_modules/puppeteer-core");

const [, , path, outfile, size, master, loggedin] = process.argv;
const [w, h] = (size || "1280x1400").split("x").map(Number);
const BASE = "http://127.0.0.1:8080";

(async () => {
    const browser = await puppeteer.launch({
        executablePath: "/usr/bin/google-chrome-stable",
        args: ["--no-sandbox", "--disable-gpu", "--hide-scrollbars"],
        defaultViewport: { width: w, height: h },
    });
    const page = await browser.newPage();

    if (master) {
        await page.setCookie(
            { name: "ljmastersession", value: master, domain: "127.0.0.1", path: "/" },
            { name: "ljloggedin", value: loggedin || "", domain: "127.0.0.1", path: "/" }
        );
    }

    const resp = await page.goto(BASE + path, { waitUntil: "networkidle2", timeout: 30000 });
    await page.screenshot({ path: outfile, fullPage: true });
    await browser.close();
    process.stderr.write("rendered " + path + " -> HTTP " + (resp && resp.status()) + "\n");
})().catch((e) => {
    console.error(e);
    process.exit(1);
});
