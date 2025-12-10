#!/bin/bash

# Storage Device Benchmark Script for Debian
# Requires root privileges

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${BLUE}=== Storage Device Benchmark Tool ===${NC}\n"

# Function to install packages
install_packages() {
    echo -e "${YELLOW}Checking and installing required packages...${NC}"
    
    PACKAGES="fio hdparm ioping sysstat smartmontools lshw util-linux"
    
    apt-get update -qq
    
    for pkg in $PACKAGES; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo -e "${GREEN}Installing $pkg...${NC}"
            apt-get install -y $pkg > /dev/null 2>&1
        else
            echo -e "${GREEN}✓ $pkg already installed${NC}"
        fi
    done
    
    echo -e "${GREEN}All required packages installed!${NC}\n"
}

# Function to list available storage devices
list_devices() {
    echo -e "${BLUE}=== Available Storage Devices ===${NC}\n"
    
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,TRAN | grep -E "disk|NAME"
    
    echo ""
}

# Function to get device details
get_device_info() {
    local device=$1
    
    echo -e "${BLUE}=== Device Information: $device ===${NC}"
    
    # Device model and serial
    echo -e "${YELLOW}Model & Serial:${NC}"
    lsblk -o NAME,MODEL,SERIAL /dev/$device | grep -v "^NAME"
    
    # Connection type
    echo -e "\n${YELLOW}Connection Type:${NC}"
    lsblk -o NAME,TRAN /dev/$device | grep -v "^NAME"
    
    # Size information
    echo -e "\n${YELLOW}Size Information:${NC}"
    lsblk -o NAME,SIZE,TYPE /dev/$device | grep -v "^NAME"
    
    # SMART status (if available)
    echo -e "\n${YELLOW}SMART Status:${NC}"
    if smartctl -i /dev/$device > /dev/null 2>&1; then
        smartctl -H /dev/$device | grep -E "SMART overall-health|result"
    else
        echo "SMART not available for this device"
    fi
    
    echo ""
}

# Function to perform sequential read/write test with fio
fio_sequential_test() {
    local device=$1
    local test_file="/tmp/fio_test_$$"
    
    echo -e "${BLUE}=== FIO Sequential Read/Write Test ===${NC}"
    echo -e "${YELLOW}Running sequential write test...${NC}"
    
    fio --name=seq-write \
        --filename=$test_file \
        --size=1G \
        --bs=1M \
        --rw=write \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=4 \
        --group_reporting \
        --output-format=normal
    
    echo -e "\n${YELLOW}Running sequential read test...${NC}"
    
    fio --name=seq-read \
        --filename=$test_file \
        --size=1G \
        --bs=1M \
        --rw=read \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=4 \
        --group_reporting \
        --output-format=normal
    
    rm -f $test_file
    echo ""
}

# Function to perform random read/write test with fio
fio_random_test() {
    local device=$1
    local test_file="/tmp/fio_random_test_$$"
    
    echo -e "${BLUE}=== FIO Random 4K Read/Write Test ===${NC}"
    echo -e "${YELLOW}Running random write test (4K blocks)...${NC}"
    
    fio --name=rand-write \
        --filename=$test_file \
        --size=512M \
        --bs=4k \
        --rw=randwrite \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=32 \
        --group_reporting \
        --output-format=normal
    
    echo -e "\n${YELLOW}Running random read test (4K blocks)...${NC}"
    
    fio --name=rand-read \
        --filename=$test_file \
        --size=512M \
        --bs=4k \
        --rw=randread \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=32 \
        --group_reporting \
        --output-format=normal
    
    rm -f $test_file
    echo ""
}

# Function to perform hdparm test
hdparm_test() {
    local device=$1
    
    echo -e "${BLUE}=== HDParm Buffered Disk Read Test ===${NC}"
    echo -e "${YELLOW}Running hdparm test (3 passes)...${NC}"
    
    hdparm -t /dev/$device
    echo ""
    hdparm -t /dev/$device
    echo ""
    hdparm -t /dev/$device
    
    echo ""
}

