//! Hand-written validators for the store-path and name grammars.
//!
//! These replace the regular expressions of the Python implementation:
//!
//! * `CANDIDATE`: `[a-z0-9]{32}-[a-zA-Z0-9+._-]+`
//! * `STORE`:     `/nix/store/` followed by a `CANDIDATE`
//! * guest store path: `STORE` plus any number of `/[a-zA-Z0-9+._-]+`
//!   components, none of which may be `..`

use crate::error::{Error, Result};

const STORE_PREFIX: &str = "/nix/store/";

fn name_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'.' | b'_' | b'-')
}

/// `[a-z0-9]{32}-[a-zA-Z0-9+._-]+`, the basename of a store path.
pub fn is_candidate_name(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() > 33
        && bytes[..32]
            .iter()
            .all(|byte| matches!(byte, b'a'..=b'z' | b'0'..=b'9'))
        && bytes[32] == b'-'
        && bytes[33..].iter().copied().all(name_byte)
}

/// A store path without any sub-path: `/nix/store/HASH-name`.
pub fn is_store_root(value: &str) -> bool {
    value
        .strip_prefix(STORE_PREFIX)
        .is_some_and(is_candidate_name)
}

/// A store path with an optional sub-path and no `..` component.
pub fn is_guest_store_path(value: &str) -> bool {
    let Some(rest) = value.strip_prefix(STORE_PREFIX) else {
        return false;
    };
    let mut parts = rest.split('/');
    if !parts.next().is_some_and(is_candidate_name) {
        return false;
    }
    parts.all(|part| !part.is_empty() && part != ".." && part.bytes().all(name_byte))
}

/// Validate a guest store path (the old `store_path`).
pub fn guest_store_path(value: &str) -> Result<()> {
    if is_guest_store_path(value) {
        Ok(())
    } else {
        Err(Error::invalid("invalid guest store path"))
    }
}

/// `[a-z_][a-z0-9_-]*`
pub fn is_user_name(value: &str) -> bool {
    let mut bytes = value.bytes();
    matches!(bytes.next(), Some(b'a'..=b'z' | b'_'))
        && bytes.all(|byte| matches!(byte, b'a'..=b'z' | b'0'..=b'9' | b'_' | b'-'))
}

/// `[a-zA-Z0-9_-]+`
pub fn is_host_name(value: &str) -> bool {
    !value.is_empty()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hash(character: char) -> String {
        character.to_string().repeat(32)
    }

    #[test]
    fn candidate_names() {
        assert!(is_candidate_name(&format!(
            "{}-termuxpp-system-test",
            hash('a')
        )));
        assert!(is_candidate_name(&format!("{}-x", hash('0'))));
        for bad in [
            "",
            "../escape",
            "/absolute",
            "short-name",
            &format!("{}-", hash('a')),
            &format!("{}_x", hash('a')),
            &format!("{}-x/nested", hash('a')),
            &format!("{}-x\n", hash('a')),
            &format!("{}-x:y", hash('a')),
            &format!("{}-x", "A".repeat(32)),
            &format!("{}-x", "a".repeat(31)),
            &format!("{}-x", "a".repeat(33)),
        ] {
            assert!(!is_candidate_name(bad), "{bad:?}");
        }
    }

    #[test]
    fn store_roots() {
        let good = format!("/nix/store/{}-home-manager-generation", hash('b'));
        assert!(is_store_root(&good));
        assert!(!is_store_root(&format!("{good}/activate")));
        assert!(!is_store_root("/tmp/not-store"));
        assert!(!is_store_root("$(false)"));
        assert!(!is_store_root(&format!("{good}\n")));
        assert!(!is_store_root("/nix/store/"));
    }

    #[test]
    fn guest_store_paths() {
        let good = format!("/nix/store/{}-bash/bin/bash", hash('a'));
        assert!(guest_store_path(&good).is_ok());
        assert!(is_guest_store_path(&format!(
            "/nix/store/{}-bash",
            hash('a')
        )));
        for bad in [
            "/bin/bash".to_owned(),
            format!("{good}/../escape"),
            format!("{good}:bad"),
            format!("{good}\nextra"),
            format!("{good}/"),
            format!("{good}//x"),
            String::new(),
        ] {
            assert!(guest_store_path(&bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn user_and_host_names() {
        assert!(is_user_name("guest"));
        assert!(is_user_name("_a-b9"));
        assert!(!is_user_name("Guest"));
        assert!(!is_user_name("1guest"));
        assert!(!is_user_name(""));
        assert!(is_host_name("guest-test_1"));
        assert!(!is_host_name("host.bad"));
        assert!(!is_host_name(""));
    }
}
