#===============================================================================
#
#         FILE: vcs_lines_zsh
#
#         USAGE: adds lines to show info about the current git project in terminal
#
#         From Brandon Williams
#===============================================================================

autoload -U colors && colors
autoload -Uz vcs_info

# Define prompt colors as globals so they survive outside source scope
# Using direct escape sequences avoids the 256-iteration FG/BG build loop
typeset -g reset gray green red yellow cyan blue purple lavender
local _e=$'\033'
reset="%{${reset_color}%}"
gray="%{${_e}[38;5;250m%}"
green="%{${_e}[38;5;77m%}"
red="%{${_e}[38;5;203m%}"
yellow="%{${_e}[38;5;214m%}"
cyan="%{${_e}[38;5;80m%}"
blue="%{${_e}[38;5;69m%}"
purple="%{${_e}[38;5;135m%}"
lavender="%{${_e}[38;5;189m%}"

local -A pr_com            # Associative array
local -a prompt_left_lines # Array parameters

zstyle ":pr_jrock:" mode full
zstyle ':pr_jrock:*' hooks pwd usr vcs venv npm jobs prompt
zstyle ':pr_jrock:*' pwd "%~"

# Set vcs_info options
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:(git*):*' check-for-changes false  # We run git status ourselves in +vi-git-statuses
# Format of what we will display for the git repo information.
# %s - The VCS in use (git, hg, svn, etc.).
# %i - The current revision number or identifier. (SHA we only display 10 chars)
# %c - The string from the stagedstr style if there are staged changes in the repository.
# %u - The number of unapplied patches (unapplied-string).
# %b - Information about the current branch.
# %m - A "misc" replacement. It is at the discretion of the backend to decide what this replacement expands to.
#      It is currently used by the hg and git backends to display patch information from the mq and stgit extensions.
# Format of what we will display during a special action on the repo (Ex. Interactive rebase or merge conflict)
zstyle ':vcs_info:(git*)' actionformats "(${lavender}%b${gray}|${red}%a${gray}%m${gray})"
zstyle ':vcs_info:(git*)' formats "(${lavender}%b${gray}%m${gray})"
zstyle ':vcs_info:git*+set-message:*' hooks git-statuses git-st

