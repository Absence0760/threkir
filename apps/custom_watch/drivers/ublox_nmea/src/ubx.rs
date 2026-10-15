//! UBX binary frames — both directions of the binary protocol the u-blox
//! receiver speaks beside its NMEA output.
//!
//! **Transmit.** Only the frames the firmware actually sends are provided;
//! this is not a generic UBX message catalogue:
//!
//! - **UBX-RXM-PMREQ** — the tier-1 breakout's software power-down path (no
//!   load switch): put the receiver into backup mode between the selected
//!   recording mode's fixes. `watch_core::gnss_power` decides the windows; the
//!   gps task sends the frame.
//! - **UBX-CFG-VALSET** ([`cfg_valset_runner`]) — the one configuration the
//!   firmware owns: the pedestrian dynamic platform model and a UBX-NAV-PVT
//!   per navigation epoch on UART1. See that function for why PED and not
//!   WRIST.
//!
//! **Receive.** [`FrameAssembler`] recognises UBX frames in the byte stream and
//! decodes the two the firmware reads: **UBX-NAV-PVT** ([`NavPvt`]) for the
//! receiver's own horizontal + speed accuracy estimates, and **UBX-ACK-ACK /
//! NAK** for the VALSET above. [`crate::Parser`] runs it beside the NMEA
//! assembler.
//!
//! Frame layout (u-blox interface description, "UBX frame structure"): sync
//! chars `0xB5 0x62`, message class, message id, little-endian u16 payload
//! length, payload, then a two-byte 8-bit Fletcher checksum computed over
//! class..payload (sync chars excluded).
//!
//! **PMREQ form: the extended 16-byte payload** (`version 0x00` + 3 reserved
//! bytes + `duration` ms + `flags` + `wakeupSources`), not the legacy 8-byte
//! duration+flags form. Two reasons: the M10 interface description (the
//! MAX-M10S's generation) documents the extended form, and it makes the wake
//! source explicit — [`PMREQ_WAKE_UARTRX`] — instead of leaving wake
//! behaviour to the legacy form's implicit defaults. Flags carry only
//! `backup` (bit 1); `force` (bit 2) is deliberately NOT set — it exists to
//! force backup while USB is connected, the tier-1 breakout wires no USB to
//! the module, and leaving the interlock intact costs nothing.
//!
//! Wake is any activity on the module's RX line: the sender writes
//! [`WAKE_BYTE`] (`0xFF`, the u-blox-documented dummy byte the receiver
//! consumes without parsing), then allows a reacquire window before the next
//! fix is owed. A bounded `duration` is always encoded too, as the self-wake
//! backstop for a lost wake byte — never 0, which the spec reads as "no time
//! limit" (i.e. asleep forever if the byte is lost).

/// First UBX sync char.
pub const SYNC1: u8 = 0xB5;
/// Second UBX sync char.
pub const SYNC2: u8 = 0x62;

/// UBX-RXM message class.
pub const CLASS_RXM: u8 = 0x02;
/// UBX-RXM-PMREQ message id.
pub const ID_PMREQ: u8 = 0x41;
/// UBX-CFG message class.
pub const CLASS_CFG: u8 = 0x06;
/// UBX-CFG-VALSET message id.
pub const ID_VALSET: u8 = 0x8A;
/// UBX-NAV message class.
pub const CLASS_NAV: u8 = 0x01;
/// UBX-NAV-PVT message id.
pub const ID_NAV_PVT: u8 = 0x07;
/// UBX-ACK message class.
pub const CLASS_ACK: u8 = 0x05;
/// UBX-ACK-ACK message id.
pub const ID_ACK_ACK: u8 = 0x01;
/// UBX-ACK-NAK message id.
pub const ID_ACK_NAK: u8 = 0x00;

/// Framing bytes around a payload: sync (2) + class + id + length (2) +
/// checksum (2).
pub const FRAME_OVERHEAD: usize = 8;

/// The extended PMREQ payload: version + reserved[3] + duration + flags +
/// wakeupSources, each of the last three a little-endian u32.
pub const PMREQ_PAYLOAD_LEN: usize = 16;
/// A complete PMREQ frame.
pub const PMREQ_FRAME_LEN: usize = FRAME_OVERHEAD + PMREQ_PAYLOAD_LEN;

/// The dummy byte that wakes a receiver sleeping on UART-RX activity: the
/// receiver discards `0xFF` rather than trying to parse it as the start of a
/// message, so it can never corrupt the frame that follows.
pub const WAKE_BYTE: u8 = 0xFF;

