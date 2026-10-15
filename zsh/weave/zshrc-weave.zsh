#!/usr/bin/env zsh
# zshrc-weave renders three fixed blocks into ~/.zshrc and maps edited blocks
# back to their files below ~/.config. It never invokes Git.

emulate -LR zsh
setopt pipefail

SCRIPT_DIR="${0:A:h}"
CONFIG_DIR="${ZSH_WEAVE_CONFIG_DIR:-${SCRIPT_DIR:h}}"
CONFIG_ROOT="${CONFIG_DIR:h}"
OUTPUT_FILE="${ZSH_WEAVE_OUTPUT_FILE:-$HOME/.zshrc}"
WEAVE_DIR="$CONFIG_DIR/weave"
STATUS_FILE="$WEAVE_DIR/.status"
TRANSACTION_DIR="$WEAVE_DIR/.sync-transaction"
LOG_DIR="${ZSH_WEAVE_LOG_DIR:-$CONFIG_ROOT/logs}"
ERROR_LOG="$LOG_DIR/zshrc-weave.error.log"

typeset -ga PLATFORM_PATHS

# Describe the internal rendering and write-back entry points.
usage() {
    print 'Usage: zshrc-weave.zsh <render|check|sync> [macos|debian|auto]'
    print 'Environment: ZSH_WEAVE_CONFIG_DIR, ZSH_WEAVE_OUTPUT_FILE'
}

# Report failures; read-only checks do not create persistent logs.
fail() {
    local message="$*"
    if [[ "${CHECK_ONLY:-0}" == 1 ]]; then
        print -u2 -- "zshrc-weave: $message"
        return 1
    fi
    command mkdir -p "$LOG_DIR" 2>/dev/null || true
    command chmod 700 "$LOG_DIR" 2>/dev/null || true
    print -r -- "$(now) ERROR ${message}" >> "$ERROR_LOG" 2>/dev/null || true
    command chmod 600 "$ERROR_LOG" 2>/dev/null || true
    print -u2 -- "zshrc-weave: $message"
    return 1
}

now() {
    command date -u '+%Y-%m-%dT%H:%M:%SZ'
}

write_status() {
    local state="$1"
    local platform="$2"
    local detail="${3:-}"
    command mkdir -p "$WEAVE_DIR" || return 1
    {
        print -r -- "state=${state}"
        print -r -- "platform=${platform}"
        print -r -- "updated_at=$(now)"
        print -r -- "detail=${detail}"
    } > "$STATUS_FILE"
    command chmod 600 "$STATUS_FILE" 2>/dev/null || true
}

file_mode() {
    local target_file="$1"
    if [[ "$OSTYPE" == darwin* ]]; then
        command stat -f '%Lp' "$target_file"
    else
        command stat -c '%a' "$target_file"
    fi
}

resolve_platform() {
    local requested="${1:-auto}"
    case "$requested" in
        macos|debian)
            print -r -- "$requested"
            ;;
        auto)
            if [[ "${ZSH_WEAVE_PLATFORM:-}" == macos || "${ZSH_WEAVE_PLATFORM:-}" == debian ]]; then
                print -r -- "$ZSH_WEAVE_PLATFORM"
            elif [[ "$OSTYPE" == darwin* ]]; then
                print -r -- macos
            elif [[ -f /etc/debian_version ]]; then
                print -r -- debian
            else
                fail "unsupported platform: $OSTYPE"
            fi
            ;;
        *)
            fail "unknown platform: $requested"
            ;;
    esac
}

load_platform_paths() {
    local platform="$1"
    local source_path

    case "$platform" in
        macos|debian)
            PLATFORM_PATHS=(
                'zsh/before.zshrc'
                "zsh/zshrc.${platform}"
                'zsh/after.zshrc'
            )
            ;;
        *)
            fail "unknown platform: $platform"
            return 1
            ;;
    esac

    for source_path in "${PLATFORM_PATHS[@]}"; do
        [[ -r "$CONFIG_ROOT/$source_path" ]] || fail "missing source block: $CONFIG_ROOT/$source_path" || return 1
    done
}

acquire_sync_lock() {
    local lock_variable="$1"

    command mkdir -p "$WEAVE_DIR" || {
        fail "cannot create weave directory: $WEAVE_DIR"
        return 1
    }
    : >> "$STATUS_FILE" || {
        fail "cannot open sync lock: $STATUS_FILE"
        return 1
    }
    command chmod 600 "$STATUS_FILE" 2>/dev/null || true
    zmodload zsh/system 2>/dev/null || {
        fail 'zsh/system is required for the sync lock'
        return 1
    }
    zsystem flock -t 5 -f "$lock_variable" "$STATUS_FILE" 2>/dev/null || {
        fail "cannot acquire sync lock: $STATUS_FILE"
        return 1
    }
}

