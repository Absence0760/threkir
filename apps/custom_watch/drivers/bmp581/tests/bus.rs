//! Bus-level behaviour of the BMP581 driver against a register-map fake:
//! the bring-up sequence, a wrong chip, "no sample ready", the 6-byte
//! temperature + pressure burst, and an I2C fault reaching the caller.
//! The conversion maths is pinned in tests/pressure.rs.
//! Run via `bin/watch-test.sh`.

use bmp581::{
    altitude_from_pressure_m, encode_dsp_config, encode_dsp_iir, encode_odr_config,
    encode_osr_config, raw_to_celsius, raw_to_pa, Bmp581, Config, Error, PowerMode, I2C_ADDR,
    STANDARD_SEA_LEVEL_PA,
};
use embedded_hal::i2c::{ErrorKind, ErrorType, I2c, Operation};
use std::cell::RefCell;
use std::rc::Rc;

const CHIP_ID: u8 = 0x01;
const INT_STATUS: u8 = 0x27;
const TEMP_DATA_XLSB: u8 = 0x1D;
const PRESS_DATA_XLSB: u8 = 0x20;
const DSP_CONFIG: u8 = 0x30;
const DSP_IIR: u8 = 0x31;
const OSR_CONFIG: u8 = 0x36;
const ODR_CONFIG: u8 = 0x37;
const CMD: u8 = 0x7E;
const ODR_50HZ: u8 = 0x0F;

#[derive(Debug)]
struct BusFault;

impl embedded_hal::i2c::Error for BusFault {
    fn kind(&self) -> ErrorKind {
        ErrorKind::Other
    }
}

/// A register map: writes land in `regs` and are logged; reads come from it.
/// The test keeps a handle on the same state, since the driver owns the bus.
struct State {
    regs: [u8; 128],
    writes: Vec<(u8, u8)>,
    burst_reads: Vec<(u8, usize)>,
    fail: bool,
}

impl State {
    fn put24(&mut self, reg: u8, raw: u32) {
        let b = raw.to_le_bytes();
        self.regs[reg as usize..reg as usize + 3].copy_from_slice(&b[..3]);
    }
}

#[derive(Clone)]
struct RegBus(Rc<RefCell<State>>);

impl RegBus {
    fn new() -> Self {
        let mut regs = [0u8; 128];
        regs[CHIP_ID as usize] = 0x50;
        regs[INT_STATUS as usize] = 0x01;
        Self(Rc::new(RefCell::new(State {
            regs,
            writes: Vec::new(),
            burst_reads: Vec::new(),
            fail: false,
        })))
    }

    fn state(&self) -> std::cell::RefMut<'_, State> {
        self.0.borrow_mut()
    }
}

impl ErrorType for RegBus {
    type Error = BusFault;
}

