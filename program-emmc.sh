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
#   - TODO: add whiptail gauges for wget downloads, FPGA programming,
#           and image copy to eMMC

#################################################
# Global variable initialization
#################################################

OS_IS_WINDOWS=$(uname -a | grep -ic Microsoft)

# latest tested version of Quartus Prime Pro
# version used is not critical since we are only using programmer function in this script
# any recent version (20.3 or newer) should work
QTS_VER=22.1

# when this script is launched stand-alone, this is set to 0
# when launched from the GSRD build script, this is set to 1
SOURCED_FROM_GSRD_SCRIPT=0

#LATEST_RELEASE_URL=https://github.com/reflexces/meta-achilles/releases/download/v2021.12
LATEST_RELEASE_URL=https://github.com/reflexces/meta-achilles/releases/download/v2022.06

PROG_FILES_URL=https://raw.githubusercontent.com/reflexces/build-scripts/master/prog-files

YOCTO_IMG=console
YOCTO_BRANCH=kirkstone

#################################################
# Functions
#################################################

warn_empty_selection() {
    whiptail \
        --title "/!\ WARNING /!\\" \
        --msgbox "Empty selection not allowed.  Please make a selection." 0 0
}

script_intro() {
    if [ -f script_intro.txt ]; then
        rm script_intro.txt
    fi

    cat > script_intro.txt <<EOF
This is the REFLEX CES MMC boot flash programming script, used
to program selected partitions or the full MMC boot flash on
supported REFLEX CES boards.  

Menu selections and navigation:
 - Use Up/Down arrow keys to make selections.
 - Use the Space Bar to enable/disable a selection.
 - Use the Tab key to move down to the <Ok>, <Next>, <Back> buttons.
 - Use the Enter key to execute the button function.
 - Press the Esc key at any time to exit the script.

Press Enter to continue.
EOF

    whiptail \
        --title "REFLEX CES MMC Programming Script" \
        --textbox script_intro.txt 20 80

    if [ -f script_intro.txt ]; then
        rm script_intro.txt
    fi

    if [ $SOURCED_FROM_GSRD_SCRIPT -eq 1 ]; then
        case $BOARD in
            "achilles-indus")
                BOARD_FAM=achilles
                INFO_BOARD="Achilles Indus SOM"
            ;;
            "achilles-lite")
                BOARD_FAM=achilles
                INFO_BOARD="Achilles Lite SOM"
            ;;
            "achilles-turbo")
                BOARD_FAM=achilles
                INFO_BOARD="Achilles Turbo SOM"
            ;;
#            "comxpress")
#                BOARD_FAM=comxpress
#            ;;
            *)
                exit 1
            ;;
        esac

        get_programming_task
    else
        get_board_name
    fi
}

achilles_pgm_steps() {
    if [ -f pgm_steps.txt ]; then
        rm pgm_steps.txt
    fi

    cat > pgm_steps.txt <<EOF
Before proceeding follow these steps below.  For detailed instructions, refer to
the Achilles SOM page (PROGRAM EMMC tab) on rocketboards.org:
https://rocketboards.org/foswiki/Documentation/REFLEXCESAchillesArria10SoCSOM

 1. A TFTP server must be setup with the parameters shown in the table on the
    rocketboards.org page above.
 2. Power off the board, remove SOM from Carrier, and set MSEL switch to "ON".
 3. Plug SOM back into Carrier and connect USB cable between this PC and the USB
    port labeled "BLASTER" on the Carrier.
 4. Connect an Ethernet cable between the RJ-45 ETH1 port on the SOM and the 
    network router where the TFTP server is also connected.
 5. Verify BSEL switches = "ON OFF ON".
 6. Open a terminal window, power on the board, and establish a connection with
    the board.  If U-Boot begins to load, it MUST be stopped at the U-Boot prompt.

Press Enter to continue when above steps are complete.

Pres Esc key to cancel.
EOF

    whiptail \
        --title "Prepare for Programming" \
        --textbox pgm_steps.txt 0 0

    if [ -f pgm_steps.txt ]; then
        rm pgm_steps.txt
    fi
}