release_sync_lock() {
    local lock_fd="$1"
    [[ -n "$lock_fd" ]] || return 0
    zsystem flock -u "$lock_fd" 2>/dev/null || true
}

cleanup_stale_transactions_locked() {
    local stale_dir
    for stale_dir in "$WEAVE_DIR"/.sync-transaction.*(N/); do
        command rm -rf "$stale_dir" || {
            fail "cannot remove stale transaction: $stale_dir"
            return 1
        }
    done
}

recover_transaction_locked() {
    [[ -d "$TRANSACTION_DIR" ]] || return 0

    local platform source_path source_file staged_file source_dir temp_file mode completed_dir
    local -i block_index cmp_status

    [[ -r "$TRANSACTION_DIR/platform" ]] || {
        fail "invalid sync transaction: missing platform"
        return 1
    }
    IFS= read -r platform < "$TRANSACTION_DIR/platform" || {
        fail "invalid sync transaction: unreadable platform"
        return 1
    }
    load_platform_paths "$platform" || return 1

    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        [[ -f "$TRANSACTION_DIR/$block_index" && -r "$TRANSACTION_DIR/$block_index" ]] || {
            fail "invalid sync transaction: missing block $block_index"
            return 1
        }
    done

    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        source_path="${PLATFORM_PATHS[$block_index]}"
        source_file="$CONFIG_ROOT/$source_path"
        staged_file="$TRANSACTION_DIR/$block_index"

        command cmp -s "$staged_file" "$source_file"
        cmp_status=$?
        (( cmp_status == 0 )) && continue
        (( cmp_status == 1 )) || {
            fail "cannot compare transaction block: $source_path"
            return 1
        }

        mode="$(file_mode "$source_file")" || {
            fail "cannot read source mode: $source_path"
            return 1
        }
        source_dir="${source_file:h}"
        temp_file="$(command mktemp "$source_dir/.${source_file:t}.zshrc-weave.XXXXXX")" || {
            fail "cannot stage source block: $source_path"
            return 1
        }
        if ! command cat "$staged_file" > "$temp_file"; then
            command rm -f "$temp_file"
            fail "cannot write staged source block: $source_path"
            return 1
        fi
        if ! command chmod "$mode" "$temp_file"; then
            command rm -f "$temp_file"
            fail "cannot preserve source mode: $source_path"
            return 1
        fi
        if ! command mv "$temp_file" "$source_file"; then
            command rm -f "$temp_file"
            fail "cannot replace source block: $source_path"
            return 1
        fi
    done

    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        source_path="${PLATFORM_PATHS[$block_index]}"
        command cmp -s "$TRANSACTION_DIR/$block_index" "$CONFIG_ROOT/$source_path" || {
            fail "sync transaction verification failed: $source_path"
            return 1
        }
    done

    completed_dir="$WEAVE_DIR/.sync-transaction.completed.$$"
    if ! command mv "$TRANSACTION_DIR" "$completed_dir"; then
        fail 'cannot finalize sync transaction'
        return 1
    fi
    command rm -rf "$completed_dir" 2>/dev/null || true
}

stage_transaction_locked() {
    local workspace="$1"
    local platform="$2"
    local transaction_temp
    local -i block_index

    [[ ! -e "$TRANSACTION_DIR" ]] || {
        fail 'cannot stage sync while another transaction is pending'
        return 1
    }

    transaction_temp="$(command mktemp -d "$WEAVE_DIR/.sync-transaction.XXXXXX")" || {
        fail 'cannot create sync transaction'
        return 1
    }
    if ! command chmod 700 "$transaction_temp"; then
        command rm -rf "$transaction_temp"
        fail 'cannot protect sync transaction'
        return 1
    fi

    if ! print -r -- "$platform" > "$transaction_temp/platform"; then
        command rm -rf "$transaction_temp"
        fail 'cannot write sync transaction platform'
        return 1
    fi
    if ! command chmod 600 "$transaction_temp/platform"; then
        command rm -rf "$transaction_temp"
        fail 'cannot protect sync transaction platform'
        return 1
    fi

    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        if ! command cat "$workspace/$block_index" > "$transaction_temp/$block_index"; then
            command rm -rf "$transaction_temp"
            fail "cannot stage sync transaction block $block_index"
            return 1
        fi
        if ! command chmod 600 "$transaction_temp/$block_index"; then
            command rm -rf "$transaction_temp"
            fail "cannot protect sync transaction block $block_index"
            return 1
        fi
    done

    if ! command mv "$transaction_temp" "$TRANSACTION_DIR"; then
        command rm -rf "$transaction_temp"
        fail 'cannot activate sync transaction'
        return 1
    fi
}

