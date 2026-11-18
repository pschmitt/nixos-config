//! nixpp: declarative Android guest system manager and native journaled controller.
//!
//! One executable plays several roles:
//!
//! * the guest CLI (`prepare`, `build`, `rebuild`, `switch`, `check`,
//!   `list-generations`, `rollback`, `recover`) which talks to the controller
//!   over a Unix socket,
//! * the native controller (`serve` and the direct `controller` operations)
//!   which owns the system state, the activation journal and all locks,
//! * `init` and `resume`, which prepare the isolated runtime.

pub mod bootstrap;
pub mod cli;
pub mod controller;
mod enroll;
pub mod error;
pub mod fsutil;
pub mod guest;
pub mod progress;
pub mod provision;
pub mod runner;
pub mod server;
pub mod store;
pub mod ui;

#[cfg(test)]
mod testutil;
