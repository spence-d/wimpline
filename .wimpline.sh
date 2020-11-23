export TERM=xterm-256color CLICOLOR=1
[ -z $TMUX ] || ZLE_RPROMPT_INDENT=0

autoload -Uz vcs_info
precmd_vcs_info() { vcs_info }
#precmd_functions+=( precmd_vcs_info )
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr " ●"
zstyle ':vcs_info:git:*' unstagedstr " ✼"
zstyle ':vcs_info:git:*' formats ' %b%c%u'
zstyle ':vcs_info:git:*' actionformats ' %b%c%u' ' %a'

zmodload zsh/datetime
function preexec() {
    echo -n "\033[0 q"
    WIMP_START=$EPOCHREALTIME
}

function zshexit() {
    echo -n "\033[0 q"
}

#FIXME
alias wimpline=~/wimpline/wimpline

function wimp_rprompt() {
    wimpline -r -w$(($COLUMNS / 3)) -d --\
             -f15 -Kred -X$exit_code\
             -k233 -f247 -T"$time_delta"\
             -c"1j" -k129 -f231 " %j" ""\
             -k208 -f0 "$vcs_info_msg_1_"\
             -k11 -f0 "$vcs_info_msg_0_"
}

function wimp_prompt() {
    wimpline -w$(($COLUMNS / 3)) --\
             -k17 -f7 '%h'\
             -k238 -f247 -b '%*'\
             -k7 -f0 -h\
             -k234 -f80 -d6\
             -k60 -f40 -K40 -F60 -s -v$KEYMAP
}

function wimp_prompt2 {
    wimpline -w$(($COLUMNS / 3)) --\
             -k17 -f7 '%h'\
             -k238 -f247 -b '%*'\
             -k7 -f0 -h\
             -k234 -f80 -d6\
             -k60 -f40 -K40 -F60 -s -v$KEYMAP\
             -k3 -f16 "%_"
}

function wimp_prompt4 {
    wimpline --\
             -k17 -f7 '%i'\
             -k238 -f247 -b '%*'\
             -k234 -f80 "%N"\
             -c"1_" -k3 -f16 "%_" ""\
             -c"?" "" -kred -fwhite "%?"
}

function wimpline_precmd() {
    exit_code=$?
    if [ -n "$WIMP_START" ]
    then
        time_delta=$(( $EPOCHREALTIME - $WIMP_START ))
        unset WIMP_START
    fi

    #PROMPT="$(wimp_prompt)"
    #RPROMPT=" $(wimp_rprompt)"
    PROMPT2="$(wimp_prompt2)"
    echo -n "\033[6 q"
}

export PROMPT4="$(wimp_prompt4)"

function zle-keymap-select {
    #PROMPT="$(wimp_prompt)"
    PROMPT2="$(wimp_prompt2)"
    zle reset-prompt

    if [ $KEYMAP = "vicmd" ]
    then
        echo -n "\033[0 q"
    else
        echo -n "\033[6 q"
    fi
}

zle -N zle-keymap-select
precmd_functions+=(wimpline_precmd)

function wimp_header() {
    wimpline -w$(( $COLUMNS / 2 )) --\
             -k90 -f51 "☰ %L"\
             -k238 -f247 -b '%D{%A %B %e %Y}'\
             -k60 -f255 -b "%n"\
             -k7 -f0 -s -H\
             -k234 -f80 "%d"\
}

function wimp_rheader() {
    wimpline -r -w$1 --\
             -k233 "$(uptime | sed -n 's/.*up \(.*\), [0-9]* users[^:]*: \(.*\)/\1   \2/p')"\
             -k66 -f0 "$(ifconfig en0 | grep -i mask | cut -d' ' -f2)"\
}

function wimp_header3() {
    wimpline -w$COLUMNS --\
             -k90 -f51 "☰ $SHLVL"\
             -k238 -f247 -b "$(strftime '%A %B %e %Y')"\
             -k60 -f255 -b "$USER"\
             -k7 -f0 -s -H"$(hostname)"\
             -p -k234 -f80 "$PWD"\
             -k233 "$(uptime | sed -n 's/.*up \(.*\), [0-9]* users[^:]*: \(.*\)/\1   \2/p')"\
             -k66 -f0 "$(ifconfig en0 | grep -i mask | cut -d' ' -f2)"\
}

function wimp_header2() {
    left="$(print -Pn "$(wimp_header)")"
    left_len=$(echo -n "$left" | perl -pe 's/\e\[[0-9;]*m//g' | wc -m)
    right_available=$(( $COLUMNS - $left_len ))
    right=$(print -Pn "$(wimp_rheader $right_available)")
    right_len=$(echo -n "$right" | perl -pe 's/\e\[[0-9;]*m//g' | wc -m)
    right_pos=$(( $right_available - $right_len ))
    print -n "$left"
    head -c $right_pos /dev/zero | tr '\0' ' '
    print "$right"
    echo
}

function wimp_dir_header() {
    local dirs=0
    local files=0
    for f in `ls -A`
    do
        if [ -d $f ]
        then
            dirs=$(( $dirs + 1 ))
        else
            files=$(( $files + 1 ))
        fi
    done

    wimpline -w$COLUMNS --\
             -k60 -f255 -b "$dirs directories $files files"\
             -k7 -f17 "$(ls -dl . | awk '{print $1 " " $3 ":" $4}')"\
             -p -k234 -f80 "$PWD"\
             -k232 -f240 "($OLDPWD)"\
             -k11 -f0 "$(git tip 2> /dev/null)"\
}

function chpwd() {
    print -P "$(wimp_dir_header)"
    echo
}

alias clear="clear; print -P \"`wimp_header3`\"; echo"

print -P "`wimp_header3`"
echo
