/** Isolated real app shell; no native operations, credentials or external navigation. */
import {mockIPC} from '@tauri-apps/api/mocks';
import metadata from '../package.json';
const commands:string[]=[];
const events:{command:string;args:unknown}[]=[];
Object.assign(window,{brandingFixture:{commands,events}});
mockIPC((command,args)=>{
  commands.push(command);
  events.push({command,args});
  if(command==='plugin:app|version')return metadata.version;
  if(command==='ui_language_read')return 'zh';
  if(command==='ui_language_write')return;
  if(command==='terminal_setup_open'||command==='network_open_resource'||command==='copy_result')return;
  if(command==='get_regions')return [{id:'us-west',label:'美国西部',language:'en-US',locale:'en-US',timezone:'America/Los_Angeles'}];
  throw new Error(`Unexpected branding fixture command: ${command}`);
});
await import('../src/main');