ip_addr_info_msg() {
    if [ -f ip_info.txt ]; then
        rm ip_info.txt
    fi

    cat > ip_info.txt <<EOF
Go to the terminal window with the active connection to the target board and look
for the IP address in the following example text below (you may need to allow some
time for the SOM to complete the boot process).  You will find this just before
the Linux prompt:

   Sending select for ###.###.###.###...
   Lease of ###.###.###.### obtained, lease time 7200
   deleting routers

where ###.###.###.### is the IP address of the the target board.
  
Press Enter after you have identified the IP address.
EOF

    whiptail \
        --title "Identify Target Board IP Address" \
        --textbox ip_info.txt 0 0

    if [ -f ip_info.txt ]; then
        rm ip_info.txt
    fi
}

# adapted from https://github.com/pageauc/FileBrowser
file_browser()
{
# $1 = valid file name; use "*" to allow any file
# $2 = start folder

    script_dir=$(pwd)
    cd "$2"
    dir_list=$(ls -lhp  | awk -F ' ' ' { print $9 " " $5 } ')
    curdir=$(pwd)

    if [ "$curdir" == "/" ] ; then  # Check if root folder
        selection=$(whiptail \
            --title "Browse for $1 File" \
            --menu "Up/Down arrows to browse \nEnter to select file or folder \nTab to <Select>/<Cancel> buttons\n$curdir" 0 0 0 \
            --ok-button "Select" $dir_list \
            --cancel-button "Cancel" 3>&1 1>&2 2>&3
        )
    else   # Not root so show "../ BACK" selection in menu
        selection=$(whiptail \
            --title "Browse for $1 File" \
            --menu "Up/Down arrows to browse \nEnter to select file or folder \nTab to <Select>/<Cancel> buttons\n$curdir" 0 0 0 \
            --ok-button "Select" ../ BACK $dir_list \
            --cancel-button "Cancel" 3>&1 1>&2 2>&3
        )
    fi

    exit_status=$?
    if [ $exit_status -eq 1 ]; then  # <Cancel> button pressed
        program_mmc
    elif [ $exit_status -eq 0 ]; then
        if [ -d "$selection" ]; then  # Check if Directory Selected
            file_browser "$1" "$selection"
        elif [ -f "$selection" ]; then  # Check if File Selected
            if [[ $selection == $1 ]]; then   # Check if expected file was selected
                if (whiptail \
                    --title "Confirm Selection" --yesno "Path : $curdir\nFile: $selection" 0 0 \
                    --yes-button "Confirm" \
                    --no-button "Retry" \
                ); then
                    BROWSE_FILE_NAME="$selection"
                    BROWSE_FILE_PATH="$curdir"    # Return full file path and file name as selection variables
                    cd "$script_dir"  # upon successful exit, go back to dir where this script is running from
                else
                    file_browser "$1" "$curdir"
                fi
            else   # incorrect file
                whiptail \
                    --title "/!\ ERROR /!\\" \
                    --msgbox "You selected $selection\nSelected file must be $1" 0 0
                file_browser "$1" "$curdir"
            fi
        else
            # Could not detect a file or folder so try again
            whiptail \
                --title "/!\ ERROR /!\\" \
                --msgbox "Error Changing to Path $selection" 0 0
            file_browser "$1" "$curdir"
       fi
    fi
}

get_board_name() {
    BOARD_SEL=$(whiptail \
        --title "Select Target Board" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose the target board for programming." 0 0 0 \
        "Achilles Indus SOM" "" OFF \
        "Achilles Lite SOM" "" OFF \
        "Achilles Turbo SOM" "" OFF 3>&1 1>&2 2>&3 \
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
        "Achilles Indus SOM")
            INFO_BOARD="Achilles Indus SOM"
            BOARD=achilles-indus
            BOARD_FAM=achilles
        ;;
        "Achilles Lite SOM")
            INFO_BOARD="Achilles Lite SOM"
            BOARD=achilles-lite
            BOARD_FAM=achilles
        ;;
        "Achilles Turbo SOM")
            INFO_BOARD="Achilles Turbo SOM"
            BOARD=achilles-turbo
            BOARD_FAM=achilles
        ;;
