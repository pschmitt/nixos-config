{
  # index-recursive-directories defaults to the whole $HOME, which includes
  # dev tool caches under ~/.cache and ~/.local/share (npm/go/cargo/rustup/
  # containers/model caches, tens of GB of constantly-churning files).
  # localsearch-3 (upstream-broken in 3.11.1) spins into a worker-pool spawn
  # storm crawling those, pegging a CPU core for hours — the cause of
  # intermittent tmux/desktop freezes seen on both ge2 and fnuc.
  dconf.settings."org/freedesktop/tracker3/miner/files" = {
    ignored-directories = [
      ".cache"
      ".direnv"
      ".local"
      ".venv"
      "core-dumps"
      "CVS"
      "lost+found"
      "node_modules"
      "po"
      "result"
      "target"
    ];
  };
}
