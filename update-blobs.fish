#!/bin/fish

# Process args
argparse 'v/verbose' -- $argv
set -q _flag_verbose
and set -g verbose_out /dev/stdout
or set -g verbose_out /dev/null

# Temporary dir that will be used to store pulled files later
set -g tmpdir_name tmpdir-(shuf -i 5000-9000 -n1)

# Directory to search
set -g search_dirs "recovery/root"

# Files to exclude, such as unified-script
set -g exclude_files "recovery/root/system/bin/resetprop" \
    "recovery/root/system/bin/unified-script.sh"

# Directory prefixes & config
set -g copy_directory $PWD
set -g copy_prefix "recovery/root"

# Functions
function update_progress
    echo -ne (set_color magenta)"$argv ($current_iter/$files_count)\r"(set_color normal)
end

function finish_progress
    echo (set_color magenta)"$argv ($current_iter/$files_count).. Complete!"(set_color normal)
end

## Begin operation
# Find files
set -g files (find $search_dirs -type f)
set -g files_count (count $files)
set -g current_iter 0

# Remove excluded files
set -g index 1
for file in $files
    update_progress Processing files
    for excluded_file in in $exclude_files
        if test "$excluded_file" = "$file"
            set -ge files[$index]
            set index (math $index - 1)
        end
    end
    set -g current_iter (math $current_iter + 1)
    set -g index (math $index + 1)
end
finish_progress Processing files

set_color brwhite
string repeat -n$COLUMNS '-'
set_color normal
echo "Total files: $files_count"
echo "Total files after excluding excluded files: $(count $files)"
set -g files_count (count $files)

if test "$verbose_out" = /dev/stdout
    echo
    echo "Files:"
    for file in $files
        echo " - $file"
    end
end

## Search and pull files from device
echo (set_color brblack)"Waiting for device..."(set_color normal)
adb wait-for-device

echo "Checking for root access"
set -g root_access false
if test (adb shell "whoami") = root
    set -g root_access true
    set -g adb_prefix ""
else if test (adb shell "which su") = "/system/bin/su"
    set -g root_access true
    set -g adb_prefix "su -c"
end

if test $root_access = false
    echo (set_color brred)"Error: cannot find root access in your device!"(set_color normal)
    exit 1
end

echo (set_color brblack)"Creating tmpdir $tmpdir_name"(set_color normal) >$verbose_out
mkdir -p $tmpdir_name

echo (set_color brblack)"Entering tmpdir $tmpdir_name"(set_color normal) >$verbose_out
cd $tmpdir_name


########################
## Find blobs

# echo (set_color brblack)"Creating and entering directory: system"(set_color normal) >$verbose_out
# mkdir system
set -g current_iter 0
for file in $files
    update_progress Finding blobs
    set -ga blobs_found (string replace -r '^/' '' (adb shell "$adb_prefix find /system -name '$(basename $file)'"))
    set -g current_iter (math $current_iter + 1)
end
finish_progress Finding blobs

# echo (set_color brblack)"Creating and entering directory: vendor"(set_color normal) >$verbose_out
# mkdir vendor
set -g current_iter 0
for file in $files
    update_progress Finding blobs
    set -ga blobs_found (string replace -r '^/' '' (adb shell "$adb_prefix find /vendor -name '$(basename $file)'"))
    set -g current_iter (math $current_iter + 1)
end
finish_progress Finding blobs

if test "$verbose_out" = /dev/stdout
    echo
    echo "Found:"
    for blob in $blobs_found
        echo " - $blob"
    end
end

########################
## Pull blobs

# We can't pull certain files if we have root access
# through su -c instead of adb root, so
# copy it to a temporary directory first
# and change the permission before
# pulling it.

mkdir -p system vendor
set -g files_count (count $blobs_found)
set -g current_iter 0
for blob in $blobs_found
    update_progress Pulling blobs
    set -l blob_pull

    if test "$adb_prefix" = "su -c"
        adb shell "su -c cp $blob /data/local/tmp"
        set blob_pull "/data/local/tmp/$(basename $blob)"
    else
        set blob_pull $blob
    end

    set -l dir (dirname $blob)
    mkdir -p $dir
    adb pull $blob_pull $dir >$verbose_out
    set -g current_iter (math $current_iter + 1)

    if test "$adb_prefix" = "su -c"
        adb shell "su -c rm -f /data/local/tmp/$(basename $blob)"
    end
end
finish_progress Pulling blobs

########################
## Copy files

set -g current_iter 0
for file in $blobs_found
    update_progress Copying files
    cp -f $file $copy_directory/$copy_prefix/(dirname $file)
    set -g current_iter (math $current_iter + 1)
end
finish_progress

echo "Cleanup"
cd $copy_directory
rm -rf $tmpdir_name
