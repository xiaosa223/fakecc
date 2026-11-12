/**
 * [INPUT]: 五项标准安装 agent/调用入口与精简中英文 YAML 提示词。
 * [OUTPUT]: npm 命令、调用符、Skill 来源、语言和恰好五项的回归。
 * [POS]: 网络页复制内容验收，不安装 Skill 或连接服务器。
 * [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
 */
import {test,expect} from 'bun:test';
import {agents,installationPrompt} from './network-skill';
test('自有 Skill 的安装与认证路线保持官方终端流程',()=>{
    expect(agents.map(a=>a.id)).toEqual(['claude']);
    for(const agent of agents){
        const zh=installationPrompt(agent.id,'zh'),en=installationPrompt(agent.id,'en');
        if(agent.cli){expect(zh).toContain(`--agent ${agent.cli}`);expect(en).toContain(`--agent ${agent.cli}`);}
        expect(en).toContain('xiaosa223/claude-code-setup');
        expect(en).toContain('npx --yes skills add');
        expect(en).toContain('--global --copy --yes');
        expect(en).toContain('DO_NOT_TRACK=1');
        expect(en).toContain('--skill claude-code-setup');
        expect(en).toContain('claude setup-token');
        expect(zh).toContain('claude setup-token');
        expect(en).not.toContain('liseami');
        expect(en).toContain(agent.invoke);expect(zh).toContain(agent.invoke);
        expect(en).toContain('English');
        expect(/[\u3400-\u9fff]/.test(en)).toBe(false);
        expect(/[\u3400-\u9fff]/.test(zh)).toBe(true);
        expect(en).not.toContain('api.lsidestudio.com');expect(en).not.toContain('xiaosa.win');
    }
});
