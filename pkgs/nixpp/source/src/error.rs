//! Error type shared by the guest CLI and the native controller.

use std::fmt;
use std::io;

/// Failure of a guest or controller operation.
///
/// `Invalid` carries the user-facing message of a rejected input or refused
/// state transition. `Timeout`, `Interrupted` and `Terminated` are kept apart
/// because the native controller maps them to dedicated exit codes (124, 130
/// and 143) and the server must not turn the last two into protocol replies.
#[derive(Debug)]
pub enum Error {
    /// A rejected request, malformed state or refused transition.
    Invalid(String),
    /// An operating-system failure (including a contended lock, `WouldBlock`).
    Io(io::Error),
    /// A guest command exceeded its execution budget.
    Timeout { seconds: u64 },
    /// The controller received SIGINT while a guest command was running.
    Interrupted,
    /// The controller received SIGTERM while a guest command was running.
    Terminated,
}

pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    /// Shorthand for [`Error::Invalid`].
    pub fn invalid(message: impl Into<String>) -> Self {
        Self::Invalid(message.into())
    }

    /// True for a failed non-blocking lock attempt.
    pub fn is_would_block(&self) -> bool {
        matches!(self, Self::Io(error) if error.kind() == io::ErrorKind::WouldBlock)
    }

    /// True when the process itself is being stopped (SIGINT or SIGTERM).
    pub fn is_stop_request(&self) -> bool {
        matches!(self, Self::Interrupted | Self::Terminated)
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Invalid(message) => formatter.write_str(message),
            Self::Io(error) => write!(formatter, "{error}"),
            Self::Timeout { seconds } => {
                write!(formatter, "command timed out after {seconds} seconds")
            }
            Self::Interrupted => formatter.write_str("interrupted"),
            Self::Terminated => formatter.write_str("terminated"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            _ => None,
        }
    }
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

impl From<serde_json::Error> for Error {
    fn from(error: serde_json::Error) -> Self {
        Self::Invalid(format!("invalid JSON: {error}"))
    }
}
