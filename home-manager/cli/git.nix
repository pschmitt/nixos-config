# Git client config (formerly ~/.config/git in yadm). Work identity and
# private forge rewrites live in the private repo (hm/git.nix).
{ pkgs, ... }:
{
  home.packages = [ pkgs.diff-so-fancy ];

  programs.git = {
    enable = true;

    ignores = [
      ".envrc"
      ".envrc.md5sum"
    ];

    # These Android repositories publish a rolling release under the latest tag.
    includes =
      builtins.concatMap
        (
          repo:
          map
            (gitDir: {
              condition = "gitdir:${gitDir}";
              contents.remote.origin.fetch = "+refs/tags/latest:refs/tags/latest";
            })
            [
              "~/devel/private/pschmitt/${repo}.git/.git"
              "~/devel/private/pschmitt/${repo}.git/.git/worktrees/"
            ]
        )
        [
          "alles"
          "stricknani"
          "termuxpp"
        ];

    settings = {
      user = {
        name = "Philipp Schmitt";
        email = "philipp@schmitt.co";
        signingkey = "DC439C47EACB17F9";
      };

      init.defaultBranch = "main";
      commit.gpgsign = true;
      fetch = {
        prune = true;
        pruneTags = true;
        all = true;
      };
      pull.rebase = true;
      push = {
        default = "simple";
        autoSetupRemote = true;
        followTags = true;
      };
      rebase = {
        autoSquash = true;
        autoStash = true;
        updateRefs = true;
      };

      core = {
        autocrlf = "input";
        pager = "diff-so-fancy | less --tabs=4 -RFX";
        # Print paths with emojis as-is in "git diff --name-only"
        quotepath = false;
      };

      color = {
        ui = true;
        "diff-highlight" = {
          oldNormal = "red bold";
          oldHighlight = "red bold 52";
          newNormal = "green bold";
          newHighlight = "green bold 22";
        };
        diff = {
          meta = 227;
          frag = "magenta bold";
          commit = "227 bold";
          old = "red bold";
          new = "green bold";
          whitespace = "red reverse";
        };
      };
      diff-so-fancy.useUnicodeRuler = true;
      diff.sopsdiffer.textconv = "sops --decrypt";
      help.autocorrect = 10;
      safe.directory = [
        "/etc/*"
        "/mnt/*"
      ];
      # better tag version sorting
      tag.sort = "v:refname";

      alias = {
        permission-reset = "!zhj git::permission-reset";
        prune-merged = "!zhj git::prune-merged";
        prune-local-branches = "!zhj git::prune-local-branches";
        pushall = "!git remote | xargs --verbose -L1 git push --all";
        push-all = "!git remote | xargs --verbose -L1 git push --all";
        # 69420
        ass = "add";
        cum = "commit -m";
      };

      # GitHub: push over SSH, and always SSH for my own repos.
      # ghp is an alias for github.com/pschmitt (git clone ghp:adb.sh)
      github.user = "pschmitt";
      url = {
        "git@github.com:".pushInsteadOf = [
          "https://github.com/"
          "git://github.com/"
          "https://git::@github.com/"
        ];
        "git@github.com:pschmitt/".insteadOf = [
          "ghp:"
          "https://github.com/pschmitt/"
        ];
      };
      credential = {
        "https://github.com".helper = [
          ""
          "!gh auth git-credential"
        ];
        "https://gist.github.com".helper = [
          ""
          "!gh auth git-credential"
        ];
      };
    };
  };
}