# Run all the prompt hook functions
# (stolen, wholesale, from the excellent hook system in vcs_info)
function pr_run_hooks() {
    local hook func
    local -a hooks

    zstyle -g hooks ":pr_jrock:*" hooks

    (( ${#hooks} == 0 )) && return 0

    for hook in ${hooks} ; do
        func="+pr-${hook}"
        if (( ${+functions[$func]} == 0 )); then
            continue
        fi
        true
        ${func} "$@"
        case $? in
            (0)
                ;;
            (*)
                break
                ;;
        esac
    done
}

# This is our prompt, this is a compressed example it will expand
# to the width of the console
# ┌──(~/src/dotfiles)v(dotfiles)──────(✔)─
# ├──(master [origin/master ] Unstaged)
# └───>
function +pr-mode-full() {
    local i info_line_width filler_width filler

    infoline=( ${pr_com[pwd]} ${pr_com[usr]} )

    # If we are in a directory that has a node_modules subdirectory we want to
    # display that on the info line
     [[ -n ${pr_com[npm]} ]] && infoline[1]=(
         ${infoline[1]}
         "${cyan} n${gray}(${pr_com[npm]}${gray})${reset}"
     )

    # If we are in a virtualenv we want to display that on the info line
    [[ -n ${pr_com[venv]} ]] && infoline[1]=(
        ${infoline[1]}
        "${blue} v${gray}(${pr_com[venv]}${gray})${reset}"
    )

    # Full-width filler; search/replace color wraps to find real text width
    info_line_width=${(S)infoline//\%\{*\%\}} # search-and-replace color escapes
    info_line_width=${#${(%)info_line_width}} # expand all escapes and count the chars
    filler_width=$(( COLUMNS - info_line_width - 4 )) # ┌── prefix + trailing ─
    (( filler_width < 0 )) && filler_width=0

    # Set the text string that will be used to fill the width of the terminal filler
    filler="${gray}${(l:${filler_width}::─:)}${reset}"
    infoline[-1]=( ${filler} ${infoline[-1]} )

    # --------------------------
    # Assemble the prompt lines
    # --------------------------
    # Default we will always have a info line and a prompt line
    lines=(
        ${(j::)infoline}
        ${pr_com[prompt]}
    )

    # If we are in a git repo we will have three lines info, git_info, prompt
    [[ -n ${pr_com[vcs]} ]] && lines[1]=(
        ${lines[1]}
        "${pr_com[vcs]}"

    )

    # Add some connecting lines to the beginning of our prompts
    if [[ -n ${pr_com[vcs]} ]]; then
        lines[1]="${gray}┌──${lines[1]}${gray}─${reset}"
        lines[2]="${gray}├──${lines[2]}${reset}"
        lines[3]="${gray}└──➤${lines[3]}${reset}"
    else
        lines[1]="${gray}┌──${lines[1]}${gray}─${reset}"
        lines[2]="${gray}└──➤${lines[2]}${reset}"
    fi

    # And we set the value for the prompt_left_lines
    prompt_left_lines=( ${lines[@]} )
}


# Show info collected from vcs_info
function +pr-vcs() {
    local -a v_vcs

    [[ -n ${vcs_info_msg_0_} ]] && v_vcs=(
        ${gray}
        ${vcs_info_msg_0_}
        ${reset}
    )

    pr_com[vcs]=${(j::)v_vcs}
}

# Show virtualenv information
function +pr-venv() {
    local -a v_venv

    # Use zsh :t modifier instead of spawning a basename subshell
    [[ -n ${VIRTUAL_ENV} ]] && v_venv=(
        ${blue}
        ${VIRTUAL_ENV:t}
        ${reset}
    )

    pr_com[venv]=${(j::)v_venv}
}

# Show npm information
function +pr-npm() {
    local -a v_npm

    if [[ ${NODE_NAME}  != "" ]]; then
        v_npm=(
            ${cyan}
            ${NODE_NAME}
            ${reset}
        )
    fi

    pr_com[npm]=${(j::)v_npm}
}

# Show number of background jobs, or hide if none
function +pr-jobs() {
    local -a v_jobs
    v_jobs=( "%(1j.${gray}%j${reset}.)" )
    pr_com[jobs]=${(j::)v_jobs}
}

function +pr-prompt() {
    local -a v_pwd i_pwd
    local -a exit_status i_usr i_host exit_status
    # account=$(_get_aws_account)

    # Add the print working directory logic
    zstyle -g i_pwd ":pr_jrock:*" pwd
    v_pwd+=( ${gray}\( )
    [[ -w $PWD ]] && v_pwd+=( ${purple} ) || v_pwd+=( ${yellow} )
    v_pwd+=( ${i_pwd} )
    v_pwd+=( ${gray}\) )
    # v_pwd+=( ${account} )
    v_pwd+=( ${reset} )
    pr_com[pwd]=${(j::)v_pwd}${reset}


    # Add exit status check or x logic
    exit_status=( ${gray}\( )
    exit_status+="%(0?.${green}✔.${red}✘)"
    exit_status+=( ${gray}\) )
    exit_status+=( ${reset} )

    pr_com[usr]=${(j::)exit_status}
}

# vcs_info functions ##########################################################

# Show remote ref name and number of commits ahead-of or behind
function +vi-git-st() {
    local ahead behind remote
    local -a gitstatus

    # Are we on a remote-tracking branch?
    remote=${$(git rev-parse --verify ${hook_com[branch]}@{upstream} \
        --symbolic-full-name --abbrev-ref 2>/dev/null)}

    if [[ -n ${remote} ]] ; then
        local ahead_out behind_out
        ahead_out=$(git rev-list ${hook_com[branch]}@{upstream}..HEAD 2>/dev/null)
        local ahead=$(( ${#ahead_out} ? ${#${(f)ahead_out}} : 0 ))
        (( ahead )) && gitstatus+=( "${green}+${ahead}${gray}" )

        behind_out=$(git rev-list HEAD..${hook_com[branch]}@{upstream} 2>/dev/null)
        local behind=$(( ${#behind_out} ? ${#${(f)behind_out}} : 0 ))
        (( behind )) && gitstatus+=( "${red}-${behind}${gray}" )

        user_data[gitstatus]=${gitstatus}
        hook_com[branch]="${hook_com[branch]} [${remote} ${(j:/:)gitstatus}]"
    fi
}

# Show the above/behind upstream counts more tersely for the compact display
function +vi-git-st-compact() {
    [[ -n ${user_data[gitstatus]} ]] \
        && hook_com[misc]="@{u}${(j:/:)user_data[gitstatus]}"
}

function +vi-git-statuses() {
    # Run git status once into an array — no temp file, no repeated greps
    local -a glines
    glines=(${(f)"$(git status --porcelain 2>/dev/null)"})
    local staged=0 unstaged=0 untracked=0 line
    for line in "${glines[@]}"; do
        [[ ${line[1]} == [MARCD] ]] && (( staged++ ))
        [[ ${line[2]} == [MARCD] ]] && (( unstaged++ ))
        [[ ${line[1,2]} == '??' ]]  && (( untracked++ ))
    done
    local stashes=${#${(f)$(git stash list 2>/dev/null)}}

    if [[ ${staged} != 0 ]] ; then
        hook_com[misc]+=" ${green}${staged}${gray}"
    fi

    if [[ ${unstaged} != 0 ]] ; then
        hook_com[misc]+=" ${red}${unstaged}${gray}"
    fi

    if [[ ${untracked} != 0 ]] ; then
        hook_com[misc]+=" ${yellow}${untracked}${gray}"
    fi

    if [[ ${stashes} != 0 ]] ; then
        hook_com[misc]+=" ${gray}${stashes}${gray}"
    fi
}


# --------------------------
# Finally we execute the above prompt functions
# --------------------------

# To be added to the precmd_* array so it is executed before each prompt
function precmd_prompt {
    local func

    # Clear out old values
    pr_com=()
    prompt_left_lines=()

    # Collect needed data
    vcs_info
    pr_run_hooks

    # Use the above data and build the prompt arrays
    func="+pr-mode-full"
    ${func} "$@"

    # Set the prompts
    PROMPT="${(F)prompt_left_lines} "
}

# Rebuild and repaint the active prompt when the terminal is resized. Without
# this, the full-width filler can leave stale line fragments after SIGWINCH.
function TRAPWINCH() {
    precmd_prompt
    zle && zle reset-prompt
}

# Display a cheatsheet of what each prompt color/symbol means
function prompt-help() {
    echo ""
    echo "  Prompt Color & Symbol Reference"
    echo "  ────────────────────────────────────────────────"
    echo ""
    echo "  Directory"
    echo "    \e[38;5;135m(~/path/to/dir)\e[0m  purple  — directory is writable"
    echo "    \e[38;5;214m(~/path/to/dir)\e[0m  yellow  — directory is read-only"
    echo ""
    echo "  Last Command"
    echo "    \e[38;5;77m✔\e[0m  green  — last command succeeded (exit 0)"
    echo "    \e[38;5;203m✘\e[0m  red    — last command failed (non-zero exit)"
    echo ""
    echo "  Git Branch  (branch-name [remote +ahead/-behind staged unstaged ?untracked stashes])"
    echo "    \e[38;5;189m(branch-name)\e[0m  lavender — branch name"
    echo "    \e[38;5;77m+N\e[0m  green   — N commits ahead of remote"
    echo "    \e[38;5;203m-N\e[0m  red     — N commits behind remote"
    echo "    \e[38;5;77mN\e[0m   green   — N staged changes"
    echo "    \e[38;5;203mN\e[0m   red     — N unstaged changes"
    echo "    \e[38;5;214mN\e[0m   yellow  — N untracked files"
    echo "    \e[38;5;250mN\e[0m   gray    — N stashed changesets"
    echo ""
    echo "  Extras (shown on info line when active)"
    echo "    \e[38;5;080mn(name)\e[0m  cyan  — active node version (NODE_NAME)"
    echo "    \e[38;5;069mv(name)\e[0m  blue  — active Python virtualenv"
    echo "    \e[38;5;250mN\e[0m       gray  — number of background jobs"
    echo ""
}
