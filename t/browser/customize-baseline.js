// Capture customization states before migrating the page/widget resource layer.
// Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const puppeteer = require('/opt/dw-screenshot/node_modules/puppeteer-core');
(async () => {
    const browser = await puppeteer.launch({executablePath:'/usr/bin/google-chrome-stable',args:['--no-sandbox']});
    try {
        const page = await browser.newPage();
        await page.setViewport({width:1280,height:900});
        let errors = [];
        page.on('pageerror', e => errors.push(e.message));
        const base = 'http://127.0.0.1:8080';
        const output = process.argv[2] || '/tmp/customize-baseline';
        fs.mkdirSync(output,{recursive:true});
        await page.goto(base + '/mobile/login',{waitUntil:'networkidle0'});
        await page.type('[name=user]','test_user');
        await page.type('[name=password]','dreamwidth');
        await Promise.all([page.waitForNavigation({waitUntil:'networkidle0'}),page.click('[type=submit]')]);
        const states = [['themes','/customize/?cat=all'], ['community','/customize/?authas=test_comm']];
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
            results.push({name,path,errors:[...errors],widgets:await page.$$eval('[class*=appwidget]', els=>els.map(e=>e.id).filter(Boolean))});
        }
        fs.writeFileSync(output+'/results.json',JSON.stringify(results,null,2));
        console.log(JSON.stringify(results,null,2));
    } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
