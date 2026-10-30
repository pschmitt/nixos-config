use std::process;

use clap::Parser;
use gtk4::{Application, gio, prelude::*};

mod capture;
mod config;
mod css;
mod decoration;
mod desktop;
mod hyprland;
mod indicator;
mod overlay;
mod ui;

#[derive(Parser, Debug)]
#[command(name = "hyprland-share-picker-gtk")]
#[command(
    version = "0.1.0",
    about = "A GTK4 share picker for Hyprland and xdg-desktop-portal-hyprland"
)]
struct Args {
    #[arg(long)]
    allow_token: bool,

    #[arg(long)]
    self_test: bool,

    #[arg(long)]
    runtime_check: bool,

    /// Debug: capture OUTPUT like the shm previews and save PREFIX-*.jpg.
    #[arg(long, num_args = 2, value_names = ["OUTPUT", "PREFIX"], hide = true)]
    probe_capture: Option<Vec<String>>,

    /// Draw a border around a shared region or window until its stream ends.
    #[arg(long, value_name = "TARGET")]
    indicator: Option<String>,

    #[arg(index = 1)]
    window_list: Option<String>,
}

fn run_self_test() {
    println!("Running hyprland-share-picker-gtk self-test...");

    let entries = hyprland::parse_window_list(
        "42[HC>]firefox[HT>]A tab[HE>]43[HC>]kitty[HT>]shell[HE>]0xabc[HA>]",
    );
    assert_eq!(entries.len(), 2);
    assert_eq!(entries[0].id, "42");
    assert_eq!(entries[0].class, "firefox");
    assert_eq!(entries[0].title, "A tab");
    assert_eq!(entries[1].address.as_deref(), Some("0xabc"));

    let workspaces = hyprland::parse_workspace_list_v3("42[HN>]1:1[HM>]1:4:DP-3[HE>]");
    assert_eq!(workspaces.len(), 1);
    assert_eq!(workspaces[0].id, 42);
    assert_eq!(workspaces[0].outputs, vec!["DP-3"]);

    let conf = config::parse_picker_config(
        "columns = 3\npreview {\n  scale = 0.5\n  jpeg_quality = 90\n  refresh_rate = 8\n}",
    );
    assert_eq!(conf.columns, 3);
    assert_eq!(conf.scale, 0.5);
    assert_eq!(conf.jpeg_quality, 90);
    assert_eq!(conf.refresh_rate, 8.0);

    let monitors = vec![hyprland::Monitor {
        id: 0,
        name: "DP-1".into(),
        description: "".into(),
        width: 1920,
        height: 1080,
        x: 1920,
        y: 0,
        scale: 1.0,
        focused: true,
        active_workspace: Some(hyprland::Workspace {
            id: 1,
            name: "1".into(),
        }),
        special_workspace: None,
    }];
    let region = hyprland::parse_region("DP-1 2048 120 640 480", &monitors);
    assert_eq!(region.as_deref(), Some("region:DP-1@128,120,640,480"));

    let details = hyprland::parse_region_details("region:DP-1@128,120,640,480", &monitors);
    assert!(details.is_some());
    let d = details.unwrap();
    assert_eq!(d.output, "DP-1");
    assert_eq!(d.x, 128);
    assert_eq!(d.y, 120);
    assert_eq!(d.width, 640);
    assert_eq!(d.height, 480);
    assert_eq!(d.global_x, 2048);
    assert_eq!(d.global_y, 120);

    let (r, g, b, a) = config::parse_rgba_color("#a855f7", config::DEFAULT_HIGHLIGHT_RGBA);
    assert!((r - 0.6588).abs() < 0.01);
    assert!((g - 0.3333).abs() < 0.01);
    assert!((b - 0.9686).abs() < 0.01);
    assert_eq!(a, 1.0);

    println!("All self-tests passed successfully!");
}

fn main() {
    let args = Args::parse();

    if args.self_test {
        run_self_test();
        process::exit(0);
    }

    if let Some(probe) = args.probe_capture {
        if let Err(err) = capture::probe_output(&probe[0], &probe[1]) {
            eprintln!("probe failed: {err:#}");
            process::exit(1);
        }
        process::exit(0);
    }

    if let Some(target) = args.indicator {
        indicator::run(&target);
    }

    if args.runtime_check {
        gtk4::init().expect("initialize GTK");
        if std::env::var_os("WAYLAND_DISPLAY").is_some() {
            assert!(
                gtk4_layer_shell::is_supported(),
                "gtk4-layer-shell is not supported"
            );
        }
        process::exit(0);
    }

    let app = Application::builder()
        .application_id(hyprland::PICKER_APP_ID)
        .flags(gio::ApplicationFlags::NON_UNIQUE)
        .build();

    let allow_token = args.allow_token;
    let window_list = args
        .window_list
        .or_else(|| std::env::var("XDPH_WINDOW_SHARING_LIST").ok());

    // XDPH 1.5.0 and later lists shareable workspaces too.
    let workspace_list = std::env::var("XDPH_WORKSPACE_SHARING_LIST_V3").ok();

    app.connect_activate(move |app| {
        ui::build_ui(
            app,
            allow_token,
            window_list.clone(),
            workspace_list.clone(),
        );
    });

    app.run_with_args::<&str>(&[]);
}
