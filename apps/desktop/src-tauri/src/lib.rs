mod local_api;

use std::path::PathBuf;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WindowEvent,
};

/// 本地数据源端口，前端通过 invoke("local_api_port") 获取。
struct LocalApiPort(u16);

#[tauri::command]
fn local_api_port(state: tauri::State<'_, LocalApiPort>) -> u16 {
    state.0
}

#[tauri::command]
fn show_main_window(app: tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "显示主窗口", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出 ToolBox", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;

    let _tray = TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .tooltip("ToolBox")
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                if let Some(window) = tray.app_handle().get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.unminimize();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_log::Builder::new().build())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_window_state::Builder::new().build())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .setup(|app| {
            tray(app.handle())?;

            // 本地数据源：把 SQLite 放在用户的 AppData 下，
            // 与云端库（服务器上的 toolbox.db）完全独立。
            let data_dir = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| PathBuf::from("."));
            let db_path = data_dir.join("local.db");
            match local_api::start(db_path) {
                Ok(port) => {
                    log::info!("本地数据源已启动，端口 {port}");
                    app.manage(LocalApiPort(port));
                }
                Err(error) => {
                    log::error!("本地数据源启动失败: {error}");
                    app.manage(LocalApiPort(0));
                }
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![local_api_port, show_main_window])
        .on_window_event(|window, event| {
            // 关闭按钮：默认最小化到托盘，真正退出走托盘菜单
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running ToolBox");
}
