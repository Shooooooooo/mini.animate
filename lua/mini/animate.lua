--- *mini.animate* Animate common Neovim actions
---
--- MIT License Copyright (c) 2022 Evgeni Chasnovski

--- Features:
--- - Works out of the box with a single `require('mini.animate').setup()`.
---   No extra mappings or commands needed.
---
--- - Animate cursor movement inside same buffer by showing customizable path.
---   See |MiniAnimate.config.cursor| for more details.
---
--- - Animate scrolling with a series of subscrolls ("smooth scrolling").
---   See |MiniAnimate.config.scroll| for more details.
---
--- - Animate window resize by gradually changing sizes of all windows.
---   See |MiniAnimate.config.resize| for more details.
---
--- - Animate window open/close with visually updating floating window.
---   See |MiniAnimate.config.open| and |MiniAnimate.config.close| for more details.
---
--- - Animate split window open/close by moving split line from/to right or
---   bottom edge. See |MiniAnimate.config.split| for more details.
---
--- - Timings for all actions can be customized independently.
---   See |MiniAnimate-timing| for more details.
---
--- - Action animations can be enabled/disabled independently.
---
--- - All animations are asynchronous/non-blocking and trigger a targeted event
---   which can be used to perform actions after animation is done.
---
--- - |MiniAnimate.animate()| function which can be used to perform own animations.
---
--- Notes:
--- - Cursor movement is animated inside same window and buffer, not as cursor
---   moves across the screen.
---
--- - Scroll, resize, and split open animations are done with "side effects":
---   they actually change the state of what is animated (window view for
---   scroll and window sizes for others). This has a downside of possibly
---   needing extra work to account for asynchronous nature of animation (like
---   adjusting certain mappings, etc.). See |MiniAnimate.config.scroll|,
---   |MiniAnimate.config.resize|, and |MiniAnimate.config.split| for more details.
---
--- # Setup ~
---
--- This module needs a setup with `require('mini.animate').setup({})` (replace
--- `{}` with your `config` table). It will create global Lua table `MiniAnimate`
--- which you can use for scripting or manually (with `:lua MiniAnimate.*`).
---
--- See |MiniAnimate.config| for available config settings.
---
--- You can override runtime config settings (like `config.modifiers`) locally
--- to buffer inside `vim.b.minianimate_config` which should have same structure
--- as `MiniAnimate.config`. See |mini.nvim-buffer-local-config| for more details.
---
--- # Comparisons ~
---
--- - [Neovide](https://neovide.dev/):
---     - Neovide is a standalone GUI which has more control over its animations.
---       While |mini.animate| works inside terminal emulator (with all its
---       limitations, like lack of pixel-size control over animations).
---     - Neovide animates cursor movement across screen, while |mini.animate| -
---       as it moves across same buffer.
---     - Neovide has fixed number of animation effects per action, while
---       |mini.animate| is fully customizable.
---     - |mini.animate| implements animations for window open/close, while
---       Neovide does not.
--- - [edluffy/specs.nvim](https://github.com/edluffy/specs.nvim):
---     - |mini.animate| approaches cursor movement visualization via
---       customizable path function (uses extmarks), while `specs.nvim` can
---       customize within its own visual effects (shading and floating
---       window resizing).
--- - [karb94/neoscroll.nvim](https://github.com/karb94/neoscroll.nvim):
---     - Scroll animation is triggered only inside dedicated mappings.
---       |mini.animate| animates scroll resulting from any window view change.
--- - [anuvyklack/windows.nvim](https://github.com/anuvyklack/windows.nvim):
---     - Resize animation is done only within custom commands and mappings,
---       while |mini.animate| animates any resize with appropriate values of
---       |'winheight'| / |'winwidth'| and |'winminheight'| / |'winminwidth'|).
---
--- # Highlight groups ~
--- *MiniAnimate-hl-groups*
---
--- - `MiniAnimateCursor` - highlight of cursor during its animated movement.
--- - `MiniAnimateNormalFloat` - highlight of floating window for `open` and
---   `close` animations.
---
--- To change any highlight group, set it directly with |nvim_set_hl()|.
---
--- # Disabling ~
---
--- To disable, set `vim.g.minianimate_disable` (globally) or
--- `vim.b.minianimate_disable` (for a buffer) to `true`. Considering high
--- number of different scenarios and customization intentions, writing exact
--- rules for disabling module's functionality is left to user. See
--- |mini.nvim-disabling-recipes| for common recipes.
---@tag MiniAnimate

---@diagnostic disable:undefined-field

-- Module definition ==========================================================
local MiniAnimate = {}
local H = {}

--- Module setup
---
---@param config table|nil Module config table. See |MiniAnimate.config|.
---
---@usage >lua
---   require('mini.animate').setup() -- use default config
---   -- OR
---   require('mini.animate').setup({}) -- replace {} with your config table
--- <
MiniAnimate.setup = function(config)
  -- Export module
  _G.MiniAnimate = MiniAnimate

  -- Setup config
  config = H.setup_config(config)

  -- Apply config
  H.apply_config(config)

  -- Define behavior
  H.create_autocommands()
  H.track_scroll_state()

  -- Create default highlighting
  H.create_default_hl()
end

--- Defaults ~
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
---@text # General ~
---
--- - *MiniAnimate-timing* Every animation is a non-blockingly scheduled series of
---   specific actions. They are executed in a sequence of timed steps controlled
---   by `timing` option. It is a callable which, given next and total step numbers,
---   returns wait time (in ms).
---   See |MiniAnimate.gen_timing| for builtin timing functions.
---   See |MiniAnimate.animate()| for more details about animation process.
---
--- - Every animation can be enabled/disabled independently by setting `enable`
---   option to `true`/`false`.
---
--- - *MiniAnimate-done-event* Every animation triggers custom |User| event when it
---   is finished. It is named `MiniAnimateDoneXxx` with `Xxx` replaced by capitalized
---   supported animation action name (like `MiniAnimateDoneCursor`). Use it to
---   schedule some action after certain animation is completed. Alternatively,
---   you can use |MiniAnimate.execute_after()| (usually preferred in mappings).
---
--- - Each animation has its main step generator which defines how particular
---   animation is done. They all are callables which take some input data and
---   return an array of step data. Length of that array determines number of
---   animation steps. Outputs `nil` and empty table result in no animation.
---
--- # Cursor ~
--- *MiniAnimate.config.cursor*
---
--- This animation is triggered for each movement of cursor inside same window
--- and buffer. Its visualization step consists from placing single extmark (see
--- |extmarks|) at certain position. This extmark contains single space and is
--- highlighted with `MiniAnimateCursor` highlight group.
---
--- Exact places of extmark and their number is controlled by `path` option. It
--- is a callable which takes `destination` argument (2d integer point in
--- `(line, col)` coordinates) and returns array of relative to `(0, 0)` places
--- for extmark to be placed. Example:
--- - Input `(2, -3)` means cursor jumped 2 lines forward and 3 columns backward.
--- - Output `{ {0, 0 }, { 0, -1 }, { 0, -2 }, { 0, -3 }, { 1, -3 } }` means
---   that path is first visualized along the initial line and then along final
---   column.
---
--- See |MiniAnimate.gen_path| for builtin path generators.
---
--- Notes:
--- - Input `destination` value is computed ignoring folds. This is by design
---   as it helps better visualize distance between two cursor positions.
--- - Outputs of path generator resulting in a place where extmark can't be
---   placed are silently omitted during animation: this step won't show any
---   visualization.
---
--- Configuration example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     cursor = {
---       -- Animate for 200 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 200, unit = 'total' }),
---
---       -- Animate with shortest line for any cursor move
---       path = animate.gen_path.line({
---         predicate = function() return true end,
---       }),
---     }
---   })
--- <
--- After animation is done, `MiniAnimateDoneCursor` event is triggered.
---
--- # Scroll ~
--- *MiniAnimate.config.scroll*
---
--- This animation is triggered for each vertical scroll of current window.
--- Its visualization step consists from performing a small subscroll which all
--- in total will result into needed total scroll.
---
--- Exact subscroll values and their number is controlled by `subscroll` option.
--- It is a callable which takes `total_scroll` argument (single non-negative
--- integer) and returns array of non-negative integers each representing the
--- amount of lines needed to be scrolled inside corresponding step. All
--- subscroll values should sum to input `total_scroll`.
--- Example:
--- - Input `5` means that total scroll consists from 5 lines (either up or down,
---   which doesn't matter).
--- - Output of `{ 1, 1, 1, 1, 1 }` means that there are 5 equal subscrolls.
---
--- See |MiniAnimate.gen_subscroll| for builtin subscroll generators.
---
--- Notes:
--- - Input value of `total_scroll` is computed taking folds into account.
--- - As scroll animation is essentially a precisely scheduled non-blocking
---   subscrolls, this has two important interconnected consequences:
---     - If another scroll is attempted during the animation, it is done based
---       on the CURRENTLY VISIBLE window view. Example: if user presses |CTRL-D|
---       and then |CTRL-U| when animation is half done, window will not display
---       the previous view half of |'scroll'| above it. This especially affects
---       mouse wheel scrolling, as each its turn results in a new scroll for
---       number of lines defined by |'mousescroll'|. Tweak it to your liking.
---     - It breaks the use of several relative scrolling commands in the same
---       command. Use |MiniAnimate.execute_after()| to schedule action after
---       reaching target window view.
---       Example: a useful `nnoremap n nzvzz` mapping (consecutive application
---       of |n|, |zv|, and |zz|) should be expressed in the following way: >lua
---
---         '<Cmd>lua vim.cmd("normal! n"); ' ..
---           'MiniAnimate.execute_after("scroll", "normal! zvzz")<CR>'
--- <
--- - Default timing might conflict with scrolling via holding a key (like `j` or `k`
---   with |'wrap'| enabled) due to high key repeat rate: next scroll is done before
---   first step of current one finishes. Resolve this by not scrolling like that
---   or by ensuring maximum value of step duration to be lower than between
---   repeated keys: set timing like `function(_, n) return math.min(250/n, 10) end`
---   or use timing with constant step duration.
---
--- Configuration example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     scroll = {
---       -- Animate for 200 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 200, unit = 'total' }),
---
---       -- Animate equally but with at most 120 steps instead of default 60
---       subscroll = animate.gen_subscroll.equal({ max_output_steps = 120 }),
---     }
---   })
--- <
--- After animation is done, `MiniAnimateDoneScroll` event is triggered.
---
--- # Resize ~
--- *MiniAnimate.config.resize*
---
--- This animation is triggered for window resize while having same layout of
--- same windows. For example, it won't trigger when window is opened/closed or
--- after something like |CTRL-W_K|. Its visualization step consists from setting
--- certain sizes to all visible windows (last step being for "true" final sizes).
---
--- Exact window step sizes and their number is controlled by `subresize` option.
--- It is a callable which takes `sizes_from` and `sizes_to` arguments (both
--- tables with window id as keys and dimension table as values) and returns
--- array of same shaped data.
--- Example:
--- - Input: >lua
---
---   -- First
---   { [1000] = {width = 7, height = 5}, [1001] = {width = 7, height = 10} }
---   -- Second
---   { [1000] = {width = 9, height = 5}, [1001] = {width = 5, height = 10} }
---   -- Means window 1000 increased its width by 2 in expense of window 1001
--- <
--- - The following output demonstrates equal resizing: >lua
---
---   {
---     { [1000] = {width = 8, height = 5}, [1001] = {width = 6, height = 10} },
---     { [1000] = {width = 9, height = 5}, [1001] = {width = 5, height = 10} },
---   }
--- <
--- See |MiniAnimate.gen_subresize| for builtin subresize generators.
---
--- Notes:
---
--- - As resize animation is essentially a precisely scheduled non-blocking
---   subresizes, this has two important interconnected consequences:
---     - If another resize is attempted during the animation, it is done based
---       on the CURRENTLY VISIBLE window sizes. This might affect relative
---       resizing.
---     - It breaks the use of several relative resizing commands in the same
---       command. Use |MiniAnimate.execute_after()| to schedule action after
---       reaching target window sizes.
---
--- Configuration example: >lua
---
---   local is_many_wins = function(sizes_from, sizes_to)
---     return vim.tbl_count(sizes_from) >= 3
---   end
---   local animate = require('mini.animate')
---   animate.setup({
---     resize = {
---       -- Animate for 200 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 200, unit = 'total' }),
---
---       -- Animate only if there are at least 3 windows
---       subresize = animate.gen_subscroll.equal({ predicate = is_many_wins }),
---     }
---   })
--- <
--- After animation is done, `MiniAnimateDoneResize` event is triggered.
---
--- # Window open/close ~
--- *MiniAnimate.config.open*
--- *MiniAnimate.config.close*
---
--- These animations are similarly triggered for regular (non-floating) window
--- open/close. Their visualization step consists from drawing empty floating
--- window with customizable config and transparency.
---
--- Note: if |MiniAnimate.config.split| animation is enabled (default), it is
--- used instead of these for windows in current tabpage which are opened as a
--- split or closed while not being the only window in tabpage. These
--- animations are then used only for other windows (like the first window in
--- a new tabpage). Set `split.enable` to `false` to use them for all windows.
---
--- Exact window visualization characteristics are controlled by `winconfig`
--- and `winblend` options.
---
--- The `winconfig` option is a callable which takes window id (|window-ID|) as
--- input and returns an array of floating window configs (as in `config`
--- argument of |nvim_open_win()|). Its length determines number of animation steps.
--- Example:
--- - The following output results into two animation steps with second being
---   upper left quarter of a first: >lua
---
---   {
---     {
---       row      = 0,        col    = 0,
---       width    = 10,       height = 10,
---       relative = 'editor', anchor = 'NW',   focusable = false,
---       zindex   = 1,        border = 'none', style  = 'minimal',
---     },
---     {
---       row      = 0,        col    = 0,
---       width    = 5,        height = 5,
---       relative = 'editor', anchor = 'NW',   focusable = false,
---       zindex   = 1,        border = 'none', style  = 'minimal',
---     },
---   }
--- <
--- The `winblend` option is similar to `timing` option: it is a callable
--- which, given current and total step numbers, returns value of floating
--- window's |'winblend'| option. Note, that it is called for current step (so
--- starts from 0), as opposed to `timing` which is called before step.
--- Example:
--- - Function `function(s, n) return 80 + 20 * s / n end` results in linear
---   transition from `winblend` value of 80 to 100.
---
--- See |MiniAnimate.gen_winconfig| for builtin window config generators.
--- See |MiniAnimate.gen_winblend| for builtin window transparency generators.
---
--- Configuration example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     open = {
---       -- Animate for 400 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 400, unit = 'total' }),
---
---       -- Animate with wiping from nearest edge instead of default static one
---       winconfig = animate.gen_winconfig.wipe({ direction = 'from_edge' }),
---
---       -- Make bigger windows more transparent
---       winblend = animate.gen_winblend.linear({ from = 80, to = 100 }),
---     },
---
---     close = {
---       -- Animate for 400 milliseconds with linear easing
---       timing = animate.gen_timing.linear({ duration = 400, unit = 'total' }),
---
---       -- Animate with wiping to nearest edge instead of default static one
---       winconfig = animate.gen_winconfig.wipe({ direction = 'to_edge' }),
---
---       -- Make bigger windows more transparent
---       winblend = animate.gen_winblend.linear({ from = 100, to = 80 }),
---     },
---   })
--- <
--- After animation is done, `MiniAnimateDoneOpen` or `MiniAnimateDoneClose`
--- event is triggered for `open` and `close` animation respectively.
---
--- # Window split ~
--- *MiniAnimate.config.split*
---
--- This animation is triggered when regular (non-floating) window in current
--- tabpage is opened as a split (like with |:vsplit|, |:split|, |CTRL-W_v|,
--- |:new|) or closed while not being the only window in tabpage (like with
--- |:quit|, |:close|, |:only|). It takes precedence over `open` and `close`
--- animations for such windows (even if it results into no animation).
---
--- Its visualization is a moving split line (window separator or status line):
--- - On open, split line between new window and the one it was split from
---   flies in from the right (for vertical split) or bottom (for horizontal
---   split) edge of their combined area. This is done by actually resizing
---   these windows (similar to resize animation).
--- - On close, split lines fly out to the right or bottom edge of container
---   which had closed window(s). As closed window can not be resized anymore,
---   what was shown after the split line (window text, separators, status
---   lines, winbars) is imitated with floating windows. They are shown over
---   the actual final layout and are gradually squeezed out.
---
--- Exact split line positions and their number is controlled by `subsplit`
--- option. It is a callable which takes `size_from` and `size_to` arguments
--- (both non-negative integers) and returns array of sizes for every step.
--- Last one is usually equal to `size_to`. Size is a number of cells after the
--- split line (to the right of vertical or below horizontal one):
--- - Open animation: size of window(s) after the split line (as in
---   |nvim_win_get_width()| or |nvim_win_get_height()|) going from the smallest
---   possible to the final one.
--- - Close animation: number of cells between split line and the edge of
---   container (including separators and status lines) going to 0. It is
---   computed for every container which had closed window(s), as there can be
---   several of them (like after |:only|). Their steps are evenly spread over
---   the whole animation, so that all split lines reach the edge together.
--- Example:
--- - Input `(0, 10)` means that split line travels 10 cells from the edge.
--- - Output `{ 2, 4, 6, 8, 10 }` means that it is done in five equal steps.
---
--- See |MiniAnimate.gen_subsplit| for builtin subsplit generators.
---
--- Notes:
--- - Any key press during animation finishes it immediately. This way the key
---   is always executed with the final layout (like navigating to or resizing
---   a window). Use |MiniAnimate.execute_after()| to schedule action from
---   other places.
--- - Open animation has the same consequences as resize animation, as it
---   actually changes window sizes. It is stopped (keeping current sizes) if
---   sizes of animated windows are changed during animation not by it.
---   Size changes of other windows are preserved.
--- - Open animation moves only the split line between new window and the one
---   it was split from. If other windows are resized as a result of a split
---   (like due to |'equalalways'|), they get their final sizes immediately.
--- - Close animation uses floating windows with `zindex` 1 (see |nvim_open_win()|)
---   to be below other floating windows. They show text only of regular
---   buffers (with empty |'buftype'|) which are still loaded, otherwise an
---   empty buffer is shown.
---   Separators, status lines, and winbars are imitated with borders or
---   separate floating windows (using |hl-WinSeparator|, |hl-StatusLine|,
---   |hl-StatusLineNC|, |hl-WinBar|, |hl-WinBarNC| highlight groups), so they
---   might look slightly different from actual ones.
---   On Neovim<0.11 resizing floating windows triggers |WinResized| and
---   |WinScrolled| events (as there is no |'eventignorewin'|).
---
--- Configuration example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     split = {
---       -- Animate for 150 milliseconds with quadratic easing
---       timing = animate.gen_timing.quadratic({ duration = 150, unit = 'total' }),
---
---       -- Animate with at most 30 steps
---       subsplit = animate.gen_subsplit.equal({ max_output_steps = 30 }),
---     },
---   })
--- <
--- After animation is done, `MiniAnimateDoneSplit` event is triggered.
MiniAnimate.config = {
  -- Cursor path
  cursor = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Path generator for visualized cursor movement
    --minidoc_replace_start path = --<function: implements shortest line path no longer than 1000>,
    path = function(destination)
      return H.path_line(destination, { predicate = H.default_path_predicate, max_output_steps = 1000 })
    end,
    --minidoc_replace_end
  },

  -- Vertical scroll
  scroll = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Subscroll generator based on total scroll
    --minidoc_replace_start subscroll = --<function: implements equal scroll with at most 60 steps>,
    subscroll = function(total_scroll)
      return H.subscroll_equal(total_scroll, { predicate = H.default_subscroll_predicate, max_output_steps = 60 })
    end,
    --minidoc_replace_end
  },

  -- Window resize
  resize = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Subresize generator for all steps of resize animations
    --minidoc_replace_start subresize = --<function: implements equal linear steps>,
    subresize = function(sizes_from, sizes_to)
      return H.subresize_equal(sizes_from, sizes_to, { predicate = H.default_subresize_predicate })
    end,
    --minidoc_replace_end
  },

  -- Window open
  open = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Floating window config generator visualizing specific window
    --minidoc_replace_start winconfig = --<function: implements static window for 25 steps>,
    winconfig = function(win_id)
      return H.winconfig_static(win_id, { predicate = H.default_winconfig_predicate, n_steps = 25 })
    end,
    --minidoc_replace_end

    -- 'winblend' (window transparency) generator for floating window
    --minidoc_replace_start winblend = --<function: implements equal linear steps from 80 to 100>,
    winblend = function(s, n) return 80 + 20 * (s / n) end,
    --minidoc_replace_end
  },

  -- Window close
  close = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Floating window config generator visualizing specific window
    --minidoc_replace_start winconfig = --<function: implements static window for 25 steps>,
    winconfig = function(win_id)
      return H.winconfig_static(win_id, { predicate = H.default_winconfig_predicate, n_steps = 25 })
    end,
    --minidoc_replace_end

    -- 'winblend' (window transparency) generator for floating window
    --minidoc_replace_start winblend = --<function: implements equal linear steps from 80 to 100>,
    winblend = function(s, n) return 80 + 20 * (s / n) end,
    --minidoc_replace_end
  },

  -- Window split (split line movement on split window open/close)
  split = {
    -- Whether to enable this animation
    enable = true,

    -- Timing of animation (how steps will progress in time)
    --minidoc_replace_start timing = --<function: linear animation, total 250ms>,
    timing = function(_, n) return 250 / n end,
    --minidoc_replace_end

    -- Subsplit generator for all steps of split line movement
    --minidoc_replace_start subsplit = --<function: implements equal steps with at most 60 steps>,
    subsplit = function(size_from, size_to)
      return H.subsplit_equal(size_from, size_to, { predicate = H.default_subsplit_predicate, max_output_steps = 60 })
    end,
    --minidoc_replace_end
  },
}
--minidoc_afterlines_end

