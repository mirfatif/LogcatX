logcatx() {
	if [ $# -gt 0 ]; then
		adb $ADB_OPTS shell -t "exec /data/local/tmp/logcatx $(printf '"%s" ' "$@")"
	else
		adb $ADB_OPTS shell -t "exec /data/local/tmp/logcatx"
	fi
}

_logcatx_completion() {
	local cur prev
	local IFS=$' \t\n'
	COMPREPLY=()
	cur="${COMP_WORDS[COMP_CWORD]:-}"
	prev="${COMP_WORDS[COMP_CWORD - 1]:-}"

	# Option names (no '=' so bash appends a space)
	local option_list='-p --pid -u --uid -pkg --package -pcs --process -mp --match-pkg-pid -mn --match-process-name -i --refresh-interval -d --dump -t --tail -b --buffers -c --color -lf --log-format -dt --date -ms --millis -tf --ts-format -tw --tag-width -w --width -rt --repeat-tag -pr --priority -x --exclude -v --version -h --help'

	# Options that accept values (both short and long forms)
	local options_with_values='-p --pid -u --uid -pkg --package -pcs --process -mn --match-process-name -i --refresh-interval -t --tail -b --buffers -c --color -lf --log-format -tf --ts-format -tw --tag-width -w --width -pr --priority -x --exclude'

	# Options that must be treated as single-valued (no comma splitting)
	local single_valued='-c --color -mn --match-process-name -pr --priority'

	# Enumerated lists for completions
	local match_process_name_vals="contains exact start regex"
	local buffers_vals="main radio events system crash stats security kernel"
	local color_vals="never always terminal"
	local log_format_vals="ts uid pid buf prio tag msg"
	local priority_vals="verb debug info warn error fatal"

	# adb helpers (only used if exactly one device attached)
	_one_adb_device() {
		local n
		n=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{count++} END{print (count+0)}')
		[[ "$n" -eq 1 ]]
	}
	_adb() { eval "$1" 2>/dev/null | tr -d '\r'; }
	_get_pids() { _adb "adb shell 'ls /proc/'" | tr -s '[:space:]' '\n' | grep -E '^[0-9]+$' | sort -n; }
	_get_packages() { _adb "adb shell pm list packages" | awk -F: '{print $2}' | sed '/^$/d' | sort; }
	_get_uids() { _adb "adb shell pm list packages -U" | awk -F: '{print $3}' | sed '/^$/d' | sort -nu; }

	# Helpers
	_in_list() {
		local needle="$1"
		shift
		for e in $*; do [[ "$e" == "$needle" ]] && return 0; done
		return 1
	}

	# Split last comma only when option allows comma lists and is not in single_valued
	_split_comma_maybe() {
		# args: <option> <string>
		local opt="$1"
		local s="$2"
		# If opt is single-valued, do not split; FRAG is entire s, LEFTPART empty
		if _in_list "$opt" $single_valued; then
			LEFTPART=""
			FRAG="$s"
			return
		fi
		# Otherwise split on last comma
		if [[ "$s" == *,* ]]; then
			LEFTPART="${s%,*},"
			FRAG="${s##*,}"
		else
			LEFTPART=""
			FRAG="$s"
		fi
	}

	# If prev is an option that accepts values, provide completions for the value.
	if [[ -n "$prev" ]] && _in_list "$prev" $options_with_values; then
		# For single-valued options we must not treat commas specially.
		_split_comma_maybe "$prev" "$cur"

		local candidates_raw=""
		case "$prev" in
		-p | --pid) if _one_adb_device; then candidates_raw="$(_get_pids)"; fi ;;
		-u | --uid) if _one_adb_device; then candidates_raw="$(_get_uids)"; fi ;;
		-pkg | --package) if _one_adb_device; then candidates_raw="$(_get_packages)"; fi ;;
		-mn | --match-process-name) candidates_raw="$match_process_name_vals" ;;
		-b | --buffers) candidates_raw="$buffers_vals" ;;
		-c | --color) candidates_raw="$color_vals" ;;
		-lf | --log-format) candidates_raw="$log_format_vals" ;;
		-pr | --priority) candidates_raw="$priority_vals" ;;
		# Free text/int options -> no specialized completions
		-pcs | -i | -t | -tf | -tw | -w | -x) candidates_raw="" ;;
		*) candidates_raw="" ;;
		esac

		# Nothing to suggest
		if [[ -z "$candidates_raw" ]]; then
			return 0
		fi

		# Convert raw newline-separated candidates into array then space-joined string
		local -a cand_arr
		if command -v mapfile >/dev/null 2>&1; then
			mapfile -t cand_arr < <(printf '%s\n' "$candidates_raw")
		else
			local IFSbak="$IFS"
			IFS=$'\n' read -r -d '' -a cand_arr < <(printf '%s\n' "$candidates_raw" && printf '\0')
			IFS="$IFSbak"
		fi
		local joined
		joined="$(printf '%s\n' "${cand_arr[@]}" | tr '\n' ' ')"

		# Produce completions.
		# For single-valued options we inserted FRAG==entire cur even if cur had commas; so pressing TAB after a trailing comma won't show suggestions.
		COMPREPLY=($(compgen -W "$joined" -- "$FRAG"))
		# If the option accepts lists and LEFTPART is non-empty, prefix suggestions with LEFTPART
		if [[ ${#COMPREPLY[@]} -gt 0 && -n "$LEFTPART" ]]; then
			local i
			for i in "${!COMPREPLY[@]}"; do
				COMPREPLY[$i]="${LEFTPART}${COMPREPLY[$i]}"
			done
		fi
		return 0
	fi

	# Otherwise complete option names
	COMPREPLY=($(compgen -W "$option_list" -- "$cur"))
	return 0
}

complete -o bashdefault -o default -F _logcatx_completion logcatx
