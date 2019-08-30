#   -*- mode: sh-mode; -*-

# OK idiot, this is for future you when you finally clean this mess up.
#
# You need to distinguish between environments necessary (or useful) for
# interactive and non-interactive use (e.g. PATH is useful to any process that
# calls exec(3), so it's important in both, but shell completion is really only
# useful interactively).
#
# Try to isolate the bits that you want portable between shells and have
# distinct scripts for the shell-specific stuff.  *Use*
# .bash{rc,_login,_profile} and .z{shrc,shenv,profile,login} and source the
# common stuff from there when appropriate.  Understand which of these files is
# read automatically and when.
#
# To that end, the following is useful:
#
#  - `sh`, when it's *really* an `sh` equivalent will read the file named by
#    the environment variable ENV.  Note that `zsh` does *not* do this when
#    invoked as `emulate sh`, but it *does* if `sh` is a symlink to `zsh`.  The
#    same is true of Bash (w.r.t. symlinks).  $HOME/.profile is only sourced on
#    startup.
#
#    > This variable can be used to set aliases and other items local to the
#    > invocation of a shell. The file referred to by ENV differs from
#    > $HOME/.profile in that .profile is typically executed at session start-up,
#    > whereas the ENV file is executed at the beginning of each shell
#    > invocation. The ENV value is interpreted in a manner similar to a dot
#    > script, in that the commands are executed in the current environment and
#    > the file needs to be readable, but not executable. However, unlike dot
#    > scripts, no PATH searching is performed. This is used as a guard against
#    > Trojan Horse security breaches.
#
#    See http://pubs.opengroup.org/onlinepubs/9699919799/xrat/V4_xcu_chap02.html
#
#  - Bash has some funny rules for which files are read and when.
#
#    See https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files.html
#
#  - Zsh has a (subjectively) saner set of rules:
#
#    Unless there's something login-specific, the two files that really matter
#    are .zshrc and .zshenv (prefixed by $ZDOTDIR, if set).  .zshenv is sourced
#    on all shell invocations (except when -f (NO_RCS) is given), whereas .zshrc
#    is only sourced in interactive shells. .zshenv is sourced before .zshrc.
#    The official documentation has more detailed info, including explanations
#    of .zprofile, .zlogin, and .zlogout
#
#    See http://zsh.sourceforge.net/Intro/intro_3.html
#
# Also worth perusing: https://docstore.mik.ua/orelly/unix/upt/index.htm
#
# With all this said, this file (linked to $HOME/.profile) should be able to be
# sourced with {ba,z,da,}sh without issue and should be idempotent w.r.t. the
# environment (variables, functions, etc.).

# set some reasonable default perms on new files
umask u=rwx,g=r,o=


# Check if a command (binary or shell function/builtin) is available.
# This is, as far as I can tell, the most portable way of doing this.
cmd_exists() {
  : "${1:? Expecting an argument to test for availability.}"
  command -v "$1" 2>&1 > /dev/null
}

# Add a component to a colon separated PATH-y variables.  This really just
# exists so I can more conveniently document additions item-wise.
prepend() {
  # require the args
  : "${1:? expecting a variable name to prepend to}"
  : "${2:? expecting a path-y argument to prepend}"
  eval "$1=$2:\$$1"
}


shell_type() {
  # Try to determine what the actual shell is, not whether it was
  # invoked as `sh` or anything like that.
  if [ -n "${BASH_VERSION:-}" ]
  then
    echo bash
  elif [ -n "${ZSH_VERSION:-}" ]
  then
    echo zsh
  elif [ -n "${KSH_VERSION:-}" ]
  then
    echo ksh
  else
    # Try to figure it out based on the program invocation
    basename "$(ps -p $$ -o comm | sed -ne '2s/^-//p')"
  fi
}

_shell="$(shell_type)"


# set these for convenience, but the paths are all the defaults*
# Rationale
#  1. There are a programs that use the XDG defaults but don't read env vars
#  2. In some cases, it's difficult to ensure these are set when a program
#     starts (dunst, started by dbus is a good example)
XDG_CONFIG_HOME="$HOME/.config"
XDG_DATA_HOME="$HOME/.local/share"
XDG_CACHE_HOME="$HOME/.cache"
# No default for the RUNTIME_DIR, so keep it under an existing prefix
XDG_RUNTIME_DIR="$HOME/.local/run"

# make sure we actually have these directories
mkdir -p \
      "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"

# These permissions are required for the runtime dir to be used
chmod 0700 "$XDG_RUNTIME_DIR"

# See notes at head of file
ENV="${XDG_CONFIG_HOME}/sh/env"


# Try to keep $HOME cleanish, keep Go-managed stuff out of sight
GOPATH="$HOME/.local/go"

# This is sometimes missing, but important for homebrew (on macOS, at least)
prepend PATH "/usr/local/bin"

