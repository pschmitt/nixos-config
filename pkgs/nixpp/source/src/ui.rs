//! Terminal output: colour policy, progress lines and tables.
//!
//! Results go to stdout and are never decorated unless stdout is a colour
//! capable terminal; progress and diagnostics go to stderr.

use clap::ValueEnum;
use std::io::{self, IsTerminal, Write};

/// The `--color` option.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum ColorChoice {
    /// Colour only on a terminal that is not `TERM=dumb` and without `NO_COLOR`.
    Auto,
    Always,
    Never,
}

/// Decide whether to emit ANSI colour for one stream.
///
/// `no_color` and `term` are the raw environment values; an empty `NO_COLOR`
/// counts as unset, as specified by no-color.org.
pub fn enabled(
    choice: ColorChoice,
    is_tty: bool,
    no_color: Option<&str>,
    term: Option<&str>,
) -> bool {
    match choice {
        ColorChoice::Never => false,
        ColorChoice::Always => true,
        ColorChoice::Auto => is_tty && no_color.is_none_or(str::is_empty) && term != Some("dumb"),
    }
}

/// The few text styles used by the CLI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Style {
    Bold,
    Dim,
    Red,
    Green,
    Yellow,
    Cyan,
    BoldCyan,
}

impl Style {
    fn code(self) -> &'static str {
        match self {
            Self::Bold => "1",
            Self::Dim => "2",
            Self::Red => "31",
            Self::Green => "32",
            Self::Yellow => "33",
            Self::Cyan => "36",
            Self::BoldCyan => "1;36",
        }
    }
}

/// Wrap `text` in `style` when `on`; empty text is never decorated.
pub fn paint(text: &str, style: Style, on: bool) -> String {
    if on && !text.is_empty() {
        format!("\x1b[{}m{text}\x1b[0m", style.code())
    } else {
        text.to_owned()
    }
}

/// Output settings for one invocation.
#[derive(Debug, Clone, Copy)]
pub struct Ui {
    out_color: bool,
    err_color: bool,
    quiet: bool,
    json: bool,
}

impl Ui {
    /// Resolve the policy from the options, the environment and the streams.
    pub fn detect(choice: ColorChoice, json: bool, quiet: bool) -> Self {
        let no_color = std::env::var("NO_COLOR").ok();
        let term = std::env::var("TERM").ok();
        let decide =
            |is_tty: bool| !json && enabled(choice, is_tty, no_color.as_deref(), term.as_deref());
        Self {
            out_color: decide(io::stdout().is_terminal()),
            err_color: decide(io::stderr().is_terminal()),
            quiet,
            json,
        }
    }

    /// Explicit settings (tests and embedding).
    pub fn new(out_color: bool, err_color: bool, quiet: bool, json: bool) -> Self {
        Self {
            out_color: out_color && !json,
            err_color: err_color && !json,
            quiet,
            json,
        }
    }

    /// Machine-readable output was requested.
    pub fn json(&self) -> bool {
        self.json
    }

    /// Whether stdout is an interactive terminal.
    pub fn stdout_is_terminal() -> bool {
        io::stdout().is_terminal()
    }

    pub fn format_step(&self, message: &str) -> String {
        format!("{} {message}", paint("::", Style::BoldCyan, self.err_color))
    }

    pub fn format_ok(&self, message: &str) -> String {
        format!("{} {message}", paint("ok", Style::Green, self.err_color))
    }

    pub fn format_warning(&self, message: &str) -> String {
        format!(
            "{} {message}",
            paint("warning:", Style::Yellow, self.err_color)
        )
    }

    pub fn format_error(&self, message: &str) -> String {
        format!("{} {message}", paint("nixpp:", Style::Red, self.err_color))
    }

    /// A progress step (suppressed by `--quiet`).
    pub fn step(&self, message: &str) {
        if !self.quiet {
            stderr_line(&self.format_step(message));
        }
    }

    /// A success note (suppressed by `--quiet`).
    pub fn ok(&self, message: &str) {
        if !self.quiet {
            stderr_line(&self.format_ok(message));
        }
    }

    /// A warning (suppressed by `--quiet`).
    pub fn warn(&self, message: &str) {
        if !self.quiet {
            stderr_line(&self.format_warning(message));
        }
    }

    /// An error; always shown.
    pub fn error(&self, message: &str) {
        stderr_line(&self.format_error(message));
    }

    /// Write a result line to stdout.
    pub fn print(&self, text: &str) {
        let mut out = io::stdout().lock();
        let _ = writeln!(out, "{text}");
    }

