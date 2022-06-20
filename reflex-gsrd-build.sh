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

OS_IS_WINDOWS=$(uname -a | grep -c Microsoft)
LATEST_BRANCH=kirkstone

# latest tested version of Quartus Prime Pro is v22.1
# you may override the version here but results are not guaranteed
# TODO: add version option to function below
QTS_VER=22.1

if [ $OS_IS_WINDOWS -ne 0 ]; then
    QTS_TOOL_PATH=/mnt/c/intelFPGA_pro/$QTS_VER/quartus/bin64
else
    QTS_TOOL_PATH=$HOME/intelFPGA_pro/$QTS_VER/quartus/bin
fi

BUILD_GHRD=0
BUILD_YOCTO=0
PROGRAM_MMC=0

#################################################
# Functions
#################################################

warn_empty_selection() {
    whiptail \
        --title "/!\ WARNING /!\\" \
        --msgbox "Empty selection not allowed.  Please make a selection." 8 78
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

    get_board_name

    if [ -f script_intro.txt ]; then
        rm script_intro.txt
    fi
}

get_board_name() {
    BOARD_SEL=$(whiptail \
        --title "Select Board" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose your target board." 15 60 4 \
        "Achilles Indus SOM" "" OFF \
        "Achilles Lite SOM" "" OFF \
        "Achilles Turbo SOM" "" OFF 3>&1 1>&2 2>&3 \
    )
    exit_status=$?
    if [ $exit_status -eq 0 ] && [ "$BOARD_SEL" = "" ]; then
            warn_empty_selection
            get_board_name
    elif [ $exit_status -eq 1 ]; then  # <Back> button was pressed
        script_intro
    fi

    case $BOARD_SEL in
        "Achilles Indus SOM")
            INFO_BOARD="Achilles Indus SOM"
            BOARD=achilles-indus
            SOM_VER=indus
        ;;
        "Achilles Lite SOM")
            INFO_BOARD="Achilles Lite SOM"
            BOARD=achilles-lite
            SOM_VER=lite
        ;;
        "Achilles Turbo SOM")
            INFO_BOARD="Achilles Turbo SOM"
            BOARD=achilles-turbo
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
    if [ $exit_status -eq 0 ] && [ "$TASK_SEL" = "" ]; then
        warn_empty_selection
        get_gsrd_build_tasks
    elif [ $exit_status -eq 1 ]; then
        get_board_name
    fi

    # Read $TASK_SEL array to determine which tasks to enable
    BUILD_GHRD=$(echo $TASK_SEL | grep -c GHRD)
    BUILD_YOCTO=$(echo $TASK_SEL | grep -c YOCTO)
    PROGRAM_MMC=$(echo $TASK_SEL | grep -c PROGRAM)
    
    # check if user is running script in Windows/WSL and disable incompatible build tasks
    if [ $OS_IS_WINDOWS -ne 0 ]; then
        if [ $BUILD_YOCTO -eq 1 ] || [ $PROGRAM_MMC -eq 1 ]; then
            BUILD_YOCTO=0
            PROGRAM_MMC=0
            whiptail \
                --title "/!\ WARNING /!\\" \
                --msgbox "The YOCTO and PROGRAM functions are only available to run in a native Linux enviroment or Linux Virtual Machine.  They cannot run under Windows WSL.  Only the GHRD task will run." 10 78
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
    if [ $exit_status -eq 0 ] && [ "$GHRD_TYPE_SEL" = "" ]; then
        warn_empty_selection
        get_ghrd_type
    elif [ $exit_status -eq 1 ]; then    # <Back> button was pressed
        get_gsrd_build_tasks
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
    
    # check for Quartus tools in the expected location
    if [ ! -d $QTS_TOOL_PATH ]; then
        QTS_TOOL_PATH=$(whiptail \
            --title "Create New User" \
            --inputbox "\nQuartus tools were not found in default installation path $QTS_TOOL_PATH.  Please enter the full path to your Quartus installation \"bin\" directory:" 10 60 3>&1 1>&2 2>&3 $QTS_TOOL_PATH \
        )
    fi

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
    if [ $exit_status -eq 0 ] && [ "$YOCTO_IMG_SEL" = "" ]; then
        warn_empty_selection
        get_yocto_image
    elif [ $exit_status -eq 1 ]; then    # <Back> button was pressed
        get_gsrd_build_tasks
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
    if [ $exit_status -eq 0 ] && [ "$BRANCH_SEL" = "" ]; then
        warn_empty_selection
        get_branch
    elif [ $exit_status -eq 1 ]; then    # <Back> button was pressed
        get_yocto_image
    fi

    case $BRANCH_SEL in
        "LATEST BRANCH")
            USE_BRANCH=$LATEST_BRANCH
        ;;
        "HONISTER")
            USE_BRANCH=honister
            OVERRIDE_BRANCH=1
        ;;
        "GATESGARTH")
            USE_BRANCH=gatesgarth
            OVERRIDE_BRANCH=1
        ;;
        *)
            exit 1
        ;;
    esac

    review_selections
}