# My local bin directory. *Most* of my local binaries will either reside here,
# or be symlinked here.
prepend PATH "$HOME/.local/bin"
# Note: It's not really clear how much I should worry about symlinking
# built-from-source packages manually, in particular, those that may make
# assumptions about the (relative) locations of dependencies (e.g. python
# modules or shared libs).  Ideally, install scripts will manage all this
# properly, of course.


# Some systems can manage their own local binary directories.  Since the
# contents of theses tend to fluctuate between my computers, I don't symlink
# them (mostly because I'd forget to do so frequently enough to be a point of
# friction).  Usually, I'll prefer something here over something I put in
# ~/.local/bin.
prepend PATH "$GOPATH/bin"  # GO managed bins
prepend PATH "$HOME/.cabal/bin" # Cabal-managed bins


# Arch-specific local binaries (useful on shared filesystems across multiple
# architectures).  Should take precedence over just about any other PATH
# component
if [ -d "$HOME/local-$(uname -i)/bin" ]
then
  prepend PATH "$HOME/local-$(uname -i)/bin"
fi


# I almost always use Conda for managing python-y projects, but only the minimal
# distribution. Recent versions encourage you to source their init script and
# activate the base environment, but I only want `conda` available by default. I
# can always activate the base environment as necessary.
_conda_base="$HOME/miniconda3"

# Similar idea to arch-specific binary dir above
if [ -d "${_conda_base}-$(uname -i)" ]
then
  _conda_base="${_conda_base}-$(uname -i)"
fi

if [ -d "$_conda_base" ]
then
  if [ "$_shell" = "bash" ] || [ "$_shell" = "zsh" ]
  then
    # source the fancier setup with known compatible shells
    . "$_conda_base/etc/profile.d/conda.sh"
  else
    # unknown/simple shell, just do the dumb thing
    prepend PATH "$_conda_base/bin"
  fi
  # WORKON_HOME is used by virtualenvwrapper.sh and pyvenv for Emacs
  WORKON_HOME="$(conda info | awk '/envs directories/{print$3}')"
  export WORKON_HOME
fi


# if I have linuxbrew around, I'm probably using it for something
_lbrew="$HOME/.linuxbrew/bin"
if [ -d "$_lbrew" ]
then
  prepend PATH "$_lbrew"
  unbrew() {
    PATH=$(printenv PATH | tr : \\n | grep -v $(brew --prefix)/bin | tr \\n :)
    export PATH
  }
fi

sys_type="$(uname -s | tr '[:upper:]' '[:lower:]')"

# Is homebrew being used?
if cmd_exists brew
then
  have_brew() { return 0; }
  BREW_PFX=$(brew config | grep HOMEBREW_PREFIX | cut -d' ' -f2)

  prepend PATH "$BREW_PFX/bin"
  prepend MANPATH "$BREW_PFX/share/man"
  prepend INFOPATH "$BREW_PFX/share/info"
else

  have_brew() { return 1; }
fi

