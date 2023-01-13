#!/bin/bash
#
# MIT License
# Copyright (c) 2022 REFLEX CES
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Author: Dan Negvesky <dnegvesky@reflexces.com>
# Contributors:
#
# Description:
# GSRD configuration script used to configure and launch build tasks for supported
# REFLEX CES boards.
#
# Release info:
#
# 2022.06
#   - initial release for GSRD 2022.06 supporting Achilles SOMs

#################################################
# Global variable initialization
#################################################

OS_IS_WINDOWS=$(uname -a | grep -ic Microsoft)
LATEST_BRANCH=kirkstone

# latest tested version of Quartus Prime Pro
# user is given option to choose different version, but results are not guaranteed
QTS_VER=22.1

BUILD_GHRD=0
BUILD_YOCTO=0
PROGRAM_MMC=0
USER_QTS_VER=0

#################################################
# Functions
#################################################

warn_empty_selection() {
    whiptail \
        --title "/!\ WARNING /!\\" \
        --msgbox "Empty selection not allowed.  Please make a selection." 8 78
}

warn_unsupported_quartus() {
    whiptail \
        --title "/!\ WARNING /!\\" \
        --msgbox "You are specifying an untested version of Quartus.  You may encounter build errors.  Support will not be provided." 10 78
}

script_intro() {
    if [ -f script_intro.txt ]; then
        rm script_intro.txt
    fi

    cat > script_intro.txt <<EOF
This is the REFLEX CES Golden System Reference Design (GSRD) configuration
script, used to configure and launch build tasks for supported REFLEX CES
boards.  

Menu selections and navigation:
 - Use Up/Down arrow keys to make selections.
 - Use the Space Bar to enable/disable a selection.
 - Use the Tab key to move down to the <Ok>, <Next>, <Back> buttons.
 - Use the Enter key to execute the button function.
 - Press the Esc key at any time to exit the script.

Press Enter to continue.
EOF

    whiptail \
        --title "REFLEX CES GSRD Build Script" \
        --textbox script_intro.txt 20 80

    if [ -f script_intro.txt ]; then
        rm script_intro.txt
    fi

    get_board_name
}

get_board_name() {
    BOARD_SEL=$(whiptail \
        --title "Select Board" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose your target board." 15 60 4 \
        "Achilles v2 Indus SOM" "" OFF \
        "Achilles v2 Lite SOM" "" OFF \
        "Achilles v2 Turbo SOM" "" OFF 3>&1 1>&2 2>&3 \
    )
    exit_status=$?
    if [ $exit_status -eq 1 ]; then  # <Back> button was pressed
        script_intro
    elif [ $exit_status -eq 0 ] && [ "$BOARD_SEL" = "" ]; then
        warn_empty_selection
        get_board_name
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        :
    else
        exit
    fi

    case $BOARD_SEL in
        "Achilles v2 Indus SOM")
            INFO_BOARD="Achilles v2 Indus SOM"
            BOARD=achilles-v2-indus
            SOM_VER=indus
        ;;
        "Achilles v2 Lite SOM")
            INFO_BOARD="Achilles v2 Lite SOM"
            BOARD=achilles-v2-lite
            SOM_VER=lite
        ;;
        "Achilles v2 Turbo SOM")
            INFO_BOARD="Achilles v2 Turbo SOM"
            BOARD=achilles-v2-turbo
            SOM_VER=turbo
        ;;
        *)
            exit 1
        ;;
    esac

    get_gsrd_build_tasks
}

