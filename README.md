## REFLEX CES Build Scripts

This repository contains build scripts for use with supported REFLEX CES boards using Intel SoC FPGAs.

The primary script is **reflex-gsrd-build.sh**.  The script uses a series of menus to choose the build task(s) to run,
apply the required settings for each task, and then begin processing those tasks by downloading and launching other scripts.

System reference design build tasks consist of:
1. Building the FPGA reference design (GHRD).
2. Building the HPS software components using the Yocto project build system.
3. Programming the boot flash on the supported target board using the generated WIC image from step 2 above.

To use the script, open a terminal console and create a directory to work from, for example:
```
mkdir achilles-gsrd-2023.07
cd achilles-gsrd-2023.07
```

Then, install required packages used by Yocto and other build tasks:
```
wget https://raw.githubusercontent.com/reflexces/build-scripts/2023.07/yocto-packages.sh
chmod +x yocto-packages.sh
sudo ./yocto-packages.sh
```

Download and run the GSRD Build Script:
```
wget https://raw.githubusercontent.com/reflexces/build-scripts/2023.07/reflex-gsrd-build.sh
chmod +x reflex-gsrd-build.sh
./reflex-gsrd-build.sh
```

The image below provides a graphical representation of the **reflex-gsrd-build.sh** functionality.
![GSRD Build Script Flow](/doc/reflex-gsrd-build.png)
