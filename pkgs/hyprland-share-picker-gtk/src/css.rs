use gtk4::{CssProvider, STYLE_PROVIDER_PRIORITY_APPLICATION, gdk};

pub const CSS_DATA: &str = r#"
window.share-picker {
  background: @window_bg_color;
  border-radius: 16px;
  border: 1px solid alpha(@window_fg_color, 0.15);
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.5);
}
.picker-content {
  border-radius: 16px;
}
.picker-header {
  border-radius: 16px 16px 0 0;
}
.source-card {
  background: alpha(@window_fg_color, 0.045);
  border: 2px solid transparent;
  border-radius: 14px;
  padding: 0;
  min-height: 246px;
  max-height: 246px;
}
.source-card:hover { background: alpha(@accent_bg_color, 0.12); }
.source-card:checked {
  background: alpha(@accent_bg_color, 0.16);
  border-color: @accent_bg_color;
  box-shadow: 0 4px 16px alpha(@accent_bg_color, 0.18);
}
.source-card > box {
  min-width: 220px;
  min-height: 246px;
  max-height: 246px;
}
.action-card {
  background: alpha(@accent_bg_color, 0.08);
  border-style: dashed;
}
.preview {
  background: alpha(@window_fg_color, 0.09);
  border-radius: 12px 12px 0 0;
  min-height: 170px;
  max-height: 170px;
}
.region-preview {
  background: alpha(@window_fg_color, 0.09);
  border-radius: 12px;
}
.card-info {
  min-height: 56px;
  max-height: 56px;
}
.app-icon {
  border-radius: 6px;
}
window.overlay-highlighter {
  background-color: transparent;
  background: none;
  border: none;
  box-shadow: none;
}
"#;

pub fn install_css() {
    if let Some(display) = gdk::Display::default() {
        let provider = CssProvider::new();
        provider.load_from_data(CSS_DATA);
        gtk4::style_context_add_provider_for_display(
            &display,
            &provider,
            STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}
