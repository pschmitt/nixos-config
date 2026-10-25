{
  services.ssh-clipboard = {
    headlessWayland = true;
    # Wayland has no clipboard change events, so the daemon re-reads the whole
    # clipboard every poll; 75ms burns ~14% of a core with a screenshot on it
    pollIntervalMs = 500;
  };
}