get_gsrd_build_tasks() {
    TASK_SEL=$(whiptail \
        --title "GSRD Build Tasks" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --checklist "\nChoose the GSRD build task(s) you will run.  \nTasks are run in the order shown." 15 78 4 \
        "GHRD" "Build Quartus GHRD FPGA Reference Design" OFF \
        "YOCTO" "Build Yocto software image" OFF \
        "PROGRAM" "Program board eMMC" OFF 3>&1 1>&2 2>&3 \
    )

    exit_status=$?
    if [ $exit_status -eq 1 ]; then  # <Back> button was pressed
        get_board_name
    elif [ $exit_status -eq 0 ] && [ "$TASK_SEL" = "" ]; then
        warn_empty_selection
        get_gsrd_build_tasks
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        :
    else
        exit
    fi

    # Read $TASK_SEL array to determine which tasks to enable
    BUILD_GHRD=$(echo $TASK_SEL | grep -c GHRD)
    BUILD_YOCTO=$(echo $TASK_SEL | grep -c YOCTO)
    PROGRAM_MMC=$(echo $TASK_SEL | grep -c PROGRAM)
    
    # check if user is running script in Windows/WSL and disable incompatible build task
    if [ $OS_IS_WINDOWS -ne 0 ]; then
        if [ $BUILD_YOCTO -eq 1 ]; then
            BUILD_YOCTO=0
            whiptail \
                --title "/!\ WARNING /!\\" \
                --msgbox "The YOCTO build can only run in a native Linux enviroment or Linux Virtual Machine.  It cannot run under Windows WSL." 10 78
        fi
    fi

    if [ $BUILD_GHRD -eq 1 ]; then
        get_ghrd_type
    elif [ $BUILD_YOCTO -eq 1 ]; then 
        get_yocto_image
    else
        review_selections
    fi
}

get_ghrd_type() {
    GHRD_TYPE_SEL=$(whiptail \
        --title "GHRD Type" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose GHRD type to build." 15 70 4 \
        "Standard" "Standard reference design" OFF \
        "PR" "Reference design with Partial Reconfiguration" OFF 3>&1 1>&2 2>&3 \
    )

    exit_status=$?
    if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
        get_gsrd_build_tasks
    elif [ $exit_status -eq 0 ] && [ "$GHRD_TYPE_SEL" = "" ]; then
        warn_empty_selection
        get_ghrd_type
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        :
    else
        exit
    fi

    case $GHRD_TYPE_SEL in
        "Standard")
            INFO_GHRD_TYPE=Standard
            GHRD_TYPE=std
        ;;
        "PR")
            INFO_GHRD_TYPE=PR
            GHRD_TYPE=pr
        ;;
        *)
            exit 1
        ;;
    esac

    get_quartus_info
}

get_quartus_info() {
    QTS_VER_SEL=$(whiptail \
        --title "Quartus Version" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose Quartus Prime Pro version for GHRD build." 15 70 4 \
        "22.1" "Latest tested and supported version" ON \
        "21.3" "Minimal testing done" OFF \
        "Other" "Manually enter the Quartus version (in next menu)." OFF 3>&1 1>&2 2>&3 \
    )

    exit_status=$?
    if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
        get_ghrd_type
    elif [ $exit_status -eq 0 ] && [ "$GHRD_TYPE_SEL" = "" ]; then
        warn_empty_selection
        get_quartus_info
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        :
    else
        exit
    fi

    case $QTS_VER_SEL in
        "22.1")
            QTS_VER=22.1
        ;;
        "21.3")
            QTS_VER=21.3
            USER_QTS_VER=1
        ;;
        "Other")
            warn_unsupported_quartus
            QTS_VER=$(whiptail \
                --title "Specify Quartus Version" \
                --ok-button "Next" \
                --cancel-button "Back" \
                --inputbox "\nEnter the Quartus Prime Pro version to be used:" 10 60 3>&1 1>&2 2>&3 $QTS_VER \
            )

            USER_QTS_VER=1

            exit_status=$?
            if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
                get_quartus_info
            elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
                :
            else
                exit
            fi
        ;;
        *)
            exit 1
        ;;
    esac

    if [ $OS_IS_WINDOWS -ne 0 ]; then
        QTS_TOOL_PATH=/mnt/c/intelFPGA_pro/$QTS_VER/quartus/bin64
    else
        QTS_TOOL_PATH=$HOME/intelFPGA_pro/$QTS_VER/quartus/bin
    fi

    # check for Quartus tools in the expected location
    while [ ! -d $QTS_TOOL_PATH ]
    do
        QTS_TOOL_PATH=$(whiptail \
            --title "Quartus Tool Path" \
            --ok-button "Next" \
            --cancel-button "Back" \
            --inputbox "\nQuartus tools were not found in default installation path $QTS_TOOL_PATH.  Please enter the full path to your Quartus installation \"bin\" directory:" 12 60 3>&1 1>&2 2>&3 $QTS_TOOL_PATH \
        )

        USER_QTS_TOOL_PATH=1

        exit_status=$?
        if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
            get_quartus_info
        elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
            :
        else
            exit
        fi
    done

    if [ $BUILD_YOCTO -eq 1 ]; then 
        get_yocto_image
    else
        review_selections
    fi
}