-- Module functionality =======================================================
--- Check animation activity
---
---@param animation_type string One of supported animation types
---   (entries of |MiniAnimate.config|, like `'cursor'`, etc.).
---
---@return boolean Whether the animation is currently active.
MiniAnimate.is_active = function(animation_type)
  local res = H.cache[animation_type .. '_is_active']
  if res == nil then H.error('Wrong `animation_type` for `is_active()`.') end
  return res
end

--- Execute action after some animation is done
---
--- Execute action immediately if animation is not active (checked with
--- |MiniAnimate.is_active()|). Else, schedule its execution until after
--- animation is done (on corresponding "done event", see
--- |MiniAnimate-done-event|).
---
--- Mostly meant to be used inside mappings.
---
--- Example:
---
--- A useful `nnoremap n nzvzz` mapping (consecutive application of |n|, |zv|, and |zz|)
--- should be expressed in the following way: >lua
---
---   '<Cmd>lua vim.cmd("normal! n"); ' ..
---     'MiniAnimate.execute_after("scroll", "normal! zvzz")<CR>'
--- <
---@param animation_type string One of supported animation types
---   (as in |MiniAnimate.is_active()|).
---@param action string|function Action to be executed. If string, executed as
---   command (via |vim.cmd()|).
MiniAnimate.execute_after = function(animation_type, action)
  local event_name = H.animation_done_events[animation_type]
  if event_name == nil then H.error('Wrong `animation_type` for `execute_after`.') end

  local callable = action
  if type(callable) == 'string' then callable = function() vim.cmd(action) end end
  if not vim.is_callable(callable) then
    H.error('Argument `action` of `execute_after()` should be string or callable.')
  end

  -- Schedule conditional action execution to allow animation to actually take
  -- effect. This helps creating more universal mappings, because some commands
  -- (like `n`) not always result into scrolling.
  vim.schedule(function()
    if MiniAnimate.is_active(animation_type) then
      vim.api.nvim_create_autocmd('User', { pattern = event_name, once = true, callback = callable })
    else
      callable()
    end
  end)
end

-- Action (step 0) - wait (step 1) - action (step 1) - ...
-- `step_action` should return `false` or `nil` (equivalent to not returning anything explicitly) in order to stop animation.
--- Animate action
---
--- This is equivalent to asynchronous execution of the following algorithm:
--- - Call `step_action(0)` immediately after calling this function. Stop if
---   action returned `false` or `nil`.
--- - Wait `step_timing(1)` milliseconds.
--- - Call `step_action(1)`. Stop if it returned `false` or `nil`.
--- - Wait `step_timing(2)` milliseconds.
--- - Call `step_action(2)`. Stop if it returned `false` or `nil`.
--- - ...
---
--- Notes:
--- - Animation is also stopped on action error or if maximum number of steps
---   is reached.
--- - Asynchronous execution is done with |uv.new_timer()|. It only allows
---   integer parts as repeat value. This has several implications:
---     - Outputs of `step_timing()` are accumulated in order to preserve total
---       execution time.
---     - Any wait time less than 1 ms means that action will be executed
---       immediately.
---
---@param step_action function|table Callable which takes `step` (integer 0, 1, 2,
---   etc. indicating current step) and executes some action. Its return value
---   defines when animation should stop: values `false` and `nil` (equivalent
---   to no explicit return) stop animation timer; any other continues it.
---@param step_timing function|table Callable which takes `step` (integer 1, 2, etc.
---   indicating next step) and returns how many milliseconds to wait before
---   executing this step action.
---@param opts table|nil Options. Possible fields:
---   - <max_steps> - Maximum value of allowed step to execute. Default: 10000000.
MiniAnimate.animate = function(step_action, step_timing, opts)
  opts = vim.tbl_deep_extend('force', { max_steps = 10000000 }, opts or {})

  local step, max_steps = 0, opts.max_steps
  local timer, wait_time = vim.loop.new_timer(), 0

  local draw_step
  draw_step = vim.schedule_wrap(function()
    local ok, should_continue = pcall(step_action, step)
    if not (ok and should_continue and step < max_steps) then
      timer:stop()
      return
    end

    step = step + 1
    wait_time = wait_time + step_timing(step)

    -- Repeat value of `timer` seems to be rounded down to milliseconds. This
    -- means that values less than 1 will lead to timer stop repeating. Instead
    -- call next step function directly.
    if wait_time < 1 then
      timer:set_repeat(0)
      -- Use `return` to make this proper "tail call"
      return draw_step()
    else
      timer:set_repeat(wait_time)
      wait_time = wait_time - timer:get_repeat()
      timer:again()
    end
  end)

  -- Start non-repeating timer without callback execution
  timer:start(10000000, 0, draw_step)

  -- Draw step zero (at origin) immediately
  draw_step()
end

--- Generate animation timing
---
--- Each field corresponds to one family of progression which can be customized
--- further by supplying appropriate arguments.
---
--- This is a table with function elements. Call to actually get timing function.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     cursor = {
---       timing = animate.gen_timing.linear({ duration = 100, unit = 'total' })
---     },
---   })
--- <
---@seealso |MiniIndentscope.gen_animation| for similar concept in |mini.indentscope|.
MiniAnimate.gen_timing = {}

---@alias __animate_timing_opts table|nil Options that control progression. Possible keys:
---   - <easing> `(string)` - a subtype of progression. One of "in"
---     (accelerating from zero speed), "out" (decelerating to zero speed),
---     "in-out" (default; accelerating halfway, decelerating after).
---   - <duration> `(number)` - duration (in ms) of a unit. Default: 20.
---   - <unit> `(string)` - which unit's duration `opts.duration` controls. One
---     of "step" (default; ensures average duration of step to be `opts.duration`)
---     or "total" (ensures fixed total duration regardless of scope's range).
---@alias __animate_timing_return function Timing function (see |MiniAnimate-timing|).

--- Generate timing with no animation
---
--- Show final result immediately. Usually better to use `enable` field in `config`
--- if you want to disable animation.
MiniAnimate.gen_timing.none = function()
  return function() return 0 end
end

--- Generate timing with linear progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.linear = function(opts) return H.timing_arithmetic(0, H.normalize_timing_opts(opts)) end

--- Generate timing with quadratic progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.quadratic = function(opts) return H.timing_arithmetic(1, H.normalize_timing_opts(opts)) end

--- Generate timing with cubic progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.cubic = function(opts) return H.timing_arithmetic(2, H.normalize_timing_opts(opts)) end

--- Generate timing with quartic progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.quartic = function(opts) return H.timing_arithmetic(3, H.normalize_timing_opts(opts)) end

--- Generate timing with exponential progression
---
---@param opts __animate_timing_opts
---
---@return __animate_timing_return
MiniAnimate.gen_timing.exponential = function(opts) return H.timing_geometrical(H.normalize_timing_opts(opts)) end

--- Generate cursor animation path
---
--- For more information see |MiniAnimate.config.cursor|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     cursor = {
---       -- Animate with line-column angle instead of shortest line
---       path = animate.gen_path.angle(),
---     }
---   })
--- <
MiniAnimate.gen_path = {}

---@alias __animate_path_opts_common table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `destination` as input and
---     returns boolean value indicating whether animation should be done.
---     Default: `false` if `destination` is within one line of origin (reduces
---     flickering), `true` otherwise.
---@alias __animate_path_return function Path function (see |MiniAnimate.config.cursor|).

--- Generate path as shortest line
---
---@param opts __animate_path_opts_common
---   - <max_output_steps> `(number)` - maximum number of steps in output.
---     Default: 1000.
---
---@return __animate_path_return
MiniAnimate.gen_path.line = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_path_predicate, max_output_steps = 1000 }, opts or {})

  return function(destination) return H.path_line(destination, opts) end
end

--- Generate path as line/column angle
---
---@param opts __animate_path_opts_common
---   - <max_output_steps> `(number)` - maximum number of steps per side in output.
---     Default: 1000.
---   - <first_direction> `(string)` - one of `"horizontal"` (default; animates
---     across initial line first) or `"vertical"` (animates across initial
---     column first).
---
---@return __animate_path_return
MiniAnimate.gen_path.angle = function(opts)
  local default_opts = { predicate = H.default_path_predicate, max_output_steps = 1000, first_direction = 'horizontal' }
  opts = vim.tbl_deep_extend('force', default_opts, opts or {})

  local append_horizontal = function(res, dest_col, const_line)
    if dest_col == 0 then return end
    local n_steps = math.min(math.abs(dest_col), opts.max_output_steps)
    local coef = dest_col / n_steps
    for i = 0, n_steps - 1 do
      table.insert(res, { const_line, H.round(coef * i) })
    end
  end

  local append_vertical = function(res, dest_line, const_col)
    if dest_line == 0 then return end
    local n_steps = math.min(math.abs(dest_line), opts.max_output_steps)
    local coef = dest_line / n_steps
    for i = 0, n_steps - 1 do
      table.insert(res, { H.round(coef * i), const_col })
    end
  end

  return function(destination)
    -- Don't animate in case of false predicate
    if not opts.predicate(destination) then return {} end

    -- Travel along horizontal/vertical lines
    local res = {}
    if opts.first_direction == 'horizontal' then
      append_horizontal(res, destination[2], 0)
      append_vertical(res, destination[1], destination[2])
    else
      append_vertical(res, destination[1], 0)
      append_horizontal(res, destination[2], destination[1])
    end

    return res
  end
end

--- Generate path as closing walls at final position
---
---@param opts __animate_path_opts_common
---   - <width> `(number)` - initial width of left and right walls. Default: 10.
---
---@return __animate_path_return
MiniAnimate.gen_path.walls = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_path_predicate
  local width = opts.width or 10

  return function(destination)
    -- Don't animate in case of false predicate
    if not predicate(destination) then return {} end

    -- Don't animate in case of no movement
    if destination[1] == 0 and destination[2] == 0 then return {} end

    local dest_line, dest_col = destination[1], destination[2]
    local res = {}
    for i = width, 1, -1 do
      table.insert(res, { dest_line, dest_col + i })
      table.insert(res, { dest_line, dest_col - i })
    end
    return res
  end
end

--- Generate path as diminishing spiral at final position
---
---@param opts __animate_path_opts_common
---   - <width> `(number)` - initial width of spiral. Default: 2.
---
---@return __animate_path_return
MiniAnimate.gen_path.spiral = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_path_predicate
  local width = opts.width or 2

  --stylua: ignore
  local add_layer = function(res, w, destination)
    local dest_line, dest_col = destination[1], destination[2]
    for j = -w, w-1 do table.insert(res, { dest_line - w, dest_col + j }) end
    for i = -w, w-1 do table.insert(res, { dest_line + i, dest_col + w }) end
    for j = -w, w-1 do table.insert(res, { dest_line + w, dest_col - j }) end
    for i = -w, w-1 do table.insert(res, { dest_line - i, dest_col - w }) end
  end

  return function(destination)
    -- Don't animate in case of false predicate
    if not predicate(destination) then return {} end

    -- Don't animate in case of no movement
    if destination[1] == 0 and destination[2] == 0 then return {} end

    local res = {}
    for w = width, 1, -1 do
      add_layer(res, w, destination)
    end
    return res
  end
