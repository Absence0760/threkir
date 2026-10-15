//! Host-side UBX encoder + decoder tests. Run via `bin/watch-test.sh` from the repo
//! root, or `cargo test --target <HOST_TRIPLE> -p ublox_nmea` from anywhere.

use ublox_nmea::{ubx, Parser, Sentence};

/// A published known-good UBX frame, independent of any byte this crate
/// produces: the UBX-CFG-RATE example (1000 ms measurement rate, nav rate 1,
/// UTC aligned) that appears across u-blox integration guides —
/// `B5 62 06 08 06 00 E8 03 01 00 01 00` with Fletcher checksum `01 39`.
const CFG_RATE_1HZ: [u8; 14] = [
    0xB5, 0x62, 0x06, 0x08, 0x06, 0x00, 0xE8, 0x03, 0x01, 0x00, 0x01, 0x00, 0x01, 0x39,
];

#[test]
fn checksum_matches_the_published_cfg_rate_vector() {
    // Checksum runs over class..payload — sync chars and the checksum itself
    // excluded.
    assert_eq!(ubx::checksum(&CFG_RATE_1HZ[2..12]), (0x01, 0x39));
}

#[test]
fn write_frame_reproduces_the_published_vector() {
    let mut out = [0u8; CFG_RATE_1HZ.len()];
    let n = ubx::write_frame(0x06, 0x08, &CFG_RATE_1HZ[6..12], &mut out);
    assert_eq!(n, Some(CFG_RATE_1HZ.len()));
    assert_eq!(out, CFG_RATE_1HZ);
}

#[test]
fn write_frame_encodes_the_length_little_endian() {
    // A 300-byte payload exercises both length bytes: 300 = 0x012C.
    let payload = [0u8; 300];
    let mut out = [0u8; 308];
    assert_eq!(ubx::write_frame(0x01, 0x02, &payload, &mut out), Some(308));
    assert_eq!(&out[4..6], &[0x2C, 0x01]);
}

#[test]
fn write_frame_handles_an_empty_payload() {
    // Smallest legal frame: framing + checksum only. Checksum still covers
    // class/id/length.
    let mut out = [0u8; ubx::FRAME_OVERHEAD];
    assert_eq!(
        ubx::write_frame(0x0A, 0x04, &[], &mut out),
        Some(ubx::FRAME_OVERHEAD)
    );
    let (ck_a, ck_b) = ubx::checksum(&out[2..6]);
    assert_eq!(&out[..6], &[0xB5, 0x62, 0x0A, 0x04, 0x00, 0x00]);
    assert_eq!(&out[6..], &[ck_a, ck_b]);
}

#[test]
fn write_frame_refuses_a_too_small_buffer() {
    let mut out = [0u8; ubx::PMREQ_FRAME_LEN - 1];
    assert_eq!(ubx::write_frame(0x02, 0x41, &[0; 16], &mut out), None);
}

#[test]
fn write_frame_refuses_a_payload_past_the_length_field() {
    // The u16 length field caps a payload at 65535 bytes; longer must be
    // refused, never silently truncated into a valid-looking frame.
    let payload = vec![0u8; u16::MAX as usize + 1];
    let mut out = vec![0u8; payload.len() + ubx::FRAME_OVERHEAD];
    assert_eq!(ubx::write_frame(0x02, 0x41, &payload, &mut out), None);
}

#[test]
fn pmreq_frame_bytes_are_pinned() {
    // Derived by hand from the UBX protocol spec (M10 interface description):
    // extended 16-byte RXM-PMREQ payload — version 0 + reserved, duration
    // 10 000 ms, flags = backup (bit 1), wakeupSources = uartrx (bit 3) —
    // with the 8-bit Fletcher checksum computed over class..payload.
    let expected: [u8; ubx::PMREQ_FRAME_LEN] = [
        0xB5, 0x62, // sync
        0x02, 0x41, // class RXM, id PMREQ
        0x10, 0x00, // length 16, little-endian
        0x00, 0x00, 0x00, 0x00, // version 0 + reserved[3]
        0x10, 0x27, 0x00, 0x00, // duration 10 000 ms, little-endian
        0x02, 0x00, 0x00, 0x00, // flags: backup
        0x08, 0x00, 0x00, 0x00, // wakeupSources: uartrx
        0x94, 0xB8, // Fletcher checksum
    ];
    assert_eq!(ubx::pmreq_backup(10_000), expected);
}

