#!/bin/bash
# Plenty file deletion performance test
# Some test can show - No such file or directory - it's ok
# set -x

VARSBEFORE=`compgen -v`

DISK_PATH="/dev/sdb1"
MOUNT_PATH="/test"
DISK_SIZE=$(fdisk -l ${DISK_PATH} | head -n 1 | tr -s ' ' | cut -d ' ' -f 5)
INODES_NUM=10000000
NUM_FILES=1000
EXITCODE=0
VERBOSE=true
TEMPDIR=/tmp/empty
# DISCRETENESS=1000
declare -a ARRAYOFTEST
ARRAYOFTEST=( "time ls ${MOUNT_PATH} | tail -n 0 > /dev/null 2>&1" "time ls -f ${MOUNT_PATH} | tail -n 0 > /dev/null 2>&1" "time rm -rf ${MOUNT_PATH}/ > /dev/null 2>&1" "time rm -rf ${MOUNT_PATH}/* > /dev/null 2>&1" "time find ${MOUNT_PATH}/ -type f -exec rm -v {} \; > /dev/null 2>&1" "time find ${MOUNT_PATH}/ -type f -delete > /dev/null 2>&1" "time cd ${MOUNT_PATH}/ ; ls -f . | xargs -n 100 rm > /dev/null 2>&1" "mkdir -p ${TEMPDIR}; rsync -a --delete /tmp/empty/ /test/; rm -rf ${TEMPDIR}" )
VARSIGNORED="VARSIGNORED\|PIPESTATUS\|VARSBEFORE\|VARSAFTER\|ARRAYOFTEST"

VARSAFTER=`compgen -v`

# Compose list variable for check. Exclude environment vars and array
VARSUSED=`comm -13 <(echo $VARSBEFORE | tr ' ' '\n' | grep -v "${VARSIGNORED}" | sort) <(echo $VARSAFTER | tr ' ' '\n' | grep -v "${VARSIGNORED}" | sort)`

function FN_VARS_CHECK() {
    # Check list of variables for empty values
    # EXITCODE=1 if at least one of variable is empty in the check list 
    # Print list of checked variables
    for i in $VARSUSED; do
        if [ -z `eval echo "\\${$i}"` ]; then
            echo -e "\e[31m\tERROR Parameter\e[33m ${i} \e[31mnot_defined = `eval echo "\\${$i}"`\e[0m" | cut -c 1-80
            EXITCODE=1
        else
            echo -e "\e[32m\tOK Parameter\e[36m ${i} \e[32mdefined = `eval echo "\\${$i}"`\e[0m" | cut -c 1-80
        fi
    done
}