end

--- Generate scroll animation subscroll
---
--- For more information see |MiniAnimate.config.scroll|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     scroll = {
---       -- Animate equally but with 120 maximum steps instead of default 60
---       subscroll = animate.gen_subscroll.equal({ max_output_steps = 120 }),
---     }
---   })
--- <
MiniAnimate.gen_subscroll = {}

--- Generate subscroll with equal steps
---
---@param opts table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `total_scroll` as
---     input and returns boolean value indicating whether animation should be
---     done. Default: `false` if `total_scroll` is 1 or less (reduces
---     unnecessary waiting), `true` otherwise.
---   - <max_output_steps> `(number)` - maximum number of subscroll steps in output.
---     Adjust this to reduce computations in expense of reduced smoothness.
---     Default: 60.
---
---@return function Subscroll function (see |MiniAnimate.config.scroll|).
MiniAnimate.gen_subscroll.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_subscroll_predicate, max_output_steps = 60 }, opts or {})

  return function(total_scroll) return H.subscroll_equal(total_scroll, opts) end
end

--- Generate resize animation subresize
---
--- For more information see |MiniAnimate.config.resize|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local is_many_wins = function(sizes_from, sizes_to)
---     return vim.tbl_count(sizes_from) >= 3
---   end
---   local animate = require('mini.animate')
---   animate.setup({
---     resize = {
---       -- Animate only if there are at least 3 windows
---       subresize = animate.gen_subresize.equal({ predicate = is_many_wins }),
---     }
---   })
--- <
MiniAnimate.gen_subresize = {}

--- Generate subresize with equal steps
---
---@param opts table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `sizes_from` and
---     `sizes_to` as input and returns boolean value indicating whether
---     animation should be done. Default: always `true`.
---
---@return function Subresize function (see |MiniAnimate.config.resize|).
MiniAnimate.gen_subresize.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_subresize_predicate }, opts or {})

  return function(sizes_from, sizes_to) return H.subresize_equal(sizes_from, sizes_to, opts) end
end

--- Generate open/close animation winconfig
---
--- For more information see |MiniAnimate.config.open| or |MiniAnimate.config.close|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local is_not_single_window = function(win_id)
---     local tabpage_id = vim.api.nvim_win_get_tabpage(win_id)
---     return #vim.api.nvim_tabpage_list_wins(tabpage_id) > 1
---   end
---   local animate = require('mini.animate')
---   animate.setup({
---     open = {
---       -- Animate with wiping from nearest edge instead of default static one
---       -- and only if it is not a single window in tabpage
---       winconfig = animate.gen_winconfig.wipe({
---         predicate = is_not_single_window,
---         direction = 'from_edge',
---       }),
---     },
---     close = {
---       -- Animate with wiping to nearest edge instead of default static one
---       -- and only if it is not a single window in tabpage
---       winconfig = animate.gen_winconfig.wipe({
---         predicate = is_not_single_window,
---         direction = 'to_edge',
---       }),
---     },
---   })
--- <
MiniAnimate.gen_winconfig = {}

---@alias __animate_winconfig_opts_common table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `win_id` as input and
---     returns boolean value indicating whether animation should be done.
---     Default: always `true`.
---@alias __animate_winconfig_return function Winconfig function (see |MiniAnimate.config.open|
---   or |MiniAnimate.config.close|).

--- Generate winconfig for static floating window
---
--- This will result into floating window statically covering whole target
--- window.
---
---@param opts __animate_winconfig_opts_common
---   - <n_steps> `(number)` - number of output steps, all with same config.
---     Useful to tweak smoothness of transparency animation (done inside
---     `winblend` config option). Default: 25.
---
---@return __animate_winconfig_return
MiniAnimate.gen_winconfig.static = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_winconfig_predicate, n_steps = 25 }, opts or {})

  return function(win_id) return H.winconfig_static(win_id, opts) end
end

--- Generate winconfig for center-focused animated floating window
---
--- This will result into floating window growing from or shrinking to the
--- target window center.
---
---@param opts __animate_winconfig_opts_common
---   - <direction> `(string)` - one of `"to_center"` (default; window will
---     shrink from full coverage to center) or `"from_center"` (window will
---     grow from center to full coverage).
---
---@return __animate_winconfig_return
MiniAnimate.gen_winconfig.center = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_winconfig_predicate
  local direction = opts.direction or 'to_center'

  return function(win_id)
    -- Don't animate in case of false predicate
    if not predicate(win_id) then return {} end

    local pos = vim.fn.win_screenpos(win_id)
    local row, col = pos[1] - 1, pos[2] - 1
    local height, width = vim.api.nvim_win_get_height(win_id), vim.api.nvim_win_get_width(win_id)

    local n_steps = math.max(height, width)
    local res = {}
    -- Progression should be between fully covering target window and minimal
    -- dimensions in target window center.
    for i = 1, n_steps do
      local coef = (i - 1) / n_steps

      -- Reverse output if progression is from center
      local res_ind = direction == 'to_center' and i or (n_steps - i + 1)

      --stylua: ignore
      res[res_ind] = {
        relative  = 'editor',
        anchor    = 'NW',
        row       = H.round(row + 0.5 * coef * height),
        col       = H.round(col + 0.5 * coef * width),
        width     = math.ceil((1 - coef) * width),
        height    = math.ceil((1 - coef) * height),
        focusable = false,
        zindex    = 1,
        border    = 'none',
        style     = 'minimal',
      }
    end

    return res
  end
end

--- Generate winconfig for wiping animated floating window
---
--- This will result into floating window growing from or shrinking to the
--- nearest edge. This also takes into account the split type of target window:
--- vertically split window will progress towards vertical edge; horizontally -
--- towards horizontal.
---
---@param opts __animate_winconfig_opts_common
---   - <direction> `(string)` - one of `"to_edge"` (default; window will
---     shrink from full coverage to nearest edge) or `"from_edge"` (window
---     will grow from edge to full coverage).
---
---@return __animate_winconfig_return
MiniAnimate.gen_winconfig.wipe = function(opts)
  opts = opts or {}
  local predicate = opts.predicate or H.default_winconfig_predicate
  local direction = opts.direction or 'to_edge'

  return function(win_id)
    -- Don't animate in case of false predicate
    if not predicate(win_id) then return {} end

    -- Get window data
    local win_pos = vim.fn.win_screenpos(win_id)
    local top_row, left_col = win_pos[1], win_pos[2]
    local win_height, win_width = vim.api.nvim_win_get_height(win_id), vim.api.nvim_win_get_width(win_id)

    -- Compute progression data
    local cur_row, cur_col = top_row, left_col
    local cur_width, cur_height = win_width, win_height

    local increment_row, increment_col, increment_height, increment_width
    local n_steps

    local win_container = H.get_window_parent_container(win_id)
    --stylua: ignore
    if win_container == 'col' then
      -- Determine closest top/bottom screen edge and progress to it
      local bottom_row = top_row + win_height - 1
      local is_top_edge_closer = top_row < (vim.o.lines - bottom_row + 1)

      increment_row,   increment_col    = (is_top_edge_closer and 0 or 1), 0
      increment_width, increment_height = 0,                               -1
      n_steps = win_height
    else
      -- Determine closest left/right screen edge and progress to it
      local right_col = left_col + win_width - 1
      local is_left_edge_closer = left_col < (vim.o.columns - right_col + 1)

      increment_row,   increment_col    =  0, (is_left_edge_closer and 0 or 1)
      increment_width, increment_height = -1, 0
      n_steps = win_width
    end

    -- Make step configs
    local res = {}
    for i = 1, n_steps do
      -- Reverse output if progression is from edge
      local res_ind = direction == 'to_edge' and i or (n_steps - i + 1)
      res[res_ind] = {
        relative = 'editor',
        anchor = 'NW',
        row = cur_row - 1,
        col = cur_col - 1,
        width = cur_width,
        height = cur_height,
        focusable = false,
        zindex = 1,
        border = 'none',
        style = 'minimal',
      }
      cur_row = cur_row + increment_row
      cur_col = cur_col + increment_col
      cur_height = cur_height + increment_height
      cur_width = cur_width + increment_width
    end
    return res
  end
end

--- Generate open/close animation `winblend` progression
---
--- For more information see |MiniAnimate.config.open| or |MiniAnimate.config.close|.
---
--- This is a table with function elements. Call to actually get transparency
--- function.
---
--- Example: >lua
---
---   local animate = require('mini.animate')
---   animate.setup({
---     open = {
---       -- Change transparency from 60 to 80 instead of default 80 to 100
---       winblend = animate.gen_winblend.linear({ from = 60, to = 80 }),
---     },
---     close = {
---       -- Change transparency from 60 to 80 instead of default 80 to 100
---       winblend = animate.gen_winblend.linear({ from = 60, to = 80 }),
---     },
---   })
--- <
MiniAnimate.gen_winblend = {}

--- Generate linear `winblend` progression
---
---@param opts table|nil Options that control generator. Possible keys:
---   - <from> `(number)` - initial value of |'winblend'|.
---   - <to> `(number)` - final value of |'winblend'|.
---
---@return function Winblend function (see |MiniAnimate.config.open|
---   or |MiniAnimate.config.close|).
MiniAnimate.gen_winblend.linear = function(opts)
  opts = opts or {}
  local from = opts.from or 80
  local to = opts.to or 100
  local diff = to - from

  return function(s, n) return from + (s / n) * diff end
end

--- Generate split animation subsplit
---
--- For more information see |MiniAnimate.config.split|.
---
--- This is a table with function elements. Call to actually get generator.
---
--- Example: >lua
---
---   local is_big_move = function(size_from, size_to)
---     return math.abs(size_to - size_from) >= 10
---   end
---   local animate = require('mini.animate')
---   animate.setup({
---     split = {
---       -- Animate only if split line moves at least 10 cells and use at
---       -- most 120 steps instead of default 60
---       subsplit = animate.gen_subsplit.equal({
---         predicate = is_big_move,
---         max_output_steps = 120,
---       }),
---     },
---   })
--- <
MiniAnimate.gen_subsplit = {}

--- Generate subsplit with equal steps
---
---@param opts table|nil Options that control generator. Possible keys:
---   - <predicate> `(function)` - a callable which takes `size_from` and
---     `size_to` as input and returns boolean value indicating whether
---     animation should be done. Default: `false` if split line moves 1 cell
---     or less (reduces unnecessary waiting), `true` otherwise.
---   - <max_output_steps> `(number)` - maximum number of steps in output.
---     Adjust this to reduce computations in expense of reduced smoothness.
---     Default: 60.
---
---@return function Subsplit function (see |MiniAnimate.config.split|).
MiniAnimate.gen_subsplit.equal = function(opts)
  opts = vim.tbl_deep_extend('force', { predicate = H.default_subsplit_predicate, max_output_steps = 60 }, opts or {})

  return function(size_from, size_to) return H.subsplit_equal(size_from, size_to, opts) end
end

-- Helper data ================================================================
-- Module default config
H.default_config = vim.deepcopy(MiniAnimate.config)

-- Cache for various operations
H.cache = {
  -- Cursor move animation data
  cursor_event_id = 0,
  cursor_is_active = false,
  cursor_state = { buf_id = nil, pos = {} },

  -- Scroll animation data
  scroll_event_id = 0,
  scroll_is_active = false,
  scroll_state = { buf_id = nil, win_id = nil, view = {}, cursor = {} },

  -- Resize animation data
  resize_event_id = 0,
  resize_is_active = false,
  resize_target = nil,
  resize_state = { layout = {}, sizes = {}, views = {} },

  -- Window open animation data
  open_event_id = 0,
  open_is_active = false,
  open_active_windows = {},

  -- Window close animation data
  close_event_id = 0,
  close_is_active = false,
  close_active_windows = {},

  -- Window split animation data
  split_event_id = 0,
  split_is_active = false,
  -- Data about split window open/close waiting for layout to settle
  split_pending_open = nil,
  split_pending_close = nil,
  -- Floating windows and (reusable) buffers used in close animation
  split_floats = {},
  split_line_bufs = {},
  -- Callable to immediately finish current animation
  split_finish = nil,

  -- Whether module's own Normal mode command is executing
  is_executing_normal = false,
}

-- Namespaces for module operations
H.ns_id = {
  -- Extmarks used to show cursor path
  cursor = vim.api.nvim_create_namespace('MiniAnimateCursor'),
  -- Key listener used to finish split animation
  split = vim.api.nvim_create_namespace('MiniAnimateSplit'),
}

-- Identifier of empty buffer used inside open/close animations
H.empty_buf_id = nil

-- Names of `User` events triggered after certain type of animation is done
H.animation_done_events = {
  cursor = 'MiniAnimateDoneCursor',
  scroll = 'MiniAnimateDoneScroll',
  resize = 'MiniAnimateDoneResize',
  open = 'MiniAnimateDoneOpen',
  close = 'MiniAnimateDoneClose',
  split = 'MiniAnimateDoneSplit',
}

-- Helper functionality =======================================================
-- Settings -------------------------------------------------------------------
H.setup_config = function(config)
  H.check_type('config', config, 'table', true)
  config = vim.tbl_deep_extend('force', vim.deepcopy(H.default_config), config or {})

  H.check_type('cursor', config.cursor, 'table')
  H.check_type('cursor.enable', config.cursor.enable, 'boolean')
  H.check_type('cursor.timing', config.cursor.timing, 'callable')
  H.check_type('cursor.path', config.cursor.path, 'callable')

  H.check_type('scroll', config.scroll, 'table')
  H.check_type('scroll.enable', config.scroll.enable, 'boolean')
  H.check_type('scroll.timing', config.scroll.timing, 'callable')
  H.check_type('scroll.subscroll', config.scroll.subscroll, 'callable')

  H.check_type('resize', config.resize, 'table')
  H.check_type('resize.enable', config.resize.enable, 'boolean')
  H.check_type('resize.timing', config.resize.timing, 'callable')
  H.check_type('resize.subresize', config.resize.subresize, 'callable')

  H.check_type('open', config.open, 'table')
  H.check_type('open.enable', config.open.enable, 'boolean')
  H.check_type('open.timing', config.open.timing, 'callable')
  H.check_type('open.winconfig', config.open.winconfig, 'callable')
  H.check_type('open.winblend', config.open.winblend, 'callable')

  H.check_type('close', config.close, 'table')
  H.check_type('close.enable', config.close.enable, 'boolean')
  H.check_type('close.timing', config.close.timing, 'callable')
  H.check_type('close.winconfig', config.close.winconfig, 'callable')
  H.check_type('close.winblend', config.close.winblend, 'callable')

  H.check_type('split', config.split, 'table')
  H.check_type('split.enable', config.split.enable, 'boolean')
  H.check_type('split.timing', config.split.timing, 'callable')
  H.check_type('split.subsplit', config.split.subsplit, 'callable')

  return config
end

H.apply_config = function(config) MiniAnimate.config = config end

