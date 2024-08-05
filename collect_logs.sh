#!/bin/bash

function collect-logs ()
{
  USAGE="
  Runs QEMU with .efi app, collects logs and checks them.
  Usage (as root!):
      # bash collect-logs [ARGS]
  Arguments:
      -f              - choose verifiable .efi file 
      Optional :
      --help,-h,help  - show this help
      -c              - enable color output (default 0)
      -b              - send bios (.../OVMF.4m.fd)
      -m              - choose RAM size (default 1000M)
      -s              - choose number of cores (default 2)
      -d              - choose disk space (default 200M)

      Minimum required (may differ with package managers): 
      qemu or qemu-kvm 
      libvirt
      ovmf 
      kpartx 
      dosfstools \n"

  PIPE="\n################################################\n"

  
  START=$(pwd)

  function RED ()
  {
    out=""
    for i in "$@"
    do 
      out+="$i "
    done
    
    out="${out::-1}"
    if (( "$COLOR" == 1 ))
    then
      printf "\033[91m""$out""\033[0m"
    else 
      printf "$out"
    fi
  }
  

  function GREEN ()
  {
    out=""
    for i in "$@"
    do 
      out+="$i "
    done
    
    out="${out::-1}"
    if (( "$COLOR" == 1 ))
    then
      printf "\033[92m""$out""\033[0m"
    else 
      printf "$out"
    fi
  }


  function YELLOW ()
  {
    out=""
    for i in "$@"
    do 
      out+="$i "
    done


    out="${out::-1}"

    if (( "$COLOR" == 1 ))
    then
      printf "\033[93m""$out""\033[0m"
    else
      printf "$out"
    fi
  }
  

  
  function remove ()
  {
    umount -q -f disk.img
    rm -rf disk
    rm -f disk.img
  }
  

  #Secure exit
  function my_exit ()
  {
    cd "$START" 2>/dev/null 
    sleep 1
    remove
    sudo chown -R demid:users AMDZ_UNZIPPED_LOGS 2>/dev/null
    exit "$1"
  }        


  #Secure cd
  function my_cd ()
  {
    cd "$1" || { RED "Dir ""$1"" doesn't exist or not allowed\n"; my_exit 1; }
  }

  #Outputs all files under current directory
  function recursive_ls ()
  {
    for file in `find "$1" -type f -name "*"`
    do
      printf "$(printf "$file" | sed 's/$1//' | sed 's/..//')\n"
    done
  }
  

  function signal_exit ()
  {
    printf "\nLog collection was interrupted\n"
    my_exit 0
  }
  trap signal_exit SIGHUP SIGINT SIGQUIT SIGTERM
  

   
  RAM_SIZE=1000M
  SMP=2
  DISK_SIZE=200M
  COLOR=1

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
  
  while getopts ":b:m:s:d:f:c:" opt; do
    case "${opt}" in
          b)
              BIOS="$OPTARG"

              if (( $(echo "$BIOS" | grep .4m.fd | grep OVMF | wc -l) != 1 ))
              then 
                printf "Incorrect -b option\n"
                exit 1
              fi

              ;;
          m)
              RAM_SIZE="$OPTARG"
              if (( $(echo "$RAM_SIZE" | grep M | wc -l) != 1 )) && \
                  (( $(echo "$RAM_SIZE" | grep G | wc -l) != 1 ))
              then
                printf "Incorrect -m option\n"
                exit 1 
              fi 
              

              if ! [[ $(echo "$RAM_SIZE" | sed 's/M//' | sed 's/G//') =~ ^-?[0-9]+$ ]]
              then
                printf "Incorrect -m option\n"
                exit 1
              fi
              ;;
          s)
              SMP="$OPTARG"

              if ! [[ "$SMP" =~ ^-?[0-9]+$ ]]
              then
                printf "Incorrect -s option\n"
                exit 1
              fi

              ;; 
          d)
              DISK_SIZE="$OPTARG"

              if (( $(echo "$DISK_SIZE" | grep M | wc -l) != 1 )) && \
                  (( $(echo "$DISK_SIZE" | grep G | wc -l) != 1 ))
              then
                printf "Incorrect -d option\n"
                exit 1 
              fi 
              

              if ! [[ $(echo "$DISK_SIZE" | sed 's/M//' | sed 's/G//') =~ ^-?[0-9]+$ ]]
              then
                printf "Incorrect -d option\n"
                exit 1
              fi

              ;;
          f)
              MACHINE="$OPTARG"

              if (( $(echo "$MACHINE" | grep .efi | wc -l) != 1 ))
              then 
                printf "Incorrect -f option\n"
                exit 1
              fi
              ;;
          c) 
              COLOR="$OPTARG"
              ;;
          *)
              echo "Incorrect options. Try -h to see help page"
              exit 
              ;;
      esac
  done
  
  #Try to find bios in system if it wasn't set
  if [ -z "$BIOS" ]
  then
    BIOS_PATH1="/usr/share/edk2/x64/OVMF.4m.fd"
    BIOS_PATH2="/usr/share/OVMF/x64/OVMF.4m.fd"
  
    if [ -f "$BIOS_PATH1" ]
    then
      BIOS="$BIOS_PATH1"
    elif [ -f "$BIOS_PATH2" ]
    then
      BIOS="$BIOS_PATH2"
    else
      WHERE_IS_OVMF=$(whereis OVMF | sed 's/OVMF: //')
      BIOS=$(recursive_ls "$WHERE_IS_OVMF" | grep OVMF.4m.fd)
    fi
  fi 
  
  if [ -z "$BIOS" ]
  then
    RED "BIOS wasn't set by user and wasn't found by script.\n"
    my_exit 1
  fi

  #CREATING VFAT GPT DISK
  dd if=/dev/zero of=disk.img bs="$DISK_SIZE" count=1 status=progress >> /dev/null 2>&1
  #echo 'label: gpt' | sfdisk disk.img >> /dev/null 2>&1
  parted disk.img --script mklabel gpt >> /dev/null 2>&1
  parted disk.img --script mkpart primary 0 100% >> /dev/null 2>&1
  
  mkfs.vfat disk.img >> /dev/null 2>&1
  
  mkdir -p disk
  mount -t vfat disk.img disk
  

  my_cd disk
  mkdir -p AMDZ_HW_LOG
  mkdir -p EFI
  mkdir -p EFI/BOOT

  my_cd ..
  cp $MACHINE disk/EFI/BOOT/BOOTX64.efi
  umount -q disk.img

  printf "Log collection starts. Please wait...\r"
  
  
  #QEMU BOOT
  qemu-system-x86_64               \
    -bios "$BIOS"                  \
    -drive file=disk.img,format=raw\
    -m "$RAM_SIZE"                 \
    -smp "$SMP"                    \
    --enable-kvm                   \
    -usb                           \
    -no-reboot                     \
    -d int                         \
    -nographic                     \
    -serial none                   \
    -monitor none                  \
    2>/dev/null
  
  printf "                                                \n"
  mount -t vfat disk.img disk
  
  #UNZIPPING ARCHIVE IN "AMDZ_UNZIPPED_LOGS/MACHINE_NAME/TEST+DATE/" DIRECTORY
  ARCHIVE="$(ls "disk/AMDZ_HW_LOG/" | sort | grep log___ | grep .tar.gz | tail -n 1)"
  ARCHIVE_PATH="disk/AMDZ_HW_LOG/""$ARCHIVE"

  if [ -z "$ARCHIVE" ]
  then 
    RED "\nArchive wasn't found\n"
    my_exit 1 
  fi 
  
  mkdir -p "AMDZ_UNZIPPED_LOGS"
  MACHINE_DIR=$(echo "AMDZ_UNZIPPED_LOGS/""$MACHINE" | sed 's/.efi//')
  mkdir -p "$MACHINE_DIR"

  TEST_NAME=$(echo "$ARCHIVE" | sed 's/log___/test/' | sed 's/.tar.gz//')
  TEST_DIR="$MACHINE_DIR/""$TEST_NAME/"
  
  mkdir "$TEST_DIR" || { RED "$TEST_NAME already exists\n"; my_exit 1; }
  mv "$ARCHIVE_PATH" "$TEST_DIR"

  my_cd "$TEST_DIR"
  tar xvf "$ARCHIVE" 1> /dev/null

  UNZIPPED_DIR=$(echo "$ARCHIVE" | sed 's/.tar.gz//')
  my_cd "$UNZIPPED_DIR"
  
  #LOGS TO FIND
  CHECK_LIST=(blkid.list boot_files.list cmdline.log dmesg.log dmidecode.list \
    dmi-raw-sysfs.bin drivers.log fdisk.log fstab.list grub.cfg/@boot@grub@grub.cfg \
    hwinfo.log hw.log iomem.log ioports.log kernel_config.log lsblk.log lsb.log \
    lsmod.log lspci.log lspcit.log lspcix.log mounts.log pcsc.log \
    uname.log usb.log usbt.log version.log cmos_test.bin cmos_test.txt prefix.bin nvram_test.bin)

  
  LOGS=($(recursive_ls .))
  OK_FILES=()
  EMPTY_FILES=()
  UNEXPECTED_FILES=()
  NOT_FOUND_FILES=()
  
  
  #finds substring in string
  function my_find ()
  {
    ARRAY=($@)
    let ARR_LEN="${#ARRAY[@]}"-1
    ARRAY2="${ARRAY[@]:1:$ARR_LEN}"
    FILE="\<${1}\>" 

    if [[ ${ARRAY2[@]} =~ $FILE ]]
    then
      echo 1
    else
      echo 0
    fi
  }
      

  #Find out if there are any not-found files
  for FILE in "${CHECK_LIST[@]}"
  do
    if (( "$(my_find "$FILE" "${LOGS[@]}")" == 0))
    then
      NOT_FOUND_FILES+=("$FILE")
    fi 
  done

  EFIVARS_CREATED=0
  VARS_CREATED=0

  EFIVARS_LEN=0 
  VARS_LEN=0

  ICLIBS_CREATED=0 
  ICLIBS_LEN=0

  UDEVBLOCK_CREATED=0 
  UDEVBLOCK_LEN=0

  ACPIDUMP_CREATED=0 
  ACPIDUMP_LEN=0

  #Sort successed, empty and unexpected files
  for FILE in "${LOGS[@]}"
  do 
    if (( $(echo "$FILE" | grep efivars/ | wc -l) == 1 ))
    then
      EFIVARS_CREATED=1
      let EFIVARS_LEN+=1
      continue 
    fi
    
    if (( $(echo "$FILE" | grep vars/ | wc -l) == 1 ))
    then
      VARS_CREATED=1
      let VARS_LEN+=1
      continue 
    fi 

    if (( $(echo "$FILE" | grep ic-libs/ | wc -l) == 1 ))
    then
      ICLIBS_CREATED=1
      let ICLIBS_LEN+=1
      continue 
    fi

    if (( $(echo "$FILE" | grep udevblock/ | wc -l) == 1 ))
    then
      UDEVBLOCK_CREATED=1
      let UDEVBLOCK_LEN+=1
      continue 
    fi

    if (( $(echo "$FILE" | grep acpidump/ | wc -l) == 1 ))
    then
      ACPIDUMP_CREATED=1
      let ACPIDUMP_LEN+=1
      continue 
    fi


    if (( "$(my_find "$FILE" "${CHECK_LIST[@]}")" == 1 ))
    then
      if [[ -s "$FILE" ]]
      then
        OK_FILES+=("$FILE")
      else
        EMPTY_FILES+=("$FILE")
      fi
    else
      UNEXPECTED_FILES+=("$FILE")
    fi
  done


  #Output results
  YELLOW "\n           LOG COLLECTION RESULTS:"
  printf "$PIPE"
  YELLOW "Tested machine : "
  printf "$MACHINE\n"
  YELLOW "Date : "
  printf "$(echo "$ARCHIVE" | sed 's/log___//' | sed 's/.tar.gz//')\n"

  
  LOGS_LEN="${#LOGS[@]}"
  CL_LEN="${#CHECK_LIST[@]}"
  OK_LEN="${#OK_FILES[@]}"
  NEF_LEN="${#NOT_FOUND_FILES[@]}"
  EMP_LEN="${#EMPTY_FILES[@]}"
  UNEXP_LEN="${#UNEXPECTED_FILES[@]}"
  NEEDED_LEN="$CL_LEN"

  let OK_LEN+=$EFIVARS_LEN+$VARS_LEN+$ICLIBS_LEN+$ACPIDUMP_LEN+$UDEVBLOCK_LEN
  let FOUND_LEN=$OK_LEN+$EMP_LEN
  let NEEDED_LEN+=$EFIVARS_LEN+$VARS_LEN+$ICLIBS_LEN+$ACPIDUMP_LEN+$UDEVBLOCK_LEN
  
  if [ "$OK_LEN" != 0 ]
  then
    GREEN "\nSUCCESSFUL ($OK_LEN file(s)):\n"
    
    if [[ "$EFIVARS_CREATED" == 1 ]]
    then
      printf "efivars/ ""($EFIVARS_LEN"" files)\n"
    fi 

    if [[ "$VARS_CREATED" == 1 ]]
    then
      printf "vars/ ""($VARS_LEN"" files)\n"
    fi

    if [[ "$ICLIBS_CREATED" == 1 ]]
    then
      printf "ic-libs/ ""($ICLIBS_LEN"" files)\n"
    fi

    if [[ "$ACPIDUMP_CREATED" == 1 ]]
    then
      printf "acpidump/ ""($ACPIDUMP_LEN"" files)\n"
    fi

    if [[ "$UDEVBLOCK_CREATED" == 1 ]]
    then
      printf "udevblock/ ""($UDEVBLOCK"" files)\n"
    fi


    for FILE in "${OK_FILES[@]}"
    do 
      printf "$FILE\n"
    done
  fi

  
  if [ "$NEF_LEN" != 0 ]
  then
    RED "\nNOT FOUND ($NEF_LEN file(s)):\n"

    for FILE in "${NOT_FOUND_FILES[@]}"
    do 
      printf "$FILE\n"
    done
  fi

  if [ "$EMP_LEN" != 0 ]
  then
    RED "\nEMPTY ($EMP_LEN file(s)):\n"

    for FILE in "${EMPTY_FILES[@]}"
    do 
      printf "$FILE\n"
    done
  fi

  if [ "$UNEXP_LEN" != 0 ]
  then
    RED "\nUNEXPECTED ($UNEXP_LEN file(s)):\n"

    for FILE in "${UNEXPECTED_FILES[@]}"
    do 
      printf "$FILE\n"
    done
  fi
    
  printf "$PIPE"

  
  YELLOW "Totally were found : "; printf "$LOGS_LEN\n"
  YELLOW "Needed were found : "; printf "$FOUND_LEN ""/"" $NEEDED_LEN\n"
  
  if [[ "$EMP_LEN" != 0 ]]
  then
    printf "$EMP_LEN of them are "; YELLOW "empty\n"
  fi 

  if [[ "$NEF_LEN" != 0 ]]
  then 
    YELLOW "Not found : "; printf "$NEF_LEN\n"
  fi 

  if [[ "$UNEXP_LEN" != 0 ]]
  then
    YELLOW "Unexpected : "; printf "$UNEXP_LEN\n" 
  fi

  printf "$PIPE"


  #UNMOUNT AND REMOVE DISK
  printf "Program completed\n"
  my_exit 0 2>/dev/null
}

collect-logs "$@"

