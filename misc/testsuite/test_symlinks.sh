#! /usr/bin/env bash
## vim:set ts=4 sw=4 et:
set -e; set -o pipefail
argv0=$0; argv0abs=$(readlink -fn "$argv0"); argv0dir=$(dirname "$argv0abs")

# IMPORTANT NOTE: do NOT run as user root!!
# IMPORTANT NOTE: this script only works on Unix!!
umask 0022

id || true
if [[ $UID == 0 || $EUID == 0 ]]; then
    echo "ERROR: do not run as root: UID=$UID EUID=$EUID"
    exit 91
fi

# test behaviour with symlinks; requires:
#   $upx_exe                (required, but with convenience fallback "./upx")
# optional settings:
#   $upx_exe_runner         (e.g. "qemu-x86_64 -cpu Westmere" or "valgrind")

#***********************************************************************
# init & checks
#***********************************************************************

# upx_exe
[[ -z $upx_exe && -f ./upx && -x ./upx ]] && upx_exe=./upx # convenience fallback
if [[ -z $upx_exe ]]; then echo "UPX-ERROR: please set \$upx_exe"; exit 1; fi
if [[ ! -f $upx_exe ]]; then echo "UPX-ERROR: file '$upx_exe' does not exist"; exit 1; fi
upx_exe=$(readlink -fn "$upx_exe") # make absolute
[[ -f $upx_exe ]] || exit 1
upx_run=()
if [[ -n $upx_exe_runner ]]; then
    # usage examples:
    #   export upx_exe_runner="qemu-x86_64 -cpu Westmere"
    #   export upx_exe_runner="valgrind --leak-check=no --error-exitcode=1 --quiet"
    #   export upx_exe_runner="wine"
    IFS=' ' read -r -a upx_run <<< "$upx_exe_runner" # split at spaces into array
fi
upx_run+=( "$upx_exe" )
echo "upx_run='${upx_run[*]}'"

# upx_run check, part1
if ! "${upx_run[@]}" --version-short >/dev/null; then echo "UPX-ERROR: FATAL: upx --version-short FAILED"; exit 1; fi
if ! "${upx_run[@]}" -L >/dev/null 2>&1; then echo "UPX-ERROR: FATAL: upx -L FAILED"; exit 1; fi
if ! "${upx_run[@]}" --help >/dev/null;  then echo "UPX-ERROR: FATAL: upx --help FAILED"; exit 1; fi

#***********************************************************************
#
#***********************************************************************

failed() {
    ####exit $1
    # log error and keep going
    exit_code=1
    local a="$(basename "$(dirname "$PWD")")"
    local b="$(basename "$PWD")"
    let num_errors+=1 || true
    all_errors="${all_errors} $a/$b/$1"
    echo "    FAILED $b/$1"
}

assert_file() {
    local f
    for f in "$@"; do
        [[ ! -L "$f" && -f "$f" ]] && continue
        echo "failed '$f': not a regular file"
        failed 21
    done
}

assert_symlink_to_file() {
    local f
    for f in "$@"; do
        [[ -L "$f" && -f "$f" ]] && continue
        echo "failed '$f': not a symlink to file"
        failed 22
    done
}

assert_symlink_to_dir() {
    local f
    for f in "$@"; do
        [[ -L "$f" && -d "$f" ]] && continue
        echo "failed '$f': not a symlink to dir"
        failed 23
    done
}

assert_symlink_dangling() {
    local f
    for f in "$@"; do
        [[ -L "$f" && ! -e "$f" ]] && continue
        echo "failed '$f': not a dangling symlink"
        failed 24
    done
}

create_files() {
    # clean
    for d in z_dir_1 z_dir_2 z_dir_3 z_dir_4; do
        if [[ -d $d ]]; then
            chmod -R +w "./$d"
            rm -rf "./$d"
        fi
    done

    mkdir z_dir_1
    cd z_dir_1
    : > z_file
    ln -s z_file z_symlink_file
    : > z_file_link_1
    ln z_file_link_1 z_file_link_2
    ln -s z_file_link_1 z_symlink_file_link
    mkdir z_dir
    ln -s z_dir z_symlink_dir
    ln -s z_file_missing z_symlink_dangling
    assert_file             z_file*
    assert_symlink_to_file  z_symlink_file
    assert_symlink_to_dir   z_symlink_dir
    assert_symlink_dangling z_symlink_dangling
    cd ..

    # write-protect z_dir_2/z_file*
    cp -ai z_dir_1 z_dir_2
    chmod a-w z_dir_2/z_file*

    # write-protect z_dir_3 itself
    cp -ai z_dir_1 z_dir_3
    chmod a-w z_dir_3

    # write-protect everything in z_dir_4
    cp -ai z_dir_1 z_dir_4
    chmod -R a-w z_dir_4
}