/// PMREQ `flags` bit 1: enter backup mode for the requested duration.
pub const PMREQ_FLAG_BACKUP: u32 = 1 << 1;
/// PMREQ `wakeupSources` bit 3: wake on UART RX activity.
pub const PMREQ_WAKE_UARTRX: u32 = 1 << 3;

/// 8-bit Fletcher checksum over `body` — class..payload, sync chars excluded.
pub fn checksum(body: &[u8]) -> (u8, u8) {
    let mut ck_a: u8 = 0;
    let mut ck_b: u8 = 0;
    for &b in body {
        ck_a = ck_a.wrapping_add(b);
        ck_b = ck_b.wrapping_add(ck_a);
    }
    (ck_a, ck_b)
}

/// Assemble one UBX frame into `out`; returns the frame length, or `None`
/// when `out` is too small or the payload is longer than the u16 length
/// field can carry. No allocation — callers hand a stack buffer sized by the
/// message constants above.
pub fn write_frame(class: u8, id: u8, payload: &[u8], out: &mut [u8]) -> Option<usize> {
    let frame_len = FRAME_OVERHEAD.checked_add(payload.len())?;
    if payload.len() > u16::MAX as usize || out.len() < frame_len {
        return None;
    }
    out[0] = SYNC1;
    out[1] = SYNC2;
    out[2] = class;
    out[3] = id;
    out[4..6].copy_from_slice(&(payload.len() as u16).to_le_bytes());
    out[6..6 + payload.len()].copy_from_slice(payload);
    let (ck_a, ck_b) = checksum(&out[2..6 + payload.len()]);
    out[6 + payload.len()] = ck_a;
    out[7 + payload.len()] = ck_b;
    Some(frame_len)
}

/// A ready-to-send UBX-RXM-PMREQ frame: backup mode for `duration_ms`,
/// waking on UART RX activity or the duration expiring, whichever comes
/// first.
///
/// A `duration_ms` of 0 is never encoded — the spec reads 0 as "no time
/// limit", which would strand a receiver whose wake byte got lost — so a 0
/// request becomes the shortest bounded sleep (1 ms) instead.
pub fn pmreq_backup(duration_ms: u32) -> [u8; PMREQ_FRAME_LEN] {
    let mut payload = [0u8; PMREQ_PAYLOAD_LEN];
    // payload[0] = version 0x00; payload[1..4] reserved — all already zero.
    payload[4..8].copy_from_slice(&duration_ms.max(1).to_le_bytes());
    payload[8..12].copy_from_slice(&PMREQ_FLAG_BACKUP.to_le_bytes());
    payload[12..16].copy_from_slice(&PMREQ_WAKE_UARTRX.to_le_bytes());
    let mut frame = [0u8; PMREQ_FRAME_LEN];
    let written = write_frame(CLASS_RXM, ID_PMREQ, &payload, &mut frame);
    debug_assert_eq!(written, Some(PMREQ_FRAME_LEN));
    frame
}

/// CFG-NAVSPG-DYNMODEL (`E1`): the dynamic platform model.
pub const KEY_NAVSPG_DYNMODEL: u32 = 0x2011_0021;
/// CFG-MSGOUT-UBX_NAV_PVT_UART1 (`U1`): UBX-NAV-PVT output rate on UART1,
/// in navigation epochs per message (0 = off, the factory default).
pub const KEY_MSGOUT_NAV_PVT_UART1: u32 = 0x2091_0007;

/// CFG-NAVSPG-DYNMODEL `PORT`, the factory default.
pub const DYNMODEL_PORTABLE: u8 = 0;
/// CFG-NAVSPG-DYNMODEL `PED`: pedestrian.
pub const DYNMODEL_PEDESTRIAN: u8 = 3;
/// CFG-NAVSPG-DYNMODEL `WRIST`: wrist-worn watch. Documented by the M10 SPG
/// 5.10 interface description as "not available in all products"; not sent
/// (see [`cfg_valset_runner`]).
pub const DYNMODEL_WRIST: u8 = 9;

/// VALSET `layers` bit 0: apply to the RAM (current) configuration now.
pub const LAYER_RAM: u8 = 1 << 0;
/// VALSET `layers` bit 1: also store in battery-backed RAM, which the
/// receiver restacks into RAM when it comes back from backup mode.
pub const LAYER_BBR: u8 = 1 << 1;

/// The runner configuration's payload: version + layers + reserved[2], then
/// two key/value pairs of one value byte each (4-byte key + 1-byte value).
pub const RUNNER_CFG_PAYLOAD_LEN: usize = 4 + 2 * (4 + 1);
/// A complete runner-configuration VALSET frame.
pub const RUNNER_CFG_FRAME_LEN: usize = FRAME_OVERHEAD + RUNNER_CFG_PAYLOAD_LEN;