#[test]
fn pmreq_duration_is_little_endian() {
    let frame = ubx::pmreq_backup(0x0102_0304);
    assert_eq!(&frame[10..14], &[0x04, 0x03, 0x02, 0x01]);
}

#[test]
fn pmreq_never_encodes_an_unbounded_sleep() {
    // Duration 0 means "no time limit" to the receiver — with a lost wake
    // byte that is a receiver asleep forever. A zero request must clamp to
    // the shortest bounded sleep instead.
    let frame = ubx::pmreq_backup(0);
    assert_eq!(&frame[10..14], &[0x01, 0x00, 0x00, 0x00]);
}

#[test]
fn pmreq_checksum_stays_consistent_for_any_duration() {
    for duration_ms in [1, 999, 57_000, u32::MAX] {
        let frame = ubx::pmreq_backup(duration_ms);
        let (ck_a, ck_b) = ubx::checksum(&frame[2..ubx::PMREQ_FRAME_LEN - 2]);
        assert_eq!(
            &frame[ubx::PMREQ_FRAME_LEN - 2..],
            &[ck_a, ck_b],
            "checksum drifted at duration {duration_ms}"
        );
    }
}

#[test]
fn wake_byte_is_the_documented_dummy() {
    // 0xFF is what u-blox documents as the byte a sleeping receiver consumes
    // without parsing; it must also never look like NMEA or UBX framing.
    assert_eq!(ubx::WAKE_BYTE, 0xFF);
    assert_ne!(ubx::WAKE_BYTE, b'$');
    assert_ne!(ubx::WAKE_BYTE, ubx::SYNC1);
}

/// The runner configuration, byte for byte: CFG-VALSET (06 8A), 14-byte
/// payload, version 0, layers RAM|BBR (0x03), then CFG-NAVSPG-DYNMODEL
/// (0x20110021, little-endian) = PED (3) and CFG-MSGOUT-UBX_NAV_PVT_UART1
/// (0x20910007) = 1. Key ids and the PED value are from the M10 SPG 5.10
/// interface description (UBX-21035062); the checksum was computed by hand
/// outside this crate.
const RUNNER_CFG: [u8; 22] = [
    0xB5, 0x62, 0x06, 0x8A, 0x0E, 0x00, 0x00, 0x03, 0x00, 0x00, 0x21, 0x00, 0x11, 0x20, 0x03, 0x07,
    0x00, 0x91, 0x20, 0x01, 0xAF, 0x78,
];

#[test]
fn cfg_valset_runner_is_the_documented_frame() {
    assert_eq!(ubx::cfg_valset_runner(), RUNNER_CFG);
    assert_eq!(ubx::RUNNER_CFG_FRAME_LEN, RUNNER_CFG.len());
}

#[test]
fn cfg_valset_runner_selects_pedestrian_not_wrist() {
    // WRIST is "not available in all products" (UBX-21035062) and a VALSET
    // with one invalid value NAKs as a whole, taking the NAV-PVT enable with
    // it. PED is the model until a bench run shows this module takes WRIST.
    let frame = ubx::cfg_valset_runner();
    assert_eq!(frame[14], ubx::DYNMODEL_PEDESTRIAN);
    assert_eq!(ubx::DYNMODEL_PEDESTRIAN, 3);
    assert_ne!(frame[14], ubx::DYNMODEL_WRIST);
    assert_ne!(frame[14], ubx::DYNMODEL_PORTABLE);
}

#[test]
fn cfg_valset_runner_checksum_covers_class_through_payload() {
    let frame = ubx::cfg_valset_runner();
    let n = frame.len();
    assert_eq!(
        ubx::checksum(&frame[2..n - 2]),
        (frame[n - 2], frame[n - 1])
    );
}

