//! Property tests for the GNSS fix accumulator. Its input is whatever the
//! MAX-M10S's UART produced, reduced by the NMEA parser — so a sentence stream
//! can be partial, out of order, or a receiver that just lost its fix. The
//! invariant that matters on the wrist is that a position never outlives the
//! fix it came from: a stale lat/lon leaking into the next merge would put the
//! runner somewhere they were minutes ago. The same holds for the receiver's
//! accuracy estimate: a UBX-NAV-PVT's `hAcc` / `sAcc` may only ride a fix it
//! describes, and those numbers must reach the distance estimator unchanged.

mod support;

use proptest::prelude::*;
use support::check;
use ublox_nmea::ubx::{self, NavPvt};
use ublox_nmea::{GgaData, GstData, Parser, RmcData, Sentence, ZdaData};
use watch_core::fix::{Fix, FixAccumulator, PVT_MAX_AGE_S};
use watch_core::gps_distance::GpsDistanceEstimator;
use watch_core::record::{Recorder, MAX_SPEED_MPS};

fn a_coord() -> impl Strategy<Value = Option<f64>> {
    prop::option::of(prop_oneof![
        -90.0f64..90.0,
        Just(f64::NAN),
        Just(f64::INFINITY),
    ])
}

fn an_rmc() -> impl Strategy<Value = RmcData> {
    (
        prop::option::of(0u32..86_400),
        any::<bool>(),
        a_coord(),
        a_coord(),
        prop::option::of(-1e6f32..1e6),
        prop::option::of(-1e6f32..1e6),
        prop::option::of((0u8..=40, 0u8..=15, 2000u16..2100)),
    )
        .prop_map(
            |(time, valid, lat_deg, lon_deg, speed_mps, course_deg, date_dmy)| RmcData {
                time,
                valid,
                lat_deg,
                lon_deg,
                speed_mps,
                course_deg,
                date_dmy,
            },
        )
}

fn a_gga() -> impl Strategy<Value = GgaData> {
    (
        prop::option::of(0u32..86_400),
        a_coord(),
        a_coord(),
        any::<u8>(),
        any::<u8>(),
        prop::option::of(-1e6f32..1e6),
    )
        .prop_map(|(time, lat_deg, lon_deg, quality, sats, alt_m)| GgaData {
            time,
            lat_deg,
            lon_deg,
            quality,
            sats,
            alt_m,
        })
}

fn a_pvt() -> impl Strategy<Value = NavPvt> {
    (
        prop::option::of(0u32..86_400),
        0u8..=6,
        any::<bool>(),
        0f32..5_000.0,
        0f32..50.0,
    )
        .prop_map(
            |(time_of_day, fix_type, gnss_fix_ok, h_acc_m, s_acc_mps)| NavPvt {
                time_of_day,
                fix_type,
                gnss_fix_ok,
                h_acc_m,
                s_acc_mps,
                ..NavPvt::default()
            },
        )
}

/// The accumulator's freshness rule, restated: a usable PVT, no older than
/// [`PVT_MAX_AGE_S`] on the uptime clock, and no further apart in UTC time
/// of day (across midnight) when both sides carry one.
fn pvt_describes(pvt: &NavPvt, pvt_at_s: u32, rmc_tod: Option<u32>, rmc_at_s: u32) -> bool {
    let usable = pvt.gnss_fix_ok && (2..=4).contains(&pvt.fix_type);
    let fresh = rmc_at_s >= pvt_at_s && rmc_at_s - pvt_at_s <= PVT_MAX_AGE_S;
    let same_epoch = match (pvt.time_of_day, rmc_tod) {
        (Some(a), Some(b)) => {
            let d = a.abs_diff(b);
            d.min(86_400 - d) <= PVT_MAX_AGE_S
        }
        _ => true,
    };
    usable && fresh && same_epoch
}

fn a_sentence() -> impl Strategy<Value = Sentence> {
    prop_oneof![
        4 => an_rmc().prop_map(Sentence::Rmc),
        3 => a_gga().prop_map(Sentence::Gga),
        2 => a_pvt().prop_map(Sentence::NavPvt),
        1 => any::<u8>().prop_map(|sats_in_view| Sentence::Gsv { sats_in_view }),
        1 => Just(Sentence::Zda(ZdaData::default())),
        1 => Just(Sentence::Gst(GstData::default())),
        1 => Just(Sentence::Other),
    ]
}

