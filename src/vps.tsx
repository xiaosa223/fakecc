/**
 * [INPUT]: assets/resources.json 的四项指定推广、自有终端 Skill、双语目录、四域只读诊断与原生剪贴板。
 * [OUTPUT]: 四张推广卡、官方终端 setup-token 安装提示词与原有 Claude 出口四态检测；不增加其他商家或认证入口。
 * [POS]: 网络资源与分流诊断；应用不收集密钥或执行远端部署，诊断仅进行只读网络连通性探测。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import {Button,Textarea} from 'cromma-ui';
import {Refresh} from 'cromma-ui/pika';
import {useState} from 'react';
import {invoke} from '@tauri-apps/api/core';
import {useI18n} from './i18n';
import {installationPrompt} from './network-skill';
import resources from '../assets/resources.json';

export type DomainDiagnosis = {
    domain: string;
    ok: boolean;
    status_code: number | null;
    latency_ms: number | null;
    ip: string | null;
    message: string;
};

const claudeDomains=['claude.ai','api.anthropic.com','platform.claude.com','downloads.claude.ai'] as const;
export function VpsPanel() {
    const {t,locale}=useI18n();
    const [copied,setCopied]=useState(''), [error,setError]=useState('');
    const [diagnosing,setDiagnosing]=useState(false);
    const [diagnostics,setDiagnostics]=useState<DomainDiagnosis[]|null>(null);
    const [diagnosticsError,setDiagnosticsError]=useState('');
    const results=claudeDomains.map(domain=>diagnostics?.find(item=>item.domain===domain));
    const passed=results.filter(item=>item?.ok).length;
    const phase=diagnosing?'checking':diagnosticsError?'failed':diagnostics?(passed===claudeDomains.length?'passed':'failed'):'idle';
    const statusText=phase==='checking'?'检测中':phase==='passed'?'检测成功':phase==='failed'?'检测失败':'待检测';
    const prompt=installationPrompt('claude',locale);

    async function open(provider:'dmit'|'webshare'|'recharge'|'relay'|'skill') {
        setError('');
        try { await invoke('network_open_resource',{provider}); }
        catch (e) { setError(String(e)); }
    }

    async function copy() {
        setError('');
        try { await invoke('copy_result',{text:prompt});setCopied(prompt); }
        catch(e) { setError(String(e)); }
    }

    async function runDiagnostics() {
        if(diagnosing)return;
        setDiagnosing(true);
        setError('');
        setDiagnostics(null);
        setDiagnosticsError('');
        try {
            const results = await invoke<DomainDiagnosis[]>('network_diagnose_domains');
            if(!Array.isArray(results))throw new Error('检测结果无效，请重试。');
            setDiagnostics(results);
            if(claudeDomains.some(domain=>!results.some(item=>item.domain===domain)))setDiagnosticsError('部分检测未返回结果，请重试。');
        } catch (e) {
            setDiagnosticsError(String(e));
        } finally {
            setDiagnosing(false);
        }
    }

    return <section className="system-page network-page studio-network">
        <header className="page-topline"><span>CONNECTIONS / RESOURCES</span><span>{t('按需选择')}</span></header>
        <div className="resource-intro"><div className="editorial-label">YOUR TOOLS. YOUR CHOICE.</div><h1>{t('连接，准备就绪。')}</h1><p>{t('已有线路可以直接使用。这里仅保留四项指定推广，购买与授权分别进行。')}</p></div>
        <div className="resource-grid">{(['dmit','webshare','recharge','relay'] as const).map((id,index)=>{const resource=resources[id];return <article className={`resource-card resource-${id}`} key={id}>
            <div className="resource-card-top"><span className="resource-monogram" aria-hidden="true">{['D','W','↗','⌘'][index]}</span><span className="promotion-label">{t(resource.tag)}</span></div>
            <div className="resource-card-body"><span className="resource-category">{t(resource.label)}</span><h2>{id==='recharge'?t('低价源头代充'):id==='relay'?t('不降智稳定中转站'):resource.name}</h2><p>{id==='recharge'||id==='relay'?resource.name:t(resource.description)}</p></div>
            <button className="resource-visit" onClick={()=>void open(id)}>{t('访问站点')}<span aria-hidden="true">↗</span></button>
        </article>;})}</div>
        <section className="studio-skill" aria-labelledby="skill-install-title"><div className="skill-heading"><div><span className="editorial-label">CLAUDE CODE SETUP</span><h2 id="skill-install-title">{t('让 Skill 带你完成配置')}</h2></div><button className="studio-button quiet" onClick={()=>void open('skill')}>{t('查看使用说明')}<span aria-hidden="true">↗</span></button></div><p>{t('推荐路线：终端 Claude Code → setup-token → 本机保存 → 进入项目。')}</p><Textarea id="skill-prompt" aria-labelledby="skill-install-title" readOnly value={prompt} rows={4}/><div className="skill-copy-row"><span>{t('只复制安装提示词，不包含任何凭据。')}</span><button className="studio-button primary" onClick={()=>void copy()}>{copied===prompt?t('已复制'):t('复制安装提示词')}</button></div></section>
        <section className="domain-diagnostics" aria-labelledby="diagnostics-title" data-status={phase} aria-busy={diagnosing}>
            <div className="domain-diagnostics-header">
                <h2 id="diagnostics-title">{t('Claude 出口')}</h2>
                <Button variant="secondary" size="small" disabled={diagnosing} leftIcon={<Refresh aria-hidden size={15} className={diagnosing?'spin':''}/>} onClick={()=>void runDiagnostics()}>{diagnosing?t('检测中'):phase==='idle'?t('开始检测'):t('重新检测')}</Button>
            </div>
            <div className={`domain-outcome ${phase}`} role="status" aria-live="polite">
                <span className="domain-outcome-symbol" aria-hidden="true">{phase==='passed'?'✓':phase==='failed'?'×':phase==='checking'?'◌':'·'}</span>
                <strong>{t(statusText)}</strong>
                {diagnostics&&!diagnosticsError&&<span>{t('已通过 {v0} / {v1} 项',{v0:passed,v1:claudeDomains.length})}</span>}
                {diagnosticsError&&<p>{t(diagnosticsError)}</p>}
            </div>
            <ul className="domain-diagnostics-list">{claudeDomains.map((domain,index)=>{
                const item=results[index];
                const status=diagnosing?'checking':item?item.ok?'passed':'failed':phase==='failed'?'failed':'idle';
                return <li key={domain} className={`domain-diagnostics-item ${status}`}>
                    <div className="domain-item-info"><span className="domain-name">{domain}</span>{item&&<span className="domain-detail">{item.status_code?`HTTP ${item.status_code} · `:''}{t(item.message)}</span>}{item?.ip&&<span className="domain-ip" title={t('连接对端，不代表出口 IP')}>{item.ip}</span>}</div>
                    <div className="domain-item-status">{item?.latency_ms!=null&&<span className="domain-latency">{item.latency_ms} ms</span>}<span className={`domain-badge ${status}`}><span aria-hidden="true">{status==='passed'?'✓':status==='failed'?'×':status==='checking'?'◌':'·'}</span>{t(status==='checking'?'检测中':item?item.ok?'检测成功':'检测失败':phase==='failed'?'未完成':'待检测')}</span></div>
                </li>;
            })}</ul>
        </section>
        {error&&<p role="alert" className="system-feedback error">{t(error)}</p>}
    </section>;
}
