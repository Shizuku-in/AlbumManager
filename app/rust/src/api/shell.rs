//! Opening files and revealing them through the Windows shell API. Launching
//! `explorer.exe <path>` instead leaves a `/factory,{75dff2b7-…} -Embedding`
//! host process behind on every call.

/// Opens a file, folder or URL with its default application.
pub fn shell_open(target: String) -> anyhow::Result<()> {
    #[cfg(windows)]
    {
        use std::ptr::null;
        use windows_sys::Win32::UI::Shell::ShellExecuteW;
        use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
        let _com = Com::init();
        let verb = wide("open");
        let file = wide(&target);
        // SAFETY: both strings are NUL-terminated and outlive the call.
        let r = unsafe {
            ShellExecuteW(null_mut(), verb.as_ptr(), file.as_ptr(), null(), null(), SW_SHOWNORMAL)
        };
        // Values above 32 mean success.
        if r as isize <= 32 {
            anyhow::bail!("ShellExecute failed ({}) for {target}", r as isize);
        }
        Ok(())
    }
    #[cfg(not(windows))]
    anyhow::bail!("shell_open is Windows-only: {target}")
}

/// Opens the containing folder in Explorer with the item selected.
pub fn shell_reveal(path: String) -> anyhow::Result<()> {
    #[cfg(windows)]
    {
        use windows_sys::Win32::UI::Shell::{ILCreateFromPathW, ILFree, SHOpenFolderAndSelectItems};
        let _com = Com::init();
        let p = wide(&path);
        // SAFETY: `p` is NUL-terminated; the item list is freed below.
        unsafe {
            let pidl = ILCreateFromPathW(p.as_ptr());
            if pidl.is_null() {
                anyhow::bail!("Path not found: {path}");
            }
            // With no child items the pidl itself is the item to select.
            let hr = SHOpenFolderAndSelectItems(pidl, 0, null_mut(), 0);
            ILFree(pidl);
            if hr < 0 {
                anyhow::bail!("SHOpenFolderAndSelectItems failed (0x{:08X}) for {path}", hr as u32);
            }
        }
        Ok(())
    }
    #[cfg(not(windows))]
    anyhow::bail!("shell_reveal is Windows-only: {path}")
}

#[cfg(windows)]
use std::ptr::null_mut;

#[cfg(windows)]
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain([0]).collect()
}

/// COM for the current (worker) thread, released on drop if we initialized it.
#[cfg(windows)]
struct Com(bool);

#[cfg(windows)]
impl Com {
    fn init() -> Self {
        use windows_sys::Win32::System::Com::{
            CoInitializeEx, COINIT_APARTMENTTHREADED, COINIT_DISABLE_OLE1DDE,
        };
        // SAFETY: balanced by CoUninitialize in Drop when it succeeded.
        let hr = unsafe {
            CoInitializeEx(
                std::ptr::null(),
                (COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE) as u32,
            )
        };
        Com(hr >= 0)
    }
}

#[cfg(windows)]
impl Drop for Com {
    fn drop(&mut self) {
        if self.0 {
            // SAFETY: matches the successful CoInitializeEx above.
            unsafe { windows_sys::Win32::System::Com::CoUninitialize() };
        }
    }
}
