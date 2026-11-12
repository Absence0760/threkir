//! A failed SPI write must leave the framebuffer dirty, so the next flush
//! repaints what never reached the glass, and must still drop the
//! active-HIGH chip select so the panel is not left mid-frame.
//! Run via `bin/watch-test.sh`.

use std::convert::Infallible;

use embedded_hal::digital::{ErrorType as PinErrorType, OutputPin};
use embedded_hal::spi::{Error, ErrorKind, ErrorType as SpiErrorType, SpiBus};
use sharp_mip::{Framebuffer, SharpMip, HEIGHT};

#[derive(Debug)]
struct BusFault;

impl Error for BusFault {
    fn kind(&self) -> ErrorKind {
        ErrorKind::Other
    }
}

/// Accepts `ok_writes` writes, then fails every one after.
struct FlakySpi {
    ok_writes: usize,
    writes: usize,
}

impl FlakySpi {
    fn failing_after(ok_writes: usize) -> Self {
        Self {
            ok_writes,
            writes: 0,
        }
    }
}

impl SpiErrorType for FlakySpi {
    type Error = BusFault;
}

impl SpiBus for FlakySpi {
    fn read(&mut self, _words: &mut [u8]) -> Result<(), BusFault> {
        unimplemented!("display is write-only")
    }
    fn write(&mut self, _words: &[u8]) -> Result<(), BusFault> {
        self.writes += 1;
        if self.writes > self.ok_writes {
            Err(BusFault)
        } else {
            Ok(())
        }
    }
    fn transfer(&mut self, _r: &mut [u8], _w: &[u8]) -> Result<(), BusFault> {
        unimplemented!("display is write-only")
    }
    fn transfer_in_place(&mut self, _words: &mut [u8]) -> Result<(), BusFault> {
        unimplemented!("display is write-only")
    }
    fn flush(&mut self) -> Result<(), BusFault> {
        Ok(())
    }
}

#[derive(Default)]
struct MockCs {
    transitions: Vec<bool>,
}

impl PinErrorType for MockCs {
    type Error = Infallible;
}

impl OutputPin for MockCs {
    fn set_low(&mut self) -> Result<(), Infallible> {
        self.transitions.push(false);
        Ok(())
    }
    fn set_high(&mut self) -> Result<(), Infallible> {
        self.transitions.push(true);
        Ok(())
    }
}

fn dirty_lines(fb: &Framebuffer) -> usize {
    (0..HEIGHT).filter(|&y| fb.is_dirty(y)).count()
}

#[test]
fn a_flush_that_fails_on_the_first_write_keeps_every_line_dirty() {
    let mut lcd = SharpMip::new(FlakySpi::failing_after(0), MockCs::default());
    let mut fb = Framebuffer::new();
    fb.set_pixel(3, 5, true);
    let dirty_before = dirty_lines(&fb);
    assert!(dirty_before > 0);

    assert!(lcd.flush(&mut fb).is_err());
    assert_eq!(dirty_lines(&fb), dirty_before, "nothing reached the glass");

    let (_, cs) = lcd.into_parts();
    assert_eq!(cs.transitions, vec![true, false], "SCS raised then dropped");
}

#[test]
fn a_flush_that_fails_mid_frame_keeps_the_lines_dirty_and_drops_scs() {
    // The mode byte and the first line packet go out, then the bus fails.
    let mut lcd = SharpMip::new(FlakySpi::failing_after(2), MockCs::default());
    let mut fb = Framebuffer::new();
    let dirty_before = dirty_lines(&fb);
    assert!(dirty_before > 2, "a fresh framebuffer is all dirty");

    assert!(lcd.flush(&mut fb).is_err());
    assert_eq!(
        dirty_lines(&fb),
        dirty_before,
        "a part-sent frame is repainted whole on the next flush"
    );
    let (_, cs) = lcd.into_parts();
    assert_eq!(cs.transitions.last(), Some(&false), "SCS ends low");
}

#[test]
fn the_next_flush_after_a_failure_repaints_and_then_clears() {
    let mut lcd = SharpMip::new(FlakySpi::failing_after(0), MockCs::default());
    let mut fb = Framebuffer::new();
    assert!(lcd.flush(&mut fb).is_err());
    let (_, cs) = lcd.into_parts();

    let mut lcd = SharpMip::new(FlakySpi::failing_after(usize::MAX), cs);
    assert!(lcd.flush(&mut fb).is_ok());
    assert_eq!(
        dirty_lines(&fb),
        0,
        "a successful flush clears the dirty set"
    );
}

#[test]
fn a_failed_clear_all_still_drops_scs() {
    let mut lcd = SharpMip::new(FlakySpi::failing_after(0), MockCs::default());
    assert!(lcd.clear_all().is_err());
    let (_, cs) = lcd.into_parts();
    assert_eq!(cs.transitions, vec![true, false]);
}
