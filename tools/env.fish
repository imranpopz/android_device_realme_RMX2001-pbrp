#!/bin/fish
set -g --unpath LD_LIB_PATH $PWD/recovery/root/system/lib64 $PWD/recovery/root/vendor/lib64 $PWD/recovery/root/vendor/lib64/hw

function ldcheck
    command ldcheck -p (string join ':' $LD_LIB_PATH) $argv
end
