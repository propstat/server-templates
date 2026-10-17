#!/bin/sh
# confirm_continue — POSIX shell confirmation prompt
# Source this file: . ./confirm_continue.sh

confirm_continue() {
    _default=y _quiet=0 _timeout=
    _msg_start=""
    _msg_end="This step has finished."
    _msg_y="Continuing..."  _msg_n="Aborted."
    _msg_t="Timeout reached. Aborting."  _msg_i="Invalid option. Please try again."
    _tty="${CONFIRM_TTY:-/dev/tty}"
    _on_y=""  _on_n=""
    _tty_save=""

    while [ $# -gt 0 ]; do
        case $1 in
            -q) _quiet=1 ;;
            -y) _default=y ;;
            -n) _default=n ;;
            -t) shift; _timeout=$1 ;;
            -startmsg=*) _msg_start=${1#-startmsg=} ;;
            -endmsg=*)   _msg_end=${1#-endmsg=} ;;
            msg_yes=*)     _msg_y=${1#msg_yes=} ;;
            msg_no=*)      _msg_n=${1#msg_no=} ;;
            msg_timeout=*) _msg_t=${1#msg_timeout=} ;;
            msg_invalid=*) _msg_i=${1#msg_invalid=} ;;
            on_yes=*)      _on_y=${1#on_yes=} ;;
            on_no=*)       _on_n=${1#on_no=} ;;
        esac
        shift
    done

    # Auto-quiet if no TTY is available (CI, cron, Docker, etc.)
    [ -r "$_tty" ] || _quiet=1

    # Resolve startmsg default now that _default is final
    [ -z "$_msg_start" ] && {
        [ "$_default" = y ] \
            && _msg_start="Do you want to continue? [Y/n]" \
            || _msg_start="Do you want to continue? [y/N]"
    }

    # $1=message  $2=callback  $3=default return code (0 or 1)
    # If callback is set, its exit code wins; otherwise $3 is returned.
    _cc_respond() {
        printf '%s\n' "$1" >&2
        [ -n "$2" ] && { eval "$2"; return $?; }
        return "${3:-0}"
    }

    # Restore terminal on unexpected exit (SIGINT, SIGTERM, etc.)
    _cc_restore() {
        [ -n "$_tty_save" ] && stty "$_tty_save" < "$_tty" 2>/dev/null
    }
    trap _cc_restore EXIT INT TERM

    # Print msg_yes, run on_yes callback, then print endmsg
    _cc_yes() {
        _cc_respond "$_msg_y" "$_on_y" 0; _rc=$?
        printf '%s\n' "$_msg_end" >&2
        return $_rc
    }

    if [ "$_quiet" -eq 1 ]; then
        printf '%s\n' "$_msg_start" >&2
        if [ "$_default" = y ]; then
            _cc_yes; return
        else
            _cc_respond "$_msg_n" "$_on_n" 1; return
        fi
    fi

    [ "$_default" = y ] && _prompt="Proceed? [Y/n]: " || _prompt="Proceed? [y/N]: "

    printf '%s\n' "$_msg_start" >&2

    while :; do
        printf '%s' "$_prompt" >&2
        _ans=

        if [ -n "$_timeout" ]; then
            # Phase 1: save terminal state, switch to non-canonical no-echo mode.
            # min 0 time 10: each read returns immediately on keypress or after 1s.
            _tty_save=$(stty -g < "$_tty")
            stty -icanon -echo min 0 time 10 < "$_tty"

            _i=0
            _first=""
            while [ "$_i" -lt "$_timeout" ]; do
                _first=$(dd if="$_tty" bs=1 count=1 2>/dev/null)
                if [ -n "$_first" ]; then
                    break
                fi
                _i=$((_i+1))
            done

            # Restore terminal before any further output or reads
            stty "$_tty_save" < "$_tty"
            _tty_save=""

            if [ -z "$_first" ]; then
                printf '\n' >&2
                _cc_respond "$_msg_t" "$_on_n" 1; return
            fi

            # Phase 2: first key received — echo it, read the rest of the line normally.
            # Strip newlines to correctly handle Enter as first keypress.
            printf '%s' "$_first" >&2
            IFS= read -r _rest < "$_tty"
            _ans=$(printf '%s' "${_first}${_rest}" | tr -d '\n\r')
        else
            IFS= read -r _ans < "$_tty"
        fi

        [ -z "$_ans" ] && _ans=$_default
        case $_ans in
            [yY]|[yY][eE][sS]) _cc_yes; return ;;
            [nN]|[nN][oO])     _cc_respond "$_msg_n" "$_on_n" 1; return ;;
            *)                  printf '%s\n' "$_msg_i" >&2 ;;
        esac
    done
}