#***********************************************************************
#
#***********************************************************************

export UPX="--prefer-ucl --no-color --no-progress"
export UPX_DEBUG_DISABLE_GITREV_WARNING=1
export UPX_DEBUG_DOCTEST_VERBOSE=0
export NO_COLOR=1

#set -x # debug
exit_code=0
num_errors=0
all_errors=

testsuite_header() {
    local x='==========='; x="$x$x$x$x$x$x$x"
    echo -e "\n${x}\n${1}\n${x}\n"
}

enter_dir() {
    cd "$1" || exit 1
    echo "===== $(basename "$PWD")"
}
leave_dir() {
    echo "===== $(basename "$PWD") files"
    ls -lA
    cd ..
}

# create a tmpdir in current directory
tmpdir="$(mktemp -d tmp-upx-test-XXXXXX)"
cd "./$tmpdir" || exit 1

test_file="$(readlink -fn /bin/ls)"

testsuite_header "default"
flags="-qq -1 --no-filter"
mkdir default
cd default
create_files
enter_dir z_dir_1
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          || failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              && failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       && failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      && failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link && failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
enter_dir z_dir_2
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          || failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              && failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       && failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      && failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link && failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
enter_dir z_dir_3
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          && failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              && failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       && failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      && failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link && failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
enter_dir z_dir_4
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          && failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              && failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       && failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      && failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link && failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
cd ..

testsuite_header "force-overwrite"
flags="-qq -1 --no-filter --force-overwrite"
mkdir force-overwrite
cd force-overwrite
create_files
enter_dir z_dir_1
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          || failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              || failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       || failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       || failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  || failed 18
assert_file z_symlink_file z_symlink_file_link
assert_file z_symlink_dir
assert_file z_symlink_dangling
leave_dir
enter_dir z_dir_2
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          || failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              || failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       || failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       || failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  || failed 18
assert_file z_symlink_file z_symlink_file_link
assert_file z_symlink_dir
assert_file z_symlink_dangling
leave_dir
enter_dir z_dir_3
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          && failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              || failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       || failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
enter_dir z_dir_4
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          && failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              || failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       || failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
cd ..

if [[ 1 == 1 ]]; then
testsuite_header "link"
flags="-qq -1 --no-filter --link"
mkdir link
cd link
create_files
enter_dir z_dir_1
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          || failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              || failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       || failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       || failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  || failed 18
assert_file z_symlink_file z_symlink_file_link
assert_file z_symlink_dir
assert_file z_symlink_dangling
leave_dir
enter_dir z_dir_2
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          || failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              && failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       && failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       || failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  || failed 18
assert_file z_symlink_file z_symlink_file_link
assert_file z_symlink_dir
assert_file z_symlink_dangling
leave_dir
enter_dir z_dir_3
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          && failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              || failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       || failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
enter_dir z_dir_4
"${upx_run[@]}" $flags                 z_symlink_file      && failed 10
"${upx_run[@]}" $flags "$test_file" -o z_file_new          && failed 11
"${upx_run[@]}" $flags "$test_file" -o z_dir               && failed 12
"${upx_run[@]}" $flags "$test_file" -o z_file              && failed 13
"${upx_run[@]}" $flags "$test_file" -o z_file_link_1       && failed 14
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file      || failed 15
"${upx_run[@]}" $flags "$test_file" -o z_symlink_file_link || failed 16
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dir       && failed 17
"${upx_run[@]}" $flags "$test_file" -o z_symlink_dangling  && failed 18
assert_symlink_to_file  z_symlink_file z_symlink_file_link
assert_symlink_to_dir   z_symlink_dir
assert_symlink_dangling z_symlink_dangling
leave_dir
cd ..
fi

# clean up
cd ..
chmod -R +w "./$tmpdir"
rm -rf "./$tmpdir"

if [[ $exit_code == 0 ]]; then
    echo "UPX testsuite passed. All done."
else
    echo "UPX-ERROR: UPX testsuite FAILED:${all_errors}"
    echo "UPX-ERROR: UPX testsuite FAILED with $num_errors error(s). See log file."
fi
exit $exit_code
