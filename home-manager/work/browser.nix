{ pkgs, ... }:
{
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
              inherit name;
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
              icon = "https://git.mgmt.innovo-cloud.de/assets/favicon-72a2cad5025aa931d6ea56c3201d1f18e68a8cd39788c7c80d5b2b82aa5143ef.png";
              updateInterval = 24 * 60 * 60 * 1000; # every day
              definedAliases = [ alias ];
            };
        in
        {
          # Use the helper function to define the search engines
          gec-gitlab-projects = makeGitLabSearchEngine {
            name = "GEC GitLab (projects)";
            scope = "projects";
            alias = "gitp";
          };

          gec-gitlab-code = makeGitLabSearchEngine {
            name = "GEC GitLab (code)";
            scope = "blobs";
            alias = "gitc";
          };

          wiit-jira = {
            name = "WIIT JIRA";
            urls = [
              {
                template =
                  let
                    jiraUrl = "https://jira.wiit.one";

                    # List of JIRA projects to search in
                    jiraProjects = [
                      # "Incident Management" # not available yet, still on the old instance...
                      "HELPDESK"
                      "EDGE"
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
            icon = "https://jira.wiit.one/s/-jac4wp/9170005/4r0zo/_/images/fav-generic.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "jira" ];
          };

          gec-confluence = {
            name = "GEC Confluence";
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
            icon = "https://confluence.gec.io/favicon.ico";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "confl" ];
          };
        };
    };
  };
}
