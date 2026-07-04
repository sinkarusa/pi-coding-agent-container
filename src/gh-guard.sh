#!/usr/bin/env bash
set -e

if [ "${PARANOID_MODE}" = "true" ]; then
	# Resolve the subcommand as the first non-option token rather than $1.
	# gh has few global flags today (--version/--help), but skipping leading
	# options keeps the guard correct if a global flag is ever placed before
	# the subcommand (e.g. `gh --foo auth ...`).
	COMMAND=""
	for arg in "$@"; do
		case "$arg" in
		-*) continue ;;
		*)
			COMMAND="$arg"
			break
			;;
		esac
	done

	# `alias` is blocked because `gh alias set x 'auth login'` followed by
	# `gh x` would otherwise smuggle a blocked subcommand past this guard —
	# gh expands the alias internally, so the guard never sees `auth`.
	case "$COMMAND" in
	auth | repo | secret | ssh-key | gpg-key | alias)
		echo "[SYSTEM BLOCK] Paranoid mode is active. The agent is not authorized to execute gh $COMMAND."
		exit 1
		;;
	esac
fi

exec /usr/bin/gh "$@"