#[test]
fn a_fix_never_outlives_the_sentence_it_came_from() {
    check(
        512,
        prop::collection::vec((a_sentence(), prop_oneof![any::<u32>(), 0u32..8]), 0..=24),
        |stream| {
            let mut acc = FixAccumulator::new();
            // The reference state a fix is only ever allowed to be built from.
            let mut armed_rmc: Option<RmcData> = None;
            let mut armed_gga: Option<GgaData> = None;
            let mut armed_pvt: Option<(NavPvt, u32)> = None;

            for (sentence, uptime_s) in &stream {
                match sentence {
                    Sentence::Rmc(rmc) if rmc.valid => armed_rmc = Some(*rmc),
                    Sentence::Rmc(_) => {
                        armed_rmc = None;
                        armed_gga = None;
                        armed_pvt = None;
                    }
                    Sentence::Gga(gga) if gga.quality > 0 => armed_gga = Some(*gga),
                    Sentence::NavPvt(pvt) => armed_pvt = Some((*pvt, *uptime_s)),
                    _ => {}
                }

                let Some(fix) = acc.apply(sentence, *uptime_s) else {
                    continue;
                };

                prop_assert_eq!(
                    fix.uptime_s,
                    *uptime_s,
                    "a fix must be stamped with the uptime it was assembled at"
                );
                let rmc = armed_rmc.expect("a fix requires a currently-valid RMC");
                // Compared by bit pattern, not by value: a generated NaN
                // coordinate is not equal to itself, and "the fix carried the
                // armed RMC's exact bytes through" is the claim.
                prop_assert_eq!(
                    Some(f64::to_bits(fix.lat_deg)),
                    rmc.lat_deg.map(f64::to_bits),
                    "the fix position is not the armed RMC's"
                );
                prop_assert_eq!(
                    Some(f64::to_bits(fix.lon_deg)),
                    rmc.lon_deg.map(f64::to_bits)
                );
                prop_assert_eq!(fix.time_of_day, rmc.time);
                prop_assert_eq!(fix.course_deg, rmc.course_deg);
                // The date rides the same RMC, behind the accumulator's
                // plausibility gate — a month 0 or day 40 the parser's digit
                // check cannot reject must read as absent, never as a date.
                prop_assert_eq!(
                    fix.date,
                    rmc.date_dmy
                        .filter(|(d, m, _)| (1..=31).contains(d) && (1..=12).contains(m))
                        .map(|(day, month, year)| watch_core::daylight::Date { year, month, day }),
                    "the fix date is not the armed RMC's gated date"
                );

                match armed_gga {
                    None => {
                        // Nothing has enriched the accumulator since the last
                        // void RMC, so the GGA-sourced fields must read as
                        // absent rather than carry a previous fix's numbers.
                        prop_assert_eq!(fix.sats, 0, "satellite count leaked from a cleared GGA");
                        prop_assert_eq!(fix.alt_m, None, "altitude leaked from a cleared GGA");
                    }
                    Some(gga) => {
                        prop_assert_eq!(fix.sats, gga.sats);
                        prop_assert_eq!(fix.alt_m, gga.alt_m);
                    }
                }

                // The accuracy is the latest PVT's, and only while it
                // describes this fix; otherwise it reads as absent rather
                // than as an older epoch's number.
                let expected = armed_pvt
                    .filter(|(pvt, at_s)| pvt_describes(pvt, *at_s, rmc.time, *uptime_s))
                    .map(|(pvt, _)| pvt);
                prop_assert_eq!(fix.h_acc_m, expected.map(|p| p.h_acc_m));
                prop_assert_eq!(fix.s_acc_mps, expected.map(|p| p.s_acc_mps));
            }
            Ok(())
        },
    );
}

