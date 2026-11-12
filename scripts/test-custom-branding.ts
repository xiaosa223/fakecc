/** Real React shell + isolated Chromium. Verifies local updates, branding, language and minimum window layout. */
import {strict as assert} from 'node:assert';
import {resolve} from 'node:path';
import {mkdir,readFile} from 'node:fs/promises';
const appVersion=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8')).version;
import {createServer} from 'vite';
import {chromium} from 'playwright-core';

const server=await createServer({mode:'custom',server:{host:'127.0.0.1',port:0,strictPort:false,watch:{ignored:['**/src-tauri/**','**/browser-runtime/**','**/releases/**','**/dist/**']}},optimizeDeps:{include:['@tauri-apps/api/mocks']}});
await server.listen();
const port=(server.httpServer!.address() as {port:number}).port;
const base=`http://127.0.0.1:${port}`;
const browser=await chromium.launch({executablePath:resolve('browser-runtime/WindowsBrowser/chrome.exe'),headless:true});
const output=resolve('releases/preview');
await mkdir(output,{recursive:true});
try{
  const context=await browser.newContext({viewport:{width:1160,height:860},reducedMotion:'reduce'});
  const external:string[]=[],errors:string[]=[];
  await context.route('**/*',route=>{
    const url=route.request().url();
    if(url.startsWith(base+'/'))return route.continue();
    external.push(url);return route.abort();
  });
  const page=await context.newPage();
  page.on('pageerror',error=>errors.push(error.message));
  await page.goto(base+'/tests/branding.html');
  await page.getByText('本地定制版',{exact:true}).waitFor();
  await page.getByText(`v${appVersion} · 手动安装更新`,{exact:true}).waitFor();
  assert.equal(await page.locator('.app-brand strong').innerText(),'CCBaga');
  assert.match(decodeURIComponent(await page.locator('.app-brand img').getAttribute('src')||''),/手托.*Claude/);
  assert(await page.locator('.app-brand img').evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0));
  await page.screenshot({path:resolve(output,'home-zh.png')});
  await page.getByRole('button',{name:'打开配置向导',exact:true}).click();
  await page.getByRole('status').filter({hasText:'已打开独立终端'}).waitFor();
  await page.getByRole('button',{name:'复制 setup-token 命令',exact:true}).click();
  let events=await page.evaluate(()=>(window as any).brandingFixture.events);
  assert(events.some((event:any)=>event.command==='terminal_setup_open'&&event.args.action==='configure'));
  assert(events.some((event:any)=>event.command==='copy_result'&&event.args.text==='claude setup-token'));
  await page.getByRole('button',{name:'启动 Claude Code',exact:true}).click();
  await page.getByRole('button',{name:'检查环境',exact:true}).click();
  events=await page.evaluate(()=>(window as any).brandingFixture.events);
  assert.deepEqual(events.filter((event:any)=>event.command==='terminal_setup_open').map((event:any)=>event.args.action),['configure','launch','doctor']);
  await page.getByRole('button',{name:'网络与资源',exact:true}).click();
  await page.getByRole('heading',{name:'连接，准备就绪。',exact:true}).waitFor();
  assert.equal(await page.locator('.resource-card').count(),4);
  assert.match(await page.locator('#skill-prompt').inputValue(),/xiaosa223\/claude-code-setup/);
  for(const button of await page.locator('.resource-visit').all())await button.click();
  events=await page.evaluate(()=>(window as any).brandingFixture.events);
  assert.deepEqual(events.filter((event:any)=>event.command==='network_open_resource').map((event:any)=>event.args.provider),['dmit','webshare','recharge','relay']);
  await page.screenshot({path:resolve(output,'network-zh.png')});
  await page.getByRole('button',{name:'EN',exact:true}).click();
  await page.getByText('Local edition',{exact:true}).waitFor();
  await page.screenshot({path:resolve(output,'network-en.png')});
  await page.setViewportSize({width:760,height:640});
  await page.getByRole('button',{name:'中文',exact:true}).click();
  await page.getByRole('button',{name:'开始配置',exact:true}).click();
  await page.getByRole('heading',{name:'一条清楚的开始路线',exact:true}).waitFor();
  assert(await page.locator('.workspace').evaluate(element=>element.getBoundingClientRect().right<=innerWidth));
  await page.screenshot({path:resolve(output,'home-minimum.png')});
  assert.deepEqual(external,[]);
  assert.deepEqual(errors,[]);
  const commands=await page.evaluate(()=>(window as any).brandingFixture.commands as string[]);
  assert(!commands.some(command=>command.startsWith('plugin:updater|')));
  console.log(JSON.stringify({status:'passed',externalRequests:external,unexpectedPageErrors:errors,updaterCalls:0,screenshots:output,commands},null,2));
} finally {
  await browser.close();await server.close();
}
