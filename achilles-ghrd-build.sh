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
# Release info:
#
# 2022.06
#   - initial release for GSRD 2022.06 supporting Achilles SOMs

# Color text formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

OS_IS_WINDOWS=$(uname -a | grep -ic Microsoft)

# latest tested version of Quartus Prime Pro
# override with -q option, but results are not guaranteed
QTS_VER=23.1
SUPPORTED_QTS_VER=$QTS_VER

USER_DIR=0
USER_QTS_TOOL_PATH=0

SCRIPT_VERSION=ghrd-v$QTS_VER

# set this to 1 during development/test and specify local GHRD repo
DEBUG=0
DEBUG_REPO=${HOME}/work/github

#################################################
# Functions
#################################################

usage()
{
    echo "Usage: ./achilles-ghrd-build.sh [options]"
    echo "Achilles SOM GHRD build script"
    echo ""
    echo "Options:"
    echo "  -s, --som [som version]        Valid SOM versions (required):"
    echo "                                   v2-indus"
    echo "                                   v2-lite"
    echo "                                   v2-turbo"
    echo "                                   v5-indus"
    echo "                                   v5-lite"
    echo ""
    echo "  -g, --ghrd [type]              Valid GHRD types (required):"
    echo "                                   pr (partial reconfiguration example)"
    echo "                                   std (standard, flat hierarchy example, no PR)"
    echo ""
    echo "  -d, --directory [dir name]     Build directory name (optional)."
    echo "                                 If not specified, a default directory name is used."
    echo ""
    echo "  -q, --quartus-ver [version]    Quartus version to use for build (optional)."
    echo "                                 If not specified, defaults to v$SUPPORTED_QTS_VER."
    echo ""
    echo "  -t, --tool-path [dir name]     Quartus installation tool path (optional). Specify full"
    echo "                                 Specify full path to \"bin\" or \"bin64\" directory."
    echo ""
    echo "  -h, --help                     Display this help message and exit."
    echo ""
    echo "  -v, --version                  Display script version and exit."
    echo ""
} # end usage

clone_update_repos()
{
    repo[1]=achilles-hardware

    # clean directory if it exists
    if [ -d "$BUILD_DIR" ]; then
        rm -rf $BUILD_DIR
        mkdir -p $BUILD_DIR
    else
        mkdir -p $BUILD_DIR
    fi

    pushd $BUILD_DIR > /dev/null

    for i in {1..1}
    do
        if [ ! -d "${repo[i]}" ]; then
            echo "Cloning ${repo[i]} repository..."
            if [ $DEBUG -eq 1 ]; then
                git clone $DEBUG_REPO/${repo[i]}
            else
                git clone https://github.com/reflexces/${repo[i]}.git
            fi
        else
            pushd ${repo[i]} > /dev/null
            echo "Fetching latest updates for ${repo[i]}..."
            git pull
            popd > /dev/null
        fi
    done

    popd > /dev/null
} # end clone_update_repos

check_quartus_tools()
{
    if [ $USER_QTS_TOOL_PATH -eq 0 ]; then
        if [ $OS_IS_WINDOWS -ne 0 ]; then
            QTS_TOOL_PATH=/mnt/c/intelFPGA_pro/$QTS_VER/quartus/bin64
        else
            QTS_TOOL_PATH=$HOME/intelFPGA_pro/$QTS_VER/quartus/bin
        fi
    fi

    if [ $OS_IS_WINDOWS -ne 0 ]; then
        QTS_CMD=quartus_sh.exe
    else
        QTS_CMD=quartus_sh
    fi

    while [ ! -d $QTS_TOOL_PATH ]
    do
        printf "Quartus tools were not found in default installation path $QTS_TOOL_PATH.  Please enter the full path to your Quartus installation \"bin\" directory.\n"
        printf "Do not include / after bin."
        read -i "$QTS_TOOL_PATH" -e QTS_TOOL_PATH
        printf "Confirm Quartus version matches what is shown in Quartus installation path:"
        read -i "$QTS_VER" -e QTS_VER
    done
}