#[test]
fn a_void_rmc_always_clears_the_accumulated_position() {
    // The receiver dropping to a void RMC is the "lost the fix" signal. No
    // amount of GGA enrichment afterwards may resurrect the last position.
    check(
        512,
        (
            an_rmc().prop_map(|mut r| {
                r.valid = true;
                r
            }),
            a_gga().prop_map(|mut g| {
                g.quality = g.quality.max(1);
                g
            }),
            prop::collection::vec(a_gga(), 0..=6),
            any::<u32>(),
        ),
        |(valid_rmc, good_gga, later_ggas, uptime_s)| {
            let mut acc = FixAccumulator::new();
            acc.apply(&Sentence::Gga(good_gga), uptime_s);
            acc.apply(&Sentence::Rmc(valid_rmc), uptime_s);

            let mut void = valid_rmc;
            void.valid = false;
            prop_assert_eq!(acc.apply(&Sentence::Rmc(void), uptime_s), None);

            for gga in &later_ggas {
                prop_assert_eq!(
                    acc.apply(&Sentence::Gga(*gga), uptime_s),
                    None,
                    "a GGA resurrected a position after the fix was lost"
                );
            }
            Ok(())
        },
    );
}

#[test]
fn a_fresh_pvt_rides_the_next_fix_and_a_stale_one_never_does() {
    // The receiver drains PVT and RMC in either order within an epoch, and
    // comes back from a power-down window with nothing fresh: the accuracy
    // may cross at most one epoch, never the sleep.
    check(
        512,
        (
            an_rmc().prop_map(|mut r| {
                r.valid = true;
                r.lat_deg = Some(40.0);
                r.lon_deg = Some(-105.0);
                r
            }),
            a_pvt().prop_map(|mut p| {
                p.gnss_fix_ok = true;
                p.fix_type = 3;
                p
            }),
            0u32..1_000_000,
            0u32..120,
        ),
        |(mut rmc, mut pvt, pvt_at_s, age_s)| {
            pvt.time_of_day = None;
            rmc.time = None;
            let mut acc = FixAccumulator::new();
            acc.apply(&Sentence::NavPvt(pvt), pvt_at_s);
            let fix = acc
                .apply(&Sentence::Rmc(rmc), pvt_at_s + age_s)
                .expect("a valid RMC with a position is a fix");
            if age_s <= PVT_MAX_AGE_S {
                prop_assert_eq!(fix.h_acc_m, Some(pvt.h_acc_m));
                prop_assert_eq!(fix.s_acc_mps, Some(pvt.s_acc_mps));
            } else {
                prop_assert_eq!(
                    fix.h_acc_m,
                    None,
                    "a {}-second-old hAcc rode the fix",
                    age_s
                );
                prop_assert_eq!(fix.s_acc_mps, None);
            }
            Ok(())
        },
    );
}

#[test]
fn a_pvt_from_another_utc_second_never_rides_the_fix() {
    check(
        512,
        (0u32..86_400, 2u32..86_399, 0f32..100.0),
        |(rmc_tod, offset_s, h_acc_m)| {
            let pvt_tod = (rmc_tod + offset_s) % 86_400;
            let apart = rmc_tod
                .abs_diff(pvt_tod)
                .min(86_400 - rmc_tod.abs_diff(pvt_tod));
            let pvt = NavPvt {
                time_of_day: Some(pvt_tod),
                fix_type: 3,
                gnss_fix_ok: true,
                h_acc_m,
                ..NavPvt::default()
            };
            let rmc = RmcData {
                time: Some(rmc_tod),
                valid: true,
                lat_deg: Some(40.0),
                lon_deg: Some(-105.0),
                ..RmcData::default()
            };
            let mut acc = FixAccumulator::new();
            acc.apply(&Sentence::NavPvt(pvt), 10);
            let fix = acc.apply(&Sentence::Rmc(rmc), 10).expect("fix");
            prop_assert_eq!(fix.h_acc_m, (apart <= PVT_MAX_AGE_S).then_some(h_acc_m));
            Ok(())
        },
    );
}

