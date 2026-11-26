-- Did you mean...? When a file that does not exist is opened (`vim flake.`),
-- offer the files next to it that start with that name or are a typo away
-- (flake.nix, flake.lock) in a Snacks picker, with a preview, or creating the
-- new file as asked. Escape keeps the new file too.
local M = {}

local MAX_ENTRIES = 5000 -- don't crawl huge directories
local MAX_CANDIDATES = 30

-- Optimal string alignment distance (Levenshtein plus transpositions), capped:
-- returns max + 1 as soon as the distance is known to exceed max.
local function distance(a, b, max)
  local la, lb = #a, #b
  if math.abs(la - lb) > max then
    return max + 1
  end
  local prev2, prev, cur = {}, {}, {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    cur = { [0] = i }
    local row_min = i
    for j = 1, lb do
      local cost = a:byte(i) == b:byte(j) and 0 or 1
      local d = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      if
        i > 1
        and j > 1
        and a:byte(i) == b:byte(j - 1)
        and a:byte(i - 1) == b:byte(j)
      then
        d = math.min(d, prev2[j - 2] + 1)
      end
      cur[j] = d
      row_min = math.min(row_min, d)
    end
    if row_min > max then
      return max + 1
    end
    prev2, prev = prev, cur
  end
  return prev[lb]
end

---@param path string absolute path of the missing file
---@return table[]
local function candidates(path)
  local dir, base = vim.fs.dirname(path), vim.fs.basename(path)
  local stat = vim.uv.fs_stat(dir)
  if base == "" or not stat or stat.type ~= "directory" then
    return {}
  end

  local lbase = base:lower()
  local max_typo = #base <= 3 and 1 or 2
  local found, seen = {}, 0
  for name, type in vim.fs.dir(dir) do
    seen = seen + 1
    if seen > MAX_ENTRIES then
      break
    end
    if type == "file" or type == "link" then
      local lname = name:lower()
      local kind, score
      if vim.startswith(name, base) then
        kind, score = "prefix", #name - #base
      elseif vim.startswith(lname, lbase) then
        kind, score = "prefix", #name - #base + 1
      else
        local d = distance(lname, lbase, max_typo)
        if d <= max_typo then
          kind, score = "typo", 100 + d * 10 + math.abs(#name - #base)
        end
      end
      if kind then
        found[#found + 1] = {
          name = name,
          file = vim.fs.joinpath(dir, name),
          kind = kind,
          rank = score,
        }
      end
    end
  end

  table.sort(found, function(x, y)
    if x.rank ~= y.rank then
      return x.rank < y.rank
    end
    return x.name < y.name
  end)
  return vim.list_slice(found, 1, MAX_CANDIDATES)
end

local function relative(path)
  return vim.fn.fnamemodify(path, ":~:.")
end

-- Replace the buffer of the missing file with `file` in every window.
local function open_instead(buf, file)
  local wins = vim.fn.win_findbuf(buf)
  local target = vim.fn.fnameescape(file)
  if #wins == 0 then
    vim.cmd.edit(target)
  end
  for _, win in ipairs(wins) do
    vim.api.nvim_win_call(win, function()
      vim.cmd.edit(target)
    end)
  end
  -- Drop the placeholder unless it gained content or a file meanwhile
  if
    vim.api.nvim_buf_is_valid(buf)
    and not vim.bo[buf].modified
    and not vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
  then
    pcall(vim.api.nvim_buf_delete, buf, {})
  end
end

local queue, busy = {}, false
local process

local function ask(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local found = candidates(path)
  if #found == 0 then
    return false
  end

  local items = {}
  for i, c in ipairs(found) do
    items[#items + 1] = {
      idx = i,
      text = c.name,
      file = c.file,
      kind = c.kind,
    }
  end
  local create = {
    idx = #items + 1,
    text = vim.fs.basename(path),
    create = true,
    path = path,
  }
  items[#items + 1] = create

  local choice
  Snacks.picker({
    title = ("Did you mean? %s does not exist"):format(relative(path)),
    items = items,
    sort = { fields = { "score:desc", "idx" } },
    layout = {
      layout = {
        backdrop = false,
        width = 0.5,
        min_width = 60,
        height = math.min(#items, 10) + 2 + 16,
        border = "none",
        box = "vertical",
        {
          box = "vertical",
          border = true,
          title = "{title}",
          title_pos = "center",
          height = math.min(#items, 10) + 2,
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        { win = "preview", title = "{preview}", border = true },
      },
    },
    format = function(item, picker)
      if item.create then
        return {
          { " ", "SnacksPickerSpecial" },
          { "Create new file ", "Comment" },
          { relative(item.path), "SnacksPickerFile" },
        }
      end
      local ret = Snacks.picker.format.file(item, picker)
      if item.kind == "typo" then
        ret[#ret + 1] = { "  (typo?)", "DiagnosticHint", virtual = true }
      end
      return ret
    end,
    preview = function(ctx)
      if not ctx.item.create then
        return Snacks.picker.preview.file(ctx)
      end
      ctx.preview:reset()
      ctx.preview:set_title("New file")
      ctx.preview:set_lines({
        "",
        "  Keep editing a new, empty file:",
        "",
        "    " .. relative(ctx.item.path),
        "",
        "  It is created when you write it.",
      })
    end,
    confirm = function(picker, item)
      choice = item
      picker:close()
    end,
    on_close = function()
      vim.schedule(function()
        if choice and not choice.create and vim.api.nvim_buf_is_valid(buf) then
          open_instead(buf, choice.file)
        end
        busy = false
        process()
      end)
    end,
  })
  return true
end

function process()
  while not busy and #queue > 0 do
    local buf = table.remove(queue, 1)
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buftype == ""
      and not vim.bo[buf].modified
      and not vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
    then
      busy = ask(buf)
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("BufNewFile", {
    group = vim.api.nvim_create_augroup("user_did_you_mean", { clear = true }),
    callback = function(event)
      local name = event.match
      if name == "" or name:find("://", 1, true) or vim.g.did_you_mean == false then
        return
      end
      queue[#queue + 1] = event.buf
      -- Wait for the UI on startup, then ask after the buffer has settled
      if vim.v.vim_did_enter == 1 then
        vim.schedule(process)
      else
        vim.api.nvim_create_autocmd("VimEnter", {
          once = true,
          callback = function()
            vim.schedule(process)
          end,
        })
      end
    end,
  })
end

return M
