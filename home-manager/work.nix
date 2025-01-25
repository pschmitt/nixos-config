{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  # Conditional packages based on xserver.enabled
  guiPackages = lib.optionals osConfig.services.xserver.enable [ pkgs.onlyoffice-bin ];
in
{
  # FIXME the sops-nix hm modules produces garbage
  # https://github.com/Mic92/sops-nix/issues/681
  # sops = {
  #   secrets = {
  #     "artifactory/username" = { };
  #     "artifactory/password" = { };
  #     "gitlab/username" = { };
  #     "gitlab/password" = { };
  #   };
  #   templates.doers-envrc = {
  #     path = "${config.home.homeDirectory}/.cache/sops-nix/secrets/rendered";
  #     content = ''
  #       export VENDIR_SECRET_ARTIFACTORY_USERNAME=${config.sops.placeholder."artifactory/username"}
  #       export VENDIR_SECRET_ARTIFACTORY_PASSWORD=${config.sops.placeholder."artifactory/password"}
  #       export VENDIR_SECRET_GITLAB_USERNAME=${config.sops.placeholder."gitlab/username"}
  #       export VENDIR_SECRET_GITLAB_PASSWORD=${config.sops.placeholder."gitlab/password"}
  #     '';
  #   };
  # };

  home.file."devel/work/gitops/.envrc" = {
    source = config.lib.file.mkOutOfStoreSymlink osConfig.sops.templates."doers-envrc".path;
  };

  home.packages =
    with pkgs;
    [
      # Work
      acme-sh
      argocd
      argocd-vault-plugin
      azure-cli
      cmctl
      glab
      kubectl
      (writeShellScriptBin "kubectl-1.21" ''
        ${pkgs.kubectl-121.kubectl}/bin/kubectl "$@"
      '')
      (writeShellScriptBin "kubectl-1.23" ''
        ${pkgs.kubectl-123.kubectl}/bin/kubectl "$@"
      '')
      kubernetes-helm
      ipmitool
      ldifj
      lefthook
      lego
      httptunnel
      chisel
      corkscrew
      oci-cli
      openldap
      openstackclient-full
      openvpn
      rancher
      rclone
      s3cmd
      skopeo
      stern
      sqlfluff
      taskwarrior3
      # terraform # 1.6+
      (writeShellScriptBin "terraform-unfree" ''
        ${pkgs.terraform}/bin/terraform "$@"
      '')
      pkgs.terraform-157.terraform
      terragrunt
      opentofu
      thunderbird
      timewarrior
      timewarrior-jirapush
      vendir
      velero
      vault
      yamlfmt
      ytt
    ]
    ++ guiPackages;

  programs.firefox.profiles.default = {
    search = {
      # https://nix-community.github.io/home-manager/options.xhtml#opt-programs.firefox.profiles._name_.search.engines
      engines =
        let
          # Define a helper function to create the GitLab search engine
          makeGitLabSearchEngine =
            {
              scope,
              alias,
              name,
            }:
            {
              urls = [
                {
                  template = "https://git.mgmt.innovo-cloud.de/search";
                  params = [
                    {
                      name = "scope";
                      # Allowed values:
                      # "blobs" (code)
                      # "commits"
                      # "epics"
                      # "issues"
                      # "milestones"
                      # "merge_requests"
                      # "notes" (comments)
                      # "projects"
                      # "users"
                      # "wiki_blobs"
                      value = scope;
                    }
                    {
                      name = "search";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              iconUpdateURL = "https://git.mgmt.innovo-cloud.de/assets/favicon-72a2cad5025aa931d6ea56c3201d1f18e68a8cd39788c7c80d5b2b82aa5143ef.png";
              updateInterval = 24 * 60 * 60 * 1000; # every day
              definedAliases = [ alias ];
            };
        in
        {
          # Use the helper function to define the search engines
          "GEC GitLab (projects)" = makeGitLabSearchEngine {
            name = "GEC GitLab (projects)";
            scope = "projects";
            alias = "gitp";
          };

          "GEC GitLab (code)" = makeGitLabSearchEngine {
            name = "GEC GitLab (code)";
            scope = "blobs";
            alias = "gitc";
          };

          "GEC JIRA" = {
            urls = [
              {
                template =
                  let
                    jiraUrl = "https://jira.gec.io";

                    # List of JIRA projects to search in
                    jiraProjects = [
                      "Incident Management"
                      "HELPDESK"
                      "Oncite Open Edition 🦦"
                      "❌ (deprecated) OOE-OPS"
                      "Edge Stack - Services 🐄🔑🐙💰㊙️"
                    ];

                    # Wrap the encoded project names quotes
                    quotedProjects = map (p: "\"${p}\"") jiraProjects;

                    # Construct the JQL project clause
                    projectClause = "project in (${pkgs.lib.strings.concatStringsSep "," quotedProjects})";

                    # newest to oldest sort
                    sortOrder = "ORDER BY created DESC";
                    filter = "type not in (Sub-task) and text ~ \"*{searchTerms}*\"";

                    # Construct JQL query
                    jqlQuery = "${projectClause} and ${filter} ${sortOrder}";
                  in
                  "${jiraUrl}/issues/?jql=${jqlQuery}";
              }
            ];
            iconUpdateURL = "https://jira.gec.io/s/-8atya2/9160001/1dlckms/_/images/fav-generic.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "jira" ];
          };

          "GEC Confluence" = {
            urls = [
              {
                # FIXME This search sucks. Consider using CQL aka "Enhanced Search". Sadly there seems to be no way provide a search query directly via the URL
                template = "https://confluence.gec.io/dosearchsite.action?cql=siteSearch+~+%22isd%22";
                params = [
                  {
                    name = "queryString";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            iconUpdateURL = "https://confluence.gec.io/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "confl" ];
          };
        };
    };
  };
}