#        "comxpress")
#            BOARD_FAM=comxpress
#        ;;
        *)
            exit 1
        ;;
    esac

    get_programming_task
}

#15 78 4
get_programming_task() {
    PGM_TASK_SEL=$(whiptail \
        --title "Select Programming Task" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nChoose the partition(s) to program." 0 0 0 \
        "FULL" "Program the full MMC device with Yocto generated WIC image" OFF \
        "UPDATE U-BOOT" "Program the required paritions with updated U-Boot binaries" OFF \
        "UPDATE KERNEL" "Program the required paritions with updated Linux kernel binaries" OFF \
        "UPDATE FPGA" "Program the required partitions with updated FPGA programming files" OFF \
        "P1" "add file(s) to FAT32 partition 1" OFF \
        "P3" "add file(s) to EXT Linux partition (root filesystem)" OFF 3>&1 1>&2 2>&3 \
    )

    exit_status=$?
    if [ $exit_status -eq 1 ]; then  # <Back> button was pressed
        get_board_name
    elif [ $exit_status -eq 0 ] && [ -z "$PGM_TASK_SEL" ]; then
        warn_empty_selection
        get_programming_task
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        #return 0
        program_mmc
    else
        exit
    fi
}

get_image_file_source() {
    # get the file list array passed from program_mmc
    src_file_array=("$@")
    IMAGE_SRC=$(whiptail \
        --title "Select Image/File Source" \
        --ok-button "Next" \
        --cancel-button "Back" \
        --radiolist "\nWhere is the image or file(s) coming from?" 0 0 0 \
        "PRECOMPILED" "Download latest released files from REFLEX CES repository" OFF \
        "BUILD" "Use generated image/files from recent build" OFF 3>&1 1>&2 2>&3 \
    )

    exit_status=$?
    if [ $exit_status -eq 1 ]; then  # <Back> button was pressed
        get_programming_task
    elif [ $exit_status -eq 0 ] && [ -z "$IMAGE_SRC" ]; then
        warn_empty_selection
        get_image_file_source
    elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
        :
    else
        exit
    fi

    case $IMAGE_SRC in
        "PRECOMPILED")
            IMAGE_PATH=${BOARD}-image-files
            if [ ! -d "$IMAGE_PATH" ]; then
                mkdir -p $IMAGE_PATH
            fi

            pushd $IMAGE_PATH > /dev/null
            for i in "${src_file_array[@]}"
            do
                if [ ! -f "$i" ]; then
                    # wget the source file and warn if not found
                    if ! wget $LATEST_RELEASE_URL/$i; then
#                    if ! wget $LATEST_RELEASE_URL/$i | whiptail --gauge "Downloading $i" 6 50 0; then
                        whiptail \
                            --title "/!\ ERROR /!\\" \
                            --yes-button "Retry" \
                            --no-button "Exit" \
                            --yesno "$i not found at $LATEST_RELEASE_URL" 8 78

                        exit_status=$?
                        if [ $exit_status -eq 1 ]; then  # <Exit> button was pressed
                            exit
                        elif [ $exit_status -eq 0 ]; then  # <Retry> button was pressed
                            popd > /dev/null
                            get_image_file_source "${IMAGE_NAME[@]}"
                        fi

                    else
                        whiptail \
                            --title "/!\ INFO /!\\" \
                            --msgbox "Download of $i successful." 8 78
                    fi
                fi
            done
            popd > /dev/null
        ;;
        "BUILD")
            IMAGE_PATH=./${BOARD}-yocto-poky-$YOCTO_BRANCH/${BOARD}-build-files/tmp/deploy/images/${BOARD}

            for i in "${src_file_array[@]}"
            do
                if [ ! -f "${IMAGE_PATH}/$i" ]; then
                    whiptail \
                        --title "/!\ WARNING /!\\" \
                        --msgbox "File $i not found in expected location.  Press Enter to browse for file." 8 78

                    exit_status=$?
                    if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
                        file_browser "$i" "$PWD"
                        IMAGE_PATH=$BROWSE_FILE_PATH
                        # TODO: to support user selected * files for P1 and P3, we need to read back the
                        # selected files from BROWSE_FILE_NAME and write them into array IMAGE_NAME
                    else  # Esc key pressed
                        exit
                    fi
                else
                    whiptail \
                        --title "/!\ INFO /!\\" \
                        --msgbox "Found $i from GHRD build." 8 78

                    exit_status=$?
                    if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
                        :
                    else  # Esc key pressed
                        exit
                    fi
                fi
            done
        ;;
        *)
            exit 1
        ;;
    esac
}

