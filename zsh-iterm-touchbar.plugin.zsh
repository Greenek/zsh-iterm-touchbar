# GIT
GIT_UNCOMMITTED="${GIT_UNCOMMITTED:-⊕}"
GIT_UNSTAGED="${GIT_UNSTAGED:-⊙}"
GIT_UNTRACKED="${GIT_UNTRACKED:-⊗}"
GIT_STASHED="${GIT_STASHED:-⊘}"
GIT_UNPULLED="${GIT_UNPULLED:-⬇︎}"
GIT_UNPUSHED="${GIT_UNPUSHED:-⬆︎}"

# YARN
YARN_ENABLED=false

current_dir() {
  local dir

  if [[ "$(git rev-parse --is-inside-work-tree 2> /dev/null)" == "true" ]]; then
    local git_root=${$(git rev-parse --absolute-git-dir):h}
    dir="$(basename $git_root)"
  else
    dir="$(pwd | awk -F/ -v "n=$(tput cols)" -v "h=^$HOME" '{sub(h,"~");n=0.3*n;b=$1"/"$2} length($0)<=n || NF==3 {print;next;} NF>3{b=b"/../"; e=$NF; n-=length(b $NF); for (i=NF-1;i>3 && n>length(e)+1;i--) e=$i"/"e;} {print b e;}'
)"
  fi

  echo -n "${dir}"
}

# Output name of current branch.
git_current_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # no git repo.
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

# Uncommitted changes.
# Check for uncommitted changes in the index.
git_uncomitted() {
  if ! $(git diff --quiet --ignore-submodules --cached); then
    echo -n "${GIT_UNCOMMITTED}"
  fi
}

# Unstaged changes.
# Check for unstaged changes.
git_unstaged() {
  if ! $(git diff-files --quiet --ignore-submodules --); then
    echo -n "${GIT_UNSTAGED}"
  fi
}

# Untracked files.
# Check for untracked files.
git_untracked() {
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo -n "${GIT_UNTRACKED}"
  fi
}

# Stashed changes.
# Check for stashed changes.
git_stashed() {
  if $(git rev-parse --verify refs/stash &>/dev/null); then
    echo -n "${GIT_STASHED}"
  fi
}

# Unpushed and unpulled commits.
# Get unpushed and unpulled commits from remote and draw arrows.
git_unpushed_unpulled() {
  # check if there is an upstream configured for this branch
  command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

  local count
  count="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"
  # exit if the command failed
  (( !$? )) || return

  # counters are tab-separated, split on tab and store as array
  count=(${(ps:\t:)count})
  echo -n ""
  local arrows left=${count[1]} right=${count[2]}

  (( ${right:-0} > 0 )) && arrows+="\u2B07" || arrows+="\u21E9"
  arrows+="${right} "
  (( ${left:-0} > 0 )) && arrows+="\u2B06" || arrows+="\u21E7"
  arrows+="${left}"

  [ -n $arrows ] && echo -n "${arrows}"
}

git_diff_shortstat() {
  local stat
  stat="$(command git diff --shortstat 2>/dev/null)"
  (( !$? )) || return

  array=($(echo $stat))

  echo -n "⊡${array[1]} +${array[4]}/-${array[6]}"
}

pecho() {
  if [ -n "$TMUX" ]
  then
    echo -ne "\ePtmux;\e$*\e\\"
  else
    echo -ne $*
  fi
}

# F1-12: https://github.com/vmalloc/zsh-config/blob/master/extras/function_keys.zsh
fnKeys=('^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~')
touchBarState=''
npmScripts=()
gitBranches=()
lastPackageJsonPath=''

function _clearTouchbar() {
  pecho "\033]1337;PopKeyLabels\a"
}

function _unbindTouchbar() {
  for fnKey in "$fnKeys[@]"; do
    bindkey -s "$fnKey" ''
  done
}