#[test]
fn a_pvt_without_a_usable_fix_never_lends_its_accuracy() {
    check(
        512,
        (a_pvt(), 0u8..=6, any::<bool>()),
        |(mut pvt, fix_type, gnss_fix_ok)| {
            pvt.fix_type = fix_type;
            pvt.gnss_fix_ok = gnss_fix_ok;
            pvt.time_of_day = None;
            let rmc = RmcData {
                valid: true,
                lat_deg: Some(40.0),
                lon_deg: Some(-105.0),
                ..RmcData::default()
            };
            let mut acc = FixAccumulator::new();
            acc.apply(&Sentence::NavPvt(pvt), 5);
            let fix = acc.apply(&Sentence::Rmc(rmc), 5).expect("fix");
            let usable = gnss_fix_ok && (2..=4).contains(&fix_type);
            prop_assert_eq!(fix.h_acc_m.is_some(), usable);
            prop_assert_eq!(fix.s_acc_mps.is_some(), usable);
            Ok(())
        },
    );
}

#[test]
fn the_recorder_hands_each_fixs_accuracy_to_the_estimator_unchanged() {
    // The recorder's distance must be exactly what the spec estimator credits
    // for the same fixes WITH their accuracies: a steady 3 m/s run north, so
    // the movement gate never pauses it, with an arbitrary hAcc / sAcc (or
    // none) on every fix. A recorder that dropped either number would credit
    // what the estimator credits for `None`, and differ.
    check(
        256,
        prop::collection::vec(
            (
                prop::option::of(prop_oneof![Just(0f32), 0f32..80.0]),
                prop::option::of(prop_oneof![Just(0f32), 0f32..3.0]),
            ),
            2..=40,
        ),
        |accuracies| {
            let mut rec = Recorder::new();
            rec.start(0);
            let mut reference = GpsDistanceEstimator::with_config(MAX_SPEED_MPS, 1.0, None);
            let mut expected = 0.0f64;
            for (i, (h_acc_m, s_acc_mps)) in accuracies.iter().enumerate() {
                let t = i as u32 + 1;
                let fix = Fix {
                    lat_deg: 40.0 + f64::from(t) * 3.0 / 111_195.0,
                    lon_deg: -105.0,
                    speed_mps: 3.0,
                    course_deg: Some(0.0),
                    sats: 9,
                    alt_m: None,
                    time_of_day: None,
                    date: None,
                    uptime_s: t,
                    h_acc_m: *h_acc_m,
                    s_acc_mps: *s_acc_mps,
                };
                rec.on_fix(&fix);
                expected += reference.add_fix(
                    f64::from(t),
                    fix.lat_deg,
                    fix.lon_deg,
                    h_acc_m.map(f64::from),
                    Some(3.0),
                    s_acc_mps.map(f64::from),
                    Some(0.0),
                );
            }
            prop_assert_eq!(rec.snapshot().distance_m, expected);
            Ok(())
        },
    );
}

#[test]
fn a_receiver_byte_stream_hands_the_fix_its_nav_pvt_accuracy() {
    // What the gps task feeds the accumulator once the runner valset is in:
    // a UBX-NAV-PVT and then the RMC of the same 07:30:00 epoch, as raw UART
    // bytes through the one parser.
    let mut payload = [0u8; ubx::NAV_PVT_PAYLOAD_LEN];
    payload[8..12].copy_from_slice(&[7, 30, 0, 0b0111]);
    payload[20] = 3;
    payload[21] = 1;
    payload[23] = 12;
    payload[40..44].copy_from_slice(&2_400u32.to_le_bytes());
    payload[60..64].copy_from_slice(&3_000i32.to_le_bytes());
    payload[68..72].copy_from_slice(&150u32.to_le_bytes());
    let mut stream = vec![0u8; ubx::FRAME_OVERHEAD + payload.len()];
    ubx::write_frame(ubx::CLASS_NAV, ubx::ID_NAV_PVT, &payload, &mut stream).expect("fits");
    stream.extend_from_slice(
        b"$GPRMC,073000.00,A,4000.9000,N,10516.2300,W,5.83,90.0,080726,,,A*4B\r\n",
    );

    let mut parser = Parser::new();
    let mut acc = FixAccumulator::new();
    let fixes: Vec<Fix> = stream
        .iter()
        .filter_map(|b| parser.feed(*b))
        .filter_map(|s| acc.apply(&s, 42))
        .collect();

    let [fix] = fixes[..] else {
        panic!("expected one fix, got {fixes:?}");
    };
    assert_eq!(fix.uptime_s, 42);
    assert_eq!(fix.h_acc_m, Some(2.4));
    assert_eq!(fix.s_acc_mps, Some(0.15));
}
