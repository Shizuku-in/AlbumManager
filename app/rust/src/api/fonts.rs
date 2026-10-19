//! Installed fonts, for the font setting.

use std::collections::BTreeSet;

/// Family names of the installed fonts (machine-wide and per-user), sorted.
/// Flutter resolves these names through DirectWrite.
pub fn system_font_families() -> Vec<String> {
    let mut names = BTreeSet::new();
    #[cfg(windows)]
    for root in [
        windows_sys::Win32::System::Registry::HKEY_LOCAL_MACHINE,
        windows_sys::Win32::System::Registry::HKEY_CURRENT_USER,
    ] {
        for entry in
            registry_value_names(root, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts")
        {
            names.extend(families(&entry));
        }
    }
    names.into_iter().collect()
}

/// Style words that end a registry entry but aren't part of the family
/// ("Segoe UI Semibold Italic" → "Segoe UI").
const STYLES: &[&str] = &[
    "Regular",
    "Bold",
    "Italic",
    "Oblique",
    "Thin",
    "Hairline",
    "Light",
    "Semilight",
    "SemiLight",
    "Medium",
    "Semibold",
    "SemiBold",
    "Demibold",
    "DemiBold",
    "ExtraBold",
    "Extrabold",
    "UltraBold",
    "ExtraLight",
    "Extralight",
    "UltraLight",
    "Black",
    "Heavy",
];

/// Families named by a registry entry such as
/// "Microsoft YaHei & Microsoft YaHei UI (TrueType)".
fn families(entry: &str) -> Vec<String> {
    if entry.contains("(All res)") {
        return Vec::new(); // bitmap fonts
    }
    let name = entry.rfind(" (").map_or(entry, |i| &entry[..i]);
    name.split(" & ")
        .filter_map(|n| {
            let mut words: Vec<&str> = n.split_whitespace().collect();
            while words.len() > 1 && words.last().is_some_and(|w| STYLES.contains(w)) {
                words.pop();
            }
            (!words.is_empty() && !n.starts_with('@')).then(|| words.join(" "))
        })
        .collect()
}

#[cfg(windows)]
fn registry_value_names(
    root: windows_sys::Win32::System::Registry::HKEY,
    path: &str,
) -> Vec<String> {
    use std::ptr::{null, null_mut};
    use windows_sys::Win32::System::Registry::*;
    let path: Vec<u16> = path.encode_utf16().chain([0]).collect();
    let mut out = Vec::new();
    // SAFETY: plain registry reads into buffers we own; the key is closed below.
    unsafe {
        let mut key: HKEY = null_mut();
        if RegOpenKeyExW(root, path.as_ptr(), 0, KEY_READ, &mut key) != 0 {
            return out;
        }
        // Value names are at most 16383 characters.
        let mut buf = vec![0u16; 16384];
        for i in 0.. {
            let mut len = buf.len() as u32;
            let r = RegEnumValueW(
                key,
                i,
                buf.as_mut_ptr(),
                &mut len,
                null(),
                null_mut(),
                null_mut(),
                null_mut(),
            );
            if r != 0 {
                break;
            }
            out.push(String::from_utf16_lossy(&buf[..len as usize]));
        }
        RegCloseKey(key);
    }
    out
}
