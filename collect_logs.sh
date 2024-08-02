#!/bin/bash


function collect-logs ()
{
  function RED ()
  {
    out=""
    for i in "$@"
    do 
      out+="$i "
    done

    printf "\033[91m"$out"\033[0m"
  }


  function GREEN ()
  {
    out=""
    for i in "$@"
    do 
      out+="$i "
    done

    printf "\033[92m""$out""\033[0m"
  }


  function remove ()
  {
    umount -q disk.img
    rm -r -f disk
    rm -f disk.img
  }


  #How deep pwd from starting directory 
  DEPTH=0

  #Secure exit
  function my_exit ()
  {
    EXIT_CODE="$1"
    if [[ "$DEPTH" -gt 0 ]]; then
      for ((i=0;i<"$DEPTH";i++)); do 
        cd ..
      done
    fi

    remove
    exit "$EXIT_CODE" 
  }        


  #Secure cd
  function my_cd ()
  {
    cd "$1" 2>/dev/null

    LEN=($(echo "$1" | grep -o "/" | wc -l))

    if [[ "$?" == 0 ]]; then
      if [[ "$1" == ".." ]]; then
        let DEPTH-=1 
      elif [[ "$1" == "." ]]; then
        let DEPTH-=0
      else
        let DEPTH+=1
    fi

    if [[ "$DEPTH" -lt 0 ]]; then
      RED "Climbing to a higher directory is not allowed\n"
      My_exit 1 
    fi 
    else
      RED "Error:directory ""$1"" doesn't exist or not available\n";
      My_exit 1;
    fi
  }

  #Outputs all files under current directory
  function recursive_ls ()
  {
    for file in `find "$1" -type f -name "*"`
    do
      printf "$file \n"
    done
  }


  #trap 'My_exit 1 && Red EXIT' EXIT
  #trap 'My_exit 1 && Red SIGINT' SIGINT
  #trap 'My_exit 1 && Red SIGTERM' SIGTERM
  #trap 'My_exit 1 && Red SIGHUP' SIGHUP
  #trap 'My_exit 1 && Red SIGQUIT' SIGQUIT
  #trap 'My_exit 1 && Red ERR' ERR 

  #arch
  #BIOS="/usr/share/edk2/x64/OVMF.4m.fd"
  #debian
  BIOS="/usr/share/OVMF/OVMF_CODE_4M.fd"
  RAM_SIZE=1000M
  SMP=2
  DISK_SIZE=100M


  USAGE="
  Runs QEMU with .efi app, collects logs and checks them.
  Usage (as root!):
      check-logs [ARGS]
  Arguments:
      --help,-h,help    - show this help
      -f (file)         - choose verifiable .efi file 
      -b (bios)         - choose bios version
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
  
  my_cd disk
  pwd
  mkdir -p AMDZ_HW_LOG
  mkdir -p EFI
  mkdir -p EFI/BOOT
  my_cd ..
  cp $MACHINE disk/EFI/BOOT/BOOTX64.efi
  umount -q disk.img

  printf "QEMU starts\r"
  printf "Log collection starts. Please wait...\r"
  
  
  #QEMU BOOT
  qemu-system-x86_64               \
    -bios "$BIOS"                  \
    -drive file=disk.img,format=raw\
    -m "$RAM_SIZE"                 \
    -smp "$SMP"                    \
    --enable-kvm                   \
    -usb                           \
    -nographic                     \
    -serial none                   \
    -monitor none                  \
    -vga qxl  


  mount -t vfat disk.img disk


  my_cd disk
  my_cd AMDZ_HW_LOG


  #UNZIPPING ARCHIVE IN "AMDZ_UNZIPPED_LOGS" DIRECTORY
  ARCHIVE=$(ls | sort | grep log___ | tail -n 1)
  mkdir -p ../../AMDZ_UNZIPPED_LOGS
  CURRENT_MACHINE_DIR="../../AMDZ_UNZIPPED_LOGS/""$MACHINE"
  mkdir -p $CURRENT_MACHINE_DIR
  tar xvf "$ARCHIVE" -C "$CURRENT_MACHINE_DIR" 1> /dev/null
  my_cd ..
  my_cd ..
  my_cd AMDZ_UNZIPPED_LOGS
  my_cd "$MACHINE"
  
  UNZIPPED_DIR="$(ls -d */ | sort | grep log___ | tail -n 1)"
  mkdir "$UNZIPPED_DIR"
  my_cd "$UNZIPPED_DIR"
  pwd 
  exit

  #LOGS TO FIND
  CHECK_LIST=(blkid.list boot_files.list cmdline.log dmesg.log dmidecode.list \
    dmi-raw-sysfs.bin drivers.log fdisk.log fstab.list grub.cfg/@boot@grub@grub.cfg \
    hwinfo.log hw.log iomem.log ioports.log kernel_config.log lsblk.log lsb.log \
    lsmod.log lspci.log lspcit.log lspcix.log mounts.log pcsc.log udevblock/nvme0n1.log \
    udevblock/nvme0n1p1.log  udevblock/nvme0n1p2.log  udevblock/nvme0n1p3.log  \
    udevblock/nvme0n1p4.log uname.log usb.log usbt.log version.log)

  
  LOGS=($(Recursive_ls "$UNZIPPED_DIR"))
  OK_FILES=()
  NOT_EXISTING_FILES=()
  EMPTY_FILES=()
  UNEXPECTED_FILES=()
  

  #Regular expr of array using for find
  function reg_expr ()
  {
    
    ARR=($1)
    REG_EXP=($(printf '%s|' "${ARR[@]}")) 
    LEN=${#REG_EXP}
    let LEN-=1
    REG_EXP=($(echo "$REG_EXP" | cut -c -"$LEN"))
    REG_EXP='^('"$REG_EXP"')$'
  }
      

  #Find out if there are any not-found files
  for FILE in "${CHECK_LIST[@]}"
  do
    if [[ "$FILE" =~ ($(reg_expr "${LOGS[@]}")) ]]; then
      :
    else
      NOT_FOUND_FILES+=("$FILE")
      #printf "File ""$(RED "$FILE")"" not exists\n"
    fi 
  done

  #Sort successed, empty and unexpected files
  for FILE in "${LOGS[@]}"
  do
    if [[ "$FILE" =~ ($(reg_expr "${CHECK_LIST[@]}")) ]]; then
      if [[ -s "$FILE" ]]; then
        OK_FILES+=("$FILE")
        #printf "File ""$(GREEN "$FILE")"" exists and not empty\n"
      else
        EMPTY_FILES+=("$FILE")
        #printf "File ""$(RED "$FILE")"" is empty\n"
      fi
    else
      UNEXPECTED_FILES+=("$FILE")
    fi
  done

  #Output results
  printf "\n           LOG COLLECTION RESULTS:"
  printf "$PIPE"

  CL_LEN="${#CHECK_LIST[@]}"
  OK_LEN="${#OK_FILES[@]}"
  NEF_LEN="${#NOT_FOUND_FILES[@]}"
  EMP_LEN="${#EMPTY_FILES[@]}"
  UNEXP_LEN="${UNEXPECTED_FILES[@]}"
  
  let FOUND_LEN=$OK_LEN+$EMP_LEN
  
  if [ "$OK_LEN" != 0 ]; then
    GREEN "\nSUCCESSFUL ($OK_LEN file(s)):\n"

    for FILE in "${OK_FILES[@]}"
    do 
      printf "File "
      GREEN "$FILE"
      printf " exists and not empty\n"
    done
  fi

  if [[ "$NEF_LEN" != 0 ]] || [[ "$EMP_LEN" != 0 ]]; then
    RED \
    "#############
     # BAD FILES:#
     #############\n"
  fi
  
  if [ "$NEF_LEN" != 0 ]; then
    RED "\nNOT FOUND ($NEF_LEN file(s)):\n"

    for FILE in "${NOT_EXISTING_FILES[@]}"
    do 
      printf "File "
      RED "$FILE"
      printf " not found\n"
    done
  fi

  if [ "$EMP_LEN" != 0 ]; then
    RED "\nEMPTY ($EMP_LEN file(s)):\n"

    for FILE in "${EMPTY_FILES[@]}"
    do 
      printf "File "
      RED "$FILE"
      printf " is empty\n"
    done
  fi

  if [ "$UNEXP_LEN" != 0 ]; then
    RED "\nUNEXPECTED ($UNEXP_LEN file(s)):\n"

    for FILE in "${UNEXP_FILES[@]}"
    do 
      printf "File "
      RED "$FILE"
      printf " is unexpected\n"
    done
  fi
    
  printf "$PIPE"

  printf \
  "Totally were found "$LOGS_LEN" file(s).
  $FOUND_LEN of $CL_LEN needed files were found.
  $OK_LEN of them are empty.
  $NEF_LEN file(s) not found.
  $UNEXP_LEN unexpected file(s) were found.\n"

  #UNMOUNT AND REMOVE DISK
  my_cd ../../../
  remove   

}

collect-logs "$@"

