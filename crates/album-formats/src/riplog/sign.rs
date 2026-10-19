//! Verification of the signatures EAC and XLD append to their logs. Both
//! algorithms were reverse-engineered by others; these follow cambia's
//! implementations (MIT, https://github.com/rokkhonorg/cambia).

use album_model::LogChecksum;
use regex::Regex;
use std::sync::LazyLock;

static EAC_SIGNATURE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"==== (.+)? ([0-9A-Z]{64}) ====").unwrap());
static XLD_SIGNATURE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\n-----BEGIN XLD SIGNATURE-----\n(.+)\n-----END XLD SIGNATURE-----").unwrap()
});

/// EAC writes several rips to one file separated by this line; each part is
/// signed on its own.
const EAC_SEPARATOR: &str = "\r\n------------------------------------------------------------\r\n";

/// Checks every signed part of an (untranslated) EAC log.
pub fn eac(log: &str) -> LogChecksum {
    let mut result = LogChecksum::Missing;
    for part in log.split(EAC_SEPARATOR).map(str::trim) {
        let Some(c) = EAC_SIGNATURE.captures(part) else {
            continue;
        };
        if eac_checksum(&EAC_SIGNATURE.replace_all(part, "")) != c[2] {
            return LogChecksum::Invalid;
        }
        result = LogChecksum::Valid;
    }
    result
}

pub fn xld(log: &str) -> LogChecksum {
    // Signed without the newline that ends the file.
    let log = log.trim();
    match XLD_SIGNATURE.captures(log) {
        None => LogChecksum::Missing,
        Some(c) if xld_signature(&XLD_SIGNATURE.replace_all(log, "")) == c[1].trim() => {
            LogChecksum::Valid
        }
        Some(_) => LogChecksum::Invalid,
    }
}

// ---- EAC: Rijndael with 256-bit blocks, chained over the UTF-16LE text ----

const EAC_KEY: [u8; 32] = [
    0x93, 0x78, 0x71, 0x6c, 0xf1, 0x3e, 0x42, 0x65, 0xae, 0x55, 0x33, 0x8e, 0x94, 0x0b, 0x37, 0x61,
    0x84, 0xda, 0x38, 0x9e, 0x50, 0x64, 0x77, 0x26, 0xb3, 0x5f, 0x6f, 0x34, 0x1e, 0xe3, 0xef, 0xd9,
];

fn eac_checksum(text: &str) -> String {
    let mut bytes: Vec<u8> = text
        .chars()
        .filter(|c| *c != '\r' && *c != '\n')
        .collect::<String>()
        .encode_utf16()
        .flat_map(u16::to_le_bytes)
        .collect();
    bytes.resize(bytes.len().div_ceil(32) * 32, 0);
    let cipher = Rijndael256::new(&EAC_KEY);
    let mut state = [0u8; 32];
    for block in bytes.chunks(32) {
        for (s, b) in state.iter_mut().zip(block) {
            *s ^= b;
        }
        state = cipher.encrypt(state);
    }
    state.iter().map(|b| format!("{b:02X}")).collect()
}

const SBOX: [u8; 256] = [
    0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
    0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
    0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
    0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
    0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
    0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
    0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
    0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
    0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
    0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
    0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
    0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
    0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
    0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
    0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
    0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
];

fn xtime(b: u8) -> u8 {
    (b << 1) ^ if b & 0x80 != 0 { 0x1B } else { 0 }
}

/// Rijndael with a 256-bit block and key (14 rounds). The state is
/// column-major: byte `4 * column + row`.
struct Rijndael256 {
    round_keys: [[u8; 32]; 15],
}

impl Rijndael256 {
    fn new(key: &[u8; 32]) -> Self {
        let mut words = [[0u8; 4]; 120];
        for (i, w) in words.iter_mut().take(8).enumerate() {
            w.copy_from_slice(&key[4 * i..4 * i + 4]);
        }
        let mut rcon = 1u8;
        for i in 8..120 {
            let mut t = words[i - 1];
            if i % 8 == 0 {
                t = [
                    SBOX[t[1] as usize] ^ rcon,
                    SBOX[t[2] as usize],
                    SBOX[t[3] as usize],
                    SBOX[t[0] as usize],
                ];
                rcon = xtime(rcon);
            } else if i % 8 == 4 {
                t = t.map(|b| SBOX[b as usize]);
            }
            for j in 0..4 {
                words[i][j] = words[i - 8][j] ^ t[j];
            }
        }
        let mut round_keys = [[0u8; 32]; 15];
        for (r, rk) in round_keys.iter_mut().enumerate() {
            for c in 0..8 {
                rk[4 * c..4 * c + 4].copy_from_slice(&words[8 * r + c]);
            }
        }
        Self { round_keys }
    }

