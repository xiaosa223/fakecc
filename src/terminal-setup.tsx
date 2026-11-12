/**
 * [INPUT]: 官方 setup-token 命令、原生固定终端入口与双语目录。
 * [OUTPUT]: 终端 Claude Code 的配置路线；用户主动打开向导/启动/检查，token 不进入 WebView。
 * [POS]: 首页只编排建议路线，已有高级工具保留；脚本执行和凭据保护在原生终端。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import {useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
import {useI18n} from './i18n';

export function TerminalSetupPanel({onResources}:{onResources:()=>void}){
  const {t}=useI18n();
  const [opening,setOpening]=useState(''),[feedback,setFeedback]=useState(''),[error,setError]=useState(''),[copied,setCopied]=useState(false);
  async function launch(action:'configure'|'launch'|'doctor'){
    if(opening)return;
    setOpening(action);setError('');setFeedback('');
    try{await invoke('terminal_setup_open',{action});setFeedback(t('已打开独立终端，请在终端中继续。'));}
    catch(e){setError(String(e));}finally{setOpening('');}
  }
  async function copy(){
    setError('');try{await invoke('copy_result',{text:'claude setup-token'});setCopied(true);}catch(e){setError(String(e));}
  }
  return <section className="terminal-page">
    <header className="page-topline"><span>WORKSPACE / CLAUDE CODE</span><span className="local-status"><i/>{t('本机配置')}</span></header>
    <div className="terminal-hero">
      <div className="hero-copy"><div className="editorial-label">THE TERMINAL, FIRST.</div><h1>{t('从终端，')}<br/><em>{t('开始你的 Claude。')}</em></h1><p>{t('准备网络，完成官方授权，把配置留在自己的电脑上。')}</p>
        <div className="hero-actions"><button className="studio-button primary" disabled={!!opening} onClick={()=>void launch('configure')}>{opening==='configure'?t('正在打开'):t('打开配置向导')}<span aria-hidden="true">↗</span></button><button className="studio-button quiet" onClick={onResources}>{t('查看网络与资源')}<span aria-hidden="true">→</span></button></div>
      </div>
      <div className="terminal-preview" aria-label={t('终端命令示意')}><div className="terminal-window-bar"><div><i/><i/><i/></div><span>PowerShell</span><span>01</span></div><div className="terminal-code"><span className="terminal-comment"># {t('在本机完成官方授权')}</span><div><b>›</b> claude setup-token</div><span className="terminal-comment"># {t('配置完成后进入项目')}</span><div><b>›</b> claude</div><div className="terminal-cursor" aria-hidden="true">▍</div></div><div className="terminal-caption"><span>CLAUDE CODE</span><span>{t('官方客户端 · 本机运行')}</span></div></div>
    </div>
    <div className="section-heading"><h2>{t('一条清楚的开始路线')}</h2><span>01 — 03</span></div>
    <ol className="setup-route">
      <li><span className="route-number">01</span><div><h3>{t('准备可用网络')}</h3><p>{t('使用已有线路，或让自有 Skill 协助部署 VPS。购买服务不是配置前提。')}</p></div><span className="route-marker" aria-hidden="true">↗</span></li>
      <li><span className="route-number">02</span><div><h3>{t('获取长期 token')}</h3><p>{t('运行官方命令，按授权页面指引完成。需要有效的 Claude 订阅。')}</p><button className="inline-command" onClick={()=>void copy()} aria-label={t('复制 setup-token 命令')}><code>claude setup-token</code><span>{copied?t('已复制'):t('复制命令')}</span></button></div><span className="route-marker" aria-hidden="true">↗</span></li>
      <li><span className="route-number">03</span><div><h3>{t('保存配置，进入项目')}</h3><p>{t('在向导终端中安全输入 token；加密保存后，从项目目录启动官方 Claude Code。')}</p></div><span className="route-marker" aria-hidden="true">↗</span></li>
    </ol>
    <footer className="terminal-utilities"><span>{t('已经配置过？')}</span><button disabled={!!opening} onClick={()=>void launch('launch')}>{t('启动 Claude Code')}<span aria-hidden="true">↗</span></button><button disabled={!!opening} onClick={()=>void launch('doctor')}>{t('检查环境')}<span aria-hidden="true">↗</span></button></footer>
    {feedback&&<p className="terminal-feedback" role="status">{feedback}</p>}{error&&<p className="terminal-feedback error" role="alert">{t(error)}</p>}
  </section>;
}
