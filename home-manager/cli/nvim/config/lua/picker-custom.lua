local M = {}

function M.yadm_files(opts)
  opts = opts or {}
  require("snacks").picker({
    finder = "proc",
    cmd = "yadm",
    args = { "ls-files" },
    cwd = "~",
    title = "YADM Files",
    transform = function(item)
      item.file = '~/' .. item.text
    end,
  })
end

function M.git_or_yadm_files(opts)
  opts = opts or {}

  if not require("utils").in_git_repo() then
    return M.yadm_files(opts)
  end

  return require("snacks").picker("git_files", opts)
end

function M.git_or_files(opts)
  opts = opts or {}

  local picker = require("snacks").picker
  local in_git_repo = require("utils").in_git_repo()

  if not in_git_repo then
    return picker("files")
  end

  return picker("git_files", { untracked = true })
end

return M