    fn encrypt(&self, mut s: [u8; 32]) -> [u8; 32] {
        // Row r shifts left by 0, 1, 3, 4 columns for 256-bit blocks.
        const SHIFT: [usize; 4] = [0, 1, 3, 4];
        let add_key =
            |s: &mut [u8; 32], rk: &[u8; 32]| s.iter_mut().zip(rk).for_each(|(a, b)| *a ^= b);
        add_key(&mut s, &self.round_keys[0]);
        for round in 1..=14 {
            let prev = s.map(|b| SBOX[b as usize]);
            for c in 0..8 {
                for r in 0..4 {
                    s[4 * c + r] = prev[4 * ((c + SHIFT[r]) % 8) + r];
                }
            }
            if round < 14 {
                for col in s.chunks_mut(4) {
                    let [a, b, c, d] = [col[0], col[1], col[2], col[3]];
                    col[0] = xtime(a) ^ xtime(b) ^ b ^ c ^ d;
                    col[1] = a ^ xtime(b) ^ xtime(c) ^ c ^ d;
                    col[2] = a ^ b ^ xtime(c) ^ xtime(d) ^ d;
                    col[3] = xtime(a) ^ a ^ b ^ c ^ xtime(d);
                }
            }
            add_key(&mut s, &self.round_keys[round]);
        }
        s
    }
}

// ---- XLD: SHA-256 with a custom initial state, then a scramble ----

const SHA_K: [u32; 64] = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
];
const XLD_STATE: [u32; 8] = [
    0x1D95E3A4, 0x06520EF5, 0x3A9CFB75, 0x6104BCAE, 0x09CEDA82, 0xBA55E60B, 0xEAEC16C6, 0xEB19AF15,
];
const XLD_MAGIC: [u32; 8] = [
    0x99036946, 0xE99DB8E7, 0xE3AE2FA7, 0x0A339740, 0xF06EB6A9, 0x92FF9B65, 0x028F7873, 0x9070E316,
];
const XLD_BASE64: &[u8; 64] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._";

fn xld_signature(text: &str) -> String {
    let digest: String = sha256(text.as_bytes(), XLD_STATE)
        .iter()
        .map(|w| format!("{w:08x}"))
        .collect();
    base64(&scramble(format!("{digest}\nVersion=0001").as_bytes()))
}

fn sha256(data: &[u8], mut h: [u32; 8]) -> [u32; 8] {
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend((data.len() as u64 * 8).to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for (i, b) in chunk.chunks(4).enumerate() {
            w[i] = u32::from_be_bytes([b[0], b[1], b[2], b[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ (!e & g);
            let t1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(SHA_K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let t2 = s0.wrapping_add((a & b) ^ (a & c) ^ (b & c));
            (hh, g, f, e, d, c, b, a) = (g, f, e, d.wrapping_add(t1), c, b, a, t1.wrapping_add(t2));
        }
        for (x, y) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
            *x = x.wrapping_add(y);
        }
    }
    h
}

/// XLD's block scramble over 8-byte blocks; a trailing partial block is
/// XORed with the output of an extra all-zero block.
fn scramble(data: &[u8]) -> Vec<u8> {
    let aligned = data.len() - data.len() % 8;
    let (body, tail) = data.split_at(aligned);
    let mut blocks: Vec<[u8; 8]> = body.chunks(8).map(|c| c.try_into().unwrap()).collect();
    if !tail.is_empty() {
        blocks.push([0; 8]);
    }
    let (mut x, mut y) = (0x6479B873u32, 0x48853AFCu32);
    let mut out = Vec::with_capacity(blocks.len() * 8);
    for block in blocks {
        x ^= u32::from_be_bytes(block[..4].try_into().unwrap());
        y ^= u32::from_be_bytes(block[4..].try_into().unwrap());
        for _ in 0..4 {
            for i in 0..2 {
                let m = &XLD_MAGIC[4 * i..4 * i + 4];
                y ^= x;
                let a = m[0].wrapping_add(y);
                let b = a.wrapping_sub(1).wrapping_add(a.rotate_left(1));
                x ^= b ^ b.rotate_left(4);
                let c = m[1].wrapping_add(x);
                let d = c.wrapping_add(1).wrapping_add(c.rotate_left(2));
                let e = m[2].wrapping_add(d ^ d.rotate_left(8));
                let f = e.rotate_left(1).wrapping_sub(e);
                y ^= (x | f) ^ f.rotate_left(16);
                let g = m[3].wrapping_add(y);
                x ^= g.wrapping_add(1).wrapping_add(g.rotate_left(2));
            }
        }
        out.extend(x.to_be_bytes());
        out.extend(y.to_be_bytes());
    }
    if !tail.is_empty() {
        let keystream = out.split_off(out.len() - 8);
        out.extend(keystream.iter().zip(tail).map(|(k, t)| k ^ t));
    }
    out
}

/// Base64 in XLD's alphabet, without padding.
fn base64(data: &[u8]) -> String {
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let n = chunk
            .iter()
            .enumerate()
            .fold(0u32, |n, (i, b)| n | (*b as u32) << (16 - 8 * i));
        for i in 0..=chunk.len() {
            out.push(XLD_BASE64[(n >> (18 - 6 * i) & 63) as usize] as char);
        }
    }
    out
}
