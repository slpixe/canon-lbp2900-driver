// SPDX-License-Identifier: GPL-3.0-or-later
use lbp2900_rust::codec;
use std::{
    io::Write,
    process::{Command, Stdio},
};
#[test]
fn matches_c_encoder_byte_for_byte() {
    let Some(oracle) = std::env::var_os("LBP_C_ORACLE") else {
        eprintln!(
            "C differential test requires ./scripts/test-rust.sh; skipped in standalone cargo test"
        );
        return;
    };
    let mut seed = 7u32;
    for width in [1, 8, 17, 592, 1024] {
        for rows in [1, 2, 70, 256] {
            for pattern in 0..4 {
                for last in [false, true] {
                    let data: Vec<u8> = (0..width * rows)
                        .map(|i| match pattern {
                            0 => 0,
                            1 => 255,
                            2 => {
                                if i % 2 == 0 {
                                    0x55
                                } else {
                                    0xaa
                                }
                            }
                            _ => {
                                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                                (seed >> 24) as u8
                            }
                        })
                        .collect();
                    let rust = codec::compress(&data, width, rows, last).unwrap();
                    let mut child = Command::new(&oracle)
                        .args([
                            width.to_string(),
                            rows.to_string(),
                            u8::from(last).to_string(),
                        ])
                        .stdin(Stdio::piped())
                        .stdout(Stdio::piped())
                        .stderr(Stdio::piped())
                        .spawn()
                        .unwrap();
                    let mut stdin = child.stdin.take().unwrap();
                    let writer = std::thread::spawn(move || stdin.write_all(&data).unwrap());
                    let result = child.wait_with_output().unwrap();
                    writer.join().unwrap();
                    assert!(
                        result.status.success(),
                        "{}",
                        String::from_utf8_lossy(&result.stderr)
                    );
                    assert_eq!(
                        rust, result.stdout,
                        "width={width} rows={rows} pattern={pattern} last={last}"
                    );
                }
            }
        }
    }
}