review_selections() {
    if [ -f build.config ]; then
        rm build.config
    fi

    echo "Target Board = $INFO_BOARD" > build.config
    echo "Build Tasks = $TASK_SEL" >> build.config
    echo "" >> build.config

    if [ $BUILD_GHRD -eq 1 ]; then
        echo "GHRD Options:" >> build.config
        echo "   GHRD type = $INFO_GHRD_TYPE" >> build.config
        echo "   Quartus tool path = $QTS_TOOL_PATH" >> build.config
        echo "   Quartus Prime Pro version = $QTS_VER" >> build.config
        echo "" >> build.config
    fi
    
    if [ $BUILD_YOCTO -eq 1 ]; then
        echo "YOCTO Options:" >> build.config    
        echo "   Yocto Image = $INFO_YOCTO_IMG" >> build.config
        echo "   Yocto/Poky Branch = $USE_BRANCH" >> build.config
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
        
    whiptail \
        --title "Confirm Selections" \
        --yes-button "Start" \
        --no-button "Back" \
        --yesno "Choose <Start> to launch build tasks.  Choose <Back> to make changes." 10 38

    exit_status=$?
    if [ $exit_status -eq 1 ]; then  # <Back> button was pressed
        get_board_name
    fi

    if [ -f build.config ]; then
        rm build.config
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

export BUILD_GHRD=$BUILD_GHRD
# the 'if' statment below must be updated with each new Yocto branch released after kirkstone
# the BB_ENV_EXTRAWHITE variable name changed at kirkstone branch; see here for more info:
# https://docs.yoctoproject.org/migration-guides/migration-4.0.html?highlight=bb_env_extrawhite

# TODO: This feature not yet tested
#if [ "$USE_BRANCH" = "kirkstone" ]; then
#    export BB_ENV_PASSTHROUGH_ADDITIONS=BUILD_GHRD
#else
#    export BB_ENV_EXTRAWHITE="$BB_ENV_EXTRAWHITE BUILD_GHRD"
#fi

# start enabled build tasks

if [ $BUILD_GHRD -eq 1 ]; then
    if [ ! -f achilles-ghrd-build.sh ]; then
        wget https://raw.githubusercontent.com/reflexces/build-scripts/$USE_BRANCH/achilles-ghrd-build.sh
        ./achilles-ghrd-build.sh -s $SOM_VER -g $GHRD_TYPE
    fi
fi

if [ $BUILD_YOCTO -eq 1 ]; then 
    if [ ! -f reflex-yocto-build ]; then
        wget https://raw.githubusercontent.com/reflexces/build-scripts/$USE_BRANCH/reflex-yocto-build
        if [ $OVERRIDE_BRANCH -eq 1 ]; then
            ./reflex-yocto-build -b $BOARD -i $YOCTO_IMG -o $USE_BRANCH
        else
            ./reflex-yocto-build -b $BOARD -i $YOCTO_IMG
        fi
    fi
fi

if [ $PROGRAM_MMC -eq 1 ]; then
    if [ ! -f program-emmc.sh ]; then
        wget https://raw.githubusercontent.com/reflexces/build-scripts/$USE_BRANCH/program-emmc.sh
        ./program-emmc.sh -b $BOARD -p full
    fi
fi
