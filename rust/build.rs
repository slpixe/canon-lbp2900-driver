// SPDX-License-Identifier: GPL-3.0-or-later
use std::{env, path::PathBuf, process::Command};
fn main() {
    println!("cargo:rerun-if-changed=adapter/cups.c");
    println!("cargo:rerun-if-env-changed=MACOSX_DEPLOYMENT_TARGET");
    if env::var_os("CARGO_FEATURE_CUPS").is_none() {
        return;
    }
    assert_eq!(
        env::var("HOST").unwrap(),
        env::var("TARGET").unwrap(),
        "CUPS adapter requires a native build"
    );
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let mac = env::var("CARGO_CFG_TARGET_OS").unwrap() == "macos";
    let mut cc = if mac {
        let mut c = Command::new("xcrun");
        c.arg("clang");
        c
    } else {
        Command::new("cc")
    };
    cc.args([
        "-std=c11",
        "-D_POSIX_C_SOURCE=200809L",
        "-O2",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-fstack-protector-strong",
        "-D_FORTIFY_SOURCE=2",
    ]);
    if mac {
        cc.args(["-D_DARWIN_C_SOURCE", "-mmacosx-version-min=15.0"]);
    }
    assert!(
        cc.arg("-c")
            .arg("adapter/cups.c")
            .arg("-o")
            .arg(out.join("cups.o"))
            .status()
            .unwrap()
            .success()
    );
    assert!(
        Command::new("ar")
            .arg("crs")
            .arg(out.join("liblbp_cups.a"))
            .arg(out.join("cups.o"))
            .status()
            .unwrap()
            .success()
    );
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=lbp_cups");
    println!("cargo:rustc-link-lib=cups");
}