# Function to perform ioping latency test
ioping_test() {
    local mount_point=$1
    
    echo -e "${BLUE}=== IOPing Latency Test ===${NC}"
    echo -e "${YELLOW}Testing I/O latency (10 seconds)...${NC}"
    
    ioping -c 20 $mount_point
    
    echo ""
}

# Function to run complete benchmark suite
run_benchmark() {
    local device=$1
    local mount_point=$2
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Starting benchmark for /dev/$device${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    # Get device info
    get_device_info $device
    
    # Create temporary mount point if needed
    local temp_mount=""
    if [ -z "$mount_point" ]; then
        echo -e "${YELLOW}Device not mounted. Creating temporary test file in /tmp${NC}\n"
        temp_mount="/tmp"
    else
        temp_mount="$mount_point"
    fi
    
    # Run tests
    hdparm_test $device
    
    if [ -w "$temp_mount" ]; then
        ioping_test $temp_mount
        
        # Change to the mount point for fio tests
        cd $temp_mount
        fio_sequential_test $device
        fio_random_test $device
        cd - > /dev/null
    else
        echo -e "${RED}Cannot write to mount point. Skipping fio and ioping tests.${NC}\n"
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Benchmark completed for /dev/$device${NC}"
    echo -e "${GREEN}========================================${NC}\n"
}

# Main script execution
main() {
    # Install required packages
    install_packages
    
    # List available devices
    list_devices
    
    # Get list of disk devices (excluding loop devices)
    mapfile -t devices < <(lsblk -d -n -o NAME,TYPE | grep "disk" | awk '{print $1}')
    
    if [ ${#devices[@]} -eq 0 ]; then
        echo -e "${RED}No disk devices found!${NC}"
        exit 1
    fi
    
    # Present menu for device selection
    echo -e "${YELLOW}Select devices to benchmark:${NC}"
    echo "0) All devices"
    
    for i in "${!devices[@]}"; do
        dev="${devices[$i]}"
        info=$(lsblk -d -n -o SIZE,MODEL,TRAN /dev/$dev)
        echo "$((i+1))) $dev - $info"
    done
    
    echo ""
    read -p "Enter selection (comma-separated for multiple, or 0 for all): " selection
    
    # Parse selection
    IFS=',' read -ra selected <<< "$selection"
    
    declare -a test_devices
    
    for sel in "${selected[@]}"; do
        sel=$(echo $sel | xargs) # trim whitespace
        
        if [ "$sel" == "0" ]; then
            test_devices=("${devices[@]}")
            break
        elif [ "$sel" -ge 1 ] && [ "$sel" -le "${#devices[@]}" ]; then
            test_devices+=("${devices[$((sel-1))]}")
        fi
    done
    
    if [ ${#test_devices[@]} -eq 0 ]; then
        echo -e "${RED}No valid selection made!${NC}"
        exit 1
    fi
    
    # Confirm before proceeding
    echo -e "\n${YELLOW}Will benchmark the following devices:${NC}"
    for dev in "${test_devices[@]}"; do
        echo "  - /dev/$dev"
    done
    
    echo -e "\n${RED}WARNING: This will create temporary test files and perform intensive I/O operations.${NC}"
    read -p "Continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Benchmark cancelled."
        exit 0
    fi
    
    # Run benchmarks
    for dev in "${test_devices[@]}"; do
        # Get mount point if available
        mount_point=$(lsblk -n -o MOUNTPOINT /dev/$dev | head -1)
        
        run_benchmark "$dev" "$mount_point"
        
        # Pause between devices
        if [ "$dev" != "${test_devices[-1]}" ]; then
            echo -e "${YELLOW}Pausing for 5 seconds before next device...${NC}\n"
            sleep 5
        fi
    done
    
    echo -e "${GREEN}All benchmarks completed!${NC}"
}

# Run main function
main