H.create_autocommands = function()
  local gr = vim.api.nvim_create_augroup('MiniAnimate', {})

  local au = function(event, pattern, callback, desc)
    vim.api.nvim_create_autocmd(event, { group = gr, pattern = pattern, callback = callback, desc = desc })
  end

  au('CursorMoved', '*', H.auto_cursor, 'Animate cursor')

  au('WinScrolled', '*', function()
    -- On Neovim>=0.13 `WinScrolled` is also triggered when window scrolls
    -- during 'incsearch' and when cancelling. Ignore these state changes to
    -- not have extra scroll as a result of it.
    H.ignore_incsearch_scroll()

    -- Start split animation here as it is the first event after split window
    -- open/close with already settled layout but before it is redrawn
    H.auto_split()

    -- Inside `WinScrolled` first animate resize before scroll to avoid flicker
    H.auto_resize()
    H.auto_scroll()
  end, 'Animate split, animate resize, and animate scroll')
  -- Track scroll state on buffer and window enter to animate its first scroll.
  -- Use `vim.schedule_wrap()` to allow other immediate commands to change view
  -- (like builtin cursor center on buffer change) to avoid unnecessary
  -- animated scroll.
  au({ 'BufEnter', 'WinEnter' }, '*', vim.schedule_wrap(H.track_scroll_state), 'Track scroll state')
  -- Track immediately scroll state after leaving terminal mode. Otherwise it
  -- will lead to scroll animation starting at latest non-Terminal mode view.
  au('TermLeave', '*', H.track_scroll_state, 'Track scroll state')
  -- Track scroll state (partially) on every cursor move to keep cursor
  -- position up to date. This enables visually better cursor positioning
  -- during scroll animation (convex progression from start cursor position to
  -- end). Use `vim.schedule()` to make it affect state only after scroll is
  -- done and cursor is already in correct final position.
  au('CursorMoved', '*', vim.schedule_wrap(H.track_scroll_state_partial), 'Track partial scroll state')
  au('CmdlineLeave', '*', function() H.ignore_incsearch_scroll() end, 'Ignore incsearch scroll')

  -- Use `vim.schedule_wrap()` animation to get a window data used for
  -- displaying (and not one after just opening). Useful for 'nvim-tree'.
  -- Split animation takes precedence for split windows.
  local auto_open = vim.schedule_wrap(function() H.auto_openclose('open') end)
  au('WinNew', '*', function()
    if H.track_split_open() then return end
    auto_open()
  end, 'Animate window open or split')

  au('WinClosed', '*', function()
    if H.track_split_close() then return end
    H.auto_openclose('close')
  end, 'Animate window close or split')

  au('ColorScheme', '*', H.create_default_hl, 'Ensure colors')

  -- Track keys to finish split animation before key is executed
  vim.on_key(H.on_key, H.ns_id.split)
end

H.create_default_hl = function()
  vim.api.nvim_set_hl(0, 'MiniAnimateCursor', { default = true, reverse = true, nocombine = true })
  vim.api.nvim_set_hl(0, 'MiniAnimateNormalFloat', { default = true, link = 'NormalFloat' })
end

H.is_disabled = function() return vim.g.minianimate_disable == true or vim.b.minianimate_disable == true end

H.get_config = function(config)
  return vim.tbl_deep_extend('force', MiniAnimate.config, vim.b.minianimate_config or {}, config or {})
end

-- Autocommands ---------------------------------------------------------------
H.auto_cursor = function()
  -- Don't animate if disabled
  local cursor_config = H.get_config().cursor
  if not cursor_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.cursor_state = { buf_id = nil, pos = {} }
    return
  end

  -- Don't animate if inside scroll animation
  if H.cache.scroll_is_active then return end

  -- Update necessary information. NOTE: update state only on `CursorMoved` and
  -- not inside every animation step (like in scroll animation) for performance
  -- reasons: cursor movement is much more common action than scrolling.
  local prev_state, new_state = H.cache.cursor_state, H.get_cursor_state()
  H.cache.cursor_state = new_state
  H.cache.cursor_event_id = H.cache.cursor_event_id + 1

  -- Don't animate if changed buffer
  if new_state.buf_id ~= prev_state.buf_id then return end

  -- Make animation step data and possibly animate
  local animate_step = H.make_cursor_step(prev_state, new_state, cursor_config)
  if not animate_step then return end

  H.start_cursor()
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.auto_resize = function()
  -- Don't animate if disabled
  local resize_config = H.get_config().resize
  if not resize_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.resize_state = { layout = {}, sizes = {}, views = {} }
    return
  end

  -- Don't animate if inside scroll animation. This reduces computations and
  -- occasional flickering.
  if H.cache.scroll_is_active then return end

  -- Update state. This also ensures that window views are up to date.
  local prev_state, new_state = H.cache.resize_state, H.get_resize_state()
  H.cache.resize_state = new_state

  -- Don't animate if inside split animation as it resizes windows itself
  if H.cache.split_is_active then return end

  -- Don't animate if there is nothing to animate (should be same layout but
  -- different sizes). This also stops triggering animation on window scrolls.
  local same_state = H.is_equal_resize_state(prev_state, new_state)
  if not (same_state.layout and not same_state.sizes) then return end

  -- Register new event only in case there is something to animate
  H.cache.resize_event_id = H.cache.resize_event_id + 1

  -- Make animation step data and possibly animate
  local animate_step = H.make_resize_step(prev_state, new_state, resize_config)
  if not animate_step then return end

  H.start_resize(prev_state)
  H.cache.resize_target = new_state
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.auto_scroll = function()
  -- Don't animate if disabled
  local scroll_config = H.get_config().scroll
  if not scroll_config.enable or H.is_disabled() then
    -- Reset state to not use an outdated one if enabled again
    H.cache.scroll_state = { buf_id = nil, win_id = nil, view = {}, cursor = {} }
    return
  end

  -- Get states
  local prev_state, new_state = H.cache.scroll_state, H.get_scroll_state()

  -- Don't animate if nothing to animate. Mostly used to distinguish
  -- `WinScrolled` resulting from module animation from the other ones.
  local is_same_bufwin = new_state.buf_id == prev_state.buf_id and new_state.win_id == prev_state.win_id
  local is_same_topline = new_state.view.topline == prev_state.view.topline
  if is_same_topline and is_same_bufwin then return end

  -- Update necessary information. Don't register new event if view is
  -- changed by split animation to not stop current scroll animation.
  H.cache.scroll_state = new_state
  if is_same_bufwin and H.cache.split_is_active then return end
  H.cache.scroll_event_id = H.cache.scroll_event_id + 1

  -- Don't animate if changed buffer or window
  if not is_same_bufwin then return end

  -- Don't animate if inside resize animation. This reduces computations and
  -- occasional flickering.
  if H.cache.resize_is_active then return end

  -- Make animation step data and possibly animate
  local animate_step = H.make_scroll_step(prev_state, new_state, scroll_config)
  if not animate_step then return end

  H.start_scroll(prev_state)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.track_scroll_state = function() H.cache.scroll_state = H.get_scroll_state() end

H.track_scroll_state_partial = function()
  -- This not only improves computation load, but seems to be crucial for
  -- a proper state tracking
  if H.cache.scroll_is_active then return end

  H.cache.scroll_state.cursor = { line = vim.fn.line('.'), virtcol = vim.fn.virtcol('.') }
end

H.ignore_incsearch_scroll = function()
  local cmd_type = vim.fn.getcmdtype()
  local is_insearch = vim.o.incsearch and (cmd_type == '/' or cmd_type == '?')
  if not (is_insearch or H.cache.scroll_state.aborted_incsearch) then return end

  -- Update scroll state so that there is no scroll animation after confirming
  -- incremental search. Otherwise it leads to unnecessary animation from
  -- initial scroll state to the one **already shown**.
  H.track_scroll_state()
  H.cache.scroll_state.aborted_incsearch = vim.v.event.abort
end

H.auto_openclose = function(action_type)
  action_type = action_type or 'open'

  -- Don't animate if disabled
  local config = H.get_config()[action_type]
  if not config.enable or H.is_disabled() then return end

  -- Get window id to act upon
  local win_id
  if action_type == 'close' then win_id = tonumber(vim.fn.expand('<amatch>')) end
  if action_type == 'open' then win_id = math.max(unpack(vim.api.nvim_list_wins())) end

  -- Don't animate if created window is not right (valid and not floating)
  if win_id == nil or not vim.api.nvim_win_is_valid(win_id) then return end
  if vim.api.nvim_win_get_config(win_id).relative ~= '' then return end

  -- Register new event only in case there is something to animate
  local event_id_name = action_type .. '_event_id'
  H.cache[event_id_name] = H.cache[event_id_name] + 1

  -- Make animation step data and possibly animate
  local animate_step = H.make_openclose_step(action_type, win_id, config)
  if not animate_step then return end

  H.start_openclose(action_type)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.track_split_open = function()
  -- Don't animate if disabled
  local split_config = H.get_config().split
  if not split_config.enable or H.is_disabled() then return false end

  -- New window is current during `WinNew` (even if created without entering)
  local win_id = vim.api.nvim_get_current_win()
  if not H.is_split_window(win_id) then return false end

  -- Delay animation until layout is settled (like after 'winwidth' is
  -- applied). It is usually on first `WinScrolled`, but use `vim.schedule()`
  -- in case there is none. Previous window is usually the one split from.
  H.cache.split_pending_open = { win_id = win_id, prev_win_id = vim.fn.win_getid(vim.fn.winnr('#')) }
  vim.schedule(H.auto_split)
  return true
end

H.track_split_close = function()
  -- Don't animate if disabled
  local split_config = H.get_config().split
  if not split_config.enable or H.is_disabled() then return false end

  local win_id = tonumber(vim.fn.expand('<amatch>'))
  if win_id == nil or not H.is_split_window(win_id) then return false end

  -- Take snapshot of the layout only on first closed window, as there can be
  -- several of them closed in a row (like with `:only`)
  local data = H.cache.split_pending_close
  local tabpage_id = vim.api.nvim_win_get_tabpage(win_id)
  if data == nil or data.tabpage_id ~= tabpage_id then
    data = { tabpage_id = tabpage_id, snapshot = H.get_split_snapshot(), config = split_config }
    H.cache.split_pending_close = data
    vim.schedule(H.auto_split)
  end
  return true
end

H.auto_split = function()
  local open_data, close_data = H.cache.split_pending_open, H.cache.split_pending_close
  if open_data == nil and close_data == nil then return end
  H.cache.split_pending_open, H.cache.split_pending_close = nil, nil

  -- Prefer animating open as it is visible in actual layout (unlike close
  -- animation). Use config of current buffer for open (falling back to open
  -- animation if disabled) and of closed window for close.
  local split_config = open_data ~= nil and H.get_config().split or close_data.config
  if open_data ~= nil and (not split_config.enable or H.is_disabled()) then return H.auto_openclose('open') end

  -- Register new event (which stops previous split animation) and stop what
  -- might interfere: floating windows of close animation, resize animation.
  H.cache.split_event_id = H.cache.split_event_id + 1
  H.cache.split_finish = nil
  H.close_split_floats()
  if H.cache.resize_is_active then
    H.cache.resize_event_id = H.cache.resize_event_id + 1
    H.finish_resize()
  end

  -- Make animation step data and possibly animate
  local make_step = open_data ~= nil and H.make_split_open_step or H.make_split_close_step
  local ok, animate_step = pcall(make_step, open_data or close_data, split_config)

  -- Properly stop previous animation (as it will stop itself silently)
  if not (ok and animate_step) and H.cache.split_is_active then H.stop_split() end
  if not ok then error(animate_step, 0) end
  if not animate_step then return end

  H.start_split(animate_step.finish)
  MiniAnimate.animate(animate_step.step_action, animate_step.step_timing)
end

H.on_key = function()
  -- Finish split animation right away on any key, as its effect might depend
  -- on final layout (like window navigation, resize, scroll, etc.). Ignore
  -- keys from module's own commands (like in parallel scroll animation).
  local finish = H.cache.split_finish
  if finish == nil or H.cache.is_executing_normal then return end
  H.cache.split_event_id, H.cache.split_finish = H.cache.split_event_id + 1, nil
  pcall(finish)
  -- Don't error inside key listener as it will be removed. Show it later.
  local ok, err = pcall(H.stop_split)
  if not ok then vim.schedule(function() error(err, 0) end) end
end

-- General animation ----------------------------------------------------------
H.trigger_done_event = function(animation_type) vim.cmd('doautocmd User ' .. H.animation_done_events[animation_type]) end

