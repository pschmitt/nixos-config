{ pkgs, ... }:
let
  restartAudio = import ./restart-audio.nix pkgs;

  # Crash diagnostics: rtkit caps RLIMIT_RTTIME at 200ms and PipeWire sets
  # soft = hard = 200ms, so a realtime thread that runs too long is SIGKILLed
  # without a trace. A lower soft limit makes the kernel send SIGXCPU first,
  # which dumps core (coredumpctl) with the stuck thread.
  #
  # module-rt has to stay where the stock config loads it: a module-rt added
  # from conf.d loads after the data loop has started, which then never gets
  # realtime priority. The daemon ignores module.rt.args, so derive the whole
  # pipewire.conf from the package's stock one and only set the two limits.
  pipewireConf = pkgs.runCommand "pipewire.conf" { } ''
    sed \
      -e 's/#rt\.time\.soft = -1/rt.time.soft = 150000/' \
      -e 's/#rt\.time\.hard = -1/rt.time.hard = 200000/' \
      ${pkgs.pipewire}/share/pipewire/pipewire.conf > $out
    grep -q '^ *rt\.time\.soft = 150000' $out
    grep -q '^ *rt\.time\.hard = 200000' $out
  '';
in
{
  xdg.configFile."pipewire/pipewire.conf" = {
    source = pipewireConf;
    onChange = ''
      run ${restartAudio}/bin/restart-audio pipewire.service pipewire-pulse.service wireplumber.service
    '';
  };
}
