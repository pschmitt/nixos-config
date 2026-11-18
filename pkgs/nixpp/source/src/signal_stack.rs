use std::io;
use std::mem::MaybeUninit;
use std::ptr;

const HANDLER_RESERVE: usize = 128 * 1024;

// The launcher's SA_ONSTACK syscall handler needs more space than Rust's
// default alternate stack. Production guest commands run on the main thread;
// new worker threads must reserve their own stack before issuing guest syscalls.
pub fn reserve() -> io::Result<()> {
    let mut old = MaybeUninit::<libc::stack_t>::uninit();
    // SAFETY: old points to writable stack_t storage; a null first argument
    // queries the calling thread without changing its registration.
    if unsafe { libc::sigaltstack(ptr::null(), old.as_mut_ptr()) } != 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: successful sigaltstack initialized old.
    let old = unsafe { old.assume_init() };
    // SAFETY: sysconf and getauxval take no pointers and retain no memory.
    let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if page <= 0 {
        return Err(io::Error::other("cannot determine signal-stack page size"));
    }
    let page = page as usize;
    // SAFETY: AT_MINSIGSTKSZ is a scalar auxiliary-vector query.
    let minimum = unsafe { libc::getauxval(libc::AT_MINSIGSTKSZ) } as usize;
    let usable = HANDLER_RESERVE
        .checked_add(minimum)
        .and_then(|size| size.checked_add(page - 1))
        .map(|size| size / page * page)
        .ok_or_else(|| io::Error::other("signal-stack size overflow"))?;
    if old.ss_flags & libc::SS_DISABLE == 0 && old.ss_size >= usable {
        return Ok(());
    }
    let total = usable
        .checked_add(page)
        .ok_or_else(|| io::Error::other("signal-stack mapping size overflow"))?;
    // SAFETY: anonymous mmap owns total bytes with no aliases; -1 and zero
    // are the required descriptor and offset for an anonymous mapping.
    let mapping = unsafe {
        libc::mmap(
            ptr::null_mut(),
            total,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_PRIVATE | libc::MAP_ANONYMOUS,
            -1,
            0,
        )
    };
    if mapping == libc::MAP_FAILED {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: mapping is page-aligned and owns at least page bytes.
    if unsafe { libc::mprotect(mapping, page, libc::PROT_NONE) } != 0 {
        let error = io::Error::last_os_error();
        // SAFETY: this mapping has not been registered or shared.
        unsafe { libc::munmap(mapping, total) };
        return Err(error);
    }
    let stack = libc::stack_t {
        // SAFETY: page is within the live total-byte mapping; the remaining
        // usable bytes stay mapped for the entire process lifetime.
        ss_sp: unsafe { mapping.cast::<u8>().add(page).cast() },
        ss_flags: 0,
        ss_size: usable,
    };
    // SAFETY: stack describes a live, writable mapping. sigaltstack copies
    // the descriptor, not its address. The mapping is intentionally never freed.
    if unsafe { libc::sigaltstack(&stack, ptr::null_mut()) } != 0 {
        let error = io::Error::last_os_error();
        // SAFETY: registration failed, so no signal handler uses this mapping.
        unsafe { libc::munmap(mapping, total) };
        return Err(error);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reservation_is_large_and_idempotent() {
        reserve().unwrap();
        let query = || {
            let mut stack = MaybeUninit::<libc::stack_t>::uninit();
            // SAFETY: stack is writable storage and the null input only queries.
            assert_eq!(
                unsafe { libc::sigaltstack(ptr::null(), stack.as_mut_ptr()) },
                0
            );
            // SAFETY: successful query initialized stack.
            unsafe { stack.assume_init() }
        };
        let first = query();
        assert_eq!(first.ss_flags & libc::SS_DISABLE, 0);
        assert!(first.ss_size >= HANDLER_RESERVE);
        reserve().unwrap();
        let second = query();
        assert_eq!(first.ss_sp, second.ss_sp);
        assert_eq!(first.ss_size, second.ss_size);
    }
}