-- Cursor ---------------------------------------------------------------------
H.make_cursor_step = function(state_from, state_to, opts)
  local pos_from, pos_to = state_from.pos, state_to.pos
  local destination = { pos_to[1] - pos_from[1], pos_to[2] - pos_from[2] }
  local path = opts.path(destination)
  if path == nil or #path == 0 then return end

  local n_steps = #path
  local timing = opts.timing

  -- Using explicit buffer id allows correct animation stop after buffer switch
  local event_id, buf_id = H.cache.cursor_event_id, state_from.buf_id

  return {
    step_action = function(step)
      -- Undraw previous mark. Doing it before early return allows to clear
      -- last animation mark.
      H.undraw_cursor_mark(buf_id)

      -- Stop animation if another cursor movement is active. Don't use
      -- `stop_cursor()` because it will also stop parallel animation.
      if H.cache.cursor_event_id ~= event_id then return false end

      -- Don't draw outside of set number of steps or not inside current buffer
      if n_steps <= step or vim.api.nvim_get_current_buf() ~= buf_id then return H.stop_cursor() end

      -- Draw cursor mark (starting from initial zero step)
      local pos = path[step + 1]
      H.draw_cursor_mark(pos_from[1] + pos[1], pos_from[2] + pos[2], buf_id)
      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.get_cursor_state = function()
  -- Use virtual column to respect position outside of line width and tabs
  return { buf_id = vim.api.nvim_get_current_buf(), pos = { vim.fn.line('.'), vim.fn.virtcol('.') } }
end

H.draw_cursor_mark = function(line, virt_col, buf_id)
  -- Use only absolute coordinates. Allows to not draw outside of buffer.
  if line <= 0 or virt_col <= 0 then return end

  -- Compute window column at which to place mark. Don't use explicit `col`
  -- argument because it won't allow placing mark outside of text line.
  local win_col = virt_col - vim.fn.winsaveview().leftcol
  if win_col < 1 then return end

  -- Set extmark
  local extmark_opts = {
    id = 1,
    hl_mode = 'combine',
    priority = 1000,
    right_gravity = false,
    virt_text = { { ' ', 'MiniAnimateCursor' } },
    virt_text_win_col = win_col - 1,
    virt_text_pos = 'overlay',
  }
  pcall(vim.api.nvim_buf_set_extmark, buf_id, H.ns_id.cursor, line - 1, 0, extmark_opts)
end

H.undraw_cursor_mark = function(buf_id) pcall(vim.api.nvim_buf_del_extmark, buf_id, H.ns_id.cursor, 1) end

H.start_cursor = function()
  H.cache.cursor_is_active = true
  return true
end

H.stop_cursor = function()
  H.cache.cursor_is_active = false
  H.trigger_done_event('cursor')
  return false
end

-- Scroll ---------------------------------------------------------------------
H.make_scroll_step = function(state_from, state_to, opts)
  -- Do not animate in Select mode because it resets it
  local is_select_mode = ({ s = true, S = true, ['\19'] = true })[vim.fn.mode()]
  if is_select_mode then return end

  -- Compute how subscrolling is done
  local from_line, to_line = state_from.view.topline, state_to.view.topline
  local total_scroll = H.get_n_visible_lines(from_line, to_line) - 1
  local step_scrolls = opts.subscroll(total_scroll)

  -- Don't animate if no subscroll steps is returned
  if step_scrolls == nil or #step_scrolls == 0 then return end

  -- Compute scrolling key ('\25' and '\5' are escaped '<C-Y>' and '<C-E>')
  local scroll_key = from_line < to_line and '\5' or '\25'

  -- Cache frequently accessed data
  local from_cur_line, to_cur_line = state_from.cursor.line, state_to.cursor.line
  local from_cur_virtcol, to_cur_virtcol = state_from.cursor.virtcol, state_to.cursor.virtcol

  local event_id, buf_id, win_id = H.cache.scroll_event_id, state_from.buf_id, state_from.win_id
  local n_steps, timing = #step_scrolls, opts.timing

  return {
    step_action = function(step)
      -- Stop animation if another scroll is active. Don't use `stop_scroll()`
      -- because it will stop parallel animation.
      if H.cache.scroll_event_id ~= event_id then return false end

      -- Stop animation if jumped to different buffer or window. Don't restore
      -- window view as it can only operate on current window.
      local is_same_win_buf = vim.api.nvim_get_current_buf() == buf_id and vim.api.nvim_get_current_win() == win_id
      if not is_same_win_buf then return H.stop_scroll() end

      -- Compute intermediate cursor position. This relies on `virtualedit=all`
      -- to be able to place cursor anywhere on screen (has better animation;
      -- at least for default equally spread subscrolls).
      local coef = step / n_steps
      local cursor_line = H.convex_point(from_cur_line, to_cur_line, coef)
      local cursor_virtcol = H.convex_point(from_cur_virtcol, to_cur_virtcol, coef)
      local cursor_data = { line = cursor_line, virtcol = cursor_virtcol }

      -- Perform scroll. Possibly stop on error.
      local ok, _ = pcall(H.scroll_action, scroll_key, step_scrolls[step], cursor_data)
      if not ok then return H.stop_scroll(state_to) end

      -- Update current scroll state for two reasons:
      -- - Be able to distinguish manual `WinScrolled` event from one created
      --   by `H.scroll_action()`.
      -- - Be able to start manual scrolling at any animation step.
      H.cache.scroll_state = H.get_scroll_state()

      -- Properly stop animation if step is too big
      if n_steps <= step then return H.stop_scroll(state_to) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.scroll_action = function(key, n, cursor_data)
  -- Scroll. Allow supplying non-valid `n` for initial "scroll" which sets
  -- cursor immediately, which reduces flicker.
  if n ~= nil and n > 0 then H.exec_normal(string.format('normal! %d%s', n, key)) end

  -- Set cursor to properly handle cursor position
  -- Computation of available top/bottom line depends on `scrolloff = 0`
  -- because otherwise it will go out of bounds causing scroll overshoot with
  -- later "bounce" back on view restore (see
  -- https://github.com/nvim-mini/mini.nvim/issues/177).
  local top, bottom = vim.fn.line('w0'), vim.fn.line('w$')
  local line = math.min(math.max(cursor_data.line, top), bottom)

  -- Cursor can only be set using byte column. To place it in the most correct
  -- virtual column, tweak output of `virtcol2col()`
  local virtcol = cursor_data.virtcol
  local col = vim.fn.virtcol2col(0, line, virtcol)
  -- - Correct for virtual column being outside of line's last virtual column
  local virtcol_past_lineend = vim.fn.virtcol({ line, '$' })
  if virtcol_past_lineend <= virtcol then col = col + virtcol - virtcol_past_lineend + 1 end

  pcall(vim.api.nvim_win_set_cursor, 0, { line, col - 1 })
end

H.start_scroll = function(start_state)
  H.cache.scroll_is_active = true
  -- Disable scrolloff in order to be able to place cursor on top/bottom window
  -- line inside scroll step.
  -- Incorporating `vim.wo.scrolloff` in computation of available top and
  -- bottom window lines works, but only in absence of folds. It gets tricky
  -- otherwise, so disabling on scroll start and restore on scroll end is
  -- better solution.
  vim.wo.scrolloff = 0
  -- Allow placing cursor anywhere on screen for better cursor placing
  vim.wo.virtualedit = 'all'

  if start_state ~= nil then
    vim.fn.winrestview(start_state.view)
    -- Track state because `winrestview()` later triggers `WinScrolled`.
    -- Otherwise mapping like `u<Cmd>lua _G.n = 0<CR>` (as in 'mini.bracketed')
    -- can result into "inverted scroll": from destination to current state.
    H.track_scroll_state()
  end

  return true
end

H.stop_scroll = function(end_state)
  if end_state ~= nil then
    vim.fn.winrestview(end_state.view)
    H.track_scroll_state()
  end

  vim.wo.scrolloff = end_state.scrolloff
  vim.wo.virtualedit = end_state.virtualedit

  H.cache.scroll_is_active = false
  H.trigger_done_event('scroll')

  return false
end

H.get_scroll_state = function()
  return {
    buf_id = vim.api.nvim_get_current_buf(),
    win_id = vim.api.nvim_get_current_win(),
    view = vim.fn.winsaveview(),
    cursor = { line = vim.fn.line('.'), virtcol = vim.fn.virtcol('.') },
    scrolloff = H.cache.scroll_is_active and H.cache.scroll_state.scrolloff or vim.wo.scrolloff,
    virtualedit = H.cache.scroll_is_active and H.cache.scroll_state.virtualedit or vim.wo.virtualedit,
  }
end

-- Resize ---------------------------------------------------------------------
H.make_resize_step = function(state_from, state_to, opts)
  -- Compute number of animation steps
  local step_sizes = opts.subresize(state_from.sizes, state_to.sizes)
  if step_sizes == nil or #step_sizes == 0 then return end
  local n_steps = #step_sizes

  -- Create animation step
  local event_id, timing = H.cache.resize_event_id, opts.timing

  return {
    step_action = function(step)
      -- Do nothing on initialization
      if step == 0 then return true end

      -- Stop animation if another resize animation is active. Don't use
      -- `stop_resize()` because it will also stop parallel animation.
      if H.cache.resize_event_id ~= event_id then return false end

      -- Perform animation. Possibly stop on error.
      -- Use `false` to not restore cursor position to avoid horizontal flicker
      local ok, _ = pcall(H.apply_resize_state, { sizes = step_sizes[step] }, false)
      if not ok then return H.stop_resize(state_to) end

      -- Properly stop animation if step is too big
      if n_steps <= step then return H.stop_resize(state_to) end

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.start_resize = function(start_state)
  H.cache.resize_is_active = true
  -- Don't restore cursor position to avoid horizontal flicker
  if start_state ~= nil then H.apply_resize_state(start_state, false) end
  return true
end

H.stop_resize = function(end_state)
  if end_state ~= nil then H.apply_resize_state(end_state, true) end
  H.cache.resize_is_active, H.cache.resize_target = false, nil
  H.trigger_done_event('resize')
  return false
end

-- Finish active resize animation before layout is changed not by it (like
-- from split animation). Apply its final sizes only to windows and dimensions
-- not changed since its last step (like after split), as others are outdated.
H.finish_resize = function()
  local target, last, sizes = H.cache.resize_target, H.cache.resize_state, {}
  if target ~= nil and vim.deep_equal(target.layout, last.layout) then
    for win_id, dims in pairs(target.sizes) do
      local last_dims = last.sizes[win_id]
      if vim.api.nvim_win_is_valid(win_id) and last_dims ~= nil then
        local height, width = vim.api.nvim_win_get_height(win_id), vim.api.nvim_win_get_width(win_id)
        sizes[win_id] = {
          height = height == last_dims.height and dims.height or height,
          width = width == last_dims.width and dims.width or width,
        }
      end
    end
  end
  -- Apply twice as setting size of one window can affect others
  for _ = 1, 2 do
    pcall(H.apply_resize_state, { sizes = sizes }, false)
  end
  H.stop_resize()
end

H.get_resize_state = function()
  local layout = vim.fn.winlayout()

  local windows = H.get_layout_windows(layout)
  local sizes, views = {}, {}
  for _, win_id in ipairs(windows) do
    sizes[win_id] = { height = vim.api.nvim_win_get_height(win_id), width = vim.api.nvim_win_get_width(win_id) }
    views[win_id] = vim.api.nvim_win_call(win_id, function() return vim.fn.winsaveview() end)
  end

  return { layout = layout, sizes = sizes, views = views }
end

H.is_equal_resize_state = function(state_1, state_2)
  return {
    layout = vim.deep_equal(state_1.layout, state_2.layout),
    sizes = vim.deep_equal(state_1.sizes, state_2.sizes),
  }
end

H.get_layout_windows = function(layout)
  local res = {}
  local traverse
  traverse = function(l)
    if l[1] == 'leaf' then
      table.insert(res, l[2])
      return
    end
    for _, sub_l in ipairs(l[2]) do
      traverse(sub_l)
    end
  end
  traverse(layout)

  return res
end

H.apply_resize_state = function(state, full_view)
  for win_id, dims in pairs(state.sizes) do
    vim.api.nvim_win_set_height(win_id, dims.height)
    vim.api.nvim_win_set_width(win_id, dims.width)
  end

  -- Use `or {}` to allow states without `view` (mainly inside animation)
  for win_id, view in pairs(state.views or {}) do
    vim.api.nvim_win_call(win_id, function()
      -- Allow to not restore full view. It mainly solves horizontal flickering
      -- when resizing from small to big width and cursor is on the end of long
      -- line. This is especially visible for high 'winwidth'.
      -- Example: `set winwidth=120 winheight=40` and hop between two
      -- vertically split windows with cursor on `$` of long line.
      if full_view then
        vim.fn.winrestview(view)
        return
      end

      -- This triggers `CursorMoved` event, but nothing can be done
      -- (`noautocmd` is of no use, see https://github.com/vim/vim/issues/2084)
      pcall(vim.api.nvim_win_set_cursor, win_id, { view.lnum, view.leftcol })
      vim.fn.winrestview({ topline = view.topline, leftcol = view.leftcol })
    end)
  end

  -- Update current resize state to be able to start another resize animation
  -- at any current animation step. Recompute state to also capture `view`.
  H.cache.resize_state = H.get_resize_state()
end

-- Open/close -----------------------------------------------------------------
H.make_openclose_step = function(action_type, win_id, config)
  -- Compute winconfig progression
  local step_winconfigs = config.winconfig(win_id)
  if step_winconfigs == nil or #step_winconfigs == 0 then return end

  -- Produce animation steps.
  local n_steps, event_id_name = #step_winconfigs, action_type .. '_event_id'
  local timing, winblend, event_id = config.timing, config.winblend, H.cache[event_id_name]
  local float_win_id

  return {
    step_action = function(step)
      -- Stop animation if another similar animation is active. Don't use
      -- `stop_openclose()` because it will also stop parallel animation.
      if H.cache[event_id_name] ~= event_id then
        pcall(vim.api.nvim_win_close, float_win_id, true)
        return false
      end

      -- Stop animation if exceeded number of steps
      if n_steps <= step then
        pcall(vim.api.nvim_win_close, float_win_id, true)
        return H.stop_openclose(action_type)
      end

      H.ensure_empty_buf()

      -- Set step config to window. Possibly (re)open (it could have been
      -- manually closed like after `:only`)
      local float_config = step_winconfigs[step + 1]
      if step == 0 or not vim.api.nvim_win_is_valid(float_win_id) then
        float_win_id = vim.api.nvim_open_win(H.empty_buf_id, false, float_config)
        vim.wo[float_win_id].winhighlight = 'Normal:MiniAnimateNormalFloat'
      else
        vim.api.nvim_win_set_config(float_win_id, float_config)
      end

      vim.wo[float_win_id].winblend = H.round(winblend(step, n_steps))

      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
  }
end

H.start_openclose = function(action_type)
  H.cache[action_type .. '_is_active'] = true
  return true
end

H.stop_openclose = function(action_type)
  H.cache[action_type .. '_is_active'] = false
  H.trigger_done_event(action_type)
  return false
end

-- Split ----------------------------------------------------------------------
H.make_split_open_step = function(data, opts)
  local win_id = data.win_id
  if not H.is_split_window(win_id) then return end

  -- Compute split pair: new window and the one it was split from. Animate
  -- split line between them going from right/bottom edge of pair's area.
  local layout = vim.fn.winlayout()
  local pair = H.get_split_pair(layout, win_id, data.prev_win_id)
  if pair == nil then return end

  -- Resize by setting size of window on the far side of split line. This way
  -- Neovim takes/gives space from/to its neighbor in pair (and not others).
  local dim, first, second = pair.dim, pair.first, pair.second
  local setter_id, setter_is_second = H.get_size_setter_leaf(second, dim), true
  if setter_id == nil or not pair.second_is_last then
    setter_id, setter_is_second = H.get_size_setter_leaf(first, dim), false
  end
  if setter_id == nil then return end

  -- Track sizes as size of the pair part after split line (right/bottom)
  local state_to = H.get_resize_state()
  local first_to, second_to = H.get_layout_extent(first, dim, state_to), H.get_layout_extent(second, dim, state_to)
  local total = first_to + second_to

  local all_wins = H.get_layout_windows(layout)
  local pair_wins = vim.list_extend(H.get_layout_windows(first), H.get_layout_windows(second))
  local other_wins = vim.tbl_filter(function(id) return not vim.tbl_contains(pair_wins, id) end, all_wins)
  local get_sizes = function(win_ids)
    local res = {}
    for _, id in ipairs(win_ids) do
      res[id] = dim == 'width' and vim.api.nvim_win_get_width(id) or vim.api.nvim_win_get_height(id)
    end
    return res
  end
  local sizes_to = {}
  for id, dims in pairs(state_to.sizes) do
    sizes_to[id] = dims[dim]
  end

  local get_second_size = function()
    local size = get_sizes({ setter_id })[setter_id]
    return setter_is_second and size or (total - size)
  end
  local set_second_size = function(size)
    H.set_win_sizes({ [setter_id] = setter_is_second and size or (total - size) }, dim, pair_wins)
  end

  -- Put split line on the edge. Allow Neovim to decide the smallest size.
  -- Set it directly if possible, as it can then even be zero.
  set_second_size(setter_is_second and 0 or H.get_layout_min_extent(second, dim))
  local second_from, sizes_from = get_second_size(), get_sizes(pair_wins)

  -- Don't animate if something went wrong (like other windows got resized)
  local restore_final = function() H.set_win_sizes(sizes_to, dim, all_wins) end
  local ok, step_sizes = pcall(opts.subsplit, second_from, second_to)
  if not (ok and H.is_resize_state_kept(state_to, pair_wins) and type(step_sizes) == 'table' and #step_sizes > 0) then
    restore_final()
    if not ok then error(step_sizes, 0) end
    return
  end

  -- Resize all pair windows (not only setter) to proportionally resize the
  -- ones inside nested containers. Set split line position first (to not take
  -- space from outside of pair) and the last (to ensure its position).
  local ordered_wins = vim.tbl_filter(function(id) return id ~= setter_id end, pair_wins)
  table.insert(ordered_wins, 1, setter_id)
  table.insert(ordered_wins, setter_id)
  local apply_step = function(size)
    local coef = second_to == second_from and 1 or ((size - second_from) / (second_to - second_from))
    local sizes = {}
    for _, id in ipairs(pair_wins) do
      sizes[id] = H.convex_point(sizes_from[id], sizes_to[id], coef)
    end
    sizes[setter_id] = setter_is_second and size or (total - size)
    H.set_win_sizes(sizes, dim, ordered_wins)
  end

  -- Track state after every step to stop if changed not by animation and to
  -- restore views at the end only if there was no cursor movement (like
  -- from other scripts, as it might be scrolled because of resize)
  local last_sizes, cursors, is_moved, bufs = {}, {}, {}, {}
  for _, id in ipairs(pair_wins) do
    bufs[id] = vim.api.nvim_win_get_buf(id)
  end
  local track_state = function()
    last_sizes = get_sizes(pair_wins)
    for _, id in ipairs(pair_wins) do
      cursors[id] = vim.api.nvim_win_get_cursor(id)
    end
  end
  local track_moved = function()
    for _, id in ipairs(pair_wins) do
      local is_same = vim.deep_equal(cursors[id], vim.api.nvim_win_get_cursor(id))
        and vim.api.nvim_win_get_buf(id) == bufs[id]
      is_moved[id] = is_moved[id] or not is_same
    end
  end
  track_state()

  -- Check if state was changed not by animation: layout or pair sizes
  local tabpage_id = vim.api.nvim_get_current_tabpage()
  local is_changed_outside = function()
    if not vim.api.nvim_tabpage_is_valid(tabpage_id) then return true end
    local cur_layout = vim.fn.winlayout(vim.api.nvim_tabpage_get_number(tabpage_id))
    return not (vim.deep_equal(cur_layout, layout) and vim.deep_equal(get_sizes(pair_wins), last_sizes))
  end

  -- Use current sizes of other windows as target to not revert their resize
  -- done not by animation. This is safe as pair sizes are checked beforehand.
  local sync_others = function()
    for _, id in ipairs(other_wins) do
      local sizes = { height = vim.api.nvim_win_get_height(id), width = vim.api.nvim_win_get_width(id) }
      state_to.sizes[id], sizes_to[id] = sizes, sizes[dim]
    end
  end

  local finish = function()
    if is_changed_outside() then return end
    track_moved()
    sync_others()
    H.set_win_sizes(sizes_to, dim, ordered_wins)
    if not H.is_resize_state_kept(state_to, pair_wins) then restore_final() end
    for _, id in ipairs(pair_wins) do
      if not is_moved[id] then vim.api.nvim_win_call(id, function() vim.fn.winrestview(state_to.views[id]) end) end
    end
  end

  local event_id, timing, n_steps = H.cache.split_event_id, opts.timing, #step_sizes
  return {
    step_action = function(step)
      -- Do nothing on initialization (split line is already at the edge)
      if step == 0 then return true end

      -- Stop animation if another split animation is active. Don't use
      -- `stop_split()` because it will also stop parallel animation.
      if H.cache.split_event_id ~= event_id then return false end

      -- Stop animation without changes if layout or pair sizes were changed
      -- not by animation (like if window was closed or resized)
      if is_changed_outside() then return H.stop_split() end

      -- Perform animation. Ensure that only pair windows are affected (as it
      -- is not always the case, like with windows of fixed size).
      track_moved()
      sync_others()
      local ok_step = pcall(apply_step, step_sizes[step])
      if not (ok_step and H.is_resize_state_kept(state_to, pair_wins)) then
        restore_final()
        return H.stop_split()
      end
      track_state()

      if step < n_steps then return true end

      -- Ensure final state
      finish()
      return H.stop_split()
    end,
    step_timing = function(step) return timing(step, n_steps) end,
    finish = finish,
  }
end

H.make_split_close_step = function(data, opts)
  -- Animate only inside current tabpage and when no new windows are present
  local tabpage_id, snapshot = data.tabpage_id, data.snapshot
  if vim.api.nvim_get_current_tabpage() ~= tabpage_id then return end
  for _, win_id in ipairs(H.get_layout_windows(vim.fn.winlayout())) do
    if snapshot.wins[win_id] == nil then return end
  end

  -- Compute regions after moving split lines which should be squeezed out.
  -- Visualize them with floating windows showing their pre-close content.
  local regions = H.get_split_close_regions(snapshot)
  local n_steps = 0
  for _, r in ipairs(regions) do
    r.step_sizes = opts.subsplit(r.size, 0) or {}
    n_steps = math.max(n_steps, #r.step_sizes)
  end
  if n_steps == 0 then return end

  -- Floating windows per imitated window. Track if some were closed not by
  -- animation, as they should not be reopened.
  local floats, is_closed_outside = {}, false
  local get_size = function(r, step)
    local n = #r.step_sizes
    if n == 0 then return step == 0 and r.size or 0 end
    -- Stretch steps of every region so that all of them finish together
    local ind = math.ceil(step * n / n_steps)
    if step < n_steps then ind = math.min(ind, n - 1) end
    return ind == 0 and r.size or r.step_sizes[ind]
  end
  local draw = function(step)
    for _, r in ipairs(regions) do
      local size = get_size(r, step)
      for _, w in ipairs(r.wins) do
        floats[w.win_id] = floats[w.win_id] or {}
        is_closed_outside = is_closed_outside or not H.draw_split_floats(floats[w.win_id], w, r, size)
      end
    end
  end
  local close_floats = function()
    for _, win_floats in pairs(floats) do
      for _, float_win_id in pairs(win_floats) do
        H.close_split_floats(float_win_id)
      end
    end
    floats = {}
  end

  -- Draw initial state immediately to not show final layout even briefly
  draw(0)

  local event_id, timing = H.cache.split_event_id, opts.timing
  return {
    step_action = function(step)
      -- Do nothing on initialization (initial state is already drawn)
      if step == 0 then return true end

      -- Stop animation if another split animation is active. Don't use
      -- `stop_split()` because it will also stop parallel animation.
      if H.cache.split_event_id ~= event_id then
        close_floats()
        return false
      end

      -- Stop animation if its floating windows are not visible or interfere:
      -- tabpage has changed, some were closed outside, one became current.
      local cur_win_id = vim.api.nvim_get_current_win()
      if H.cache.split_floats[cur_win_id] then pcall(vim.cmd, 'wincmd p') end
      local is_ok = vim.api.nvim_get_current_tabpage() == tabpage_id
        and not is_closed_outside
        and vim.api.nvim_get_current_win() == cur_win_id
        and pcall(draw, step)
        and not is_closed_outside
      if not is_ok or n_steps <= step then
        close_floats()
        return H.stop_split()
      end
      return true
    end,
    step_timing = function(step) return timing(step, n_steps) end,
    finish = close_floats,
  }
end

H.get_split_snapshot = function()
  local cur_win_id = vim.api.nvim_get_current_win()
  local columns, last_row = vim.o.columns, vim.o.lines - vim.o.cmdheight - (vim.o.laststatus == 3 and 1 or 0) - 1
  local wins = {}
  local layout = vim.fn.winlayout()
  for _, win_id in ipairs(H.get_layout_windows(layout)) do
    local info = vim.fn.getwininfo(win_id)[1]
    local top, left, text_top = info.winrow - 1, info.wincol - 1, info.winrow - 1 + info.winbar
    local opts = {}
    for _, name in ipairs(H.split_float_options) do
      local ok, value = pcall(vim.api.nvim_get_option_value, name, { scope = 'local', win = win_id })
      if ok then opts[name] = value end
    end

    wins[win_id] = {
      win_id = win_id,
      buf_id = info.bufnr,
      view = vim.api.nvim_win_call(win_id, vim.fn.winsaveview),
      opts = opts,
      folds = opts.foldenable and vim.api.nvim_win_call(win_id, H.get_closed_folds) or {},
      matches = vim.fn.getmatches(win_id),
      winhighlight = vim.wo[win_id].winhighlight,
      is_current = win_id == cur_win_id,
      -- Text area data
      text_top = text_top,
      height = info.height,
      width = info.width,
      winbar = info.winbar,
      -- Frame data (together with window separator, status line, winbar)
      top = top,
      left = left,
      bottom = text_top + info.height - 1 + (text_top + info.height <= last_row and 1 or 0),
      right = left + info.width - 1 + (left + info.width < columns and 1 or 0),
    }
  end

  -- Compute status lines and winbars before layout is changed, as their
  -- content can depend on window size and whether it is current
  for _, w in pairs(wins) do
    H.eval_split_lines(w)
  end

  return { layout = layout, wins = wins, laststatus = vim.o.laststatus, fillchars = vim.opt.fillchars:get() }
end

-- Get closed folds visible in current window
H.get_closed_folds = function()
  local res, lnum, last = {}, vim.fn.line('w0'), vim.fn.line('w$')
  while lnum <= last do
    local fold_end = vim.fn.foldclosedend(lnum)
    if fold_end == -1 then
      lnum = lnum + 1
    else
      table.insert(res, { vim.fn.foldclosed(lnum), fold_end })
      lnum = fold_end + 1
    end
  end
  return res
end

-- Window options to use in floating windows imitating windows
--stylua: ignore
H.split_float_options = {
  'breakindent', 'breakindentopt', 'colorcolumn', 'concealcursor', 'conceallevel', 'cursorcolumn',
  'cursorline', 'cursorlineopt', 'fillchars', 'foldcolumn', 'foldenable', 'foldexpr', 'foldignore',
  'foldlevel', 'foldmarker', 'foldmethod', 'foldminlines', 'foldnestmax', 'foldtext', 'linebreak', 'list',
  'listchars', 'number', 'numberwidth', 'relativenumber', 'rightleft', 'scrolloff', 'showbreak',
  'sidescrolloff', 'signcolumn', 'smoothscroll', 'spell', 'statuscolumn', 'virtualedit', 'wrap',
}

-- Compute status line and winbar content (as text chunks and base highlight)
H.eval_split_lines = function(w)
  if vim.o.laststatus ~= 3 and w.bottom > w.text_top + w.height - 1 then
    w.statusline, w.statusline_hl = H.eval_statusline(w.win_id, false, w.width)
  end
  if w.winbar == 1 then
    w.winbar_line, w.winbar_hl = H.eval_statusline(w.win_id, true, w.width)
  end
end

-- Compute regions of pre-close layout which should be squeezed out. Each
-- container with closed children has one region: everything after split line
-- before first closed child (or after first child if it is closed). This way
-- split line goes to the right/bottom edge of container while showing
-- pre-close content after it.
H.get_split_close_regions = function(snapshot)
  local wins, regions = snapshot.wins, {}
  local is_alive = function(layout)
    for _, win_id in ipairs(H.get_layout_windows(layout)) do
      if vim.api.nvim_win_is_valid(win_id) then return true end
    end
    return false
  end

  local process
  process = function(layout)
    if layout[1] == 'leaf' then return end
    local children, line_ind = layout[2], nil
    for i, sub_layout in ipairs(children) do
      if not is_alive(sub_layout) then
        line_ind = math.max(i, 2)
        break
      end
    end

    -- Process only alive children before split line (others are either
    -- replaced by actual layout or are part of the region)
    for i = 1, line_ind == nil and #children or (line_ind - 1) do
      if is_alive(children[i]) then process(children[i]) end
    end
    if line_ind == nil then return end

    local r = { dim = layout[1] == 'row' and 'width' or 'height', wins = {} }
    for i = line_ind, #children do
      for _, win_id in ipairs(H.get_layout_windows(children[i])) do
        table.insert(r.wins, wins[win_id])
      end
    end

    -- Compute split line position `from` and region's last cell `to`
    local from_key, to_key = unpack(r.dim == 'width' and { 'left', 'right' } or { 'top', 'bottom' })
    r.from, r.to = math.huge, -math.huge
    for _, w in ipairs(r.wins) do
      r.from, r.to = math.min(r.from, w[from_key] - 1), math.max(r.to, w[to_key])
    end
    r.size = r.to - r.from

    -- Compute how split line looks (as in pre-close layout)
    local is_line_before_current = false
    for _, win_id in ipairs(H.get_layout_windows(children[line_ind - 1])) do
      is_line_before_current = is_line_before_current or wins[win_id].is_current
    end
    local line_type = r.dim == 'width' and 'vert' or 'horiz'
    r.line_border = H.get_split_border_char(snapshot, line_type, { is_current = is_line_before_current })

    table.insert(regions, r)
  end
  process(snapshot.layout)

  -- Precompute how floating window borders look: separators, status lines
  for _, r in ipairs(regions) do
    for _, w in ipairs(r.wins) do
      w.vert_border = H.get_split_border_char(snapshot, 'vert')
      w.horiz_border = H.get_split_border_char(snapshot, 'horiz', w)
      w.winbar_border = { snapshot.fillchars.wbr or ' ', w.winbar_hl or (w.is_current and 'WinBar' or 'WinBarNC') }
      -- Cells where separators and status lines meet
      w.corner_border = H.get_split_corner(snapshot, w.bottom, w.left - 1) or w.horiz_border
      w.stl_corner = H.get_split_corner(snapshot, w.bottom, w.right)

      -- Horizontal split line shows status lines of windows above it
      if r.dim == 'height' and w.top == r.from + 1 then
        w.line_statusline = H.get_split_line_statusline(snapshot, w, r.from)
      end
    end
  end

  return regions
end

-- Get how separator or status line of window `w` (in pre-close layout) looks
H.get_split_border_char = function(snapshot, type, w)
  local fillchars = snapshot.fillchars
  if type == 'vert' then return { fillchars.vert or '│', 'WinSeparator' } end
  if snapshot.laststatus == 3 then return { fillchars.horiz or '─', 'WinSeparator' } end
  local is_current = w ~= nil and w.is_current
  local char = (is_current and fillchars.stl or fillchars.stlnc) or ' '
  return { char, (w or {}).statusline_hl or (is_current and 'StatusLine' or 'StatusLineNC') }
end

-- Get how cell at `row` (with status line or horizontal separator) and `col`
-- (with window separator) looks. Return `nil` if there is no intersection.
H.get_split_corner = function(snapshot, row, col)
  local fillchars = snapshot.fillchars
  local find_vsep = function(r)
    for _, w in pairs(snapshot.wins) do
      if w.right == col and w.right > w.left + w.width - 1 and w.top <= r and r <= w.bottom then return w end
    end
  end
  local has_hsep = function(c)
    for _, w in pairs(snapshot.wins) do
      if w.bottom == row and w.bottom > w.text_top + w.height - 1 and w.left <= c and c <= w.right then return true end
    end
    return false
  end

  -- Separator is replaced with status line only if they are connected
  if snapshot.laststatus ~= 3 then
    local w = find_vsep(row)
    if w == nil then return nil end
    local is_stl = w.bottom == row and w.bottom > w.text_top + w.height - 1
    local is_connected = is_stl and H.is_stl_connected(snapshot.layout, w.win_id)
    return is_connected and H.get_split_border_char(snapshot, 'horiz', w) or H.get_split_border_char(snapshot, 'vert')
  end

  -- Global status line: use connector character based on adjacent separators
  local up, down = find_vsep(row - 1) ~= nil, find_vsep(row + 1) ~= nil
  if not (up or down) then return nil end
  local left, right = has_hsep(col - 1), has_hsep(col + 1)
  local char = fillchars.vert or '│'
  if up and down and left and right then
    char = fillchars.verthoriz or '┼'
  elseif up and down and right then
    char = fillchars.vertright or '├'
  elseif up and down and left then
    char = fillchars.vertleft or '┤'
  elseif down and (left or right) then
    char = fillchars.horizdown or '┬'
  elseif up and (left or right) then
    char = fillchars.horizup or '┴'
  end
  return { char, 'WinSeparator' }
end

-- Whether status line of window is connected to the window on the right.
-- Same as `stl_connected()` in Neovim: decided by the closest parent in
-- which window's frame is not the last one.
H.is_stl_connected = function(layout, win_id)
  local res
  local walk
  walk = function(l)
    if l[1] == 'leaf' then return l[2] == win_id end
    for i, sub_layout in ipairs(l[2]) do
      if walk(sub_layout) then
        if res == nil and i < #l[2] then res = l[1] == 'row' end
        return true
      end
    end
    return false
  end
  walk(layout)
  return res == true
end

-- Combine status lines (or separators) of windows above window `w` at `row`
H.get_split_line_statusline = function(snapshot, w, row)
  local aboves = vim.tbl_filter(
    function(above) return above.bottom == row and above.left <= w.right and w.left <= above.right end,
    vim.tbl_values(snapshot.wins)
  )
  if #aboves == 0 then return nil end
  table.sort(aboves, function(a, b) return a.left < b.left end)

  local res = {}
  if snapshot.laststatus == 3 then
    -- Global status line: separator with intersections of separators
    for col = aboves[1].left, w.right do
      table.insert(res, H.get_split_corner(snapshot, row, col) or H.get_split_border_char(snapshot, 'horiz'))
    end
    return H.drop_cells(res, w.left - aboves[1].left)
  end

  for _, above in ipairs(aboves) do
    -- Each status line should span whole frame width. Cell of window
    -- separator can show separator.
    local corner = H.get_split_corner(snapshot, row, above.right)
    local width = above.right - above.left + 1 - (corner and 1 or 0)
    local fill = H.get_split_border_char(snapshot, 'horiz', above)
    vim.list_extend(res, H.fit_chunks(above.statusline, width, fill))
    if corner then table.insert(res, corner) end
  end
  return H.drop_cells(res, w.left - aboves[1].left)
end

-- Draw floating windows imitating window `w` inside squeezed region `r`.
-- Update `floats` (with part names as keys and window ids as values) in place.
-- Return `false` if some of them was closed not by animation.
H.draw_split_floats = function(floats, w, r, size)
  for _, float_win_id in pairs(floats) do
    if not vim.api.nvim_win_is_valid(float_win_id) then return false end
  end

  -- Map frame coordinates into squeezed region. Line is at `r.to - size`.
  local is_vert = r.dim == 'width'
  local line, coef = r.to - size, size / r.size
  local map = function(x) return line + 1 + H.round((x - r.from - 1) * coef) end

  -- Compute frame in squeezed region and configs of all window parts
  local from_key, to_key = unpack(is_vert and { 'left', 'right' } or { 'top', 'bottom' })
  local frame = { from = map(w[from_key]), to = map(w[to_key] + 1) - 1, has_line = w[from_key] == r.from + 1 }
  local configs = (is_vert and H.get_split_vert_configs or H.get_split_horiz_configs)(w, r, frame)

  for name, float_win_id in pairs(floats) do
    if configs[name] == nil then
      H.close_split_floats(float_win_id)
      floats[name] = nil
    end
  end
  -- Use fixed order for consistent window layering
  for _, name in ipairs({ 'text', 'line', 'winbar', 'statusline' }) do
    local config = configs[name]
    if config ~= nil and floats[name] ~= nil then
      vim.api.nvim_win_set_config(floats[name], config.win_config)
    elseif config ~= nil and config.line ~= nil then
      floats[name] = H.open_split_line_float(config)
    elseif config ~= nil then
      floats[name] = H.open_split_float(w, config.win_config)
    end
  end
  return true
end

-- Vertical region: imitate window with a single floating window. Use borders
-- to show separators (left always exists), status line, and winbar. Their
-- text is shown correctly as there is left border.
H.get_split_vert_configs = function(w, r, frame)
  local has_vsep, has_stl = w.right > w.left + w.width - 1, w.bottom > w.text_top + w.height - 1
  local width = frame.to - frame.from + 1 - (has_vsep and 1 or 0)
  if width < 1 then return {} end

  local top = w.winbar == 1 and w.winbar_border or ''
  local bottom = has_stl and w.horiz_border or ''
  local left = frame.has_line and r.line_border or w.vert_border
  local bottom_left = bottom ~= '' and w.corner_border or ''
  --stylua: ignore
  local config = {
    relative  = 'editor',
    anchor    = 'NW',
    row       = w.top,
    col       = frame.from - 1,
    width     = width,
    height    = w.height,
    focusable = false,
    zindex    = 1,
    border    = { top ~= '' and left or '', top, '', '', '', bottom, bottom_left, left },
  }
  if top ~= '' and w.winbar_line ~= nil then
    config.title, config.title_pos = H.fit_chunks(w.winbar_line, width, w.winbar_border), 'left'
  end
  if bottom ~= '' and w.statusline ~= nil then
    config.footer, config.footer_pos = H.fit_chunks(w.statusline, width, w.horiz_border), 'left'
  end
  return { text = { win_config = config } }
end

-- Horizontal region: imitate text area with a floating window (with right
-- separator as border) and split line, winbar, status line as separate ones
-- (as there is no left border to show their text correctly).
H.get_split_horiz_configs = function(w, r, frame)
  local has_vsep, has_stl = w.right > w.left + w.width - 1, w.bottom > w.text_top + w.height - 1
  local height = frame.to - frame.from + 1 - w.winbar - (has_stl and 1 or 0)
  if height < 1 then return {} end

  local base_config = { relative = 'editor', anchor = 'NW', col = w.left, focusable = false, zindex = 1 }
  local text_config = vim.tbl_extend('force', base_config, {
    row = frame.from + w.winbar,
    width = w.width,
    height = height,
    border = has_vsep and { '', '', '', w.vert_border, '', '', '', '' } or 'none',
  })

  local res = { text = { win_config = text_config } }
  local line_width = w.width + (has_vsep and 1 or 0)
  local add_line = function(name, row, chunks, fill, tail)
    local config = vim.tbl_extend('force', base_config, { row = row, width = line_width, height = 1, border = 'none' })
    res[name] = { win_config = config, line = { chunks = chunks, fill = fill, tail = tail, width = line_width } }
  end
  if frame.has_line then add_line('line', frame.from - 1, w.line_statusline, r.line_border) end
  if w.winbar == 1 then add_line('winbar', frame.from, w.winbar_line, w.winbar_border, has_vsep and w.vert_border) end
  if has_stl then add_line('statusline', frame.to, w.statusline, w.horiz_border, has_vsep and w.stl_corner) end
  return res
end

-- Open floating window showing single line of highlighted text
H.open_split_line_float = function(config)
  -- Compute line content: text chunks padded with fill character up to width
  local data = config.line
  local chunks = H.fit_chunks(data.chunks, data.width - (data.tail and 1 or 0), data.fill)
  if data.tail then table.insert(chunks, data.tail) end

  local buf_id = H.get_split_line_buf()
  local line = table.concat(vim.tbl_map(function(c) return c[1] end, chunks))
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { line })
  local col = 0
  for _, chunk in ipairs(chunks) do
    local extmark_opts = { end_col = col + chunk[1]:len(), hl_group = chunk[2] }
    pcall(vim.api.nvim_buf_set_extmark, buf_id, H.ns_id.split, 0, col, extmark_opts)
    col = col + chunk[1]:len()
  end

  -- Don't trigger any events
  local win_config = vim.tbl_extend('force', config.win_config, { noautocmd = true, style = 'minimal' })
  local ok, float_win_id = pcall(vim.api.nvim_open_win, buf_id, false, win_config)
  if not ok then return nil end
  H.cache.split_floats[float_win_id] = true
  -- Use neutral base highlighting as every cell has its own
  local setlocal = 'silent! noautocmd setlocal nowrap winbar= winblend=0 winhighlight=NormalFloat:Normal'
  if H.has_eventignorewin then setlocal = setlocal .. ' eventignorewin=all' end
  vim.api.nvim_win_call(float_win_id, function() vim.cmd(setlocal) end)
  return float_win_id
end

H.get_split_line_buf = function()
  -- Reuse buffers not shown in any window to not create new ones every time
  for buf_id, _ in pairs(H.cache.split_line_bufs) do
    if not vim.api.nvim_buf_is_loaded(buf_id) then
      H.cache.split_line_bufs[buf_id] = nil
    elseif #vim.fn.win_findbuf(buf_id) == 0 then
      vim.api.nvim_buf_clear_namespace(buf_id, H.ns_id.split, 0, -1)
      return buf_id
    end
  end
  local buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(buf_id, 'split-line')
  H.cache.split_line_bufs[buf_id] = true
  return buf_id
end

H.open_split_float = function(w, config)
  -- Show buffer content only if it is safe: buffer is loaded, is a regular
  -- buffer (to not interfere with window search, like for quickfix or help),
  -- resizing its window doesn't have side effects (like with terminal)
  local buf_id = w.buf_id
  local show_buf = vim.api.nvim_buf_is_loaded(buf_id) and vim.bo[buf_id].buftype == ''
  if not show_buf then
    H.ensure_empty_buf()
    buf_id = H.empty_buf_id
    config.style = 'minimal'
  end

  -- Don't trigger any events to not affect state (like buffer being entered)
  config.noautocmd = true
  local ok, float_win_id = pcall(vim.api.nvim_open_win, buf_id, false, config)
  if not ok then return nil end
  H.cache.split_floats[float_win_id] = true

  -- Make it look like regular window and not interact with others. Set
  -- options silently and before view (as 'scrollbind' can affect others).
  -- Floating window uses 'NormalNC' only if it is set in 'winhighlight'
  local winhighlight = show_buf and w.winhighlight or ''
  local normal_hl = (',' .. winhighlight):match(',Normal:([^,]+)') or 'Normal'
  local use_normalnc = not w.is_current and (',' .. winhighlight):find(',NormalNC:') == nil
  if use_normalnc and next(vim.api.nvim_get_hl(0, { name = 'NormalNC' })) ~= nil then normal_hl = 'NormalNC' end
  local extra_hl = 'NormalFloat:' .. normal_hl .. (w.is_current and (',NormalNC:' .. normal_hl) or '')
  winhighlight = winhighlight == '' and extra_hl or (winhighlight .. ',' .. extra_hl)
  local opts = vim.tbl_extend('force', show_buf and w.opts or {}, {
    cursorbind = false,
    scrollbind = false,
    winbar = '',
    winblend = 0,
    winhighlight = winhighlight,
    eventignorewin = H.has_eventignorewin and 'all' or nil,
  })
  vim.api.nvim_win_call(float_win_id, function()
    for name, value in pairs(opts) do
      local opt = type(value) ~= 'boolean' and (name .. '=' .. vim.fn.escape(tostring(value), ' \\|"'))
        or ((value and '' or 'no') .. name)
      vim.cmd('silent! noautocmd setlocal ' .. opt)
    end
    if not show_buf then return end

    -- Imitate window-local state: closed folds, matches, view
    if #w.folds > 0 then
      vim.cmd('silent! noautocmd setlocal foldmethod=manual')
      pcall(H.exec_normal, 'silent! normal! zE')
      for _, fold in ipairs(w.folds) do
        pcall(vim.cmd, string.format('silent! %d,%dfold', fold[1], fold[2]))
      end
    end
    pcall(vim.fn.setmatches, w.matches)
    pcall(vim.fn.winrestview, w.view)
  end)

  return float_win_id
end

H.close_split_floats = function(win_id)
  local win_ids = win_id == nil and vim.tbl_keys(H.cache.split_floats) or { win_id }
  for _, id in ipairs(win_ids) do
    H.cache.split_floats[id] = nil
    if vim.api.nvim_win_is_valid(id) then
      -- Hide buffer (to not unload it due to 'hidden'). Do it silently if
      -- buffer stays loaded (to not trigger events for something already
      -- done), otherwise let it be done properly (like due to 'bufhidden').
      local buf_id = vim.api.nvim_win_get_buf(id)
      local bufhidden = vim.bo[buf_id].bufhidden
      local stays_loaded = #vim.fn.win_findbuf(buf_id) > 1 or bufhidden == '' or bufhidden == 'hide'
      if not stays_loaded and H.has_eventignorewin then
        vim.api.nvim_win_call(id, function() vim.cmd('noautocmd setlocal eventignorewin=') end)
      end
      pcall(vim.cmd, string.format('%scall nvim_win_hide(%d)', stays_loaded and 'noautocmd ' or '', id))
    end
  end
end

H.ensure_empty_buf = function()
  -- Empty buffer should always be valid (might have been closed by user command)
  if H.empty_buf_id ~= nil and vim.api.nvim_buf_is_loaded(H.empty_buf_id) then return end
  pcall(vim.api.nvim_buf_delete, H.empty_buf_id, { force = true })
  H.empty_buf_id = vim.api.nvim_create_buf(false, true)
  H.set_buf_name(H.empty_buf_id, 'open-close-scratch')
end

H.start_split = function(finish)
  H.cache.split_is_active, H.cache.split_finish = true, finish
  return true
end

H.stop_split = function()
  -- Update tracked states to not animate what split animation has done
  H.cache.resize_state = H.get_resize_state()
  H.track_scroll_state()

  H.cache.split_is_active, H.cache.split_finish = false, nil
  H.trigger_done_event('split')
  return false
end

H.is_split_window = function(win_id)
  if not vim.api.nvim_win_is_valid(win_id) or vim.api.nvim_win_get_config(win_id).relative ~= '' then return false end
  -- Should be in current tabpage (to be visible) and not the only one there
  local is_cur_tabpage = vim.api.nvim_win_get_tabpage(win_id) == vim.api.nvim_get_current_tabpage()
  return is_cur_tabpage and vim.fn.winlayout()[1] ~= 'leaf'
end

H.get_split_pair = function(layout, win_id, prev_win_id)
  local parent, ind = H.get_layout_parent(layout, win_id)
  if parent == nil then return end

  -- Neighbor is a node from which window was split. If there are two, prefer
  -- previous window (if it is one of them) or deduce from where Neovim puts
  -- new split window by default.
  local children, dim = parent[2], parent[1] == 'row' and 'width' or 'height'
  local prev, next = children[ind - 1], children[ind + 1]
  local neighbor_ind = next == nil and (ind - 1) or (ind + 1)
  if prev ~= nil and next ~= nil then
    local is_new_after = (dim == 'width' and vim.o.splitright) or (dim == 'height' and vim.o.splitbelow)
    neighbor_ind = is_new_after and (ind - 1) or (ind + 1)
    if vim.deep_equal(prev, { 'leaf', prev_win_id }) then neighbor_ind = ind - 1 end
    if vim.deep_equal(next, { 'leaf', prev_win_id }) then neighbor_ind = ind + 1 end
  end

  local first_ind, second_ind = math.min(ind, neighbor_ind), math.max(ind, neighbor_ind)
  return {
    dim = dim,
    first = children[first_ind],
    second = children[second_ind],
    second_is_last = #children == second_ind,
  }
end

H.get_layout_parent = function(layout, win_id)
  if layout[1] == 'leaf' then return end
  for i, sub_layout in ipairs(layout[2]) do
    if sub_layout[1] == 'leaf' and sub_layout[2] == win_id then return layout, i end
    local parent, ind = H.get_layout_parent(sub_layout, win_id)
    if parent ~= nil then return parent, ind end
  end
end

-- Get window which size in dimension is the same as of whole layout node
H.get_size_setter_leaf = function(layout, dim)
  if layout[1] == 'leaf' then return layout[2] end
  if layout[1] == (dim == 'width' and 'row' or 'col') then return end
  for _, sub_layout in ipairs(layout[2]) do
    if sub_layout[1] == 'leaf' then return sub_layout[2] end
  end
end

-- Size of layout node in terms of window sizes (as in `nvim_win_get_width()`
-- and `nvim_win_get_height()`). Assumes separators are one cell wide.
H.get_layout_extent = function(layout, dim, resize_state)
  if layout[1] == 'leaf' then return resize_state.sizes[layout[2]][dim] end
  if layout[1] ~= (dim == 'width' and 'row' or 'col') then
    return H.get_layout_extent(layout[2][1], dim, resize_state)
  end
  local res = #layout[2] - 1
  for _, sub_layout in ipairs(layout[2]) do
    res = res + H.get_layout_extent(sub_layout, dim, resize_state)
  end
  return res
end

H.get_layout_min_extent = function(layout, dim)
  if layout[1] == 'leaf' then
    local win_id = layout[2]
    local min_size = math.max(dim == 'width' and vim.o.winminwidth or vim.o.winminheight, 0)
    -- Current window is always at least one cell. Height includes winbar.
    if win_id == vim.api.nvim_get_current_win() then min_size = math.max(min_size, 1) end
    if dim == 'height' then min_size = min_size + vim.fn.getwininfo(win_id)[1].winbar end
    return min_size
  end

  local is_parallel = layout[1] == (dim == 'width' and 'row' or 'col')
  local res = is_parallel and (#layout[2] - 1) or 0
  for _, sub_layout in ipairs(layout[2]) do
    local sub_min = H.get_layout_min_extent(sub_layout, dim)
    res = is_parallel and (res + sub_min) or math.max(res, sub_min)
  end
  return res
end

-- Set window sizes in dimension. Ignore fixed size of target windows to not
-- take/give space from/to others. Set twice as setting size of one window
-- might affect others.
H.set_win_sizes = function(sizes, dim, win_ids)
  local set_size = dim == 'width' and vim.api.nvim_win_set_width or vim.api.nvim_win_set_height
  local fix_option = dim == 'width' and 'winfixwidth' or 'winfixheight'
  local fixed_wins = vim.tbl_filter(function(id) return vim.wo[id][fix_option] end, win_ids)
  H.set_wins_flag_silently(fixed_wins, fix_option, false)
  for _ = 1, 2 do
    for _, id in ipairs(win_ids) do
      if sizes[id] ~= nil then pcall(set_size, id, sizes[id]) end
    end
  end
  H.set_wins_flag_silently(fixed_wins, fix_option, true)
end

H.set_wins_flag_silently = function(win_ids, name, value)
  local cmd = 'noautocmd setlocal ' .. (value and '' or 'no') .. name
  for _, win_id in ipairs(win_ids) do
    vim.api.nvim_win_call(win_id, function() vim.cmd(cmd) end)
  end
end

H.is_resize_state_kept = function(resize_state, ignore_wins)
  local ignore = {}
  for _, win_id in ipairs(ignore_wins) do
    ignore[win_id] = true
  end
  for win_id, dims in pairs(resize_state.sizes) do
    local cur_dims = { height = vim.api.nvim_win_get_height(win_id), width = vim.api.nvim_win_get_width(win_id) }
    if not ignore[win_id] and not vim.deep_equal(dims, cur_dims) then return false end
  end
  return true
end

-- Animation timings ----------------------------------------------------------
H.normalize_timing_opts = function(x)
  x = vim.tbl_deep_extend('force', H.get_config(), { easing = 'in-out', duration = 20, unit = 'step' }, x or {})
  H.validate_if(H.is_valid_timing_opts, x, 'opts')
  return x
end

H.is_valid_timing_opts = function(x)
  if type(x.duration) ~= 'number' or x.duration < 0 then
    return false, [[In `gen_timing` option `duration` should be a positive number.]]
  end

  if not vim.tbl_contains({ 'in', 'out', 'in-out' }, x.easing) then
    return false, [[In `gen_timing` option `easing` should be one of 'in', 'out', or 'in-out'.]]
  end

  if not vim.tbl_contains({ 'total', 'step' }, x.unit) then
    return false, [[In `gen_timing` option `unit` should be one of 'step' or 'total'.]]
  end

  return true
end

--- Imitate common power easing function
---
--- Every step is preceded by waiting time decreasing/increasing in power
--- series fashion (`d` is "delta", ensures total duration time):
--- - "in":  d*n^p; d*(n-1)^p; ... ; d*2^p;     d*1^p
--- - "out": d*1^p; d*2^p;     ... ; d*(n-1)^p; d*n^p
--- - "in-out": "in" until 0.5*n, "out" afterwards
---
--- This way it imitates `power + 1` common easing function because animation
--- progression behaves as sum of `power` elements.
---
---@param power number Power of series.
---@param opts table Options from `MiniAnimate.gen_timing` entry.
---@private
H.timing_arithmetic = function(power, opts)
  -- Sum of first `n_steps` natural numbers raised to `power`
  local arith_power_sum = ({
    [0] = function(n_steps) return n_steps end,
    [1] = function(n_steps) return n_steps * (n_steps + 1) / 2 end,
    [2] = function(n_steps) return n_steps * (n_steps + 1) * (2 * n_steps + 1) / 6 end,
    [3] = function(n_steps) return n_steps ^ 2 * (n_steps + 1) ^ 2 / 4 end,
  })[power]

  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'total' and duration_value or (duration_value * n_steps)
    local total_parts
    if is_in_out then
      -- Examples:
      -- - n_steps=5: 3^d, 2^d, 1^d, 2^d, 3^d
      -- - n_steps=6: 3^d, 2^d, 1^d, 1^d, 2^d, 3^d
      total_parts = 2 * arith_power_sum(math.ceil(0.5 * n_steps)) - (n_steps % 2 == 1 and 1 or 0)
    else
      total_parts = arith_power_sum(n_steps)
    end
    return total_time / total_parts
  end

  return ({
    ['in'] = function(s, n) return make_delta(n) * (n - s + 1) ^ power end,
    ['out'] = function(s, n) return make_delta(n) * s ^ power end,
    ['in-out'] = function(s, n)
      local n_half = math.ceil(0.5 * n)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s + 1) or (s - n_half)
      else
        s_halved = s < n_half and (n_half - s + 1) or (s - n_half + 1)
      end
      return make_delta(n, true) * s_halved ^ power
    end,
  })[opts.easing]
end

--- Imitate common exponential easing function
---
--- Every step is preceded by waiting time decreasing/increasing in geometric
--- progression fashion (`d` is 'delta', ensures total duration time):
--- - 'in':  (d-1)*d^(n-1); (d-1)*d^(n-2); ...; (d-1)*d^1;     (d-1)*d^0
--- - 'out': (d-1)*d^0;     (d-1)*d^1;     ...; (d-1)*d^(n-2); (d-1)*d^(n-1)
--- - 'in-out': 'in' until 0.5*n, 'out' afterwards
---
---@param opts table Options from `MiniAnimate.gen_timing` entry.
---@private
H.timing_geometrical = function(opts)
  -- Function which computes common delta so that overall duration will have
  -- desired value (based on supplied `opts`)
  local duration_unit, duration_value = opts.unit, opts.duration
  local make_delta = function(n_steps, is_in_out)
    local total_time = duration_unit == 'step' and (duration_value * n_steps) or duration_value
    -- Exact solution to avoid possible (bad) approximation
    if n_steps == 1 then return total_time + 1 end
    if is_in_out then
      local n_half = math.ceil(0.5 * n_steps)
      if n_steps % 2 == 1 then total_time = total_time + math.pow(0.5 * total_time + 1, 1 / n_half) - 1 end
      return math.pow(0.5 * total_time + 1, 1 / n_half)
    end
    return math.pow(total_time + 1, 1 / n_steps)
  end

  return ({
    ['in'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (n - s)
    end,
    ['out'] = function(s, n)
      local delta = make_delta(n)
      return (delta - 1) * delta ^ (s - 1)
    end,
    ['in-out'] = function(s, n)
      local n_half, delta = math.ceil(0.5 * n), make_delta(n, true)
      local s_halved
      if n % 2 == 0 then
        s_halved = s <= n_half and (n_half - s) or (s - n_half - 1)
      else
        s_halved = s < n_half and (n_half - s) or (s - n_half)
      end
      return (delta - 1) * delta ^ s_halved
    end,
  })[opts.easing]
end

-- Animation path -------------------------------------------------------------
H.path_line = function(destination, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(destination) then return {} end

  -- Travel along the biggest horizontal/vertical difference, but stop one
  -- step before destination
  local l, c = destination[1], destination[2]
  local l_abs, c_abs = math.abs(l), math.abs(c)
  local max_diff = math.min(math.max(l_abs, c_abs), opts.max_output_steps)

  local res = {}
  for i = 0, max_diff - 1 do
    local prop = i / max_diff
    table.insert(res, { H.round(prop * l), H.round(prop * c) })
  end
  return res
end

H.default_path_predicate = function(destination) return destination[1] < -1 or 1 < destination[1] end

-- Animation subscroll --------------------------------------------------------
H.subscroll_equal = function(total_scroll, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(total_scroll) then return {} end

  -- Make equal steps, but no more than `max_output_steps`
  local n_steps = math.min(total_scroll, opts.max_output_steps)
  local res, coef = {}, total_scroll / n_steps
  for i = 1, n_steps do
    res[i] = math.floor(i * coef) - math.floor((i - 1) * coef)
  end
  return res
end

H.default_subscroll_predicate = function(total_scroll) return total_scroll > 1 end

-- Animation subresize --------------------------------------------------------
H.subresize_equal = function(sizes_from, sizes_to, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(sizes_from, sizes_to) then return {} end

  -- Don't animate single window
  if #vim.tbl_keys(sizes_from) == 1 then return {} end

  -- Compute number of steps
  local n_steps = 0
  for win_id, dims_from in pairs(sizes_from) do
    local height_absidff = math.abs(sizes_to[win_id].height - dims_from.height)
    local width_absidff = math.abs(sizes_to[win_id].width - dims_from.width)
    n_steps = math.max(n_steps, height_absidff, width_absidff)
  end
  if n_steps <= 1 then return {} end

  -- Make subresize array
  local res = {}
  for i = 1, n_steps do
    local coef = i / n_steps
    local sub_res = {}
    for win_id, dims_from in pairs(sizes_from) do
      sub_res[win_id] = {
        height = H.convex_point(dims_from.height, sizes_to[win_id].height, coef),
        width = H.convex_point(dims_from.width, sizes_to[win_id].width, coef),
      }
    end
    res[i] = sub_res
  end

  return res
end

H.default_subresize_predicate = function(sizes_from, sizes_to) return true end

-- Animation subsplit ---------------------------------------------------------
H.subsplit_equal = function(size_from, size_to, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(size_from, size_to) then return {} end

  -- Make equal steps, but no more than `max_output_steps`
  local n_steps = math.min(math.abs(size_to - size_from), opts.max_output_steps)
  local res = {}
  for i = 1, n_steps do
    res[i] = H.convex_point(size_from, size_to, i / n_steps)
  end
  return res
end

H.default_subsplit_predicate = function(size_from, size_to) return math.abs(size_to - size_from) > 1 end

-- Animation winconfig --------------------------------------------------------
H.winconfig_static = function(win_id, opts)
  -- Don't animate in case of false predicate
  if not opts.predicate(win_id) then return {} end

  local pos = vim.fn.win_screenpos(win_id)
  local width, height = vim.api.nvim_win_get_width(win_id), vim.api.nvim_win_get_height(win_id)
  local res = {}
  for i = 1, opts.n_steps do
      --stylua: ignore
      res[i] = {
        relative  = 'editor',
        anchor    = 'NW',
        row       = pos[1] - 1,
        col       = pos[2] - 1,
        width     = width,
        height    = height,
        focusable = false,
        zindex    = 1,
        border    = 'none',
        style     = 'minimal',
      }
  end
  return res
end

H.get_window_parent_container = function(win_id)
  local f
  f = function(layout, parent_container)
    local container, second = layout[1], layout[2]
    if container == 'leaf' then
      if second == win_id then return parent_container end
      return
    end

    for _, sub_layout in ipairs(second) do
      local res = f(sub_layout, container)
      if res ~= nil then return res end
    end
  end

  -- Important to get layout of tabpage window actually belongs to (as it can
  -- already be not current tabpage)
  -- NOTE: `winlayout()` takes tabpage number (non unique), not tabpage id
  local tabpage_id = vim.api.nvim_win_get_tabpage(win_id)
  local tabpage_nr = vim.api.nvim_tabpage_get_number(tabpage_id)
  return f(vim.fn.winlayout(tabpage_nr), 'single')
end

H.default_winconfig_predicate = function(win_id) return true end

-- Utilities ------------------------------------------------------------------
H.error = function(msg) error('(mini.animate) ' .. msg, 0) end

H.check_type = function(name, val, ref, allow_nil)
  if type(val) == ref or (ref == 'callable' and vim.is_callable(val)) or (allow_nil and val == nil) then return end
  H.error(string.format('`%s` should be %s, not %s', name, ref, type(val)))
end

H.has_eventignorewin = vim.fn.exists('+eventignorewin') == 1

-- Execute Normal mode command without it being treated as user keys
H.exec_normal = function(command)
  H.cache.is_executing_normal = true
  local ok, err = pcall(vim.cmd, command)
  H.cache.is_executing_normal = false
  if not ok then error(err, 0) end
end

H.set_buf_name = function(buf_id, name) vim.api.nvim_buf_set_name(buf_id, 'minianimate://' .. buf_id .. '/' .. name) end

-- Evaluate status line (or winbar) of a window as array of `{ text, hl_group }`
H.eval_statusline = function(win_id, is_winbar, maxwidth)
  local statusline = vim.wo[win_id][is_winbar and 'winbar' or 'statusline']
  if statusline == '' and not is_winbar then statusline = H.get_builtin_statusline(win_id, maxwidth) end

  -- Don't show 'showcmd' content, as it has keys of command closing window
  statusline = H.hide_showcmd(statusline)

  -- Evaluate silently, as errors are shown as messages (not caught by
  -- `pcall`) which can abort current command
  local opts = { winid = win_id, highlights = true, use_winbar = is_winbar, maxwidth = maxwidth }
  local cmd = 'silent! let g:minianimate_statusline = nvim_eval_statusline(%s, %s)'
  local errmsg = vim.v.errmsg
  vim.g.minianimate_statusline = nil
  pcall(vim.cmd, string.format(cmd, vim.fn.string(statusline), vim.fn.string(opts)))
  local data = vim.g.minianimate_statusline
  vim.g.minianimate_statusline, vim.v.errmsg = nil, errmsg
  if type(data) ~= 'table' then return nil end

  -- Use combined highlight groups if present (Neovim>=0.11). Terminal window
  -- has special base groups, but they are not reported.
  local is_term = not is_winbar and vim.bo[vim.api.nvim_win_get_buf(win_id)].buftype == 'terminal'
  local term_groups = { StatusLine = 'StatusLineTerm', StatusLineNC = 'StatusLineTermNC' }
  local res, highlights, base_hl = {}, data.highlights, nil
  for i, hl in ipairs(highlights) do
    local groups = hl.groups
    if groups ~= nil and is_term then groups[1] = term_groups[groups[1]] or groups[1] end
    base_hl = base_hl or (groups or {})[1]
    local text = data.str:sub(hl.start + 1, highlights[i + 1] == nil and data.str:len() or highlights[i + 1].start)
    if text ~= '' then table.insert(res, { text, groups or hl.group }) end
  end
  return #res > 0 and res or nil, base_hl
end

-- Imitate built-in status line (used when 'statusline' is empty)
H.get_builtin_statusline = function(win_id, width)
  -- Ruler starts at fixed column but not before the middle. File name is
  -- truncated from start to fit before it with at least one cell gap.
  local ruler_col = vim.o.ruler and math.max(width - 18, math.floor((width + 1) / 2)) or width
  local name = vim.api.nvim_eval_statusline('%f%( %h%w%m%r%)', { winid = win_id }).str
  local chars, name_width, n_drop = vim.fn.split(name, '\\zs'), vim.fn.strdisplaywidth(name), 0
  while n_drop < #chars and name_width >= ruler_col - 1 do
    n_drop, name_width = n_drop + 1, name_width - vim.fn.strdisplaywidth(chars[n_drop + 1])
  end
  if n_drop > 0 then name = '<' .. table.concat(chars, '', n_drop + 1) end
  local res = string.format('%%-%d.%d(%s%%)', ruler_col, ruler_col, name:gsub('%%', '%%%%'))
  if not vim.o.ruler then return res end

  -- Custom ruler skips its leading group specification
  if vim.o.rulerformat ~= '' then return res .. vim.o.rulerformat:gsub('^%%%-?%d*%(', '') end

  -- Show relative position only if there is enough space for it
  local get_width = function(s) return vim.api.nvim_eval_statusline(s, { winid = win_id }).width end
  local has_space = ruler_col + get_width('%l,%c%V') + get_width('%P') < width
  return res .. '%l,%c%V' .. (has_space and '%=%P' or '')
end

-- Replace top level `%S` items of status line with empty ones
H.hide_showcmd = function(statusline)
  if statusline:find('S', 1, true) == nil or vim.startswith(statusline, '%!') then return statusline end
  local res, i, n = {}, 1, statusline:len()
  while i <= n do
    local from, to, spec, item = statusline:find('%%([-0-9.]*)(.)', i)
    if from == nil then break end
    table.insert(res, statusline:sub(i, from - 1))
    if item == 'S' then
      table.insert(res, '%' .. spec .. '{""}')
    elseif item == '{' then
      -- Skip expression as is
      local is_eval = statusline:sub(to + 1, to + 1) == '%'
      local _, expr_to = statusline:find(is_eval and '%}' or '}', to + 1, true)
      to = expr_to or n
      table.insert(res, statusline:sub(from, to))
    else
      table.insert(res, statusline:sub(from, to))
    end
    i = to + 1
  end
  table.insert(res, statusline:sub(i))
  return table.concat(res)
end

-- Make text chunks span exactly `width` cells: truncate or pad with fill
-- character (highlighted as last chunk, like in status line)
H.fit_chunks = function(chunks, width, fill)
  local res = H.truncate_cells(chunks or {}, width)
  local n_fill = width
  for _, chunk in ipairs(res) do
    n_fill = n_fill - vim.fn.strdisplaywidth(chunk[1])
  end
  if n_fill > 0 then table.insert(res, { string.rep(fill[1], n_fill), #res > 0 and res[#res][2] or fill[2] }) end
  return res
end

H.truncate_cells = function(chunks, width)
  local res = {}
  for _, chunk in ipairs(chunks) do
    local text, chunk_width = chunk[1], vim.fn.strdisplaywidth(chunk[1])
    while chunk_width > width and text ~= '' do
      text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
      chunk_width = vim.fn.strdisplaywidth(text)
    end
    if text ~= '' then table.insert(res, { text, chunk[2] }) end
    width = width - chunk_width
    if width <= 0 then break end
  end
  return res
end

H.drop_cells = function(chunks, n)
  if chunks == nil or n <= 0 then return chunks end
  local res = {}
  for _, chunk in ipairs(chunks) do
    local text = chunk[1]
    while n > 0 and text ~= '' do
      n = n - vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, 1))
      text = vim.fn.strcharpart(text, 1)
    end
    -- Pad if dropped more than needed (with double width character)
    if n < 0 then
      text, n = string.rep(' ', -n) .. text, 0
    end
    if text ~= '' then table.insert(res, { text, chunk[2] }) end
  end
  return #res > 0 and res or nil
end

H.validate_if = function(predicate, x, x_name)
  local is_valid, msg = predicate(x, x_name)
  if not is_valid then H.error(msg) end
end

H.get_n_visible_lines = function(from_line, to_line)
  local min_line, max_line = math.min(from_line, to_line), math.max(from_line, to_line)

  -- If `max_line` is inside fold, scroll should stop on the fold (not after)
  local max_line_fold_start = vim.fn.foldclosed(max_line)
  local target_line = max_line_fold_start == -1 and max_line or max_line_fold_start

  local i, res = min_line, 1
  while i < target_line do
    res = res + 1
    local end_fold_line = vim.fn.foldclosedend(i)
    i = (end_fold_line == -1 and i or end_fold_line) + 1
  end
  return res
end

H.round = function(x) return math.floor(x + 0.5) end

H.convex_point = function(x, y, coef) return H.round((1 - coef) * x + coef * y) end

return MiniAnimate