impl I2c for RegBus {
    fn transaction(&mut self, addr: u8, ops: &mut [Operation<'_>]) -> Result<(), BusFault> {
        assert_eq!(addr, I2C_ADDR, "every transfer addresses the BMP581");
        let mut st = self.0.borrow_mut();
        if st.fail {
            return Err(BusFault);
        }
        let mut reg = 0u8;
        for op in ops {
            match op {
                Operation::Write(bytes) => {
                    reg = bytes[0];
                    if bytes.len() == 2 {
                        st.writes.push((bytes[0], bytes[1]));
                        st.regs[bytes[0] as usize] = bytes[1];
                    }
                }
                Operation::Read(buf) => {
                    if buf.len() > 1 {
                        st.burst_reads.push((reg, buf.len()));
                    }
                    let start = reg as usize;
                    buf.copy_from_slice(&st.regs[start..start + buf.len()]);
                }
            }
        }
        Ok(())
    }
}

#[test]
fn init_soft_resets_then_configures_from_standby_to_the_requested_mode() {
    let bus = RegBus::new();
    let mut baro = Bmp581::new(bus.clone());
    assert!(baro.init().is_ok());
    let cfg = Config::default();
    assert_eq!(
        bus.state().writes,
        vec![
            (CMD, 0xB6),
            (ODR_CONFIG, encode_odr_config(ODR_50HZ, PowerMode::Standby)),
            (
                OSR_CONFIG,
                encode_osr_config(cfg.osr_pressure, cfg.osr_temperature)
            ),
            (
                DSP_CONFIG,
                encode_dsp_config(cfg.iir_pressure, cfg.iir_temperature)
            ),
            (
                DSP_IIR,
                encode_dsp_iir(cfg.iir_pressure, cfg.iir_temperature)
            ),
            (ODR_CONFIG, encode_odr_config(ODR_50HZ, cfg.power_mode)),
        ],
        "OSR / DSP latch only in standby, so standby goes first and the power mode last"
    );
}

#[test]
fn init_refuses_a_wrong_chip_and_configures_nothing() {
    let bus = RegBus::new();
    bus.state().regs[CHIP_ID as usize] = 0x51;
    let mut baro = Bmp581::new(bus.clone());
    assert!(matches!(baro.init(), Err(Error::BadChipId)));
    assert_eq!(
        bus.state().writes,
        vec![(CMD, 0xB6)],
        "only the reset went out"
    );
}

#[test]
fn no_data_ready_is_no_sample_and_no_burst_read() {
    let bus = RegBus::new();
    bus.state().regs[INT_STATUS as usize] = 0x00;
    let mut baro = Bmp581::new(bus.clone());
    assert_eq!(baro.read_pressure_pa().unwrap(), None);
    assert_eq!(baro.read_sample().unwrap(), None);
    assert_eq!(baro.read_altitude_m().unwrap(), None);
    assert!(bus.state().burst_reads.is_empty());
}

#[test]
fn data_ready_ignores_the_other_status_bits() {
    let bus = RegBus::new();
    bus.state().regs[INT_STATUS as usize] = 0xFE; // every bit but DRDY
    let mut baro = Bmp581::new(bus);
    assert_eq!(baro.read_pressure_pa().unwrap(), None);
}

#[test]
fn read_sample_takes_temperature_and_pressure_from_one_burst() {
    let temp_raw = 0x0016_8000; // 22.5 °C at 1/65536 °C per count
    let press_raw = 6_484_800; // 101 325 Pa at 1/64 Pa per count
    let bus = RegBus::new();
    bus.state().put24(TEMP_DATA_XLSB, temp_raw);
    bus.state().put24(PRESS_DATA_XLSB, press_raw);
    let mut baro = Bmp581::new(bus.clone());

    let s = baro.read_sample().unwrap().expect("a sample is ready");
    assert_eq!(s.temperature_c, raw_to_celsius(temp_raw));
    assert_eq!(s.pressure_pa, raw_to_pa(press_raw));
    assert!((s.temperature_c - 22.5).abs() < 1e-4);
    assert!((s.pressure_pa - 101_325.0).abs() < 0.01);
    assert_eq!(
        bus.state().burst_reads,
        vec![(TEMP_DATA_XLSB, 6)],
        "one 6-byte read from TEMP_DATA_XLSB"
    );
}

#[test]
fn read_pressure_assembles_the_three_bytes_little_endian() {
    let bus = RegBus::new();
    bus.state().put24(PRESS_DATA_XLSB, 0x00AB_CDEF);
    let mut baro = Bmp581::new(bus);
    assert_eq!(
        baro.read_pressure_pa().unwrap(),
        Some(raw_to_pa(0x00AB_CDEF))
    );
}

#[test]
fn read_altitude_uses_the_calibrated_reference() {
    let bus = RegBus::new();
    bus.state()
        .put24(PRESS_DATA_XLSB, (95_000.0_f32 * 64.0) as u32);
    let mut baro = Bmp581::new(bus);
    let at_standard = baro.read_altitude_m().unwrap().unwrap();
    assert!((at_standard - altitude_from_pressure_m(95_000.0, STANDARD_SEA_LEVEL_PA)).abs() < 1e-3);

    baro.set_sea_level_pa(100_000.0);
    let calibrated = baro.read_altitude_m().unwrap().unwrap();
    assert!((calibrated - altitude_from_pressure_m(95_000.0, 100_000.0)).abs() < 1e-3);
}

#[test]
fn the_qnh_range_is_inclusive_at_both_ends() {
    let bus = RegBus::new();
    bus.state()
        .put24(PRESS_DATA_XLSB, (95_000.0_f32 * 64.0) as u32);
    let mut baro = Bmp581::new(bus);
    for edge in [87_000.0_f32, 108_500.0] {
        baro.set_sea_level_pa(edge);
        let got = baro.read_altitude_m().unwrap().unwrap();
        assert!(
            (got - altitude_from_pressure_m(95_000.0, edge)).abs() < 1e-3,
            "{edge}"
        );
    }
}

#[test]
fn an_i2c_fault_reaches_the_caller_as_an_i2c_error() {
    let bus = RegBus::new();
    bus.state().fail = true;
    let mut baro = Bmp581::new(bus);
    assert!(matches!(baro.init(), Err(Error::I2c(_))));
    assert!(matches!(baro.read_pressure_pa(), Err(Error::I2c(_))));
    assert!(matches!(baro.read_sample(), Err(Error::I2c(_))));
    assert!(matches!(baro.read_altitude_m(), Err(Error::I2c(_))));
}
