// SPDX-License-Identifier: GPL-3.0-or-later
use lbp2900_rust::{
    Error, Result, codec,
    job::{Driver, Event},
    page::{Header, Page, Raster},
    protocol::{self, Link, Transport},
    status::Status,
};
use std::{collections::VecDeque, time::Duration};
#[derive(Default)]
struct Mock {
    input: VecDeque<u8>,
    output: Vec<Vec<u8>>,
    time: Duration,
    fragment: usize,
    split: usize,
    offset: usize,
    cancel: bool,
    busy: bool,
    no_paper: bool,
    auto: bool,
    model: Vec<u8>,
    reads: usize,
}
impl Transport for Mock {
    fn write(&mut self, data: &[u8]) -> Result<()> {
        self.check()?;
        self.output.push(data.to_vec());
        if self.auto {
            let cmd = u16::from_le_bytes([data[0], data[1]]);
            if ![0xd0a9, 0xc0a0, 0xc0a4].contains(&cmd) {
                let mut payload = if cmd == protocol::CHKXSTATUS {
                    vec![0; 40]
                } else {
                    vec![0; 4]
                };
                if cmd == protocol::CHKSTATUS {
                    payload = vec![0; 2];
                }
                if cmd == protocol::CHKXSTATUS {
                    for i in [14, 16, 18, 20, 34] {
                        payload[i] = 1;
                    }
                    if self.busy {
                        payload[0] |= 0x80;
                    }
                    if self.no_paper {
                        payload[0] |= 2;
                        payload[18] = 0;
                        payload[8] |= 0x20;
                    }
                }
                if cmd == 0xa2a0 {
                    payload[2] = 0x34;
                    payload[3] = 0x12;
                }
                self.input.extend(protocol::packet(cmd, &payload)?);
            }
        }
        Ok(())
    }
    fn read(&mut self, out: &mut [u8], _: Duration) -> Result<usize> {
        self.reads += 1;
        let mut n = out.len().min(self.input.len()).min(if self.fragment == 0 {
            usize::MAX
        } else {
            self.fragment
        });
        if self.split > self.offset {
            n = n.min(self.split - self.offset);
        }
        self.offset += n;
        for byte in out.iter_mut().take(n) {
            *byte = self.input.pop_front().unwrap();
        }
        Ok(n)
    }
    fn device_id(&mut self) -> Result<Vec<u8>> {
        Ok(if self.model.is_empty() {
            b"MFG:Canon;MDL:LBP2900;".to_vec()
        } else {
            self.model.clone()
        })
    }
    fn now(&self) -> Duration {
        self.time
    }
    fn check(&self) -> Result<()> {
        if self.cancel {
            Err(Error::Cancelled)
        } else {
            Ok(())
        }
    }
    fn delay(&mut self, d: Duration) -> Result<()> {
        self.time += d;
        self.check()
    }
    fn timestamp(&self) -> Result<[u16; 6]> {
        Ok([126, 8, 13, 12, 34, 56])
    }
}
fn header() -> Header {
    let mut h = Header {
        values: [
            8, 2, 1, 842, 1, 1, 1, 0, 3, 1, 1, 600, 600, 0, 0, 28, 0, 0, 0, 0,
        ],
        media: [0; 64],
    };
    h.media[..2].copy_from_slice(b"A4");
    h
}
struct Input {
    pages: usize,
    remaining: usize,
    truncate: bool,
}
impl Raster for Input {
    fn header(&mut self) -> Result<Option<Header>> {
        if self.pages == 0 {
            return Ok(None);
        }
        self.pages -= 1;
        self.remaining = 2;
        Ok(Some(header()))
    }
    fn read_line(&mut self, out: &mut [u8]) -> Result<()> {
        if self.truncate || self.remaining == 0 {
            return Err(Error::Truncated);
        }
        self.remaining -= 1;
        out.fill(0);
        Ok(())
    }
}
#[test]
fn commands_and_limits() {
    assert_eq!(
        protocol::packet(0xa1a1, &[1, 2]).unwrap(),
        [0xa1, 0xa1, 6, 0, 1, 2]
    );
    assert!(protocol::packet(1, &vec![0; 65531]).is_ok());
    assert_eq!(protocol::packet(1, &vec![0; 65532]), Err(Error::Capacity));
    assert_eq!(
        protocol::combined(1, &[(2, &[3])]).unwrap(),
        [1, 0, 9, 0, 2, 0, 5, 0, 3]
    );
    assert_eq!(
        protocol::combined(1, &[(2, &vec![0; 65531])]),
        Err(Error::Capacity)
    );
}
#[test]
fn fragmented_replies_and_capacity() {
    for size in [2, 4, 8, 40, 1000, 65531] {
        for fragment in [1, 3, 6, 4096, 65535] {
            let payload = vec![0x57; size];
            let mock = Mock {
                input: protocol::packet(0xa1a1, &payload).unwrap().into(),
                fragment,
                ..Default::default()
            };
            assert_eq!(
                Link { io: mock }.request(0xa1a1, &[], size).unwrap(),
                payload
            );
        }
    }
    let mock = Mock {
        input: protocol::packet(1, &[0; 8]).unwrap().into(),
        ..Default::default()
    };
    assert_eq!(Link { io: mock }.request(1, &[], 7), Err(Error::Capacity));
}
#[test]
fn device_fixture_is_independent_of_fragmentation() {
    let wire: Vec<u8> = include_str!("../../tests/fixtures/lbp2900-ident.hex")
        .split_whitespace()
        .map(|s| u8::from_str_radix(s, 16).unwrap())
        .collect();
    assert_eq!(wire.len(), 56);
    for mode in 0..2 {
        for n in 1..=56 {
            let mut input: VecDeque<u8> = wire.clone().into();
            input.extend([0xa1, 0xa1, 6, 0, 0, 0]);
            let mut link = Link {
                io: Mock {
                    input,
                    split: if mode == 0 { n } else { 0 },
                    fragment: if mode == 1 { n } else { 0 },
                    ..Default::default()
                },
            };
            assert_eq!(link.request(0xa1a1, &[], 52).unwrap(), wire[4..]);
            assert_eq!(link.io.input.len(), 6);
            link.io.split = 0;
            assert_eq!(link.request(0xa1a1, &[], 2).unwrap(), [0, 0]);
            assert!(link.io.input.is_empty());
        }
    }
}
#[test]
fn undocumented_bcd_short_reply_is_rejected() {
    for fragment in 1..=44 {
        let mut wire = vec![0xa8, 0xa0, 0x44, 0];
        wire.extend_from_slice(&[0; 40]);
        let mock = Mock {
            input: wire.into(),
            fragment,
            ..Default::default()
        };
        assert_eq!(
            Link { io: mock }.request(0xa0a8, &[], 100),
            Err(Error::Truncated)
        );
    }
}
#[test]
fn rejects_bad_packets() {
    for (wire, error) in [
        (vec![1, 0, 6, 0, 0, 0], Error::UnexpectedCommand),
        (vec![2, 0, 5, 0, 0, 0], Error::InvalidPacket),
        (vec![2, 0, 9, 0, 0, 0], Error::Truncated),
        (vec![2, 0], Error::Truncated),
    ] {
        assert_eq!(
            Link {
                io: Mock {
                    input: wire.into(),
                    ..Default::default()
                }
            }
            .request(2, &[], 8),
            Err(error)
        );
    }
    let mut link = Link {
        io: Mock {
            cancel: true,
            ..Default::default()
        },
    };
    assert_eq!(link.request(2, &[], 8), Err(Error::Cancelled));
    assert!(link.io.output.is_empty());
}
#[test]
fn status_truncation_does_not_mutate() {
    for size in 0..80 {
        for extended in [false, true] {
            let mut status = Status {
                words: [42; 7],
                ..Default::default()
            };
            let before = status;
            let result = status.update(&vec![0; size], extended);
            let valid = if extended {
                size >= 40
            } else {
                size == 2 || size == 10
            };
            assert_eq!(result.is_ok(), valid);
            if !valid {
                assert_eq!(status, before);
            }
        }
    }
    let bytes: Vec<u8> = (0..40).collect();
    let mut status = Status::default();
    status.update(&bytes, true).unwrap();
    assert_eq!(
        status.words,
        [0x100, 0x908, 0xb0a, 0xd0c, 0x1918, 0x1f1e, 0x2726]
    );
    assert_eq!(
        (
            status.decoding,
            status.printing,
            status.out,
            status.completed,
            status.received
        ),
        (0xf0e, 0x1110, 0x1312, 0x1514, 0x2322)
    );
    status.update(&[0, 0], false).unwrap();
    assert_eq!(status.received, 0x2322);
}
#[test]
fn strict_model_scope() {
    for id in [b"MDL:LBP2900;".as_slice(), b"  MODEL:LBP2900;  "] {
        assert!(protocol::identify(id).is_ok());
    }
    for id in [
        b"MDL:LBP3000;".as_slice(),
        b"MDL:LBP2900\0;",
        b"MDL:LBP2900X;",
        b"",
        b"MDL:\xff;",
    ] {
        assert_eq!(protocol::identify(id), Err(Error::UnsupportedPrinter));
    }
    assert!(protocol::identify(&vec![b'x'; 4097]).is_err());
}
#[test]
fn validates_raster_before_allocation() {
    assert!(Page::from_header(&header()).is_ok());
    for (index, value) in [
        (0, 0),
        (0, 8193),
        (1, 12001),
        (2, 0),
        (2, 1025),
        (3, 1441),
        (4, 0),
        (4, 257),
        (5, 8),
        (6, 8),
        (7, 1),
        (8, 0),
        (9, 3),
        (10, 2),
        (11, 300),
        (12, 300),
        (13, 7),
        (14, 2),
        (15, 64),
        (16, 2),
        (17, 65536),
        (18, 65536),
    ] {
        let mut h = header();
        h.values[index] = value;
        assert!(Page::from_header(&h).is_err(), "{index}={value}");
    }
}
#[test]
fn codec_rejects_lengths_and_exhaustion() {
    for (width, rows, len) in [
        (0, 1, 1),
        (1025, 1, 1025),
        (1, 0, 1),
        (1, 257, 257),
        (2, 2, 3),
    ] {
        assert_eq!(
            codec::compress(&vec![0; len], width, rows, false),
            Err(Error::InvalidRaster)
        );
    }
    assert_eq!(
        codec::compress_bounded(&[0], 1, 1, false, 1),
        Err(Error::Capacity)
    );
    assert_eq!(codec::compress(&[0], 1, 1, false).unwrap().len() % 4, 0);
}
#[test]
fn full_job_and_page_accounting() {
    let mut d = Driver::new(Mock {
        auto: true,
        ..Default::default()
    });
    let mut events = Vec::new();
    d.print(
        &mut Input {
            pages: 2,
            remaining: 0,
            truncate: false,
        },
        |e| events.push(e),
    )
    .unwrap();
    assert_eq!(
        events
            .iter()
            .filter(|e| matches!(e, Event::PageCompleted(_)))
            .count(),
        2
    );
    assert_eq!(events.last(), Some(&Event::PageCompleted(2)));
    assert_eq!(
        &d.link.io.output.last().unwrap()[..2],
        &0xe0a9u16.to_le_bytes()
    );
}
#[test]
fn failure_never_reports_a_completed_page() {
    for (busy, no_paper, truncate, model, error) in [
        (true, false, false, vec![], Error::Timeout),
        (false, true, false, vec![], Error::RetryLimit),
        (false, false, true, vec![], Error::Truncated),
        (
            false,
            false,
            false,
            b"MDL:LBP3000;".to_vec(),
            Error::UnsupportedPrinter,
        ),
    ] {
        let mut d = Driver::new(Mock {
            auto: true,
            busy,
            no_paper,
            model,
            ..Default::default()
        });
        let mut events = vec![];
        assert_eq!(
            d.print(
                &mut Input {
                    pages: 1,
                    remaining: 0,
                    truncate
                },
                |e| events.push(e)
            ),
            Err(error)
        );
        assert!(!events.iter().any(|e| matches!(e, Event::PageCompleted(_))));
        assert!(d.link.io.time < Duration::from_secs(400));
    }
    let mut d = Driver::new(Mock {
        auto: true,
        ..Default::default()
    });
    assert_eq!(
        d.print(
            &mut Input {
                pages: 0,
                remaining: 0,
                truncate: false
            },
            |_| {}
        ),
        Err(Error::NoPages)
    );
    assert!(d.link.io.output.is_empty());
}
