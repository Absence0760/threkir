//! The bus paths tests/driver_logic.rs leaves alone: FIFO occupancy, popping
//! tagged and untagged samples through the I2C burst, the MEAS1 LED drive and
//! the one-shot die-temperature conversion. The pure decoders are pinned there.
//! Run via `bin/watch-test.sh`.

use std::cell::RefCell;
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;

use embedded_hal::i2c::{ErrorType, I2c, Operation};
use max86177::{decode_die_temp_milli_c, Error, Max86177, I2C_ADDR, MEAS1_TAG, MEAS2_TAG};
use watch_core::ppg::FifoWord;

const FIFO_COUNTER: u8 = 0x0B;
const FIFO_DATA: u8 = 0x0C;
const MEAS1_LEDA_CURRENT: u8 = 0x19;
const TEMP_CONFIG: u8 = 0x20;
const TEMP_INT: u8 = 0x21;
const TEMP_FRAC: u8 = 0x22;

#[derive(Default)]
struct State {
    regs: HashMap<u8, u8>,
    fifo: VecDeque<[u8; 3]>,
    writes: Vec<(u8, u8)>,
    fifo_data_reads: u32,
    /// TEMP_CONFIG reads report busy this many more times; `None` never ends.
    temp_busy_reads: Option<u32>,
    temp_config_reads: u32,
}

#[derive(Clone, Default)]
struct Bus(Rc<RefCell<State>>);

impl Bus {
    fn st(&self) -> std::cell::RefMut<'_, State> {
        self.0.borrow_mut()
    }

    fn push_word(&self, tag: u8, count: u32) {
        let raw = (u32::from(tag) << 19) | count;
        let b = raw.to_be_bytes();
        self.st().fifo.push_back([b[1], b[2], b[3]]);
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
                Operation::Read(buf) => match reg {
                    FIFO_COUNTER => buf[0] = st.fifo.len() as u8,
                    FIFO_DATA => {
                        st.fifo_data_reads += 1;
                        assert_eq!(buf.len(), 3, "one FIFO word is a 3-byte burst");
                        let word = st.fifo.pop_front().expect("read an empty FIFO");
                        buf.copy_from_slice(&word);
                    }
                    TEMP_CONFIG => {
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
                    }
                    _ => buf[0] = *st.regs.get(&reg).unwrap_or(&0),
                },
            }
        }
        Ok(())
    }
}

#[test]
fn available_is_the_fifo_counter() {
    let bus = Bus::default();
    let mut s = Max86177::new(bus.clone());
    assert_eq!(s.available().unwrap(), 0);
    bus.push_word(MEAS1_TAG, 1);
    bus.push_word(MEAS2_TAG, 2);
    assert_eq!(s.available().unwrap(), 2);
}

#[test]
fn an_empty_fifo_pops_nothing_and_never_reads_fifo_data() {
    let bus = Bus::default();
    let mut s = Max86177::new(bus.clone());
    assert_eq!(s.read_tagged_sample().unwrap(), None);
    assert_eq!(s.read_sample().unwrap(), None);
    assert_eq!(bus.st().fifo_data_reads, 0);
}

#[test]
fn tagged_samples_pop_in_order_with_their_tags() {
    let bus = Bus::default();
    bus.push_word(MEAS1_TAG, 0x1_2345);
    bus.push_word(MEAS2_TAG, 0x0_0ABC);
    let mut s = Max86177::new(bus.clone());

    assert_eq!(
        s.read_tagged_sample().unwrap(),
        Some(FifoWord {
            tag: MEAS1_TAG,
            value: 0x1_2345
        })
    );
    assert_eq!(
        s.read_tagged_sample().unwrap(),
        Some(FifoWord {
            tag: MEAS2_TAG,
            value: 0x0_0ABC
        })
    );
    assert_eq!(s.read_tagged_sample().unwrap(), None);
    assert_eq!(bus.st().fifo_data_reads, 2);
}

#[test]
fn read_sample_drops_the_tag_and_keeps_the_19_bit_count() {
    let bus = Bus::default();
    bus.push_word(MEAS2_TAG, 0x7_FFFF); // the largest 19-bit count
    let mut s = Max86177::new(bus);
    assert_eq!(s.read_sample().unwrap(), Some(0x7_FFFF));
}

#[test]
fn set_led_current_drives_only_meas1_led_a() {
    let bus = Bus::default();
    let mut s = Max86177::new(bus.clone());
    s.set_led_current(0x40).unwrap();
    assert_eq!(bus.st().writes, vec![(MEAS1_LEDA_CURRENT, 0x40)]);
}

#[test]
fn die_temp_starts_a_conversion_waits_for_it_and_decodes() {
    let bus = Bus::default();
    bus.st().temp_busy_reads = Some(2);
    bus.st().regs.insert(TEMP_INT, 0x19); // 25
    bus.st().regs.insert(TEMP_FRAC, 0x04); // 4 x 0.0625 = 0.25
    let mut s = Max86177::new(bus.clone());

    let milli = s.read_die_temp_milli_c().unwrap();
    assert_eq!(milli, 25_250);
    assert_eq!(milli, decode_die_temp_milli_c(0x19, 0x04));
    assert_eq!(bus.st().writes, vec![(TEMP_CONFIG, 0x01)]);
    assert_eq!(bus.st().temp_config_reads, 3, "two busy polls, then done");
}

#[test]
fn a_conversion_that_never_completes_times_out_after_256_polls() {
    let bus = Bus::default();
    bus.st().temp_busy_reads = None;
    let mut s = Max86177::new(bus.clone());
    assert!(matches!(s.read_die_temp_milli_c(), Err(Error::TempTimeout)));
    assert_eq!(bus.st().temp_config_reads, 256);
}