get_quartus_info() {
    if [ -z $QTS_TOOL_PATH ]; then
        if [ $OS_IS_WINDOWS -ne 0 ]; then
            QTS_TOOL_PATH=/mnt/c/intelFPGA_pro/$QTS_VER/quartus/bin64
        else
            QTS_TOOL_PATH=$HOME/intelFPGA_pro/$QTS_VER/quartus/bin
        fi
    fi

    if [ $OS_IS_WINDOWS -ne 0 ]; then
        QTS_PGM_CMD=quartus_pgm.exe
        JTAG_CONFIG=jtagconfig.exe
    else
        QTS_PGM_CMD=quartus_pgm
        JTAG_CONFIG=jtagconfig
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

        exit_status=$?
        if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
            program_mmc
        elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
            :
        else
            exit
        fi
    done
}

program_fpga_with_initramfs() {
    case $BOARD_FAM in
        "achilles")
            SOF_FILE=${BOARD}_RefDesign_HPS_boot_from_FPGA.sof
            JTAG_BOARD_ID="Arria10 IDK"
        ;;
#        "comxpress")
#            $SOF_FILE=
#        ;;
        *)
            return 255
        ;;
    esac
    
    # check if expected board is connected to host PC
    if [ "$($QTS_TOOL_PATH/$JTAG_CONFIG | grep -c "$JTAG_BOARD_ID")" -eq 0 ]; then
        whiptail \
            --title "/!\ ERROR /!\\" \
            --yes-button "Retry" \
            --no-button "Exit" \
            --yesno "$INFO_BOARD not found.  Verify programming cable drivers are installed and board is powered on and connected with USB cable." 8 78

        exit_status=$?
        if [ $exit_status -eq 1 ]; then  # <Exit> button was pressed
            exit
        elif [ $exit_status -eq 0 ]; then  # <Retry> button was pressed
            program_fpga_with_initramfs
        else
            exit
        fi
    else
        if [ ! -f $SOF_FILE ]; then
            whiptail \
                --title "/!\ INFO /!\\" \
                --msgbox "Ready to download $SOF_FILE ..." 8 78
                
            exit_status=$?
            if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
                :
            else  # Esc key pressed
                exit
            fi

            if ! wget $PROG_FILES_URL/$SOF_FILE; then
                whiptail \
                    --title "/!\ ERROR /!\\" \
                    --yes-button "Retry" \
                    --no-button "Exit" \
                    --yesno "$SOF_FILE not found at $PROG_FILES_URL." 8 78

                exit_status=$?
                if [ $exit_status -eq 1 ]; then  # <Exit> button was pressed
                    exit
                elif [ $exit_status -eq 0 ]; then  # <Retry> button was pressed
                    program_fpga_with_initramfs
                else
                    exit
                fi

            else
                whiptail \
                    --title "/!\ INFO /!\\" \
                    --msgbox "Download of $SOF_FILE successful." 8 78
                    
                exit_status=$?
                if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
                    :
                else  # Esc key pressed
                    exit
                fi
            fi
        fi

        whiptail \
            --title "/!\ INFO /!\\" \
            --msgbox "Ready for FPGA configuration with factory initramfs image..." 8 78

        exit_status=$?
        if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
            PGM_SUCCESS=$($QTS_TOOL_PATH/$QTS_PGM_CMD -c "$JTAG_BOARD_ID" -m jtag -o "p;$SOF_FILE" | grep -c "Configuration succeeded")
        else  # Esc key pressed
            exit
        fi
    fi
    
    while [ $PGM_SUCCESS -ne 1 ]
    do
        whiptail \
            --title "/!\ ERROR /!\\" \
            --yes-button "Retry" \
            --no-button "Exit" \
            --yesno "FPGA configuration with factory initramfs image was not successful.  \nRemember to stop target board boot process at U-Boot before attempting FPGA configuration." 10 38

        exit_status=$?
        if [ $exit_status -eq 1 ]; then  # <Exit> button was pressed
            exit
        elif [ $exit_status -eq 0 ]; then  # <Retry> button was pressed
            program_fpga_with_initramfs
        else
            exit
        fi
    done

    if [ $PGM_SUCCESS -eq 1 ]; then
        whiptail \
            --title "/!\ INFO /!\\" \
            --msgbox "FPGA configuration with $SOF_FILE successful." 8 78
            
        exit_status=$?
        if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
            :
        else  # Esc key pressed
            exit
        fi

        ip_addr_info_msg
        get_ip_address
    else
        program_fpga_with_initramfs
    fi
}