/// The one configuration the firmware owns, as a ready-to-send
/// UBX-CFG-VALSET (version 0) written to the RAM and BBR layers:
///
/// - `CFG-NAVSPG-DYNMODEL = PED (3)`. The receiver otherwise runs `PORT`,
///   whose motion envelope is a vehicle's; the pedestrian model constrains
///   the filter to walking/running dynamics. **Not WRIST (9):** the M10 SPG
///   5.10 interface description (UBX-21035062, table "Constants for
///   CFG-NAVSPG-DYNMODEL") lists WRIST as "not available in all products"
///   and no MAX-M10S document says it is one of them. VALSET is atomic — an
///   invalid value NAKs the whole message — so an unsupported WRIST would
///   also cost the NAV-PVT enable riding beside it. PED is in every M10
///   product's table. Whether this module takes WRIST is a bench question.
/// - `CFG-MSGOUT-UBX_NAV_PVT_UART1 = 1`: one UBX-NAV-PVT per navigation
///   epoch, the source of the receiver's own `hAcc` / `sAcc` estimates
///   ([`NavPvt`]) that NMEA does not carry.
///
/// RAM applies it immediately; BBR lets a wake from backup restack it. The
/// gps task resends it after every wake anyway, because the breakout's backup
/// cell is not guaranteed to hold BBR across a long power-off.
pub fn cfg_valset_runner() -> [u8; RUNNER_CFG_FRAME_LEN] {
    let mut payload = [0u8; RUNNER_CFG_PAYLOAD_LEN];
    payload[1] = LAYER_RAM | LAYER_BBR;
    payload[4..8].copy_from_slice(&KEY_NAVSPG_DYNMODEL.to_le_bytes());
    payload[8] = DYNMODEL_PEDESTRIAN;
    payload[9..13].copy_from_slice(&KEY_MSGOUT_NAV_PVT_UART1.to_le_bytes());
    payload[13] = 1;
    let mut frame = [0u8; RUNNER_CFG_FRAME_LEN];
    let written = write_frame(CLASS_CFG, ID_VALSET, &payload, &mut frame);
    debug_assert_eq!(written, Some(RUNNER_CFG_FRAME_LEN));
    frame
}

/// UBX-NAV-PVT's fixed payload length on protocol 34.10 (M10 SPG 5.10).
pub const NAV_PVT_PAYLOAD_LEN: usize = 92;

/// The largest payload [`FrameAssembler`] will buffer. A frame announcing a
/// longer one is abandoned at its length field, so a corrupted length can
/// hold the assembler for at most this many bytes rather than 64 KiB.
pub const MAX_RX_PAYLOAD_LEN: usize = NAV_PVT_PAYLOAD_LEN;

/// The fields of one UBX-NAV-PVT the firmware reads (M10 SPG 5.10 interface
/// description § UBX-NAV-PVT). Accuracies are the receiver's own 1-sigma-ish
/// estimates, converted from mm and mm/s.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct NavPvt {
    /// GPS time of week of the navigation epoch, ms.
    pub itow_ms: u32,
    /// UTC seconds since midnight, present only when `valid.validTime`.
    pub time_of_day: Option<u32>,
    /// 0 no fix, 1 DR only, 2 2D, 3 3D, 4 GNSS + DR, 5 time only.
    pub fix_type: u8,
    /// `flags.gnssFixOK`: the fix is within the DOP and accuracy masks.
    pub gnss_fix_ok: bool,
    /// Satellites used in the solution.
    pub num_sv: u8,
    pub lat_deg: f64,
    pub lon_deg: f64,
    /// `hAcc`: horizontal accuracy estimate, metres.
    pub h_acc_m: f32,
    /// `gSpeed`: 2-D ground speed, m/s.
    pub g_speed_mps: f32,
    /// `sAcc`: speed accuracy estimate, m/s.
    pub s_acc_mps: f32,
}

