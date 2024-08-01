#!/bin/bash


function Collect_logs ()
{
  function Red ()
  {
    out=""
    for i in "$@"
    do 
      out+="$i "
    done

    printf '\033[91m%s\033[0m' "$out"
  }


  function Green ()
  {
    out=""
    for i in "$@"
    do 
      out+="$i "
    done

    printf '\033[92m%s\033[0m' "$out"
  }


  function Remove ()
  {
    umount -q disk.img
    rm -r -f disk
    rm -f disk.img
  }


  #How deep pwd from starting directory 
  DEPTH=0

  #Secure exit
  function My_exit ()
  {
    EXIT_CODE="$1"
    if [[ "$DEPTH" -gt 0 ]]; then
      for ((i=0;i<"$DEPTH";i++)); do 
        cd ..
      done
    fi

    Remove
    exit "$EXIT_CODE" 
  }        


  #Secure cd
  function My_cd ()
  {
    cd "$1" 2>/dev/null

    if [[ "$?" == 0 ]]; then
      if [[ "$1" == ".." ]]; then
        let DEPTH-=1 
      elif [[ "$1" == "." ]]; then
        let DEPTH-=0
      else
        let DEPTH+=1
    fi

    if [[ "$DEPTH" -lt 0 ]]; then
      Red "Climbing to a higher directory is not allowed\n"
      My_exit 1 
    fi 
    else
      Red "Error:directory ""$1"" doesn't exist or not available\n";
      My_exit 1;
    fi
  }

  trap 'My_exit 1 && Red EXIT' EXIT
  trap 'My_exit 1 && Red SIGINT' SIGINT
  trap 'My_exit 1 && Red SIGTERM' SIGTERM
  trap 'My_exit 1 && Red SIGHUP' SIGHUP
  trap 'My_exit 1 && Red SIGQUIT' SIGQUIT
  #trap 'My_exit 1 && Red ERR' ERR 

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
      -d (disk)         - choose disk space (default is 100M)\n"

  PIPE="\n################################################\n"


  #HELP PAGE
  for arg in "$@"; do
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
  
  while getopts ":b:m:s:d:f:" opt; do
    case "${opt}" in
          b)
              BIOS="$OPTARG"
              ;;
          m)
              RAM_SIZE="$OPTARG"
              ;;
          s)
              SMP="$OPTARG"
              ;; 
          d)
              DISK_SIZE="$OPTARG"
              ;;
          f)
              MACHINE="$OPTARG"
              ;;
          *)
              echo "Incorrect options. Try -h to see help page"
              exit 
              ;;
      esac
  done


  #CREATING VFAT GPT DISK
  dd if=/dev/zero of=disk.img bs="$DISK_SIZE" count=1 status=progress >> /dev/null 2>&1
  #echo 'label: gpt' | sfdisk disk.img >> /dev/null 2>&1
  parted disk.img --script mklabel gpt #>> /dev/null 2>&1
  parted disk.img --script mkpart primary 0 100% #>> /dev/null 2>&1
  
  mkfs.vfat disk.img >> /dev/null 2>&1
  
  mkdir -p disk
  mount -t vfat disk.img disk
  
  My_cd disk
  mkdir -p AMDZ_HW_LOG
  mkdir -p EFI
  mkdir -p EFI/BOOT
  My_cd ..
  cp $MACHINE disk/EFI/BOOT/BOOTX64.efi
  umount -q disk.img

  printf "QEMU starts\r"
  sleep 1
  printf "Log collection starts. Please wait...\r"
  
  #QEMU BOOT
  qemu-system-x86_64        \
    -bios "$BIOS"            \
    -hda disk.img, format=raw \
    -m "$RAM_SIZE"             \
    -smp "$SMP"                 \
    --enable-kvm                 \
    -usb                          \
    -nographic                     \
    -serial none                    \
    -monitor none                    \
    -vga qxl  
    #>> /dev/null 2>&1

  mount -t vfat disk.img disk


  My_cd disk
  My_cd AMDZ_HW_LOG


  #UNZIPPING ARCHIVE IN "AMDZ_UNZIPPED_LOGS" DIRECTORY
  ARCHIVE=$(ls | sort | grep log___ | tail -n 1)
  mkdir -p ../../AMDZ_UNZIPPED_LOGS
  tar xvf "$ARCHIVE" -C ../../AMDZ_UNZIPPED_LOGS 1> /dev/null
  My_cd ../../AMDZ_UNZIPPED_LOGS
  UNZIPPED_DIR="$(ls -d */ | sort | grep log___ | tail -n 1)"
  My_cd "$UNZIPPED_DIR"


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
  printf "$PIPE"
  for FILE in "${LOGS[@]}"
  do
    if [[ -s "$FILE" ]]; then
      printf "File ""$(Green "$FILE")"" exists and not empty\n"
    elif [[ -f "$FILE" ]] && [[ ! -s "$FILE" ]]; then
      EMPTY_FILES+=("$FILE")
      printf "File ""$(Red "$FILE")"" is empty\n"
    else
      NOT_EXISTING_FILES+=("$FILE")
      printf "File ""$(Red "$FILE")"" not exists\n"
    fi 
  done
  printf "$PIPE"


  LOGS_LEN="${#LOGS[@]}"
  NEF_LEN="${#NOT_EXISTING_FILES[@]}"
  EMPTY_LEN="${#EMPTY_FILES[@]}"

  printf \
  "$(("$LOGS_LEN" - "$NEF_LEN")) of $LOGS_LEN files were found, 
  $(("$LOGS_LEN" - "$NEF_LEN" - "$EMPTY_LEN")) of them are not empty.\n"

  if [[ "$NEF_LEN" != 0 ]] || [[ "$EMPTY_LEN" != 0 ]]; then
    Red "BAD FILES:\n"
  fi

  if [ "$NEF_LEN" != 0 ]; then
    printf "File(s) $(Red "${NOT_EXISTING_FILES[@]}") not found.\n"
  fi

  if [ "$EMPTY_LEN" != 0 ]; then
    printf "Empty file(s): $(Red "${EMPTY_FILES[@]}")\n"
  fi


  #UNMOUNT AND REMOVE DISK
  My_cd ../../
  Remove   
}

Collect_logs "$@"