get_yocto_image() {
    YOCTO_IMG_SEL=$(whiptail \
        --title "Yocto Image" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose Yocto image to build." 15 90 4 \
        "CONSOLE" "Builds full image with U-Boot, Linux Kernel, and Poky root filesystem" ON \
        "U-BOOT" "Builds U-Boot binaries" OFF \
        "KERNEL" "Builds Linux kernel binaries" OFF 3>&1 1>&2 2>&3 \
    )

    exit_status=$?
    if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
        get_gsrd_build_tasks
    elif [ $exit_status -eq 0 ] && [ "$YOCTO_IMG_SEL" = "" ]; then
        warn_empty_selection
        get_yocto_image
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        :
    else
        exit
    fi

    case $YOCTO_IMG_SEL in
        "CONSOLE")
            INFO_YOCTO_IMG="Poky console image"
            YOCTO_IMG=console
        ;;
        "U-BOOT")
            INFO_YOCTO_IMG="U-Boot"
            YOCTO_IMG=virtual/bootloader
        ;;
        "KERNEL")
            INFO_YOCTO_IMG="Linux kernel"
            YOCTO_IMG=virtual/kernel
        ;;
        *)
            exit 1
        ;;
    esac

    get_branch
}

get_branch() {
    BRANCH_SEL=$(whiptail \
        --title "Yocto/Poky Branch" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose Yocto/Poky branch." 15 90 4 \
        "LATEST BRANCH" "Build Using latest available branch, currently $LATEST_BRANCH" ON \
        "HONISTER" "Build using honister branch" OFF \
        "GATESGARTH" "Build using gatesgarth branch" OFF 3>&1 1>&2 2>&3 \
    )

    exit_status=$?
    if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
        get_yocto_image
    elif [ $exit_status -eq 0 ] && [ "$BRANCH_SEL" = "" ]; then
        warn_empty_selection
        get_branch
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        :
    else
        exit
    fi

    case $BRANCH_SEL in
        "LATEST BRANCH")
            YOCTO_BRANCH=$LATEST_BRANCH
            OVERRIDE_BRANCH=0
        ;;
        "HONISTER")
            YOCTO_BRANCH=honister
            OVERRIDE_BRANCH=1
        ;;
        "GATESGARTH")
            YOCTO_BRANCH=gatesgarth
            OVERRIDE_BRANCH=1
        ;;
        *)
            exit 1
        ;;
    esac

    review_selections
}

review_selections() {
    # build.config might be left over from previously canceled script run
    if [ -f build.config ]; then
        rm build.config
    fi

    echo "Target Board = $INFO_BOARD" > build.config
    echo "Build Tasks = $TASK_SEL" >> build.config
    echo "" >> build.config

    if [ $BUILD_GHRD -eq 1 ]; then
        echo "GHRD Options:" >> build.config
        echo "   GHRD type = $INFO_GHRD_TYPE" >> build.config
        echo "   Quartus Prime Pro version = $QTS_VER" >> build.config
        echo "   Quartus tool path = $QTS_TOOL_PATH" >> build.config
        echo "" >> build.config
    fi
    
    if [ $BUILD_YOCTO -eq 1 ]; then
        echo "YOCTO Options:" >> build.config    
        echo "   Yocto Image = $INFO_YOCTO_IMG" >> build.config
        echo "   Yocto/Poky Branch = $YOCTO_BRANCH" >> build.config
        echo "" >> build.config
    fi
    
    if [ $PROGRAM_MMC -eq 1 ]; then
        echo "PROGRAM Options:" >> build.config
        echo "   Program eMMC" >> build.config
        echo "" >> build.config
    fi
    
    echo "Choose <Ok> to accept or make changes." >> build.config

    whiptail \
        --title "Confirm Selections" \
        --textbox build.config 30 78

    if [ -f build.config ]; then
        rm build.config
    fi

    whiptail \
        --title "Confirm Selections" \
        --yes-button "Start" \
        --no-button "Back" \
        --yesno "Choose <Start> to launch build tasks.  Choose <Back> to make changes." 10 38

    exit_status=$?
    if [ $exit_status -eq 1 ]; then  # <Back> button was pressed
        get_board_name
    elif [ $exit_status -eq 0 ]; then  # <Start> button was pressed
        :
    else
        exit
    fi

}