impl NavPvt {
    /// Decode a NAV-PVT payload; `None` unless it is exactly
    /// [`NAV_PVT_PAYLOAD_LEN`] bytes.
    pub fn decode(p: &[u8]) -> Option<Self> {
        if p.len() != NAV_PVT_PAYLOAD_LEN {
            return None;
        }
        let u32_at = |i: usize| u32::from_le_bytes([p[i], p[i + 1], p[i + 2], p[i + 3]]);
        let i32_at = |i: usize| i32::from_le_bytes([p[i], p[i + 1], p[i + 2], p[i + 3]]);
        let (hour, min, sec) = (u32::from(p[8]), u32::from(p[9]), u32::from(p[10]));
        let valid_time = p[11] & 0b10 != 0;
        let time_of_day = (valid_time && hour < 24 && min < 60 && sec <= 60)
            .then(|| hour * 3600 + min * 60 + sec.min(59));
        Some(Self {
            itow_ms: u32_at(0),
            time_of_day,
            fix_type: p[20],
            gnss_fix_ok: p[21] & 1 != 0,
            num_sv: p[23],
            lon_deg: f64::from(i32_at(24)) * 1e-7,
            lat_deg: f64::from(i32_at(28)) * 1e-7,
            h_acc_m: u32_at(40) as f32 / 1000.0,
            g_speed_mps: i32_at(60) as f32 / 1000.0,
            s_acc_mps: u32_at(68) as f32 / 1000.0,
        })
    }
}

/// A decoded inbound UBX frame.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Inbound {
    NavPvt(NavPvt),
    /// UBX-ACK-ACK (`acked`) or UBX-ACK-NAK for the message `class`/`id`.
    Ack {
        class: u8,
        id: u8,
        acked: bool,
    },
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum RxState {
    Idle,
    Sync2,
    Class,
    Id,
    Len1,
    Len2,
    Payload,
    CkA,
    CkB,
}

/// Byte-at-a-time UBX frame assembler. Checksum-failing, oversized and
/// undecoded frames yield nothing; noise between frames is skipped until the
/// next `0xB5 0x62`.
pub struct FrameAssembler {
    state: RxState,
    class: u8,
    id: u8,
    len: usize,
    got: usize,
    ck_a: u8,
    ck_b: u8,
    rx_ck_a: u8,
    buf: [u8; MAX_RX_PAYLOAD_LEN],
}

impl Default for FrameAssembler {
    fn default() -> Self {
        Self::new()
    }
}

impl FrameAssembler {
    pub const fn new() -> Self {
        Self {
            state: RxState::Idle,
            class: 0,
            id: 0,
            len: 0,
            got: 0,
            ck_a: 0,
            ck_b: 0,
            rx_ck_a: 0,
            buf: [0; MAX_RX_PAYLOAD_LEN],
        }
    }

    fn sum(&mut self, b: u8) {
        self.ck_a = self.ck_a.wrapping_add(b);
        self.ck_b = self.ck_b.wrapping_add(self.ck_a);
    }

    /// Feed one byte; returns a decoded frame when this byte completes one.
    pub fn feed(&mut self, b: u8) -> Option<Inbound> {
        match self.state {
            RxState::Idle => {
                if b == SYNC1 {
                    self.state = RxState::Sync2;
                }
            }
            RxState::Sync2 => {
                self.state = match b {
                    SYNC2 => RxState::Class,
                    SYNC1 => RxState::Sync2,
                    _ => RxState::Idle,
                };
                self.ck_a = 0;
                self.ck_b = 0;
            }
            RxState::Class => {
                self.class = b;
                self.sum(b);
                self.state = RxState::Id;
            }
            RxState::Id => {
                self.id = b;
                self.sum(b);
                self.state = RxState::Len1;
            }
            RxState::Len1 => {
                self.len = usize::from(b);
                self.sum(b);
                self.state = RxState::Len2;
            }
            RxState::Len2 => {
                self.len |= usize::from(b) << 8;
                self.sum(b);
                self.got = 0;
                self.state = if self.len > MAX_RX_PAYLOAD_LEN {
                    RxState::Idle
                } else if self.len == 0 {
                    RxState::CkA
                } else {
                    RxState::Payload
                };
            }
            RxState::Payload => {
                self.buf[self.got] = b;
                self.got += 1;
                self.sum(b);
                if self.got == self.len {
                    self.state = RxState::CkA;
                }
            }
            RxState::CkA => {
                self.rx_ck_a = b;
                self.state = RxState::CkB;
            }
            RxState::CkB => {
                self.state = RxState::Idle;
                if self.rx_ck_a == self.ck_a && b == self.ck_b {
                    return self.decode();
                }
            }
        }
        None
    }

    fn decode(&self) -> Option<Inbound> {
        let p = &self.buf[..self.len];
        match (self.class, self.id) {
            (CLASS_NAV, ID_NAV_PVT) => NavPvt::decode(p).map(Inbound::NavPvt),
            (CLASS_ACK, ID_ACK_ACK | ID_ACK_NAK) if p.len() == 2 => Some(Inbound::Ack {
                class: p[0],
                id: p[1],
                acked: self.id == ID_ACK_ACK,
            }),
            _ => None,
        }
    }
}