get_ip_address() {
    # get IP address and verify correct format (not checking if in valid range of 0 to 255)
    while ! [[ $IP_ADDR =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
    do
        IP_ADDR=$(whiptail \
            --title "IP Address" \
            --ok-button "Next" \
            --cancel-button "Back" \
            --inputbox "\nEnter the IP address of the target $INFO_BOARD board.  \nValid IP address must be in the format of '###.###.###.###':" 0 0 3>&1 1>&2 2>&3 \
        )

        exit_status=$?
        if [ $exit_status -eq 1 ]; then    # <Back> button was pressed
            get_quartus_info
        elif [ $exit_status -eq 0 ]; then  # <Next> button was pressed
            :
        else
            exit
        fi
    done

    if ping -c4 $IP_ADDR > /dev/null; then
        whiptail \
            --title "/!\ INFO /!\\" \
            --msgbox "Ping test passed.  ${INFO_BOARD} is connected at ${IP_ADDR}." 0 0

        exit_status=$?
        if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
            #:
            return
        else  # Esc key pressed
            exit
        fi
    else
        whiptail \
            --title "/!\ INFO /!\\" \
            --yes-button "Retry" \
            --no-button "Exit" \
            --yesno "Cannot detect ${INFO_BOARD} at ${IP_ADDR}.  Please confirm board is powered on and USB cable is connected and try again." 8 78

        exit_status=$?
        if [ $exit_status -eq 1 ]; then  # <Exit> button was pressed
            exit
        elif [ $exit_status -eq 0 ]; then  # <Retry> button was pressed
            get_ip_address
        else
            exit
        fi
    fi
}

program_mmc() {
    case $PGM_TASK_SEL in
        "FULL")
            IMAGE_NAME=("${BOARD_FAM}-${YOCTO_IMG}-image-${BOARD}.wic")
            get_image_file_source "${IMAGE_NAME[@]}"
            get_quartus_info
            ${BOARD_FAM}_pgm_steps
            program_fpga_with_initramfs
            
            whiptail \
                --title "/!\ INFO /!\\" \
                --msgbox "Ready to program $INFO_BOARD eMMC with WIC image: \n$IMAGE_NAME \nFollow prompts to continue. \nPassword for target ssh connection is 'root'" 0 0

            exit_status=$?
            if [ $exit_status -eq 0 ]; then  # <Ok> button was pressed
                ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP_ADDR" > /dev/null
                pv -tpreb $IMAGE_PATH/$IMAGE_NAME | ssh root@${IP_ADDR} dd of=/dev/mmcblk0 && sync
            else  # Esc key pressed
                exit
            fi
        ;;
        "UPDATE U-BOOT")
            whiptail \
                --title "/!\ INFO /!\\" \
                --msgbox "This feature is not yet available." 8 78
            get_programming_task
            IMAGE_NAME=("u-boot-splx4.sfp" "u-boot.img")
            get_image_file_source "${IMAGE_NAME[@]}"
            get_quartus_info
            ${BOARD_FAM}_pgm_steps
            program_fpga_with_initramfs
            #pv -tpreb $IMAGE_PATH/$IMAGE_NAME | ssh root@${IP_ADDR} dd of=/dev/mmcblk0p2 && sync
            # P1 program command here for u-boot.img
        ;;
        "UPDATE KERNEL")
            whiptail \
                --title "/!\ INFO /!\\" \
                --msgbox "This feature is not yet available." 8 78
            get_programming_task
            IMAGE_NAME=("zImage" "socfpga_arria10_${BOARD_FAM}.dtb")
            get_image_file_source "${IMAGE_NAME[@]}"
            get_quartus_info
            ${BOARD_FAM}_pgm_steps
            program_fpga_with_initramfs
            # P1 program command here
        ;;
        "UPDATE FPGA")
            whiptail \
                --title "/!\ INFO /!\\" \
                --msgbox "This feature is not yet available." 8 78
            get_programming_task
            IMAGE_NAME=("fit_spl_fpga_periph_only.itb" "fit_spl_fpga.itb")
            get_image_file_source "${IMAGE_NAME[@]}"
        ;;
        "P1")
            whiptail \
                --title "/!\ INFO /!\\" \
                --msgbox "This feature is not yet available." 8 78
            get_programming_task
            # allow to browse for any file name
            IMAGE_NAME=("*")
            get_image_file_source "${IMAGE_NAME[@]}"
            get_quartus_info
            ${BOARD_FAM}_pgm_steps
            program_fpga_with_initramfs
            # P1 program command here
        ;;
        "P3")
            whiptail \
                --title "/!\ INFO /!\\" \
                --msgbox "This feature is not yet available." 8 78
            get_programming_task
            # allow to browse for any file name
            IMAGE_NAME=("*")
            get_image_file_source "${IMAGE_NAME[@]}"
            # boot to Poky rootf
            # P3 program command here
        ;;
        *)
            exit 1
        ;;
    esac
}