function FN_ARRAY_CHECK() {
    # Check array for empty values
    # EXITCODE=1 if at least one of variable is empty in the check list 
    if [ ${#ARRAYOFTEST[*]} = 0 ]; then
        echo -e "\e[31m\tArray of test is empty\e[0m"
        EXITCODE=1
    else
        echo -e "\e[32m\tArray of test contains items\e[36m ${#ARRAYOFTEST[*]} \e[0m"
    fi
}

function FN_DECORATE {
    # Print "-" character 40 times
    echo -e "\n"
    for i in {1..40}; do
        echo -n "-"
    done
    echo -e "\n"
}

function FN_CREATE_FILES {
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tCreating\e[36m ${NUM_FILES} \e[32mfiles in\e[36m ${MOUNT_PATH}\e[0m"
        for (( i=1; i <= ${NUM_FILES}; i++ )); do
            touch ${MOUNT_PATH}/$i.file
            if [[ $((i % 1000)) = 0 ]]; then
                progress=$(echo "scale=3; ${i}/${NUM_FILES}*100" | bc)
                echo -ne "\e[?25l\r${progress}% complete (files $i of ${NUM_FILES})"
                # echo -ne "\e[?25l\e[s\e[2K${progress}% complete (files $i of ${NUM_FILES})\e[u"
                # echo -ne "\e[?25l\e[s\e[2K$i of ${NUM_FILES}\e[u"
            fi
        done
        echo -e "\n\e[36m\t${NUM_FILES} \e[32mfiles have been created\e[0m"
        df -i ${MOUNT_PATH}
    else
        for (( i=1; i <= ${NUM_FILES}; i++ )); do
            touch ${MOUNT_PATH}/$i.file
        done
    fi
    echo -e "\e[?25h"
    sh -c 'sync && echo 2 > /proc/sys/vm/drop_caches'
}

function FN_MOUNT_DISK {
    if (cat /proc/mounts | grep ${DISK_PATH}); then
        if [ ${VERBOSE} = true ]; then
            echo -e "\e[31m\tDevice \e[36m ${DISK_PATH} \e[31m already mounted\e[0m"
            echo -e "\e[32m\tUn mounting a\e[36m ${DISK_PATH} \e[0m"
        fi
        umount ${DISK_PATH}
    fi
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tMounting disk\e[36m ${DISK_PATH} \e[32mto\e[36m ${MOUNT_PATH}\e[0m"
    fi
    mount ${DISK_PATH} ${MOUNT_PATH}
    if [ ${VERBOSE} = true ]; then
        df -i ${MOUNT_PATH}
    fi
}

function FN_CREATE_FS_EXT4 {
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tCreating filesystem\e[36m ext4 \e[32mwith\e[36m ${INODES_NUM} \e[32minodes\e[0m"
        mkfs -t ext4 -N ${INODES_NUM} ${DISK_PATH}
        echo -e "\e[32m\tFilesystem has been created\e[0m"
    else
        mkfs -t ext4 -N ${INODES_NUM} ${DISK_PATH} > /dev/null 2>&1
    fi
}

function FN_WIPE_DISK {
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tWipe\e[36m ${DISK_PATH} \e[32mwith zeros... \e[0m"
        dd if=/dev/zero of=${DISK_PATH} bs=$((1024*1024)) count=$((${DISK_SIZE}/$((1024*1024)))) status=progress
        echo -e "\e[32m\tWiping complete\e[0m"
    else
        dd if=/dev/zero of=${DISK_PATH} bs=$((1024*1024)) count=$((${DISK_SIZE}/$((1024*1024)))) > /dev/null 2>&1
    fi
}

function FN_MKDIR {
    if [ -d ${MOUNT_PATH}/ ]; then
        if (cat /proc/mounts | grep ${DISK_PATH}); then
            if [ ${VERBOSE} = true ]; then
                echo -e "\e[31m\tDevice \e[36m ${DISK_PATH} \e[31m already mounted\e[0m"
                echo -e "\e[32m\tUn mounting a\e[36m ${DISK_PATH} \e[0m"
            fi
            umount ${DISK_PATH}
        fi
        if [ ${VERBOSE} = true ]; then
            echo -e "\e[32m\tDeleting directory\e[36m $MOUNT_PATH \e[0m"
        fi
        rm -rf $MOUNT_PATH/
    fi
    if [ ${VERBOSE} = true ]; then
        echo -e "\e[32m\tCreating directory\e[36m ${MOUNT_PATH}\e[0m"
    fi
    mkdir -p ${MOUNT_PATH}
    if [ ${VERBOSE} = true ]; then
        ls -la /test/ | head -n 5
    fi
}

function FN_PREPS_FN {
    # Prepare directory
    FN_MKDIR
    if [ ${VERBOSE} = true ]; then FN_DECORATE; fi

    # Wipe disk
    FN_WIPE_DISK
    if [ ${VERBOSE} = true ]; then FN_DECORATE; fi

    # Prepare filesystem for test
    FN_CREATE_FS_EXT4
    if [ ${VERBOSE} = true ]; then FN_DECORATE; fi

    # Mount disk
    FN_MOUNT_DISK
    if [ ${VERBOSE} = true ]; then FN_DECORATE; fi

    # Create many files
    FN_CREATE_FILES
    if [ ${VERBOSE} = true ]; then FN_DECORATE; fi
}

echo -e "\n\n\n\tVariable check:"
FN_DECORATE
FN_VARS_CHECK | column -t
FN_VARS_CHECK &> /dev/null
FN_ARRAY_CHECK

# If FN_VARS_CHECK generate $EXITCODE = 1, exit 1
if [ $EXITCODE = 1 ]; then
    echo -e "\nError\nVariable is empty\n"
    exit 1
fi

# ----------------------------------------
# Run tests
for array in ${!ARRAYOFTEST[@]}; do
    if [ ${VERBOSE} = true ]; then
        FN_DECORATE
        FN_PREPS_FN
    else
        FN_PREPS_FN > /dev/null 2>&1
    fi
    sh -c 'sync && echo 2 > /proc/sys/vm/drop_caches'
    echo -e "\e[30;42m\n\t Test = ${array} of ${#ARRAYOFTEST[*]} \e[0m"
    echo -e "\e[33m\tExecution time for command:\e[36m ${ARRAYOFTEST[${array}]} \e[0m"
    
    if [ ${VERBOSE} = true ]; then
        time "${ARRAYOFTEST[${array}]}"
        df -i ${MOUNT_PATH}
    else
        time "#${ARRAYOFTEST[${array}]}" > /dev/null 2>&1
    fi
done

FN_DECORATE
echo -e "\e[31m\n\tAll tests complete\e[0m"

exit 0
