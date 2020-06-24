#!/bin/bash

if [[ "${UID}" != 0 ]] ; then
  unshare -rm "${BASH_SOURCE[0]}" "${@}"
  exit $?
fi

usage() {
  cat <<EOF
${ANSI_BRIGHT}${ANSI_REVERSE}Usage:${ANSI_RESET}
${ANSI_BRIGHT}${BASH_SOURCE[0]}${ANSI_RESET} ${ANSI_FG_CYAN}[<options>]${ANSI_RESET} ${ANSI_BRIGHT}${ANSI_FG_GREEN}[<chroot dir>]${ANSI_RESET}

${ANSI_BRIGHT}${ANSI_REVERSE}Options:${ANSI_RESET}
  ${ANSI_FG_CYAN}-n      ${ANSI_RESET}Dry run, only print what would be done (non-verbose by default)
  ${ANSI_FG_CYAN}-v      ${ANSI_RESET}Verbose, print all commands that are/would be invoked
  ${ANSI_FG_CYAN}-w DIR  ${ANSI_RESET}Add DIR to the lsit of directories which need to be writable to the
          fake root
EOF
exit 0
}

function log() {
  _log "" "${@}"
}

function logn() {
  _log "-n" "${@}"
}

function _log() {
  local echoargs="${1}" level="${2}" colors ansi_col
  shift 2
  colors_v="ANSI_${level}"
  read -a colors <<<"${!colors_v}"
  for c in "${colors[@]}"; do
    col="ANSI_${c}"
    ansi_col+="${!col}"
  done
  echo ${echoargs} "${ansi_col}${*}${ANSI_RESET}"
}

bind_mount() {
  for src in "${@}" ; do
    dest="${CHROOT}${src}"
    is_writable=0
    for wrt in "${WRITABLES[@]}" ; do
      if [[ "${wrt}" == "${src}" || -d "${src}" && "${wrt#${src}/}" != "${wrt}" ]] ; then
        is_writable=1
      fi
    done
    if [[ "${is_writable}" -eq 1 ]] ; then
      if [[ -d "${src}" ]] ; then
        log INFO "${src} contains locations which should be writable"
        cmd mkdir "${CHROOT}${src}"
        bind_mount "${src}"/* || return 1
      else
        log INFO "${src} should be writable, copying"
        cmd cp "${src}" "${dest}" || return 1
      fi
      continue
    fi

    if [[ -d "${src}" ]] ; then
      cmd mkdir -p "${dest}" || return 1
      cmd chmod --reference="${src}" "${dest}" || return 1
      MOUNTED+=("${dest}")
      cmd mount --rbind "${src}" "${dest}" || return 1
    else
      cmd ln "${src}" "${dest}" || return 1
    fi
  done
}

cmd() {
  if [[ "${VERBOSE}" -eq 1 ]] ; then
    log DEBUG "${@}"
  fi
  if [[ "${DRY_RUN}" -eq 0 ]] ; then
    "${@}"
  else
    true
  fi
}

############################################################
ANSI_RESET=$'\x1b[0m'
ANSI_BRIGHT=$'\x1b[1m'
ANSI_DIM=$'\x1b[2m'
ANSI_UNDERSCORE=$'\x1b[4m'
ANSI_BLINK=$'\x1b[5m'
ANSI_REVERSE=$'\x1b[7m'
ANSI_HIDDEN=$'\x1b[8m'
 
ANSI_FG_BLACK=$'\x1b[30m'
ANSI_FG_RED=$'\x1b[31m'
ANSI_FG_GREEN=$'\x1b[32m'
ANSI_FG_YELLOW=$'\x1b[33m'
ANSI_FG_BLUE=$'\x1b[34m'
ANSI_FG_MAGENTA=$'\x1b[35m'
ANSI_FG_CYAN=$'\x1b[36m'
ANSI_FG_WHITE=$'\x1b[37m'
 
ANSI_BG_BLACK=$'\x1b[40m'
ANSI_BG_RED=$'\x1b[41m'
ANSI_BG_GREEN=$'\x1b[42m'
ANSI_BG_YELLOW=$'\x1b[43m'
ANSI_BG_BLUE=$'\x1b[44m'
ANSI_BG_MAGENTA=$'\x1b[45m'
ANSI_BG_CYAN=$'\x1b[46m'
ANSI_BG_WHITE=$'\x1b[47m'

ANSI_DEBUG="FG_BLUE"
ANSI_INFO="BRIGHT FG_WHITE"
ANSI_ERROR="BRIGHT FG_WHITE BG_RED"

VERBOSE=0
DRY_RUN=0
CHROOT=
WRITABLES=()

############################################################
while [[ $# -gt 0 ]] ; do
  case "${1}" in
    -n)
      DRY_RUN=1
      ;;
    -v)
      VERBOSE=1
      ;;
    -h)
      usage
      ;;
    -w)
      if [[ -d "${2}" ]] ; then
        # ensure trailing /
        WRITABLES+=("${2%/}/")
      else
        WRITABLES+=("${2}")
      fi
      shift
      ;;
    -*)
      log ERROR "Unknown option ${1}"
      usage
      ;;
    *)
      if [[ -n "${CHROOT}" ]] ; then
        log ERROR "Extra argument ${1}"
        usage
      fi
      CHROOT="${1%/}"
  esac
  shift
done

############################################################
if [[ -z "${CHROOT}" ]] ; then
  logn INFO "Assuming that current working directory is the chroot, is this correct? (y/n) "
  read -n 1 ans
  echo ""
  while [[ ! "${ans}" =~ [yYnN] ]] ; do
    logn INFO "Answer with y or n "
    read -n 1 ans
    echo ""
  done
  if [[ "${ans}" =~ [nN] ]] ; then
    exit 1
  fi
  CHROOT=.
fi

if test -n "$(shopt -s nullglob; echo "${CHROOT}"/*)" ; then
  log ERROR "chroot directory must be empty, aborting." >&2
  exit 1
fi

log DEBUG "Writables:" "${WRITABLES[@]}"
shopt -s dotglob
MOUNTED=()
cmd mkdir -p "${CHROOT}"
bind_mount /*
rc=$?
cmd chroot "${CHROOT}"
log INFO "Cleaning up"
for m in "${MOUNTED[@]}" ; do
  cmd umount --lazy "${m}"
  this_rc=$?
  if [[ "${rc}" -eq 0 ]] ; then
    rc="${this_rc}"
  fi
done
find "${CHROOT}" \( ! -type d -o -empty \) -delete
