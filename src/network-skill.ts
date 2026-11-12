/**
 * [INPUT]: 自有公开仓库 xiaosa223/claude-code-setup 与共享双语模板。
 * [OUTPUT]: 官方 claude-code agent 的安装/调用提示词；建议 setup-token 终端路线，关闭安装统计。
 * [POS]: 网络页纯数据/文案边界；只描述完整 Skill 的安装与运行，具体收集/验证/部署协议归 Skill。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import {translate,type Locale} from './i18n';
export const skillRepository='xiaosa223/claude-code-setup';
export const skillName='claude-code-setup';
export const agents=[{id:'claude',name:'Claude Code',cli:'claude-code',invoke:'/claude-code-setup'}];
export const installationCommand=`npx --yes skills add ${skillRepository} --skill ${skillName} --agent claude-code --global --copy --yes`;
export function installationPrompt(_id:string,locale:Locale):string {
    return translate('请先设置 DO_NOT_TRACK=1，再执行 `{v0}`。安装后运行 /claude-code-setup，引导我只在终端使用官方 Claude Code，并通过 claude setup-token 配置长期 token。已有可用线路时跳过服务器部署。不要索要或展示我的 token。',{v0:installationCommand},locale);
}