is_managed_output() {
    [[ -f "$OUTPUT_FILE" ]] && command grep -q '^# ===== BEGIN zsh/before\.zshrc =====$' "$OUTPUT_FILE"
}

prepare_output_target() {
    local output_dir="${OUTPUT_FILE:h}"
    command mkdir -p "$output_dir" || return 1

    if [[ -e "$OUTPUT_FILE" ]] && ! is_managed_output; then
        [[ "${ZSH_WEAVE_ADOPT:-0}" == 1 ]] || {
            fail "refusing to overwrite unmanaged $OUTPUT_FILE; set ZSH_WEAVE_ADOPT=1 after backing it up"
            return 1
        }
        local backup="${OUTPUT_FILE}.zshrc-weave-backup-$(command date '+%Y%m%d%H%M%S')"
        command cp -p "$OUTPUT_FILE" "$backup" || return 1
    fi
}

# Generate and validate the three blocks before replacing a file or printing a preview.
render_locked() {
    local platform="$1"
    case "${ZSH_WEAVE_RECOVER:-1}" in
        1)
            recover_transaction_locked || return 1
            ;;
        0)
            [[ ! -d "$TRANSACTION_DIR" ]] || {
                fail 'pending sync transaction prevents non-recovering render'
                return 1
            }
            ;;
        *)
            fail "invalid ZSH_WEAVE_RECOVER value: ${ZSH_WEAVE_RECOVER}"
            return 1
            ;;
    esac
    load_platform_paths "$platform" || return 1
    local output_dir="${OUTPUT_FILE:h}"
    local temp_file source_path result
    if [[ "$OUTPUT_FILE" == - ]]; then
        output_dir="${TMPDIR:-/tmp}"
    else
        prepare_output_target || return 1
    fi
    temp_file="$(command mktemp "$output_dir/.zshrc-weave.XXXXXX")" || return 1

    {
        for source_path in "${PLATFORM_PATHS[@]}"; do
            print -r -- "# ===== BEGIN $source_path ====="
            command cat "$CONFIG_ROOT/$source_path"
            print -r -- "# ===== END $source_path ====="
            print -r --
        done
    } > "$temp_file"

    if ! command zsh -n "$temp_file"; then
        command rm -f "$temp_file"
        fail "rendered output has invalid Zsh syntax"
        return 1
    fi

    if [[ "$OUTPUT_FILE" == - ]]; then
        command cat "$temp_file"
        result=$?
        command rm -f "$temp_file"
        return "$result"
    fi

    if ! command chmod 600 "$temp_file"; then
        command rm -f "$temp_file"
        fail "cannot protect rendered output: $OUTPUT_FILE"
        return 1
    fi
    if ! command mv "$temp_file" "$OUTPUT_FILE"; then
        command rm -f "$temp_file"
        fail "cannot replace rendered output: $OUTPUT_FILE"
        return 1
    fi
    write_status idle "$platform" 'rendered'
}

# Keep previews read-only; serialize file rendering and transaction recovery.
render() {
    local platform lock_fd result=0
    local CHECK_ONLY=0
    if [[ "$OUTPUT_FILE" == - ]]; then
        CHECK_ONLY=1
        local ZSH_WEAVE_RECOVER=0
        platform="$(resolve_platform "${1:-auto}")" || return 1
        render_locked "$platform"
        return $?
    fi
    platform="$(resolve_platform "${1:-auto}")" || return 1
    acquire_sync_lock lock_fd || return 1
    cleanup_stale_transactions_locked || result=$?
    if (( result == 0 )); then
        render_locked "$platform" || result=$?
    fi
    release_sync_lock "$lock_fd"
    return "$result"
}