#################################################
# Main
#################################################

# ensure not running as root
if [ `whoami` = root ] ; then
    printf "\nERROR: Do not run this script as root.\n\n"
    exit 1
fi

# do not use arguments when running script stand-alone;
# these should only be passed from the GSRD build script
# to use variables already defined there
while [ "$1" != "" ]; do
    case $1 in
        -S)
            SOURCED_FROM_GSRD_SCRIPT=1
        ;;
        -b)
            shift
            BOARD=$1
        ;;
        -q)
            shift
            QTS_VER=$1
        ;;
        -t)
            shift
            QTS_TOOL_PATH=$1
        ;;
        -i)
            shift
            YOCTO_IMG=$1
        ;;
        -o)
            shift
            YOCTO_BRANCH=$1
        ;;
        *)
            printf "\nThis script does not take any parameters unless sourced from the GSRD build script.\n\n"
            exit 1
    esac
    shift
done

script_intro

# check bash PIPESTATUS to make sure dd through pv completed successfully
if [ $PIPESTATUS -eq 0 ]; then
    whiptail \
        --title "Programming Complete" \
        --msgbox "Power cycle board to continue.  This script will now exit." 0 0
else
    whiptail \
        --title "/!\ ERROR /!\\" \
        --msgbox "There was a problem during programming.  Please exit and try again." 0 0
fi
