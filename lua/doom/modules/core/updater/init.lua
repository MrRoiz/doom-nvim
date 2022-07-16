--[[
--  Doom updater
--
--  Update your doom nvim config using the :DoomUpdate command.
--  Currently disabled (not imported) because I'm not sure how nicely this will play
--  with user's own changes to config.lua/modules.lua.  May re-enable in future once
--  we land on a strategy to solve this.
--
--  One solution could be automatically creating a `user-config` branch on first load
--  and automatically pulling from tags into the `user-config` branch.
--
--  Works by fetching tags from origin, comparing semantic versions and checking out
--  the tag with the greatest semantic version.
--
--]]
local updater = {}

--- @class DoomVersion
--- @field message string
--- @field major number
--- @field minor number
--- @field patch number

updater.packages = {
  ["plenary.nvim"] = {
    "nvim-lua/plenary.nvim",
    commit = "9c3239bc5f99b85be1123107f7290d16a68f8e64",
    module = "plenary",
  },
}

updater.settings = {
  unstable = false,
}

updater._cwd = vim.fn.stdpath("config")

--- Using git and plenary jobs gets a list of all available versions to update to
---@param callback function Handler to receive the list of versions
updater._pull_tags = function(callback)
  local Job = require("plenary.job")
  local job = Job
    :new({
      command = "git",
      args = { "fetch", "--tags", "--all" },
      cwd = updater._cwd,
      on_exit = function(j, exit_code)
        if exit_code ~= 0 then
          callback(nil, "Error pulling tags... \n\n " .. vim.inspect(j.result()))
        end
        callback(j:result())
      end,
    })
    :start()
end

--- Gets the current commit sha or error
---@param callback function(commit_sha, error_string)
updater._get_commit_sha = function(callback)
  local Job = require("plenary.job")

  Job
    :new({
      command = "git",
      args = { "rev-parse", "HEAD" },
      on_exit = function(j, exit_code)
        if exit_code ~= 0 then
          callback(nil, "Error getting current commit... \n\n" .. vim.inspect(j:result()))
          return
        end
        local result = j:result()
        if #result == 1 then
          callback(result[1])
        else
          callback(nil, "Error getting current commit... No output.")
        end
      end,
    })
    :start()
end

--- Gets all version tags as a table of strings
---@param callback function(all_versions, error_string)
updater._get_all_versions = function(callback)
  local Job = require("plenary.job")
  Job
    :new({
      command = "git",
      args = { "tag", "-l", "--sort", "-version:refname" },
      cwd = updater._cwd,
      on_exit = function(j, err_code)
        ---@param version string
        local filter_develop_predicate = function(version)
          if not updater.settings.unstable and version:match("alpha") or version:match("beta") then
            return false
          end
          return true
        end
        local result = vim.tbl_filter(filter_develop_predicate, j:result())
        callback(result)
      end,
    })
    :start()
end

--- Using a commit sha, finds the first version tag in commit history
---@param commit_sha string
---@param callback function(version_tag, error_string)
updater._get_last_version_for_commit = function(commit_sha, callback)
  local Job = require("plenary.job")
  Job
    :new({
      command = "git",
      args = { "tag", "-l", "--sort", "-version:refname", "--merged", commit_sha },
      cwd = updater._cwd,
      on_exit = function(j, exit_code)
        if exit_code ~= 0 then
          callback(nil, "Error getting current version... \n\n " .. vim.inspect(j:result()))
          return
        end
        local result = j:result()
        if #result > 1 then
          callback(result[1])
        else
          callback(nil, "Error getting current version... No output.")
        end
      end,
    })
    :start()
end

--- Gets the current version and the latest upstream version
---@param callback function(current_version, latest_version, error_string)
updater._fetch_current_and_latest_version = function(callback)
  updater._pull_tags(function(result, error)
    if error then
      callback(nil, nil, error)
      return
    end
    updater._get_commit_sha(function(commit_sha, error)
      if error then
        callback(nil, nil, error)
        return
      end

      local cur_version, all_versions = nil, nil
      local try_compare_updates = function()
        if cur_version and all_versions then
          -- Find How many versions behind we are
          if #all_versions > 1 then
            callback(cur_version, all_versions[1])
            return
          else
            callback(nil, nil, "Error getting latest version.  The versions list is empty!")
          end
        end
      end

      updater._get_last_version_for_commit(commit_sha, function(version)
        cur_version = version
        try_compare_updates()
      end)

      updater._get_all_versions(function(all)
        all_versions = all
        try_compare_updates()
      end)
    end)
  end)
end

--- Entry point for `:DoomCheckUpdates`, fetches new tags, compares with current version and notifies results
updater._check_updates = function()
  local log = require("doom.utils.logging")
  vim.notify("updater: Checking updates...")

  updater._fetch_current_and_latest_version(function(current_version, latest_version, error)
    vim.defer_fn(function()
      if error then
        log.error(("updater: Error checking updates... %s"):format(error))
        return
      end

      if current_version == latest_version then
        vim.notify(("updater: You are up to date! (%s)"):format(current_version))
      else
        vim.notify(
          (
            "updater: There is a new version (%s).  You are currently on %s.  Run `:DoomUpdate` to update."
          ):format(latest_version, current_version)
        )
      end
    end, 0)
  end)
end

--- Attempts to merge a version into the current branch, fails if working tree is dirty
---@param target_version string
---@param callback function(error_string)
updater._try_merge_version = function(target_version, callback)
  local Job = require("plenary.job")

  local merge_job = Job:new({
    command = "git",
    args = { "merge", target_version },
    cwd = updater._cwd,
    on_exit = function(j, exit_code)
      if exit_code ~= 0 then
        callback(nil, "Error merging " .. target_version .. "... \n\n " .. vim.inspect(j:result()))
        return
      end
      callback(nil)
    end,
  })

  Job
    :new({
      command = "git",
      args = { "diff", "--quiet" },
      cwd = updater._cwd,
      on_exit = function(j, exit_code)
        if exit_code ~= 0 then
          callback(
            (
              "Tried to update to new version %s but could not due to uncommitted changes.  Please commit or stash your changes before trying again."
            ):format(target_version)
          )
        else
          merge_job:start()
        end
      end,
    })
    :start()
end

--- Entry point for `:DoomUpdate`, fetches new tags, compares with current version and attempts to merge new tags into current branch
updater._try_update = function()
  local log = require("doom.utils.logging")
  vim.notify("updater: Attempting to update...")

  updater._fetch_current_and_latest_version(function(current_version, latest_version, error)
    vim.defer_fn(function()
      if error then
        log.error(("updater: Error checking updates... %s"):format(error))
        return
      end

      if current_version == latest_version then
        vim.notify(
          ("updater: You are already using the latest version! (%s)"):format(current_version)
        )
      else
        updater._try_merge_version(latest_version, function(error)
          vim.defer_fn(function()
            if error then
              log.error(("updater: Error updating... %s"):format(error))
            else
              vim.notify(
                (
                  "updater: Updated to version %s!  Check the changelog at https://github.com/NTBBloodbath/doom-nvim/releases/tag/%s"
                ):format(latest_version, latest_version)
              )
            end
          end, 0)
        end)
      end
    end, 0)
  end)
end

updater.cmds = {
  {
    "DoomUpdate",
    function()
      updater._try_update()
    end,
  },
  {
    "DoomCheckUpdates",
    function()
      updater._check_updates()
    end,
  },
}
return updater
