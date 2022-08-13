local project_dir = vim.fn.getcwd()
local gradlew = io.open(project_dir .. '/gradlew')

if gradlew then
  io.close(gradlew)
  local project_name = string.gsub(project_dir, '/', '_')
  local workspace_dir = '/home/madis/.local/jdtls/workspace/' .. project_name
  vim.fn.mkdir(workspace_dir, 'p')

  -- See `:help vim.lsp.start_client` for an overview of the supported `config` options.
  local config = {
    on_attach = function(client, bufnr)
      local opts = { noremap=true, silent=true }
      vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
      vim.api.nvim_buf_set_keymap(bufnr, 'n', "<F9>", "<Cmd>lua require'jdtls'.organize_imports()<CR>", opts)
      vim.api.nvim_buf_set_keymap(bufnr, 'i', "<F9>", "<Esc><Cmd>lua require'jdtls'.organize_imports()<CR>i", opts)
      vim.api.nvim_buf_set_keymap(bufnr, 'n', 'K', '<Cmd>lua vim.lsp.buf.hover()<CR>', opts)
    end,
    -- The command that starts the language server
    -- See: https://github.com/eclipse/eclipse.jdt.ls#running-from-the-command-line
    cmd = {
      'java', -- 💀 or '/path/to/java11_or_newer/bin/java'
              -- depends on if `java` is in your $PATH env variable and if it points to the right version.
      '-Declipse.application=org.eclipse.jdt.ls.core.id1',
      '-Dosgi.bundles.defaultStartLevel=4',
      '-Declipse.product=org.eclipse.jdt.ls.core.product',
      '-Dlog.protocol=true',
      '-Dlog.level=ALL',
      '-Xms1g',
      '--add-modules=ALL-SYSTEM',
      '--add-opens', 'java.base/java.util=ALL-UNNAMED',
      '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
      '-javaagent:/home/madis/.local/jdtls/lombok.jar',
      '-Xbootclasspath/a:/home/madis/.local/jdtls/lombok.jar',
      -- 💀 Must point to the eclipse.jdt.ls installation
      '-jar', '/home/madis/.local/jdtls/1.6/plugins/org.eclipse.equinox.launcher_1.6.400.v20210924-0641.jar',
      -- 💀 Must point to the eclipse.jdt.ls installation, depending on your system.
      '-configuration', '/home/madis/.local/jdtls/1.6/config_linux',
      -- 💀 See `data directory configuration` section in the README
      '-data', workspace_dir
    },

    -- 💀 This is the default if not provided, you can remove it. Or adjust as needed.
    -- One dedicated LSP server & client will be started per unique root_dir
    root_dir = require('jdtls.setup').find_root({'.git', 'gradlew', 'mvnw'}),

    -- Here you can configure eclipse.jdt.ls specific settings
    -- See https://github.com/eclipse/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request
    -- for a list of options
    settings = {
      java = {
      }
    }
  }
  -- This starts a new client & server,
  -- or attaches to an existing client & server depending on the `root_dir`.
  require('jdtls').start_or_attach(config)
end
