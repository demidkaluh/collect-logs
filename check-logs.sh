#!/bin/bash


function Check_logs ()
{
  function Remove ()
  {
    umount disk.img
    rm -r disk
    rm disk.img
  }


  function Red ()
  {
    out=""
    for i in $@
    do 
      out+="$i "
    done

    printf "\033[91m$out\033[0m"
  }


  function Green ()
  {
    out=""
    for i in $@
    do 
      out+="$i "
    done

    printf "\033[92m$out\033[0m"
  }


  MACHINE=get-linux-info-v12-17.10.2023-5.10.144.efi
  BIOS=/usr/share/edk2/x64/OVMF.4m.fd
  RAM_SIZE=1000M
  SMP=2
  DISK_SIZE=100M


  USAGE="
  Runs QEMU with .efi app, collects logs and checks them.
  Usage (as root!):
      check-logs [ARGS]
  Arguments:
      --help,-h,help    - show this help
      -f (file)         - choose verifiable .efi file (default is get-linux-info-v12-17.10.2023-5.10.144.efi) 
      -b (bios)         - choose bios version (default is /usr/share/edk2/x64/OVMF.4m.fd)
      -m (memory)       - choose RAM size (default is 1000M)
      -s (smp)          - choose number of cores (default is 2)
      -d (disk)         - choose disk space (default is 100M)"

  PIPE="\n################################################\n"


  #HELP PAGE
  for arg in $@; do
      case "$arg" in
          -h|--help|help)
              printf "$USAGE"
              exit
              ;;
          *)
              ;;
      esac
  done

  #OPTS PARSING
  
  while getopts ":b:m:s:d:" opt; do
    case "${opt}" in
          b)
              BIOS=${OPTARG}
              ;;
          m)
              RAM_SIZE=${OPTARG}
              ;;
          s)
              SMP=${OPTARG}
              ;; 
          d)
              DISK_SIZE=${OPTARG}
              ;;
          f)
              MACHINE=${OPTARG}
              ;;
          *)
              echo "Incorrect options. Try -h to see help page"
              exit 
              ;;
      esac
  done


  #CREATING VFAT GPT DISK
  dd if=/dev/zero of=disk.img bs=$DISK_SIZE count=1 status=progress >> /dev/null 2>&1
  #echo 'label: gpt' | sfdisk disk.img >> /dev/null 2>&1
  parted disk.img --script mklabel gpt #>> /dev/null 2>&1
  parted disk.img --script mkpart primary 0 100% #>> /dev/null 2>&1
  
  mkfs.vfat disk.img >> /dev/null 2>&1
  
  mkdir -p disk
  mount -t vfat disk.img disk
  
  cd disk
  mkdir -p AMDZ_HW_LOG
  mkdir -p EFI
  mkdir -p EFI/BOOT
  cd ..
  cp $MACHINE disk/EFI/BOOT/BOOTX64.efi
  umount disk.img

  printf "QEMU starts\r"
  sleep 1
  printf "Log collection starts. Please wait...\r"
  
  #QEMU BOOT
  qemu-system-x86_64 \
    -bios $BIOS      \
    -hda disk.img    \
    -m $RAM_SIZE     \
    -smp $SMP        \
    --enable-kvm     \
    -usb             \
    -nographic       \
    -serial none     \
    -monitor none    \
    -vga qxl
    #>> /dev/null 2>&1

  mount -t vfat disk.img disk


  cd disk
  if [ -d AMDZ_HW_LOG ]; then
    cd AMDZ_HW_LOG
  else
    Remove
    Red $"Error : dir AMDZ_HW_LOG not found\n"
    exit
  fi


  #UNZIPPING ARCHIVE IN "AMDZ_UNZIPPED_LOGS" DIRECTORY
  ARCHIVE=$(ls | sort | grep log___ | tail -n 1)
  mkdir -p ../../AMDZ_UNZIPPED_LOGS
  tar xvf $ARCHIVE -C ../../AMDZ_UNZIPPED_LOGS 1> /dev/null
  cd ../../AMDZ_UNZIPPED_LOGS
  UNZIPPED_DIR=$(ls -d */ | sort | grep log___ | tail -n 1)
  cd $UNZIPPED_DIR


  #LOGS TO FIND
  LOGS=(blkid.list boot_files.list cmdline.log dmesg.log dmidecode.list \
    dmi-raw-sysfs.bin drivers.log fdisk.log fstab.list grub.cfg/@boot@grub@grub.cfg \
    hwinfo.log hw.log iomem.log ioports.log kernel_config.log lsblk.log lsb.log \
    lsmod.log lspci.log lspcit.log lspcix.log mounts.log pcsc.log udevblock/nvme0n1.log \
    udevblock/nvme0n1p1.log  udevblock/nvme0n1p2.log  udevblock/nvme0n1p3.log  \
    udevblock/nvme0n1p4.log uname.log usb.log usbt.log version.log)


  NOT_EXISTING_FILES=()
  EMPTY_FILES=()


  printf "\n           Logs integrity check:"
  printf $PIPE
  for FILE in ${LOGS[@]}
  do
    if [[ -s $FILE ]]; then
      printf "File $(Green $FILE) exists and not empty\n"
    elif [[ -f $FILE ]] && [[ ! -s $FILE ]]; then
      EMPTY_FILES+=($FILE)
      printf "File $(Red $FILE) is empty\n"
    else
      NOT_EXISTING_FILES+=($FILE)
      printf "File $(Red $FILE) not exists\n"
    fi 
  done
  printf $PIPE


  LOGS_LEN=${#LOGS[@]}
  NEF_LEN=${#NOT_EXISTING_FILES[@]}
  EMPTY_LEN=${#EMPTY_FILES[@]}

  printf \
  "$(($LOGS_LEN - $NEF_LEN)) of $LOGS_LEN files were found, 
  $(($LOGS_LEN - $NEF_LEN - $EMPTY_LEN)) of them are not empty.\n"

  if [[ "$NEF_LEN" != 0 ]] || [[ "EMPTY_LEN" != 0 ]]; then
    Red "BAD FILES:\n"
  fi

  if [ "$NEF_LEN" != 0 ]; then
    printf "File(s) $(Red ${NOT_EXISTING_FILES[@]}) not found.\n"
  fi

  if [ "$EMPTY_LEN" != 0 ]; then
    printf "Empty file(s): $(Red ${EMPTY_FILES[@]})\n"
  fi


  #UNMOUNT AND REMOVE DISK
  cd ../../
  Remove   
}

Check_logs $@
