local source = {}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:enabled()
  return not require("utils").is_termux() and vim.fn.executable("browser-daemon") == 1
end

function source:get_completions(_, callback)
  local items, seen, jobs = {}, {}, {}
  local cancelled = false
  local function finish()
    if not cancelled then
      callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
    end
  end
  local opts = { text = true, timeout = 3000 }
  jobs[1] = vim.system({ "browser-daemon", "tabs", "--local", "--active", "--json" }, opts,
    vim.schedule_wrap(function(result)
      if cancelled then return end
      local ok, tabs = pcall(vim.json.decode, result.stdout or "")
      if result.code ~= 0 or not ok or type(tabs) ~= "table" or #tabs == 0 then
        finish()
        return
      end
      local pending = #tabs
      for _, tab in ipairs(tabs) do
        jobs[#jobs + 1] = vim.system({ "browser-daemon", "tabs", "--local", "text", tab.id, "-" }, opts,
          vim.schedule_wrap(function(page)
            if cancelled then return end
            if page.code == 0 then
              for word in (page.stdout or ""):gmatch("[%w_]+") do
                if #word >= 3 and not seen[word] then
                  seen[word] = true
                  items[#items + 1] = { label = word, kind = vim.lsp.protocol.CompletionItemKind.Text }
                end
              end
            end
            pending = pending - 1
            if pending == 0 then finish() end
          end))
      end
    end))
  return function()
    cancelled = true
    for _, job in ipairs(jobs) do
      if not job:is_closing() then job:kill(15) end
    end
  end
end

return source
