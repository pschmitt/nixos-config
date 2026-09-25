local M = {}

-- https://github.com/ibhagwan/fzf-lua/wiki/Advanced#prioritize-cwd-when-using-git_files
-- https://github.com/ibhagwan/fzf-lua/issues/459
-- The reason I added  'opts' as a parameter is so you can
-- call this function with your own parameters / customizations
-- for example: 'git_files_cwd_aware({ cwd = <another git repo> })'
function M.git_files_cwd_aware(opts)
  opts = opts or {}
  local fzf_lua = require("fzf-lua")
  local path = require("fzf-lua.path")

  -- git_root() will warn us if we're not inside a git repo
  -- so we don't have to add another warning here, if
  -- you want to avoid the error message change it to:
  -- local git_root = fzf_lua.path.git_root(opts, true)
  local git_root = path.git_root(opts)

  if not git_root then
    return
  end

  local relative = path.relative_to(vim.loop.cwd(), git_root)
  opts.fzf_opts = {
    ["--query"] = git_root ~= relative and relative or nil,
  }

  return fzf_lua.git_files(opts)
end

-- function M.yadm_files(opts)
--   opts = opts or {}
--   require("fzf-lua").files({
--     -- prompt = "Yadm> ",
--     winopts = {
--       title = "YADM files",
--     },
--     cmd = "yadm ls-files",
--     cwd = "~",
--   })
-- end

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

  local path = require("fzf-lua.path")
  local git_root = path.git_root(opts, true)

  if not git_root then
    return M.yadm_files(opts)
  end

  if opts.cwd_aware then
    return M.git_files_cwd_aware(opts)
  end

  local fzf_lua = require("fzf-lua")
  return fzf_lua.git_files(opts)
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