# if running bash (should be rare)
if [ -n "$BASH_VERSION" ]
then
  # Bash does *not* read ~/.bashrc by default as a login shell, but I'd like it
  # to, so include .bashrc if it exists.  It's also worth noting that if bash is
  # non-interactive, ~/.bash_profile and ~/.bash_login take priority (in that
  # order) over ~/.profile.  See
  # http://www.solipsys.co.uk/new/2BashInitialisationFiles.html
  if [ -f "$HOME/.bashrc" ]
  then
    . "$HOME/.bashrc"
  fi

  if have_brew
  then
    for comp in "$BREW_PFX"/etc/bash_completion.d/*
    do
      . "$comp"
    done
  fi
fi

case "$sys_type" in
  darwin* )
    # detect system-configured proxies and export them if they exist
    cmd_exists mac-prox \
      && eval $(scutil --proxy | mac-prox)

    if [ -n "$http_proxy" ]; then export http_proxy HTTP_PROXY; fi
    if [ -n "$https_proxy" ]; then export https_proxy HTTPS_PROXY; fi

    if have_brew
    then
      # Homebrew paths for GNU coreutils stuff
      gnubin="$BREW_PFX/opt/coreutils/libexec/gnubin"
      gnuman="$BREW_PFX/opt/coreutils/libexec/gnuman"
      if [ -d "$gnubin" ] && [ -d "$gnuman" ]
      then
        prepend PATH "$gnubin"
        prepend MANPATH "$gnuman"
      fi
      # same deal for gnu-tar (supports xattrs)
      gnubin="$BREW_PFX/opt/gnu-tar/libexec/gnubin"
      gnuman="$BREW_PFX/opt/gnu-tar/libexec/gnuman"
      if [ -d "$gnubin" ] && [ -d "$gnuman" ]
      then
        prepend PATH "$gnubin"
        prepend MANPATH "$gnuman"
      fi
    fi
    ;;
esac


# Rust(up) bin dir
[ -d "$HOME/.cargo/bin" ] && prepend PATH "$HOME/.cargo/bin"


# It's possible that some of these components were already in the PATH, so
# remove the duplicates (script in the bin/ directory of the dotfiles)
PATH="$(printf %s "$PATH" | dedup_path)"
INFOPATH="$(printf %s "$INFOPATH" | dedup_path):"

# The terminating colon is important here! Basically, it has the effect of
# appending the system man path(s) at the end of this list.  See manpath(1) for
# details or https://askubuntu.com/q/197461
if [ -n "$MANPATH" ]
then
  MANPATH="$(printf '%s' "$MANPATH" | dedup_path):"
fi

# Don't need to keep this around
unset -f prepend

# emacsclient wrapper in bin/. I don't know if this is necessary, but it seems
# like some things that use EDITOR don't split it on whitespace (so,
# e.g. EDITOR="emacsclient -c" doesn't work so well). A wrapper script has no
# such problem.
EDITOR=ec-wrapper-nw
VISUAL=ec-wrapper

# Helps emacs figure out what shell to use for `M-x shell`
if cmd_exists zsh
then
  SHELL="$(which zsh)"
elif cmd_exists bash
then
  SHELL="$(which zsh)"
fi

ESHELL="$SHELL"


for var in \
  PATH MANPATH INFOPATH GOPATH EDITOR SHELL ESHELL CDPATH ENV \
       XDG_CONFIG_HOME XDG_RUNTIME_DIR XDG_DATA_HOME XDG_CACHE_HOME
do
  if [ -n "$var" ]
  then
    export $var
  fi
done


# Since I use loopback pinentry with gnupg for simplicity, we need to tell
# password-store to use the "ask" pinentry-mode (i.e. force the use of Pinentry)
# since it operates in the loopback-incompatible "batch" mode.
if cmd_exists pass
then
  PASSWORD_STORE_GPG_OPTS='--pinentry-mode ask'
  export PASSWORD_STORE_GPG_OPTS
fi


# In some Gnome-y setups, the ssh-agent started by the system doesn't seem to
# work so well. ssh hangs, maybe during communication through the socket?
# Manually starting an agent will fix this, but I don't want to do that for
# every new shell I start.  This function will try to setup *one* ssh-agent
# instance (if it has not done so yet) and record the PID and SOCK vars to a
# file.  If there is an instance, it will just try to source the file.
setup_ssh_agent() {

  local sock="$XDG_RUNTIME_DIR/ssh-agent/sock"
  local env="$XDG_RUNTIME_DIR/ssh-agent/env"
  local cmd="ssh-agent -a $sock"

  # first try sourcing env file if it exists and see if the exported PID is
  # alive and matches the command we expect
  if { [ -f "$env" ] \
         && . "$env" \
         && ps -oargs -p "$SSH_AGENT_PID" | grep -qe "$cmd"; }  > /dev/null
  then
    # >&2 printf "ssh-agent(%s) active and env setup successfully\\n" "$SSH_AGENT_PID"
  else
    # >&2 printf "valid ssh-agent not detected, setting one up now\\n"

    # make sure directory exists
    mkdir -p "$(dirname "$sock")"

    # NOTE: if there actually *is* a valid agent, but we somehow missed it, this
    # will break ssh in other sessions that rely on that agent's existence.
    #
    # kill old sock so a new on can be made.
    [ -e "$sock" ] && rm -f "$sock"

    # start the agent and source the resulting file
    ssh-agent -a "$sock" > "$env"
    if ! . "$env" > /dev/null
    then
      # Who knows what may cause this to be reached
      echo "Unable to setup ssh agent. Not sure why..."
    fi
  fi
}

setup_ssh_agent


# xprofile stuff
#
# It seems like xprofile is not consistently sourced by common display managers
# or desktop sessions, but .profile is still pretty well respected.

# TODO: maybe check for wayland too? `xset` and `setxkbmap` seems to work with
# Gnome on Wayland, but `autorandr` almost certainly won't do much.
if [ "$XDG_SESSION_TYPE" = x11 ]
then

  # set a better keyboard repeat delay and rate - 200ms delay before repeat, 100
  # repetitions per second. Note: the delay is pretty accurate, I think, but the
  # number of repetitions is nowhere near 100.  It's just the value that
  # produces a good rate for me
  xset r rate 200 100

  # Make the capslock key an extra control key
  setxkbmap -option ctrl:nocaps


  # if we've got autorandr, we're probably using it
  # TODO: "probably" is not a great solution
  command -v autorandr 2>&1 > /dev/null && autorandr -c


  xres="$HOME/.Xresources"

  if [ -f "$xres" ]
  then
    xrdb -merge "$xres"
  fi
fi
