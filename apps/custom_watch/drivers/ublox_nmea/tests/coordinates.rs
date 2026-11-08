//! Coordinates outside the north-west quadrant the other fixtures sit in, and
//! the checksum forms the parser accepts or drops. Every expected value is
//! worked by hand from `ddmm.mmmm`: degrees + minutes / 60.
//! Run via `bin/watch-test.sh`.

use ublox_nmea::{Parser, Sentence};

fn parse_one(text: &str) -> Option<Sentence> {
    let mut p = Parser::new();
    text.bytes().filter_map(|b| p.feed(b)).next()
}

fn upper(body: &str) -> String {
    let c = body.bytes().fold(0u8, |c, b| c ^ b);
    format!("${}*{:02X}\r\n", body, c)
}

fn gga(lat: &str, ns: &str, lon: &str, ew: &str) -> (Option<f64>, Option<f64>) {
    let body = format!("GPGGA,073000.00,{lat},{ns},{lon},{ew},1,08,1.02,10.0,M,0.0,M,,");
    let Some(Sentence::Gga(g)) = parse_one(&upper(&body)) else {
        panic!("expected GGA for {lat},{ns},{lon},{ew}");
    };
    (g.lat_deg, g.lon_deg)
}

fn close(got: Option<f64>, want: f64) -> bool {
    got.is_some_and(|g| (g - want).abs() < 1e-9)
}

#[test]
fn south_and_east_are_negative_latitude_and_positive_longitude() {
    // Sydney: 33° 52.1' S, 151° 12.6' E.
    let (lat, lon) = gga("3352.1000", "S", "15112.6000", "E");
    assert!(close(lat, -(33.0 + 52.1 / 60.0)), "{lat:?}");
    assert!(close(lon, 151.0 + 12.6 / 60.0), "{lon:?}");
}

#[test]
fn rmc_carries_the_same_signs() {
    // Cape Town: 33° 55.5' S, 18° 25.4' E.
    let body = "GPRMC,073000.00,A,3355.5000,S,01825.4000,E,0.0,0.0,080726,,,A";
    let Some(Sentence::Rmc(r)) = parse_one(&upper(body)) else {
        panic!("expected RMC");
    };
    assert!(close(r.lat_deg, -(33.0 + 55.5 / 60.0)));
    assert!(close(r.lon_deg, 18.0 + 25.4 / 60.0));
}

#[test]
fn the_equator_prime_meridian_and_antimeridian_read_exactly() {
    let (lat, lon) = gga("0000.0000", "N", "00000.0000", "E");
    assert!(close(lat, 0.0) && close(lon, 0.0));
    let (_, lon) = gga("0000.0000", "S", "18000.0000", "W");
    assert!(close(lon, -180.0));
}

#[test]
fn an_unknown_hemisphere_letter_drops_that_coordinate_only() {
    // Hemisphere letters are upper-case in NMEA; anything else is unreadable
    // rather than guessed, and the other axis is unaffected.
    let (lat, lon) = gga("4000.9000", "n", "10516.2300", "W");
    assert_eq!(lat, None);
    assert!(close(lon, -(105.0 + 16.23 / 60.0)));
    let (lat, _) = gga("4000.9000", "", "10516.2300", "W");
    assert_eq!(lat, None);
}

#[test]
fn a_coordinate_too_short_to_hold_degrees_and_minutes_is_absent() {
    let (lat, lon) = gga("40", "N", "105", "W");
    assert_eq!(lat, None);
    assert_eq!(lon, None);
}

#[test]
fn a_lowercase_checksum_is_accepted() {
    // Altitude 1628.0 gives checksum 0x5E, so upper and lower case differ.
    let body = "GPGGA,073000.00,4000.9000,N,10516.2300,W,1,08,1.02,1628.0,M,-21.3,M,,";
    let c = body.bytes().fold(0u8, |c, b| c ^ b);
    let lower = format!("${}*{:02x}\r\n", body, c);
    assert_ne!(lower, upper(body), "the checksum has a letter in it");
    assert!(matches!(parse_one(&lower), Some(Sentence::Gga(_))));
}

#[test]
fn a_non_hex_or_missing_checksum_is_dropped() {
    let body = "GPGGA,073000.00,4000.9000,N,10516.2300,W,1,08,1.02,1624.0,M,-21.3,M,,";
    assert_eq!(parse_one(&format!("${body}*ZZ\r\n")), None);
    assert_eq!(parse_one(&format!("${body}*5\r\n")), None);
    assert_eq!(parse_one(&format!("${body}\r\n")), None);
}