#################################################
# Main
#################################################

script_intro

# to export variables to enviroment, you must run this script with "source" or "."
# e.g. "source reflex-gsrd-build.sh" or ". reflex-gsrd-build.sh'
# use this to determine where to get FPGA .rbf configuration files
# if BUILD_GHRD is enabled, export this variable so the .rbf files generated from the GHRD
# build are used instead of the precompiled .rbf files

# the 'if' statment below must be updated with each new Yocto branch released after kirkstone
# the BB_ENV_EXTRAWHITE variable name changed at kirkstone branch; see here for more info:
# https://docs.yoctoproject.org/migration-guides/migration-4.0.html?highlight=bb_env_extrawhite

# TODO: This feature not yet tested
#if [ "$YOCTO_BRANCH" = "kirkstone" ]; then
#    export BB_ENV_PASSTHROUGH_ADDITIONS=BUILD_GHRD
#else
#    export BB_ENV_EXTRAWHITE="$BB_ENV_EXTRAWHITE BUILD_GHRD"
#fi

# start enabled build tasks

if [ $BUILD_GHRD -eq 1 ]; then
    if [ ! -f achilles-ghrd-build.sh ]; then
        wget https://raw.githubusercontent.com/reflexces/build-scripts/master/achilles-ghrd-build.sh
        chmod +x achilles-ghrd-build.sh
    fi

    if [[ $USER_QTS_VER -eq 1 || $USER_QTS_TOOL_PATH -eq 1 ]]; then
        ./achilles-ghrd-build.sh -s $SOM_VER -g $GHRD_TYPE -q $QTS_VER -t $QTS_TOOL_PATH
    else
        ./achilles-ghrd-build.sh -s $SOM_VER -g $GHRD_TYPE
    fi
fi

if [ $BUILD_YOCTO -eq 1 ]; then 
    if [ ! -f reflex-yocto-build ]; then
        wget https://raw.githubusercontent.com/reflexces/build-scripts/master/reflex-yocto-build
        chmod +x reflex-yocto-build
    fi

    if [ $OVERRIDE_BRANCH -eq 1 ]; then
        ./reflex-yocto-build -S -b $BOARD -i $YOCTO_IMG -o $YOCTO_BRANCH
    else
        ./reflex-yocto-build -S -b $BOARD -i $YOCTO_IMG
    fi
fi

if [ $PROGRAM_MMC -eq 1 ]; then
    if [ ! -f program-emmc.sh ]; then
        wget https://raw.githubusercontent.com/reflexces/build-scripts/master/program-emmc.sh
        chmod +x program-emmc.sh
    fi

    if [[ $BUILD_GHRD -eq 1 && $BUILD_YOCTO -eq 1 ]]; then
        if [ $OVERRIDE_BRANCH -eq 1 ]; then
            ./program-emmc.sh -S -q $QTS_VER -t $QTS_TOOL_PATH -b $BOARD -i $YOCTO_IMG -o $YOCTO_BRANCH
        else
            ./program-emmc.sh -S -q $QTS_VER -t $QTS_TOOL_PATH -b $BOARD -i $YOCTO_IMG
        fi
    elif [ $BUILD_GHRD -eq 1 ]; then
        ./program-emmc.sh -S -q $QTS_VER -t $QTS_TOOL_PATH
    elif [ $BUILD_YOCTO -eq 1 ]; then
        if [ $OVERRIDE_BRANCH -eq 1 ]; then
            ./program-emmc.sh -S -b $BOARD -i $YOCTO_IMG -o $YOCTO_BRANCH
        else
            ./program-emmc.sh -S -b $BOARD -i $YOCTO_IMG
        fi
    else
        ./program-emmc.sh -S -b $BOARD
    fi
fi
