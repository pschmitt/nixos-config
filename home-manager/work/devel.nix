{ config, pkgs, ... }:
{

  # FIXME the sops-nix hm modules produces garbage
  # https://github.com/Mic92/sops-nix/issues/681
  sops = {
    secrets = {
      "artifactory/username" = { };
      "artifactory/password" = { };
      "gitlab/username" = { };
      "gitlab/password" = { };
    };
    templates.doers-envrc = {
      # TODO Can we somehow retrieve the value of XDG_RUNTIME_DIR in hm?
      # Or maybe the user's UID?
      # path = "/run/user/1000/secrets.d/doers.envrc";
      content = ''
        export VENDIR_SECRET_ARTIFACTORY_USERNAME=${config.sops.placeholder."artifactory/username"}
        export VENDIR_SECRET_ARTIFACTORY_PASSWORD=${config.sops.placeholder."artifactory/password"}
        export VENDIR_SECRET_GITLAB_USERNAME=${config.sops.placeholder."gitlab/username"}
        export VENDIR_SECRET_GITLAB_PASSWORD=${config.sops.placeholder."gitlab/password"}
      '';
    };
  };

  home.file."devel/work/gitops/.envrc" = {
    # NOTE we need to use mkOutOfStoreSymlink here to avoid placing the
    # rendered secrets in the store
    source = config.lib.file.mkOutOfStoreSymlink config.sops.templates."doers-envrc".path;
  };

  home.packages = with pkgs; [
    lefthook
    meld
    sqlfluff
    yamlfmt
    ytt
  ];
}
