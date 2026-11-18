#[cfg(all(target_os = "linux", target_env = "gnu"))]
mod signal_stack;

fn main() -> std::process::ExitCode {
    #[cfg(all(target_os = "linux", target_env = "gnu"))]
    if let Err(error) = signal_stack::reserve() {
        eprintln!("nixpp: cannot reserve guest signal stack: {error}");
        return std::process::ExitCode::FAILURE;
    }
    nixpp::cli::run()
}