launch_quartus()
{
    pushd $BUILD_DIR/achilles-hardware > /dev/null
    git checkout ghrd-v$SUPPORTED_QTS_VER

    # TODO: manually copy the correct top level VHDL file until the set_parameter feature in create_achilles_ghrd_project.tcl is tested
    cp src/hdl/top/achilles_${SOM_VER}_ghrd_${GHRD_TYPE}.vhd src/hdl/achilles_ghrd.vhd

    {
    $QTS_TOOL_PATH/$QTS_CMD -t src/script/achilles_ghrd_build_flow.tcl $SOM_REV $SOM_VER $GHRD_TYPE
    } 2>&1 | tee -a ${BUILD_DIR}-build.log

    # TODO: create_achilles_ghrd_project.tcl script is creating this other .qpf, need to fix in that script; manually remove for now
    if [ -f achilles_${SOM_REV}_${SOM_VER}_ghrd.qpf ]; then
        rm achilles_${SOM_REV}_${SOM_VER}_ghrd.qpf
    fi
} # end launch_quartus

#################################################
# Main
#################################################

# ensure not running as root
if [ `whoami` = root ] ; then
    printf "\n${RED}ERROR: Do not run this script as root\n\n"
    exit 1
fi

# check & validate arguments
if [ -z $1 ]; then
    usage
    exit 1
fi

while [ "$1" != "" ]; do
    case $1 in
        -s | --som)
            shift
                case "$1" in
                    v2-indus)
                        SOM_REV="v2"
                        SOM_VER="indus"
                    ;;
                    v2-lite)
                        SOM_REV="v2"
                        SOM_VER="lite"
                    ;;
                    v2-turbo)
                        SOM_REV="v2"
                        SOM_VER="turbo"
                    ;;
                    v5-indus)
                        SOM_REV="v5"
                        SOM_VER="indus"
                    ;;
                    v5-lite)
                        SOM_REV="v5"
                        SOM_VER="lite"
                    ;;
                    *)
                        echo ""
                        echo "Invalid SOM version \"$1\" specified.  Use --help for valid options."
                        echo ""
                        exit 1
                esac
        ;;
        -g | --ghrd)
            shift
                if [[ "$1" = "std" || "$1" = "pr" ]]; then
                    GHRD_TYPE=$1
                else
                    echo ""
                    echo "Invalid GHRD type \"$1\" specified.  Use --help for valid options."
                    echo ""
                    exit 1
                fi
        ;;
        -d | --directory)
            shift
            BUILD_DIR=$1
            USER_DIR=1
        ;;
        # TODO: add version number validation
        -q | --quartus-ver)
            shift
            QTS_VER=$1
        ;;
        -t | --tool-path)
            shift
            QTS_TOOL_PATH=$1
            USER_QTS_TOOL_PATH=1
        ;;
        -h | --help)
            usage
            exit
        ;;
        -v | --version)
            echo "${SCRIPT_VERSION}"
            exit
        ;;
        *)
            usage
            exit 1
    esac
    shift
done

check_quartus_tools

# use default director if user specified directory not given
if [ $USER_DIR -eq 0 ]; then
    BUILD_DIR=achilles-${SOM_REV:?}-${SOM_VER:?}-ghrd-${GHRD_TYPE:?}-qpp_v${QTS_VER:?}
fi

# start a build time counter
SECONDS=0

clone_update_repos

if launch_quartus ; then
    # display elapsed build time for successful build
    ELAPSED="$(($SECONDS / 3600)) hrs $((($SECONDS / 60) % 60)) min $(($SECONDS % 60)) sec"
    echo -e ${GREEN}
    printf "*******************************************************************\n"
    printf " Achilles GHRD build for ${SOM_REV}-${SOM_VER} SOM\n"
    printf " completed in ${NC}${ELAPSED}${GREEN}\n"
    printf " on ${NC}$(date -d "today" +"%d-%b-%Y %H:%M")${GREEN}\n"
    printf "*******************************************************************\n"
    printf "\n"
    echo -e ${NC}
else
    echo -e ${ORANGE}
    echo "*******************************************************************"
    echo " There was a problem with the GHRD build process.  Please examine  "
    echo " the console output or report files for more information.          "
    echo "*******************************************************************"
    echo -e ${NC}
fi
