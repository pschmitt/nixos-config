{
  # An X display per session: groundwork for streaming the handoff view as
  # H.264 video (each session's screen captured on its own), tried on fnuc
  # first since its GPU can encode it.
  services.browser-daemon.displayMode = "per-session";
}
