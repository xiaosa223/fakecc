/**
 * [INPUT]: 手托 Claude 矢量图、Landing 侧栏、Cromma UI、共享 YAML、身份/浏览器/系统页面、网络入口与按构建模式区分的更新组件。
 * [OUTPUT]: CCBaga 终端工作空间；首页为 setup-token 配置路线，资源/帮助前置，身份/浏览器/系统与快捷操作归高级工具。
 * [POS]: 单窗口编排层；任务运行时锁定导航，完成后重新挂载高级页面以刷新快照。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import { Panel, NavButton, MotionRoot, TooltipProvider } from 'cromma-ui';
import { ShieldCheck as IdentityIcon, HomeDefault as HomeIcon, WindowBrowser as BrowserIcon, Settings01 as SettingsIcon, Share01 as NetworkIcon, FolderDefault as HelpIcon } from 'cromma-ui/pika';
import { Fragment, useState } from 'react';
import {useI18n} from "./i18n";
import { createRoot } from 'react-dom/client';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { IdentityPanel } from './identities';
import { BrowserPanel } from './browser';
import { SystemPanel } from './system';
import { useQuickActions } from './quick-actions';
import { VpsPanel } from './vps';
import { LanguageSwitch } from './language-switch';
import { AppUpdate } from './app-update';
import { HelpPanel } from './help';
import { TerminalSetupPanel } from './terminal-setup';
import appLogo from '../assets/claude-in-hand.svg';
import './index.css';
import './style.css';
type Page = 'quick' | 'tools' | 'cleaner' | 'browser' | 'system' | 'vps' | 'help';
const titles: Record<Page, string> = { quick: '开始配置', tools: '快捷工具', cleaner: 'Claude 身份管理', browser: '浏览器环境', system: '电脑环境', vps: '网络与资源', help: '使用说明' };
const icons: Record<Page, typeof HomeIcon> = { quick: HomeIcon, tools: SettingsIcon, cleaner: IdentityIcon, browser: BrowserIcon, system: SettingsIcon, vps: NetworkIcon, help: HelpIcon };
function App() {
    const {t}=useI18n();
    const [emptyRequested,setEmptyRequested]=useState(false);
    const [page, setPage] = useState<Page>('quick'), [revision, setRevision] = useState(0), [advancedBusy, setAdvancedBusy] = useState(false), [updateBusy, setUpdateBusy] = useState(false);
    const quick = useQuickActions(() => setPage('tools'), () => setRevision(v => v + 1),()=>{setEmptyRequested(true);setRevision(v=>v+1);setPage("cleaner");});
    const locked = quick.busy || advancedBusy || updateBusy;
    return <><div className="drag-strip studio-topbar" onMouseDown={e => { if (e.button === 0)
        void getCurrentWindow().startDragging(); }}><span>CCBAGA STUDIO</span><span>{t('本地工作空间')}</span></div><div className="app-shell studio-shell"><aside className="app-sidebar">
    <div className="app-brand"><img src={appLogo} width={52} height={52} alt="" draggable={false}/><div><strong>CCBaga</strong><small>CLAUDE CODE COMPANION</small></div></div>
    <nav aria-label={t("主要页面")}>{(['quick', 'vps', 'help', 'tools', 'cleaner', 'browser', 'system'] as const).map(p => { const Icon = icons[p]; return <Fragment key={p}>{p==='quick'&&<span className="nav-label">{t('工作空间')}</span>}{p==='tools'&&<span className="nav-label advanced-label">{t('高级工具')}</span>}<NavButton className="workspace-nav" active={page === p} aria-current={page === p ? "page" : undefined} disabled={locked} icon={<Icon size={18} aria-hidden="true"/>} onClick={() => {setEmptyRequested(false);setPage(p);}}>{t(titles[p])}</NavButton></Fragment>; })}</nav>
    <div className="sidebar-bottom"><p className="sidebar-note">{t('配置在本机，工作在终端。')}</p><AppUpdate blocked={quick.busy || advancedBusy} onBusy={setUpdateBusy}/><LanguageSwitch /></div>
  </aside><Panel frame className="workspace" inert={updateBusy}>{page==='quick'&&<TerminalSetupPanel onResources={()=>setPage('vps')}/>}<fieldset disabled={advancedBusy} className={`cleaner-slot quick-fieldset ${page !== 'tools' ? 'page-hidden' : ''}`}>{quick.content}</fieldset>
    {page === 'cleaner' && <div className="cleaner-slot"><IdentityPanel key={revision} initialEmpty={emptyRequested} onBusy={setAdvancedBusy}/></div>}{page === 'browser' && <div className="cleaner-slot"><BrowserPanel key={revision} onBusy={setAdvancedBusy}/></div>}{page === 'system' && <div className="cleaner-slot"><SystemPanel key={revision} onBusy={setAdvancedBusy}/></div>}{page === 'vps' && <div className="cleaner-slot"><VpsPanel/></div>}{page === 'help' && <div className="cleaner-slot"><HelpPanel/></div>}
  </Panel></div></>;
}
createRoot(document.getElementById('app')!).render(<MotionRoot><TooltipProvider delayDuration={600} skipDelayDuration={300}><App /></TooltipProvider></MotionRoot>);
