//! The register paths tests/driver_logic.rs leaves alone: FIFO occupancy
//! (`available`), the green LED drive (`set_led_current`) and the one-shot
//! die-temperature conversion. Run via `bin/watch-test.sh`.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use embedded_hal::i2c::{ErrorType, I2c, Operation};
use max30101::{decode_die_temp_milli_c, Error, Max30101, I2C_ADDR};

const FIFO_WR_PTR: u8 = 0x04;
const FIFO_RD_PTR: u8 = 0x06;
const LED3_PA: u8 = 0x0E;
const TEMP_INT: u8 = 0x1F;
const TEMP_FRAC: u8 = 0x20;
const TEMP_CONFIG: u8 = 0x21;

#[derive(Default)]
struct State {
    regs: HashMap<u8, u8>,
    writes: Vec<(u8, u8)>,
    /// TEMP_CONFIG reads report the conversion busy this many more times;
    /// `None` never completes.
    temp_busy_reads: Option<u32>,
    temp_config_reads: u32,
}

#[derive(Clone, Default)]
struct Bus(Rc<RefCell<State>>);

impl Bus {
    fn st(&self) -> std::cell::RefMut<'_, State> {
        self.0.borrow_mut()
    }
}

impl ErrorType for Bus {
    type Error = core::convert::Infallible;
}

impl I2c for Bus {
    fn transaction(&mut self, addr: u8, ops: &mut [Operation<'_>]) -> Result<(), Self::Error> {
        assert_eq!(addr, I2C_ADDR);
        let mut st = self.0.borrow_mut();
        let mut reg = 0u8;
        for op in ops {
            match op {
                Operation::Write(b) => {
                    reg = b[0];
                    if b.len() == 2 {
                        st.writes.push((b[0], b[1]));
                        st.regs.insert(b[0], b[1]);
                    }
                }
                Operation::Read(buf) => {
                    if reg == TEMP_CONFIG {
                        st.temp_config_reads += 1;
                        let busy = match st.temp_busy_reads {
                            None => true,
                            Some(0) => false,
                            Some(n) => {
                                st.temp_busy_reads = Some(n - 1);
                                true
                            }
                        };
                        buf[0] = u8::from(busy);
                    } else {
                        buf[0] = *st.regs.get(&reg).unwrap_or(&0);
                    }
                }
            }
        }
        Ok(())
    }
}

fn occupancy(wr: u8, rd: u8) -> usize {
    let bus = Bus::default();
    bus.st().regs.insert(FIFO_WR_PTR, wr);
    bus.st().regs.insert(FIFO_RD_PTR, rd);
    Max30101::new(bus).available().unwrap()
}

#[test]
fn available_is_the_pointer_distance_modulo_the_32_sample_fifo() {
    assert_eq!(occupancy(0, 0), 0);
    assert_eq!(occupancy(5, 2), 3);
    assert_eq!(occupancy(31, 0), 31);
    // The writer has wrapped past the end: (3 + 32 - 30) % 32.
    assert_eq!(occupancy(3, 30), 5);
}

#[test]
fn available_masks_the_read_pointer_so_stray_high_bits_cannot_underflow() {
    // Only bits 4:0 are the pointer; 0xE5 is 5 and 0xC2 is 2. The read
    // pointer's mask is the load-bearing one: unmasked, 0xC2 makes
    // `wr + 32 - rd` underflow. The write pointer's high bits here are a
    // multiple of 32, which the modulo already discards.
    assert_eq!(occupancy(0xE5, 0xC2), 3);
}

#[test]
fn set_led_current_drives_only_the_green_led() {
    let bus = Bus::default();
    let mut sensor = Max30101::new(bus.clone());
    sensor.set_led_current(0x5A).unwrap();
    assert_eq!(bus.st().writes, vec![(LED3_PA, 0x5A)]);
}

#[test]
fn die_temp_starts_a_conversion_waits_for_it_and_decodes() {
    let bus = Bus::default();
    bus.st().temp_busy_reads = Some(3);
    bus.st().regs.insert(TEMP_INT, 0xE7); // -25 as two's complement
    bus.st().regs.insert(TEMP_FRAC, 0x08); // 8 x 0.0625 = 0.5
    let mut sensor = Max30101::new(bus.clone());

    let milli = sensor.read_die_temp_milli_c().unwrap();
    // -25 °C + 0.5 °C = -24.5 °C.
    assert_eq!(milli, -24_500);
    assert_eq!(milli, decode_die_temp_milli_c(0xE7, 0x08));
    assert_eq!(
        bus.st().writes,
        vec![(TEMP_CONFIG, 0x01)],
        "TEMP_EN starts the one-shot"
    );
    assert_eq!(bus.st().temp_config_reads, 4, "three busy polls, then done");
}

#[test]
fn a_conversion_that_never_completes_times_out_after_256_polls() {
    let bus = Bus::default();
    bus.st().temp_busy_reads = None;
    let mut sensor = Max30101::new(bus.clone());
    assert!(matches!(
        sensor.read_die_temp_milli_c(),
        Err(Error::TempTimeout)
    ));
    assert_eq!(bus.st().temp_config_reads, 256);
}
