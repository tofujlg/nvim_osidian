local vault_path = vim.fn.expand '~/docs/Obsidian_vault'

return {
  {
    'obsidian-nvim/obsidian.nvim',
    version = '*', -- use latest release, remove to use latest commit
    ft = 'markdown',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-telescope/telescope.nvim',
      'saghen/blink.cmp',
    },
  ---@module 'obsidian'
  ---@type obsidian.config
  opts = {
    legacy_commands = false, -- this will be removed in the next major release
    completion = {
      blink = true,
      min_chars = 0,
    },
    ui = {
      hl_groups = {
        ObsidianRefText = { underline = true, fg = '#7c9aa0' },
        ObsidianExtLinkIcon = { fg = '#7c9aa0' },
      },
    },
    frontmatter = {
      enabled = false,
    },
    workspaces = {
      {
        name = 'main',
        path = vault_path,
      },
    },
    daily_notes = {
      folder = 'Journals',
      date_format = '%Y%m%d',
      template = 'Journal/Template_daily_note_nvim.md',
    },
    weekly_notes = {
      folder = 'Journals/Weekly notes',
      date_format = 'Week-%V-%Y',
    },
    templates = {
      folder = 'Templater',
      substitutions = {
        yesterday = function()
          return os.date('%Y%m%d', os.time() - 86400)
        end,
        tomorrow = function()
          return os.date('%Y%m%d', os.time() + 86400)
        end,
        week_year = function()
          return 'Week-' .. os.date('%V-%Y')
        end,
        month_year = function()
          return os.date('%B-%Y')
        end,
        date_iso = function()
          return os.date('%Y-%m-%d')
        end,
        date_compact = function()
          return os.date('%Y%m%d')
        end,
        date_slash = function()
          return os.date('%Y/%m/%d')
        end,
      },
    },
    -- Use the note title as the filename instead of random ID
    note_id_func = function(title)
      return title
    end,
  },
  config = function(_, opts)
    require('obsidian').setup(opts)
    do
      local api = require 'obsidian.api'
      local original_resolve_workspace_dir = api.resolve_workspace_dir
      api.resolve_workspace_dir = function()
        if vim.in_fast_event() then
          return Obsidian.workspace.root
        end
        return original_resolve_workspace_dir()
      end
    end

    local vault_root = vault_path .. '/'

    -- Custom function to search by alias and filename
    local function search_by_alias()
      local pickers = require 'telescope.pickers'
      local finders = require 'telescope.finders'
      local conf = require('telescope.config').values
      local actions = require 'telescope.actions'
      local action_state = require 'telescope.actions.state'

      -- Collect all files with their aliases
      local entries = {}
      local scandir = require 'plenary.scandir'
      local files = scandir.scan_dir(vault_root, { hidden = false, depth = 10, add_dirs = false })

      for _, file in ipairs(files) do
        if file:match '%.md$' then
          local rel_path = file:gsub(vault_root, '')
          local filename = vim.fn.fnamemodify(file, ':t:r')

          -- Always add an entry for the filename
          table.insert(entries, {
            alias = nil,
            filename = filename,
            path = file,
            display = filename .. ' (' .. rel_path .. ')',
            ordinal = filename,
          })

          local f = io.open(file, 'r')
          if f then
            local content = f:read '*a'
            f:close()

            -- Parse YAML frontmatter
            local frontmatter = content:match '^%-%-%-\n(.-)\n%-%-%-'
            if frontmatter then
              -- Extract aliases (supports both list and inline formats)
              local aliases = {}

              -- Match "aliases: [alias1, alias2]" format
              local inline_aliases = frontmatter:match 'aliases:%s*%[(.-)%]'
              if inline_aliases then
                for alias in inline_aliases:gmatch '[^,]+' do
                  alias = alias:match '^%s*(.-)%s*$' -- trim
                  alias = alias:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1') -- remove quotes
                  if alias ~= '' then
                    table.insert(aliases, alias)
                  end
                end
              end

              -- Match YAML list format:
              -- aliases:
              --   - alias1
              --   - alias2
              local list_section = frontmatter:match 'aliases:%s*\n(.-)\n%w' or frontmatter:match 'aliases:%s*\n(.-)$'
              if list_section then
                for alias in list_section:gmatch '%s*%-%s*([^\n]+)' do
                  alias = alias:match '^%s*(.-)%s*$'
                  alias = alias:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1')
                  if alias ~= '' then
                    table.insert(aliases, alias)
                  end
                end
              end

              -- Add entries for each alias
              for _, alias in ipairs(aliases) do
                table.insert(entries, {
                  alias = alias,
                  filename = filename,
                  path = file,
                  display = alias .. ' -> ' .. rel_path,
                  ordinal = alias .. ' ' .. filename,
                })
              end
            end
          end
        end
      end

      -- Custom sorter that prioritizes aliases over filenames
      local sorters = require 'telescope.sorters'
      local alias_priority_sorter = sorters.Sorter:new {
        scoring_function = function(_, prompt, line, entry)
          if prompt == '' or prompt == nil then
            return 1
          end

          local prompt_lower = prompt:lower()
          local value = entry.value
          local is_alias = value.alias ~= nil

          -- Check for exact match on alias
          if is_alias and value.alias:lower() == prompt_lower then
            return 0 -- Best possible score
          end

          -- Check for exact match on filename (but lower priority than alias)
          if not is_alias and value.filename:lower() == prompt_lower then
            return 0.5
          end

          -- Check for prefix match on alias
          if is_alias and value.alias:lower():sub(1, #prompt_lower) == prompt_lower then
            return 1
          end

          -- Check for prefix match on filename
          if not is_alias and value.filename:lower():sub(1, #prompt_lower) == prompt_lower then
            return 1.5
          end

          -- Check if alias contains the prompt
          if is_alias and value.alias:lower():find(prompt_lower, 1, true) then
            return 2
          end

          -- Check if filename contains the prompt
          if value.filename:lower():find(prompt_lower, 1, true) then
            return is_alias and 2.5 or 3
          end

          -- No match
          return -1
        end,
      }

      pickers
        .new({}, {
          prompt_title = 'Search Obsidian (Alias & Filename)',
          finder = finders.new_table {
            results = entries,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.display,
                ordinal = entry.ordinal,
                path = entry.path,
              }
            end,
          },
          sorter = alias_priority_sorter,
          previewer = conf.file_previewer {},
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if selection then
                vim.cmd('edit ' .. vim.fn.fnameescape(selection.path))
              end
            end)
            return true
          end,
        })
        :find()
    end

    -- Open weekly note
    local function open_weekly_note()
      local filename = os.date 'Week-%V-%Y'
      local filepath = vault_root .. 'Journals/Weekly notes/' .. filename .. '.md'
      vim.cmd('edit ' .. vim.fn.fnameescape(filepath))
    end

    -- Open monthly note
    local function open_monthly_note()
      local filename = os.date '%B-%Y'
      local filepath = vault_root .. 'Journals/' .. filename .. '.md'
      vim.cmd('edit ' .. vim.fn.fnameescape(filepath))
    end

    -- Insert link to today's daily note
    local function insert_today_link()
      local date_link = os.date '%Y%m%d'
      local date_display = os.date '%Y/%m/%d'
      local link = '[[' .. date_link .. '|' .. date_display .. ']]'
      vim.api.nvim_put({ link }, 'c', true, true)
    end

    -- Paste URL as markdown link (fetches page title)
    local function paste_url_as_markdown_link()
      local url = vim.fn.getreg '+'
      if url:match '^https?://' then
        local cmd = string.format("curl -sL '%s' | grep -oP '(?<=<title>).*(?=</title>)' | head -1", url)
        local title = vim.fn.system(cmd):gsub('\n', '')
        if title == '' then
          title = url
        end
        local link = string.format('[%s](%s)', title, url)
        vim.api.nvim_put({ link }, 'c', true, true)
      else
        vim.api.nvim_put({ url }, 'c', true, true)
      end
    end

    -- Set up keymaps
    vim.keymap.set('n', '<leader> ', search_by_alias, { desc = 'Search Obsidian (Alias & Filename)' })
    vim.keymap.set('n', '<leader>od', '<cmd>Obsidian today<cr>', { desc = '[O]bsidian [D]aily note (today)' })
    vim.keymap.set('n', '<leader>ow', open_weekly_note, { desc = '[O]bsidian [W]eekly note' })
    vim.keymap.set('n', '<leader>om', open_monthly_note, { desc = '[O]bsidian [M]onthly note' })
    vim.keymap.set('n', '<leader>ot', insert_today_link, { desc = '[O]bsidian insert [T]oday link' })
    vim.keymap.set('n', '<leader>op', paste_url_as_markdown_link, { desc = '[O]bsidian [P]aste URL as link' })

    vim.api.nvim_create_user_command('ObsidianMonthly', open_monthly_note, {
      desc = 'Open Obsidian monthly note',
    })
  end,
  },
}
