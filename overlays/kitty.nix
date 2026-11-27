{ prev }:
{
  # kitty always runs the remote_file kitten (remote file:// hyperlinks) in
  # "ask" mode. Let KITTY_REMOTE_FILE_ACTION (open, edit or save; set through
  # `env` in kitty.conf) skip the prompt. Local feature, not upstream.
  kitty = prev.kitty.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/kitty/kitty-remote-file-default-action.patch ];
  });
}
