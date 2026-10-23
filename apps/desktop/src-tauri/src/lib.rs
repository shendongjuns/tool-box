mod local_api;

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WindowEvent,
};

/// 本地数据源端口，前端通过 invoke("local_api_port") 获取。
struct LocalApiPort(u16);

/// 应用根目录（exe 所在目录）。
///
/// 便携版与安装版都把**全部数据**放在这里，不写 AppData / 文档目录，
/// 卸载或整目录拷走即可，不污染系统其它位置。
fn app_root() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."))
}

/// 数据目录：<exe 目录>/data
fn data_dir() -> PathBuf {
    app_root().join("data")
}

/// 日志目录：<exe 目录>/data/logs
fn log_dir() -> PathBuf {
    data_dir().join("logs")
}

/// 窗口状态文件：<exe 目录>/data/window-state.json
fn window_state_path() -> PathBuf {
    data_dir().join("window-state.json")
}

#[derive(serde::Serialize, serde::Deserialize)]
struct WindowState {
    width: u32,
    height: u32,
    maximized: bool,
}

/// 启动时恢复窗口尺寸（只恢复尺寸，不恢复位置 —— 换显示器时旧坐标可能落到屏幕外）。
fn restore_window_state(window: &tauri::WebviewWindow) {
    let Ok(raw) = std::fs::read_to_string(window_state_path()) else {
        return;
    };
    let Ok(state) = serde_json::from_str::<WindowState>(&raw) else {
        return;
    };

    let _ = window.set_size(tauri::PhysicalSize::new(
        state.width.max(960),
        state.height.max(640),
    ));
    if state.maximized {
        let _ = window.maximize();
    }
}

/// 退出前保存窗口尺寸。
fn save_window_state(window: &tauri::WebviewWindow) {
    let (Ok(size), Ok(maximized)) = (window.inner_size(), window.is_maximized()) else {
        return;
    };
    let state = WindowState {
        width: size.width,
        height: size.height,
        maximized,
    };
    if let Ok(json) = serde_json::to_string_pretty(&state) {
        let _ = std::fs::create_dir_all(data_dir());
        let _ = std::fs::write(window_state_path(), json);
    }
}

/// 是否已通过「直接退出」放行关闭事件。
static ALLOW_EXIT: AtomicBool = AtomicBool::new(false);

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

/// 隐藏到托盘（前端选择「最小化到托盘」后调用）。
#[tauri::command]
fn hide_to_tray(window: tauri::WebviewWindow) {
    let _ = window.hide();
}

/// 真正退出：先标记放行，再销毁窗口，避免被关闭拦截挡回来。
#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    ALLOW_EXIT.store(true, Ordering::SeqCst);
    app.exit(0);
}

/// 通用 HTTP 转发（桌面端云端模式使用）。
///
/// 渲染进程被 CSP 限制为 `connect-src 'none'`，不能自己发网络请求；
/// 所有出网流量统一走这里，由 Rust 侧发出。这样做的好处：
/// 1. CSP 可以收得很死，渲染层被注入脚本也偷不走数据；
/// 2. 出网目标、方法、大小集中可控。
///
/// 限制：仅允许 http/https，单次响应上限 16MB。
#[tauri::command]
async fn http_request(
    method: String,
    url: String,
    body: Option<String>,
    headers: Option<std::collections::HashMap<String, String>>,
) -> Result<serde_json::Value, String> {
    let parsed = url::Url::parse(&url).map_err(|_| "URL 不合法".to_string())?;
    if parsed.scheme() != "http" && parsed.scheme() != "https" {
        return Err("仅支持 http/https".to_string());
    }

    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|e| e.to_string())?;

    let mut request = client.request(
        reqwest::Method::from_bytes(method.to_uppercase().as_bytes())
            .map_err(|_| "HTTP 方法不合法".to_string())?,
        url,
    );
    for (key, value) in headers.unwrap_or_default() {
        request = request.header(key, value);
    }
    if let Some(payload) = body {
        request = request.body(payload);
    }

    let response = request.send().await.map_err(|e| format!("请求失败: {e}"))?;
    let status = response.status().as_u16();
    let text = response
        .text()
        .await
        .map_err(|e| format!("读取响应失败: {e}"))?;
    if text.len() > 16 * 1024 * 1024 {
        return Err("响应过大".to_string());
    }

    // 统一返回 { status, body }，前端自行解析
    Ok(serde_json::json!({ "status": status, "body": text }))
}

fn focus_main(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

/// 系统托盘：单击显示窗口，右键菜单提供「显示 / 退出」。
fn setup_tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "显示主窗口", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出 ToolBox", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;

    let mut builder = TrayIconBuilder::with_id("main")
        .menu(&menu)
        .tooltip("ToolBox")
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => focus_main(app),
            "quit" => {
                ALLOW_EXIT.store(true, Ordering::SeqCst);
                app.exit(0);
            }
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                focus_main(tray.app_handle());
            }
        });

    // 托盘图标：显式加载 32x32 PNG。
    //
    // 不用 default_window_icon()：它来自 bundle.icon 的第一项，
    // 尺寸与托盘期望的不一定匹配；而且没有图标时会静默退化成空白托盘。
    match tauri::image::Image::from_bytes(include_bytes!("../icons/32x32.png")) {
        Ok(icon) => {
            builder = builder.icon(icon);
        }
        Err(error) => {
            log::warn!("托盘图标加载失败，回退到窗口图标: {error}");
            if let Some(icon) = app.default_window_icon() {
                builder = builder.icon(icon.clone());
            }
        }
    }

    builder.build(app)?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            focus_main(app);
        }))
        .plugin(
            tauri_plugin_log::Builder::new()
                .level(log::LevelFilter::Info)
                // 日志也放在 <exe>/data/logs，与数据库同处一个可整体带走的目录
                .target(tauri_plugin_log::Target::new(
                    tauri_plugin_log::TargetKind::Folder {
                        path: log_dir(),
                        file_name: Some("app".into()),
                    },
                ))
                .build(),
        )
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .setup(|app| {
            // 本地数据源：SQLite 放在 <exe>/data/local.db，
            // 与云端库（服务器上的 toolbox.db）完全独立。
            let db_path = data_dir().join("local.db");
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

            if let Some(window) = app.get_webview_window("main") {
                restore_window_state(&window);
            }

            // 托盘失败不应该阻止应用启动：退化为「关闭即退出」
            match setup_tray(app.handle()) {
                Ok(()) => log::info!("系统托盘已创建"),
                Err(error) => log::error!("系统托盘创建失败: {error}"),
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            local_api_port,
            show_main_window,
            hide_to_tray,
            quit_app,
            http_request
        ])
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                // 「直接退出」放行后不再拦截
                if ALLOW_EXIT.load(Ordering::SeqCst) {
                    return;
                }
                /*
                 * 关闭 = 隐藏到托盘。
                 *
                 * 这里必须由 Rust 直接执行，不能只发事件让前端处理：
                 * 登录页没有壳层组件，一旦前端没挂监听器，点 × 就完全没反应。
                 * 在 Rust 侧 hide 可以保证任何页面下行为一致。
                 */
                if let Some(webview) = window.get_webview_window(window.label()) {
                    save_window_state(&webview);
                }
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running ToolBox");
}