    /// Render rows under bold headers with aligned columns and no trailing
    /// whitespace. `cell_style` may colour individual data cells.
    pub fn table(
        &self,
        headers: &[&str],
        rows: &[Vec<String>],
        cell_style: &dyn Fn(usize, &str) -> Option<Style>,
    ) -> String {
        let widths: Vec<usize> = (0..headers.len())
            .map(|column| {
                rows.iter()
                    .map(|row| row[column].chars().count())
                    .chain([headers[column].chars().count()])
                    .max()
                    .unwrap_or(0)
            })
            .collect();
        let render = |cells: Vec<(String, Option<Style>)>| {
            let mut line = String::new();
            for (column, (text, style)) in cells.iter().enumerate() {
                if column > 0 {
                    line.push_str("  ");
                }
                line.push_str(&paint(
                    text,
                    style.unwrap_or(Style::Bold),
                    self.out_color && style.is_some(),
                ));
                if column + 1 < cells.len() {
                    let padding = widths[column].saturating_sub(text.chars().count());
                    line.push_str(&" ".repeat(padding));
                }
            }
            line.trim_end().to_owned()
        };
        let mut lines = vec![render(
            headers
                .iter()
                .map(|header| ((*header).to_owned(), Some(Style::Bold)))
                .collect(),
        )];
        for row in rows {
            lines.push(render(
                row.iter()
                    .enumerate()
                    .map(|(column, text)| (text.clone(), cell_style(column, text)))
                    .collect(),
            ));
        }
        lines.join("\n")
    }
}

fn stderr_line(text: &str) {
    let mut err = io::stderr().lock();
    let _ = writeln!(err, "{text}");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn color_matrix() {
        use ColorChoice::{Always, Auto, Never};
        // choice, tty, NO_COLOR, TERM, expected
        let cases = [
            (Never, true, None, Some("xterm"), false),
            (Never, false, None, None, false),
            (Always, false, Some("1"), Some("dumb"), true),
            (Auto, true, None, Some("xterm-256color"), true),
            (Auto, true, None, None, true),
            (Auto, false, None, Some("xterm"), false),
            (Auto, true, Some("1"), Some("xterm"), false),
            (Auto, true, Some(""), Some("xterm"), true),
            (Auto, true, None, Some("dumb"), false),
        ];
        for (choice, tty, no_color, term, expected) in cases {
            assert_eq!(
                enabled(choice, tty, no_color, term),
                expected,
                "{choice:?} tty={tty} NO_COLOR={no_color:?} TERM={term:?}"
            );
        }
    }

    #[test]
    fn paint_wraps_only_when_enabled_and_non_empty() {
        assert_eq!(paint("x", Style::Red, false), "x");
        assert_eq!(paint("", Style::Red, true), "");
        assert_eq!(paint("x", Style::Red, true), "\x1b[31mx\x1b[0m");
        assert_eq!(paint("x", Style::BoldCyan, true), "\x1b[1;36mx\x1b[0m");
    }

    #[test]
    fn plain_lines_have_no_escape_sequences() {
        let ui = Ui::new(false, false, false, false);
        assert_eq!(ui.format_step("build"), ":: build");
        assert_eq!(ui.format_ok("done"), "ok done");
        assert_eq!(ui.format_warning("careful"), "warning: careful");
        assert_eq!(ui.format_error("boom"), "nixpp: boom");
    }

    #[test]
    fn colored_lines_use_the_expected_styles() {
        let ui = Ui::new(true, true, false, false);
        assert!(ui.format_step("x").starts_with("\x1b[1;36m::\x1b[0m"));
        assert!(ui.format_ok("x").starts_with("\x1b[32mok\x1b[0m"));
        assert!(ui.format_warning("x").starts_with("\x1b[33m"));
        assert!(ui.format_error("x").starts_with("\x1b[31mnixpp:\x1b[0m"));
    }

    #[test]
    fn json_mode_never_colors() {
        let ui = Ui::new(true, true, false, true);
        assert!(ui.json());
        assert!(!ui.format_error("boom").contains('\x1b'));
        assert!(!ui.format_step("x").contains('\x1b'));
        let table = ui.table(&["A"], &[vec!["b".to_owned()]], &|_, _| Some(Style::Green));
        assert!(!table.contains('\x1b'));
    }

    fn rows() -> Vec<Vec<String>> {
        vec![
            vec!["aaa".to_owned(), "hm1".to_owned(), "current".to_owned()],
            vec!["b".to_owned(), "hm22222".to_owned(), String::new()],
        ]
    }

    #[test]
    fn table_aligns_columns_and_trims_trailing_space() {
        let ui = Ui::new(false, false, false, false);
        let table = ui.table(
            &["GENERATION", "HOME MANAGER", "STATE"],
            &rows(),
            &|_, _| None,
        );
        let lines: Vec<&str> = table.lines().collect();
        assert_eq!(lines[0], "GENERATION  HOME MANAGER  STATE");
        assert_eq!(lines[1], "aaa         hm1           current");
        assert_eq!(lines[2], "b           hm22222");
        assert!(lines.iter().all(|line| line == &line.trim_end()));
    }

    #[test]
    fn colored_table_keeps_alignment_of_plain_text() {
        let ui = Ui::new(true, true, false, false);
        let table = ui.table(
            &["GENERATION", "STATE"],
            &[vec!["a".to_owned(), "current".to_owned()]],
            &|column, text| (column == 1 && text == "current").then_some(Style::Green),
        );
        let lines: Vec<&str> = table.lines().collect();
        assert_eq!(lines[0], "\x1b[1mGENERATION\x1b[0m  \x1b[1mSTATE\x1b[0m");
        assert_eq!(lines[1], "a           \x1b[32mcurrent\x1b[0m");
    }
}
