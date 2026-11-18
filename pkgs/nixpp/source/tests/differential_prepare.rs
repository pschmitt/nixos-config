//! Differential test: the Rust `prepare` against the Python reference
//! (`system/prepare-session.py`) on identical fixtures.
//!
//! Compared per fixture: success or failure, the error text of a rejected
//! candidate, and the complete resulting tree under the fixture root (path,
//! kind, permission bits, file contents, link targets). Wording of unrelated
//! CLI output is intentionally out of scope.
//!
//! The reference is test-only. Set `NIXPP_REFERENCE_PREPARE` to the path of
//! `prepare-session.py` (and optionally `NIXPP_REFERENCE_PYTHON`, default
//! `python3`). Without it the test reports that it was skipped and passes.

use nixpp::guest::prepare_with;
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, symlink};
use std::path::{Path, PathBuf};
use std::process::Command;

const DRIVER: &str = r#"
import importlib.util, json, os, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('prepare_system', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.store_path = lambda value: value
os.umask(0o077)
outcomes = []
for _ in range(int(sys.argv[4])):
    try:
        outcomes.append({'ok': str(module.prepare(Path(sys.argv[2]), Path(sys.argv[3])))})
    except ValueError as error:
        outcomes.append({'error': str(error)})
print(json.dumps(outcomes))
"#;

#[derive(Debug, PartialEq, Eq)]
enum Entry {
    Dir(u32),
    File(u32, Vec<u8>),
    Link(Vec<u8>),
    Special(u32),
}

type Snapshot = BTreeMap<String, Entry>;

struct Fixture {
    root: PathBuf,
    runtime: PathBuf,
    generation: PathBuf,
}

impl Fixture {
    fn build(root: &Path) -> Self {
        let _ = fs::remove_dir_all(root);
        let runtime = root.join("runtime");
        let generation = root.join(format!("{}-termuxpp-system-test", "a".repeat(32)));
        for path in [
            runtime.join("root/etc"),
            generation.join("etc/nested"),
            generation.join("sw/bin"),
            generation.join("terminfo"),
        ] {
            fs::create_dir_all(path).unwrap();
        }
        let fixture = Self {
            root: root.to_owned(),
            runtime,
            generation,
        };
        fixture.write_runtime(
            "session.json",
            r#"{"schema": 1, "system": "aarch64-linux", "pageSize": 4096}"#,
        );
        fixture.write_runtime(
            "root/etc/passwd",
            "guest:x:123:456:Guest:/home/guest:/bin/sh\n",
        );
        fixture.write_runtime("root/etc/group", "guest:x:456:\n");
        fixture.write_runtime("root/etc/resolv.conf", "nameserver 127.0.0.1\n");
        fixture.write_runtime("root/etc/example", "old\n");
        fixture.write_generation("etc/example", "new\n");
        fixture.write_generation("etc/nested/value", "nested\n");
        fixture.write_generation("shell", "");
        fixture.write_generation("cert", "");
        fixture.save(&fixture.manifest());
        fixture
    }

    fn text(&self, name: &str) -> String {
        self.generation.join(name).to_str().unwrap().to_owned()
    }

    fn manifest(&self) -> Value {
        json!({
            "formatVersion": 1, "stateVersion": "1", "runtime": "droid-nix",
            "name": "guest", "home": "/home/guest", "homeManager": null,
            "systemPath": self.text("sw"),
            "session": {
                "shell": self.text("shell"),
                "certificate": self.text("cert"),
                "terminfo": self.text("terminfo"),
            },
        })
    }

    fn save(&self, data: &Value) {
        fs::write(self.generation.join("manifest.json"), data.to_string()).unwrap();
    }

    fn write_runtime(&self, relative: &str, text: &str) {
        fs::write(self.runtime.join(relative), text).unwrap();
    }

    fn write_generation(&self, relative: &str, text: &str) {
        fs::write(self.generation.join(relative), text).unwrap();
    }

    fn edit(&self, change: impl FnOnce(&mut Value)) {
        let mut data = self.manifest();
        change(&mut data);
        self.save(&data);
    }
}

fn snapshot(root: &Path) -> Snapshot {
    fn visit(root: &Path, directory: &Path, out: &mut Snapshot) {
        let mut entries: Vec<_> = fs::read_dir(directory)
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .collect();
        entries.sort();
        for path in entries {
            let relative = path
                .strip_prefix(root)
                .unwrap()
                .to_str()
                .unwrap()
                .to_owned();
            let metadata = fs::symlink_metadata(&path).unwrap();
            let mode = metadata.mode() & 0o777;
            if metadata.file_type().is_symlink() {
                let target = fs::read_link(&path).unwrap();
                out.insert(
                    relative,
                    Entry::Link(target.as_os_str().as_bytes().to_vec()),
                );
            } else if metadata.is_dir() {
                out.insert(relative, Entry::Dir(mode));
                visit(root, &path, out);
            } else if metadata.is_file() {
                out.insert(relative, Entry::File(mode, fs::read(&path).unwrap()));
            } else {
                out.insert(relative, Entry::Special(mode));
            }
        }
    }
    let mut out = Snapshot::new();
    visit(root, root, &mut out);
    out
}

/// One outcome per attempt: the candidate path or the rejection text.
type Outcomes = Vec<Result<String, String>>;

fn run_reference(
    python: &str,
    script: &str,
    driver: &Path,
    fixture: &Fixture,
    attempts: usize,
) -> Outcomes {
    let output = Command::new(python)
        .arg("-I")
        .arg(driver)
        .arg(script)
        .arg(&fixture.runtime)
        .arg(&fixture.generation)
        .arg(attempts.to_string())
        .output()
        .expect("python reference starts");
    assert!(
        output.status.success(),
        "reference crashed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let parsed: Vec<Value> = serde_json::from_slice(&output.stdout).unwrap();
    parsed
        .into_iter()
        .map(|item| match item.get("ok") {
            Some(path) => Ok(path.as_str().unwrap().to_owned()),
            None => Err(item["error"].as_str().unwrap().to_owned()),
        })
        .collect()
}

fn run_rust(fixture: &Fixture, attempts: usize) -> Outcomes {
    (0..attempts)
        .map(|_| {
            prepare_with(&fixture.runtime, &fixture.generation, &|_| Ok(()))
                .map(|path| path.to_str().unwrap().to_owned())
                .map_err(|error| error.to_string())
        })
        .collect()
}

type Setup = fn(&Fixture);

struct Scenario {
    name: &'static str,
    attempts: usize,
    setup: Setup,
}

fn scenarios() -> Vec<Scenario> {
    fn scenario(name: &'static str, setup: Setup) -> Scenario {
        Scenario {
            name,
            attempts: 1,
            setup,
        }
    }
    vec![
        scenario("baseline", |_| {}),
        Scenario {
            name: "second attempt never overwrites",
            attempts: 2,
            setup: |_| {},
        },
        scenario("configuration file links are materialized", |f| {
            symlink(
                f.generation.join("etc/example"),
                f.generation.join("etc/linked"),
            )
            .unwrap();
        }),
        scenario("identity mismatch", |f| {
            f.edit(|d| {
                d["name"] = json!("other");
                d["home"] = json!("/home/other");
            });
        }),
        scenario("home differs from name", |f| {
            f.edit(|d| d["home"] = json!("/home/x"))
        }),
        scenario("uppercase user name", |f| {
            f.edit(|d| d["name"] = json!("Guest"))
        }),
        scenario("unsupported format version", |f| {
            f.edit(|d| d["formatVersion"] = json!(2));
        }),
        scenario("unsupported state version", |f| {
            f.edit(|d| d["stateVersion"] = json!("2"));
        }),
        scenario("unsupported runtime kind", |f| {
            f.edit(|d| d["runtime"] = json!("other"));
        }),
        scenario("reserved passwd file", |f| {
            f.write_generation("etc/passwd", "x\n")
        }),
        scenario("reserved group dangling link", |f| {
            symlink("/nonexistent", f.generation.join("etc/group")).unwrap();
        }),
        scenario("missing closure", |f| {
            fs::remove_file(f.generation.join("shell")).unwrap();
        }),
        scenario("directory symlink", |f| {
            symlink(f.generation.join("etc"), f.generation.join("etc/cycle")).unwrap();
        }),
        scenario("dangling file", |f| {
            symlink("/nonexistent", f.generation.join("etc/dangling")).unwrap();
        }),
        scenario("special file", |f| {
            let path = std::ffi::CString::new(f.generation.join("etc/fifo").as_os_str().as_bytes())
                .unwrap();
            assert_eq!(unsafe { libc::mkfifo(path.as_ptr(), 0o600) }, 0);
        }),
        scenario("overlay directory over base file", |f| {
            f.write_runtime("root/etc/clash", "file\n");
            fs::create_dir(f.generation.join("etc/clash")).unwrap();
        }),
        scenario("overlay file over base directory", |f| {
            fs::create_dir(f.runtime.join("root/etc/clash")).unwrap();
            f.write_generation("etc/clash", "file\n");
        }),
        scenario("home manager with activate script", |f| {
            fs::create_dir(f.generation.join("hm")).unwrap();
            f.write_generation("hm/activate", "");
            let path = f.text("hm");
            f.edit(|d| d["homeManager"] = json!(path));
        }),
        scenario("home manager without activate script", |f| {
            fs::create_dir(f.generation.join("hm")).unwrap();
            let path = f.text("hm");
            f.edit(|d| d["homeManager"] = json!(path));
        }),
        scenario("unsupported base runtime page size", |f| {
            f.write_runtime(
                "session.json",
                r#"{"schema": 1, "system": "aarch64-linux", "pageSize": 16384}"#,
            );
        }),
        scenario("unsupported base runtime system", |f| {
            f.write_runtime(
                "session.json",
                r#"{"schema": 1, "system": "x86_64-linux", "pageSize": 4096}"#,
            );
        }),
        scenario("duplicate passwd records", |f| {
            f.write_runtime(
                "root/etc/passwd",
                "guest:x:123:456:Guest:/home/guest:/bin/sh\nguest:x:124:456:Guest:/home/guest:/bin/sh\n",
            );
        }),
        scenario("malformed passwd record", |f| {
            f.write_runtime("root/etc/passwd", "guest:x:123:456:Guest:/home/guest\n");
        }),
        scenario("passwd record with another home", |f| {
            f.write_runtime(
                "root/etc/passwd",
                "guest:x:123:456:Guest:/home/elsewhere:/bin/sh\n",
            );
        }),
        scenario("candidate directory is a symlink", |f| {
            fs::create_dir(f.root.join("elsewhere")).unwrap();
            symlink(
                f.root.join("elsewhere"),
                f.runtime.join("system-candidates"),
            )
            .unwrap();
        }),
        scenario("gc root directory is a symlink", |f| {
            let roots = f
                .runtime
                .join("root/nix/var/nix/gcroots/termuxpp-system-candidates");
            fs::create_dir_all(roots.parent().unwrap()).unwrap();
            fs::create_dir(f.root.join("elsewhere")).unwrap();
            symlink(f.root.join("elsewhere"), roots).unwrap();
        }),
        scenario("base file permissions are normalized", |f| {
            use std::os::unix::fs::PermissionsExt;
            let path = f.runtime.join("root/etc/example");
            fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
        }),
        scenario("non-ascii manifest is canonicalized", |f| {
            f.edit(|d| {
                d["extra"] = json!({"\u{e9}": "\u{1F600}\n", "list": [1, true, null, "x\"y"]});
            });
        }),
        scenario("nested directories and many files", |f| {
            for index in 0..12 {
                fs::create_dir_all(f.generation.join(format!("etc/d{index}/inner"))).unwrap();
                f.write_generation(&format!("etc/d{index}/inner/f"), &format!("{index}\n"));
            }
        }),
    ]
}

#[test]
fn rust_prepare_matches_the_python_reference() {
    let Ok(script) = std::env::var("NIXPP_REFERENCE_PREPARE") else {
        eprintln!("skipped: NIXPP_REFERENCE_PREPARE is not set");
        return;
    };
    let python = std::env::var("NIXPP_REFERENCE_PYTHON").unwrap_or_else(|_| "python3".into());
    let scratch = tempfile::tempdir().unwrap();
    let driver = scratch.path().join("driver.py");
    fs::write(&driver, DRIVER).unwrap();
    // Both implementations run at the same path so that absolute paths stored
    // in candidates compare equal.
    let root = fs::canonicalize(scratch.path()).unwrap().join("fixture");
    unsafe { libc::umask(0o077) };

    let mut compared = 0;
    let mut accepted = 0;
    let mut failures = Vec::new();
    for scenario in scenarios() {
        let reference_fixture = Fixture::build(&root);
        (scenario.setup)(&reference_fixture);
        let reference_outcomes = run_reference(
            &python,
            &script,
            &driver,
            &reference_fixture,
            scenario.attempts,
        );
        let reference_tree = snapshot(&root);

        let rust_fixture = Fixture::build(&root);
        (scenario.setup)(&rust_fixture);
        let rust_outcomes = run_rust(&rust_fixture, scenario.attempts);
        let rust_tree = snapshot(&root);

        compared += 1;
        accepted += reference_outcomes.iter().filter(|o| o.is_ok()).count();
        if reference_outcomes != rust_outcomes {
            failures.push(format!(
                "{}: outcomes differ\n  reference: {reference_outcomes:?}\n  rust:      {rust_outcomes:?}",
                scenario.name
            ));
        }
        if reference_tree != rust_tree {
            let differing: Vec<_> = reference_tree
                .keys()
                .chain(rust_tree.keys())
                .filter(|key| reference_tree.get(*key) != rust_tree.get(*key))
                .collect();
            failures.push(format!(
                "{}: trees differ at {:?}",
                scenario.name,
                differing.iter().collect::<std::collections::BTreeSet<_>>()
            ));
        }
    }
    eprintln!("differential prepare: compared {compared} fixtures ({accepted} accepted attempts)");
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}