/// A NAV-PVT payload with the fields the firmware reads set to `fields`, and
/// everything else zero.
struct Pvt {
    hms: (u8, u8, u8),
    valid: u8,
    fix_type: u8,
    flags: u8,
    num_sv: u8,
    lon_e7: i32,
    lat_e7: i32,
    h_acc_mm: u32,
    g_speed_mms: i32,
    s_acc_mms: u32,
}

fn pvt_payload(f: &Pvt) -> [u8; ubx::NAV_PVT_PAYLOAD_LEN] {
    let mut p = [0u8; ubx::NAV_PVT_PAYLOAD_LEN];
    p[0..4].copy_from_slice(&123_456u32.to_le_bytes());
    p[8] = f.hms.0;
    p[9] = f.hms.1;
    p[10] = f.hms.2;
    p[11] = f.valid;
    p[20] = f.fix_type;
    p[21] = f.flags;
    p[23] = f.num_sv;
    p[24..28].copy_from_slice(&f.lon_e7.to_le_bytes());
    p[28..32].copy_from_slice(&f.lat_e7.to_le_bytes());
    p[40..44].copy_from_slice(&f.h_acc_mm.to_le_bytes());
    p[60..64].copy_from_slice(&f.g_speed_mms.to_le_bytes());
    p[68..72].copy_from_slice(&f.s_acc_mms.to_le_bytes());
    p
}

const OPEN_SKY: Pvt = Pvt {
    hms: (7, 30, 5),
    valid: 0b0111,
    fix_type: 3,
    flags: 0b1,
    num_sv: 17,
    lon_e7: -1_052_705_000,
    lat_e7: 400_150_000,
    h_acc_mm: 2_350,
    g_speed_mms: 3_120,
    s_acc_mms: 180,
};

fn framed(class: u8, id: u8, payload: &[u8]) -> Vec<u8> {
    let mut out = vec![0u8; ubx::FRAME_OVERHEAD + payload.len()];
    ubx::write_frame(class, id, payload, &mut out).expect("fits");
    out
}

#[test]
fn nav_pvt_decodes_the_fields_the_estimator_reads() {
    let pvt = ubx::NavPvt::decode(&pvt_payload(&OPEN_SKY)).expect("92 bytes");
    assert_eq!(pvt.itow_ms, 123_456);
    assert_eq!(pvt.time_of_day, Some(7 * 3600 + 30 * 60 + 5));
    assert_eq!(pvt.fix_type, 3);
    assert!(pvt.gnss_fix_ok);
    assert_eq!(pvt.num_sv, 17);
    assert!((pvt.lat_deg - 40.015).abs() < 1e-9);
    assert!((pvt.lon_deg - -105.2705).abs() < 1e-9);
    assert!((pvt.h_acc_m - 2.35).abs() < 1e-6);
    assert!((pvt.g_speed_mps - 3.12).abs() < 1e-6);
    assert!((pvt.s_acc_mps - 0.18).abs() < 1e-6);
}

#[test]
fn nav_pvt_without_valid_time_reports_no_time_of_day() {
    let pvt = ubx::NavPvt::decode(&pvt_payload(&Pvt {
        valid: 0b0001,
        ..OPEN_SKY
    }))
    .expect("decodes");
    assert_eq!(pvt.time_of_day, None);
    assert!(
        !ubx::NavPvt::decode(&pvt_payload(&Pvt {
            flags: 0,
            ..OPEN_SKY
        }))
        .expect("decodes")
        .gnss_fix_ok
    );
}

#[test]
fn nav_pvt_refuses_a_payload_of_the_wrong_length() {
    assert_eq!(ubx::NavPvt::decode(&[0u8; 84]), None);
    assert_eq!(ubx::NavPvt::decode(&[0u8; 93]), None);
}