# Validate one immutable snapshot, extract its blocks, and identify changed sources.
check_blocks() {
    local platform="$1" workspace="$2"
    load_platform_paths "$platform" || return 1
    is_managed_output || {
        fail "not a managed output: $OUTPUT_FILE"
        return 1
    }
    command cp "$OUTPUT_FILE" "$workspace/output" || return 1
    if ! command zsh -f -n "$workspace/output" >/dev/null 2>&1; then
        fail 'edited output has invalid Zsh syntax; source blocks were not changed'
        return 1
    fi

    local expected_markers actual_markers expected_path output_content
    local begin_marker end_marker block_content source_file
    local -i block_index cmp_status
    expected_markers="$(for expected_path in "${PLATFORM_PATHS[@]}"; do
        print -r -- "# ===== BEGIN $expected_path ====="
        print -r -- "# ===== END $expected_path ====="
    done)"
    actual_markers="$(command grep -E '^# ===== (BEGIN|END) ' "$workspace/output")"
    [[ "$actual_markers" == "$expected_markers" ]] || {
        fail 'expected exactly three fixed blocks in the correct order'
        return 1
    }

    IFS= read -r -d '' output_content < "$workspace/output" || true
    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        expected_path="${PLATFORM_PATHS[$block_index]}"
        if (( block_index > 1 )); then
            [[ "${output_content[1,1]}" == $'\n' ]] || {
                fail "missing separator before block: $expected_path"
                return 1
            }
            output_content="${output_content[2,-1]}"
        fi
        begin_marker="# ===== BEGIN $expected_path ====="$'\n'
        [[ "$output_content" == "$begin_marker"* ]] || {
            fail "expected block: $expected_path"
            return 1
        }
        output_content="${output_content[$(( ${#begin_marker} + 1 )),-1]}"
        end_marker="# ===== END $expected_path ====="$'\n'
        [[ "$output_content" == *"$end_marker"* ]] || {
            fail "missing END marker for: $expected_path"
            return 1
        }
        block_content="${output_content%%"$end_marker"*}"
        output_content="${output_content#*"$end_marker"}"
        print -rn -- "$block_content" > "$workspace/$block_index" || return 1
        if ! command zsh -f -n "$workspace/$block_index" >/dev/null 2>&1; then
            fail "invalid Zsh syntax in block: $expected_path"
            return 1
        fi
    done
    [[ "$output_content" == $'\n' ]] || {
        fail 'unmanaged content outside fixed blocks'
        return 1
    }

    CHANGED_PATHS=()
    for (( block_index = 1; block_index <= ${#PLATFORM_PATHS}; block_index++ )); do
        expected_path="${PLATFORM_PATHS[$block_index]}"
        source_file="$CONFIG_ROOT/$expected_path"
        command cmp -s "$workspace/$block_index" "$source_file"
        cmp_status=$?
        (( cmp_status == 0 )) && continue
        (( cmp_status == 1 )) || {
            fail "cannot compare source block: $expected_path"
            return 1
        }
        CHANGED_PATHS+=("$expected_path")
        print -r -- "different: $expected_path"
    done
    print -r -- "check passed; changed=${#CHANGED_PATHS}"
}

# Check syntax, boundaries, and differences without changing repository or status files.
check() {
    local CHECK_ONLY=1 platform workspace
    local -a CHANGED_PATHS
    platform="$(resolve_platform "${1:-auto}")" || return 1
    [[ ! -e "$TRANSACTION_DIR" ]] || {
        fail 'pending sync transaction; run render or sync to recover it first'
        return 1
    }
    workspace="$(command mktemp -d "${TMPDIR:-/tmp}/zshrc-weave.XXXXXX")" || return 1
    {
        check_blocks "$platform" "$workspace"
    } always {
        command rm -rf "$workspace"
    }
}

# Recover interrupted writes, check a snapshot, and write changed blocks transactionally.
sync_locked() {
    local platform="$1" workspace source_path
    local -a CHANGED_PATHS
    recover_transaction_locked || return 1
    workspace="$(command mktemp -d "${TMPDIR:-/tmp}/zshrc-weave.XXXXXX")" || return 1
    {
        check_blocks "$platform" "$workspace" || return 1
        if (( ${#CHANGED_PATHS} )); then
            stage_transaction_locked "$workspace" "$platform" || return 1
            recover_transaction_locked || return 1
        fi
        for source_path in "${CHANGED_PATHS[@]}"; do
            print -r -- "updated=$source_path"
        done
        write_status idle "$platform" "sync changed=${#CHANGED_PATHS}" || return 1
        print -r -- "sync changed=${#CHANGED_PATHS}"
    } always {
        command rm -rf "$workspace"
    }
}

# Serialize write-back and recovery through the existing fixed advisory lock.
sync() {
    local platform lock_fd result=0
    platform="$(resolve_platform "${1:-auto}")" || return 1
    acquire_sync_lock lock_fd || return 1
    cleanup_stale_transactions_locked || result=$?
    if (( result == 0 )); then
        sync_locked "$platform" || result=$?
    fi
    release_sync_lock "$lock_fd"
    return "$result"
}

case "${1:-}" in
    render) render "${2:-auto}" ;;
    check) check "${2:-auto}" ;;
    sync) sync "${2:-auto}" ;;
    *) usage; exit 64 ;;
esac