function _displayDefault() {
  _clearTouchbar
  _unbindTouchbar

  touchBarState=''

  # CURRENT_DIR
  # -----------
  local dir="$(current_dir)"
  current_path="${dir}"

  # Check if the current directory is in .git before running git checks.
  if [[ "$(git rev-parse --is-inside-git-dir 2> /dev/null)" == 'false' ]]; then
    pecho "\033]1337;SetKeyLabel=F1=› $current_path\a"

    # Ensure the index is up to date.
    git update-index --really-refresh -q &>/dev/null

    # String of indicators
    local indicators="$(git_unpushed_unpulled)"

    [ -n "${indicators}" ] && touchbarIndicators="${indicators}" || touchbarIndicators="✓";

    pecho "\033]1337;SetKeyLabel=F2=\u2325 $(git_current_branch)\a"
    pecho "\033]1337;SetKeyLabel=F3=$touchbarIndicators\a"
    pecho "\033]1337;SetKeyLabel=F4=⤓ Pull\a";

    # bind git actions
    bindkey -s '^[OP' 'dirname $(git rev-parse --absolute-git-dir)\n'
    bindkey "^[OQ" _displayBranches
    bindkey -s '^[OR' 'git status \n'
    bindkey -s '^[OS' "git pull --rebase \n"
  else
    pecho "\033]1337;SetKeyLabel=F1=$current_path\a"
    bindkey -s '^[OP' 'pwd \n'
  fi

  if [[ -f package.json ]]; then
    if [[ -f yarn.lock ]] && [[ "$YARN_ENABLED" = true ]]; then
      pecho "\033]1337;SetKeyLabel=F5=▶︎ Run\a"
      bindkey "${fnKeys[5]}" _displayYarnScripts
    else
      pecho "\033]1337;SetKeyLabel=F5=▶︎ Run\a"
      bindkey "${fnKeys[5]}" _displayNpmScripts
    fi
  fi
}

function _displayNpmScripts() {
  # find available npm run scripts only if new directory
  if [[ $lastPackageJsonPath != $(echo "$(pwd)/package.json") ]]; then
    lastPackageJsonPath=$(echo "$(pwd)/package.json")
    npmScripts=($(node -e "console.log(Object.keys($(npm run --json)).filter(name => !name.includes(':')).sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 12).join(' '))"))
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='npm'

  fnKeysIndex=1
  for npmScript in "$npmScripts[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    bindkey -s $fnKeys[$fnKeysIndex] "npm run $npmScript; _displayDefault \n"
    pecho "\033]1337;SetKeyLabel=F$fnKeysIndex=$npmScript\a"
  done

  pecho "\033]1337;SetKeyLabel=F1=↩︎\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

function _displayYarnScripts() {
  # find available yarn run scripts only if new directory
  if [[ $lastPackageJsonPath != $(echo "$(pwd)/package.json") ]]; then
    lastPackageJsonPath=$(echo "$(pwd)/package.json")
    yarnScripts=($(node -e "console.log($(yarn run --json 2>&1 | sed '4!d').data.items.filter(name => !name.includes(':')).sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 12).join(' '))"))
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='yarn'

  fnKeysIndex=1
  for yarnScript in "$yarnScripts[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    bindkey -s $fnKeys[$fnKeysIndex] "yarn run $yarnScript; _displayDefault \n"
    pecho "\033]1337;SetKeyLabel=F$fnKeysIndex=$yarnScript\a"
  done

  pecho "\033]1337;SetKeyLabel=F1=↩︎\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

function _displayBranches() {
  # List of branches for current repo
  gitBranches=($(node -e "console.log('$(echo $(git branch))'.split(/[ ,]+/).toString().split(',').join(' ').toString().replace('* ', ''))"))

  _clearTouchbar
  _unbindTouchbar

  # change to github state
  touchBarState='github'

  fnKeysIndex=1
  # for each branch name, bind it to a key
  for branch in "$gitBranches[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    bindkey -s $fnKeys[$fnKeysIndex] "git checkout $branch; _displayDefault \n"
    pecho "\033]1337;SetKeyLabel=F$fnKeysIndex=$branch\a"
  done

  pecho "\033]1337;SetKeyLabel=F1=↩︎\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

zle -N _displayDefault
zle -N _displayNpmScripts
zle -N _displayYarnScripts
zle -N _displayBranches

precmd_iterm_touchbar() {
  if [[ $touchBarState == 'npm' ]]; then
    _displayNpmScripts
  elif [[ $touchBarState == 'yarn' ]]; then
    _displayYarnScripts
  elif [[ $touchBarState == 'github' ]]; then
    _displayBranches
  else
    _displayDefault
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd precmd_iterm_touchbar