#[test]
fn the_parser_delivers_a_nav_pvt_frame_between_nmea_sentences() {
    let rmc = b"$GPRMC,073000.00,A,4000.9000,N,10516.2300,W,5.83,90.0,080726,,,A*4B\r\n";
    let mut stream = rmc.to_vec();
    stream.extend(framed(
        ubx::CLASS_NAV,
        ubx::ID_NAV_PVT,
        &pvt_payload(&OPEN_SKY),
    ));
    stream.extend_from_slice(rmc);
    let mut p = Parser::new();
    let out: Vec<Sentence> = stream.iter().filter_map(|b| p.feed(*b)).collect();
    assert_eq!(out.len(), 3, "{out:?}");
    assert!(matches!(out[0], Sentence::Rmc(_)));
    assert!(matches!(out[1], Sentence::NavPvt(v) if v.num_sv == 17));
    assert!(matches!(out[2], Sentence::Rmc(_)));
}

#[test]
fn nmea_framing_bytes_inside_a_ubx_payload_cost_nothing() {
    // `$`, CR and LF are ordinary payload bytes to UBX. The NMEA side starts
    // a bogus sentence on the `$` and drops it on the checksum; the frame and
    // the sentence after it both survive.
    let mut payload = pvt_payload(&OPEN_SKY);
    payload[80..84].copy_from_slice(b"$\r\n$");
    let rmc = b"$GPRMC,073000.00,A,4000.9000,N,10516.2300,W,5.83,90.0,080726,,,A*4B\r\n";
    let mut stream = framed(ubx::CLASS_NAV, ubx::ID_NAV_PVT, &payload);
    stream.extend_from_slice(rmc);
    let mut p = Parser::new();
    let out: Vec<Sentence> = stream.iter().filter_map(|b| p.feed(*b)).collect();
    assert_eq!(out.len(), 2, "{out:?}");
    assert!(matches!(out[0], Sentence::NavPvt(_)));
    assert!(matches!(out[1], Sentence::Rmc(_)));
}

#[test]
fn the_parser_reports_the_valset_ack_and_nak() {
    // UBX-ACK-ACK for CFG-VALSET: B5 62 05 01 02 00 06 8A + checksum 98 C1.
    let ack = [0xB5, 0x62, 0x05, 0x01, 0x02, 0x00, 0x06, 0x8A, 0x98, 0xC1];
    let mut p = Parser::new();
    let out: Vec<Sentence> = ack.iter().filter_map(|b| p.feed(*b)).collect();
    assert_eq!(
        out,
        vec![Sentence::UbxAck {
            class: ubx::CLASS_CFG,
            id: ubx::ID_VALSET,
            acked: true
        }]
    );
    let nak = framed(
        ubx::CLASS_ACK,
        ubx::ID_ACK_NAK,
        &[ubx::CLASS_CFG, ubx::ID_VALSET],
    );
    let out: Vec<Sentence> = nak.iter().filter_map(|b| p.feed(*b)).collect();
    assert!(matches!(out[..], [Sentence::UbxAck { acked: false, .. }]));
}

#[test]
fn a_ubx_frame_with_a_bad_checksum_yields_nothing() {
    let mut frame = framed(ubx::CLASS_NAV, ubx::ID_NAV_PVT, &pvt_payload(&OPEN_SKY));
    let n = frame.len();
    frame[n - 1] ^= 0x01;
    let mut p = Parser::new();
    assert!(frame.iter().all(|b| p.feed(*b).is_none()));
}

#[test]
fn an_oversized_length_is_abandoned_at_the_length_field() {
    // A corrupted length must not hold the assembler: a frame announcing more
    // than it buffers is dropped at once, so the NAV-PVT right behind it
    // still decodes.
    let mut stream = vec![0xB5, 0x62, 0x01, 0x07, 0xFF, 0xFF];
    stream.extend(framed(
        ubx::CLASS_NAV,
        ubx::ID_NAV_PVT,
        &pvt_payload(&OPEN_SKY),
    ));
    let mut p = Parser::new();
    let out: Vec<Sentence> = stream.iter().filter_map(|b| p.feed(*b)).collect();
    assert!(matches!(out[..], [Sentence::NavPvt(_)]), "{out:?}");
}
