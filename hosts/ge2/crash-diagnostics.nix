# ge2 was hitting hard freezes needing a manual power-cycle. The NMI
# watchdog is enabled (kernel.nmi_watchdog=1) and detects hard/soft
# lockups, but by default it only logs - useless if the machine is too
# wedged to flush that log to disk. Forcing a panic on lockup detection
# makes the kernel dump state into pstore (EFI-backed, survives the
# forced reboot) via systemd-pstore.service, which is already enabled.
#
# That capture (/var/lib/systemd/pstore after reboot) caught the actual
# cause twice: an "Oops: Split lock detected" at skb_clone+0x190/0x220,
# hit from ordinary UDP sends (seen from both rygel and kubectl - not
# app-specific). Intel's split-lock detector on this Raptor Lake CPU is
# flagging an atomic op in the kernel's own skb_clone as a split lock;
# a #AC exception in kernel mode is always fatal, so it panics
# (panic_on_oops-style) instead of just warning like it would for
# userspace. The machine doesn't auto-reboot after (no kernel.panic
# timeout set), so it just sits there dead - indistinguishable from a
# true hang unless you already have a serial console or pstore capture.
# Disabling the split-lock detector at the CPU/MSR level sidesteps this
# false-positive entirely.
{
  boot.kernel.sysctl = {
    "kernel.hardlockup_panic" = 1;
    "kernel.softlockup_panic" = 1;
  };

  boot.kernelParams = [ "split_lock_detect=off" ];
}
