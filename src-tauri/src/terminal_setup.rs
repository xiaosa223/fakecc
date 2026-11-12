// [INPUT]: 固定动作编号、内嵌终端向导脚本与 Windows PowerShell。
// [OUTPUT]: 用户点击后打开独立控制台；不接收任意路径、命令、token 或其他参数。
// [POS]: WebView 与交互终端之间的窄桥，脚本保留确认、DPAPI 和子进程环境边界。
// [PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
fn script_for(action: &str) -> Result<&'static str, String> {
    match action {
        "configure" => Ok("Setup.ps1"),
        "launch" => Ok("Launch.ps1"),
        "doctor" => Ok("Doctor.ps1"),
        _ => Err("无效的终端操作。".into()),
    }
}

#[tauri::command]
pub fn terminal_setup_open(app: tauri::AppHandle, action: String) -> Result<(), String> {
    let name = script_for(&action)?;
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        use tauri::Manager;
        let script = app.path().resource_dir().map_err(|_| "无法定位终端向导资源。")?
            .join("terminal-setup").join("scripts").join(name);
        let host = script.with_file_name("TerminalHost.ps1");
        if !script.is_file() || !host.is_file() { return Err("终端向导资源缺失，请重新安装。".into()); }
        let system_root = std::env::var_os("SystemRoot").ok_or("无法定位 Windows PowerShell。")?;
        let powershell = std::path::PathBuf::from(system_root).join("System32/WindowsPowerShell/v1.0/powershell.exe");
        std::process::Command::new(powershell)
            .args(["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
            .arg(host).arg("-ScriptName").arg(name)
            .creation_flags(0x00000010) // CREATE_NEW_CONSOLE: visible, interactive terminal requested by the user.
            .spawn().map_err(|_| "无法打开配置终端。")?;
        Ok(())
    }
    #[cfg(not(windows))]
    { let _ = (app, name); Err("此配置向导仅支持 Windows，请在终端运行 claude setup-token。".into()) }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn accepts_only_fixed_terminal_actions() {
        assert_eq!(script_for("configure").unwrap(), "Setup.ps1");
        assert_eq!(script_for("launch").unwrap(), "Launch.ps1");
        assert_eq!(script_for("doctor").unwrap(), "Doctor.ps1");
        for action in ["", "../Setup.ps1", "configure;whoami", "powershell", "setup-token"] {
            assert!(script_for(action).is_err());
        }
    }
}
