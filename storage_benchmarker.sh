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

# Global variables for report
REPORT_DIR="/tmp/storage_benchmark_$$"
REPORT_FILE="$REPORT_DIR/benchmark_report.md"
REPORT_PDF=""

# Arrays to store test results
declare -A DEVICE_RESULTS

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${BLUE}=== Storage Device Benchmark Tool ===${NC}\n"

# Function to install packages
install_packages() {
    echo -e "${YELLOW}Checking and installing required packages...${NC}"
    
    PACKAGES="fio hdparm ioping sysstat smartmontools lshw util-linux pandoc texlive-latex-base texlive-latex-extra bc"
    
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

# Function to initialize report
init_report() {
    mkdir -p "$REPORT_DIR"
    
    cat > "$REPORT_FILE" <<'EOFMARKER'
---
title: "Storage Device Benchmark Report"
author: "Storage Benchmark Tool"
date: "DATEPLACEHOLDER"
geometry: margin=2cm
output: pdf_document
---

# System Information

**Hostname:** HOSTNAMEPLACEHOLDER  
**Kernel:** KERNELPLACEHOLDER  
**Date:** FULLDATEPLACEHOLDER  
**User:** USERPLACEHOLDER

---

EOFMARKER

    sed -i "s/DATEPLACEHOLDER/$(date '+%B %d, %Y %H:%M:%S')/g" "$REPORT_FILE"
    sed -i "s/HOSTNAMEPLACEHOLDER/$(hostname)/g" "$REPORT_FILE"
    sed -i "s/KERNELPLACEHOLDER/$(uname -r)/g" "$REPORT_FILE"
    sed -i "s/FULLDATEPLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S')/g" "$REPORT_FILE"
    sed -i "s/USERPLACEHOLDER/$(whoami)/g" "$REPORT_FILE"
}

# Function to add section to report
add_to_report() {
    echo "$1" >> "$REPORT_FILE"
}

# Function to parse FIO output and extract metrics
parse_fio_output() {
    local output="$1"
    local metric_type="$2"  # read or write
    
    # Extract bandwidth (MB/s or GB/s)
    local bw=$(echo "$output" | grep -i "$metric_type:" | grep -oP 'BW=\K[0-9.]+[MG]iB/s' | head -1)
    if [[ $bw == *"GiB/s"* ]]; then
        bw=$(echo "$bw" | sed 's/GiB\/s//' | awk '{printf "%.0f", $1 * 1024}')
    else
        bw=$(echo "$bw" | sed 's/MiB\/s//' | awk '{printf "%.0f", $1}')
    fi
    
    # Extract IOPS
    local iops=$(echo "$output" | grep -i "$metric_type:" | grep -oP 'IOPS=\K[0-9.]+[kM]?' | head -1)
    if [[ $iops == *"k"* ]]; then
        iops=$(echo "$iops" | sed 's/k//' | awk '{printf "%.0f", $1 * 1000}')
    elif [[ $iops == *"M"* ]]; then
        iops=$(echo "$iops" | sed 's/M//' | awk '{printf "%.0f", $1 * 1000000}')
    else
        iops=$(echo "$iops" | awk '{printf "%.0f", $1}')
    fi
    
    # Extract latency (convert to ms)
    local lat=$(echo "$output" | grep -A 10 "lat.*:" | grep "avg=" | head -1 | grep -oP 'avg=\K[0-9.]+')
    if [ -z "$lat" ]; then
        lat=$(echo "$output" | grep -i "clat.*avg=" | head -1 | grep -oP 'avg=\K[0-9.]+')
    fi
    
    # Check if latency is in microseconds or milliseconds
    if echo "$output" | grep -q "lat (usec)"; then
        lat=$(echo "$lat" | awk '{printf "%.2f", $1 / 1000}')
    elif echo "$output" | grep -q "lat (msec)"; then
        lat=$(echo "$lat" | awk '{printf "%.2f", $1}')
    else
        # Try to parse from clat
        lat=$(echo "$lat" | awk '{printf "%.2f", $1 / 1000}')
    fi
    
    echo "${bw:-0}|${iops:-0}|${lat:-0}"
}

# Function to parse hdparm output
parse_hdparm_output() {
    local output="$1"
    # Extract the average of the three tests
    local speeds=$(echo "$output" | grep -oP 'Timing buffered disk reads:.*=\s*\K[0-9.]+' | awk '{sum+=$1; count++} END {printf "%.0f", sum/count}')
    echo "${speeds:-0}"
}

# Function to parse ioping output
parse_ioping_output() {
    local output="$1"
    # Extract average latency
    local lat=$(echo "$output" | grep "avg=" | grep -oP 'avg=\K[0-9.]+\s*[mu]?s' | head -1)
    
    if [[ $lat == *"ms"* ]]; then
        lat=$(echo "$lat" | sed 's/ms//' | awk '{printf "%.2f", $1}')
    elif [[ $lat == *"us"* ]]; then
        lat=$(echo "$lat" | sed 's/us//' | awk '{printf "%.2f", $1 / 1000}')
    else
        lat=$(echo "$lat" | awk '{printf "%.2f", $1}')
    fi
    
    # Extract IOPS if available
    local iops=$(echo "$output" | grep "iops=" | grep -oP 'iops=\K[0-9.]+[k]?' | head -1)
    if [[ $iops == *"k"* ]]; then
        iops=$(echo "$iops" | sed 's/k//' | awk '{printf "%.0f", $1 * 1000}')
    else
        iops=$(echo "$iops" | awk '{printf "%.0f", $1}')
    fi
    
    echo "${lat:-0}|${iops:-0}"
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
    
    add_to_report "# Device: /dev/$device"
    add_to_report ""
    add_to_report "## Device Information"
    add_to_report ""
    
    # Device model and serial
    echo -e "${YELLOW}Model & Serial:${NC}"
    local model_info=$(lsblk -d -n -o MODEL,SERIAL /dev/$device)
    echo "$model_info"
    add_to_report "**Model & Serial:** $model_info  "
    
    # Connection type
    echo -e "\n${YELLOW}Connection Type:${NC}"
    local tran_info=$(lsblk -d -n -o TRAN /dev/$device)
    echo "$tran_info"
    add_to_report "**Connection Type:** $tran_info  "
    
    # Size information
    echo -e "\n${YELLOW}Size Information:${NC}"
    local size_info=$(lsblk -d -n -o SIZE /dev/$device)
    echo "$size_info"
    add_to_report "**Size:** $size_info  "
    
    # SMART status (if available)
    echo -e "\n${YELLOW}SMART Status:${NC}"
    if smartctl -i /dev/$device > /dev/null 2>&1; then
        local smart_status=$(smartctl -H /dev/$device 2>/dev/null | grep -E "SMART overall-health|result" || echo "Unable to read")
        echo "$smart_status"
        add_to_report "**SMART Status:** $smart_status  "
    else
        echo "SMART not available for this device"
        add_to_report "**SMART Status:** Not available  "
    fi
    
    add_to_report ""
    echo ""
}

# Function to perform sequential read/write test with fio
fio_sequential_test() {
    local device=$1
    local test_file="/tmp/fio_test_$$"
    
    echo -e "${BLUE}=== FIO Sequential Read/Write Test ===${NC}"
    echo -e "${YELLOW}Running sequential write test...${NC}"
    
    add_to_report "## Sequential Performance Test"
    add_to_report ""
    add_to_report "### Sequential Write (1GB, 1M blocks)"
    add_to_report ""
    echo '```' >> "$REPORT_FILE"
    
    local write_output=$(fio --name=seq-write \
        --filename=$test_file \
        --size=1G \
        --bs=1M \
        --rw=write \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=4 \
        --group_reporting \
        --output-format=normal 2>&1 | tee /dev/tty)
    
    echo "$write_output" | grep -E "WRITE:|write:" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    add_to_report ""
    
    # Parse sequential write results
    local seq_write_results=$(parse_fio_output "$write_output" "write")
    IFS='|' read -r seq_write_bw seq_write_iops seq_write_lat <<< "$seq_write_results"
    DEVICE_RESULTS["${device}_seq_write_bw"]=$seq_write_bw
    DEVICE_RESULTS["${device}_seq_write_iops"]=$seq_write_iops
    DEVICE_RESULTS["${device}_seq_write_lat"]=$seq_write_lat
    
    echo -e "\n${YELLOW}Running sequential read test...${NC}"
    
    add_to_report "### Sequential Read (1GB, 1M blocks)"
    add_to_report ""
    echo '```' >> "$REPORT_FILE"
    
    local read_output=$(fio --name=seq-read \
        --filename=$test_file \
        --size=1G \
        --bs=1M \
        --rw=read \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=4 \
        --group_reporting \
        --output-format=normal 2>&1 | tee /dev/tty)
    
    echo "$read_output" | grep -E "READ:|read:" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    add_to_report ""
    
    # Parse sequential read results
    local seq_read_results=$(parse_fio_output "$read_output" "read")
    IFS='|' read -r seq_read_bw seq_read_iops seq_read_lat <<< "$seq_read_results"
    DEVICE_RESULTS["${device}_seq_read_bw"]=$seq_read_bw
    DEVICE_RESULTS["${device}_seq_read_iops"]=$seq_read_iops
    DEVICE_RESULTS["${device}_seq_read_lat"]=$seq_read_lat
    
    rm -f $test_file
    echo ""
}

# Function to perform random read/write test with fio
fio_random_test() {
    local device=$1
    local test_file="/tmp/fio_random_test_$$"
    
    echo -e "${BLUE}=== FIO Random 4K Read/Write Test ===${NC}"
    echo -e "${YELLOW}Running random write test (4K blocks)...${NC}"
    
    add_to_report "## Random 4K Performance Test"
    add_to_report ""
    add_to_report "### Random Write (512MB, 4K blocks, QD=32)"
    add_to_report ""
    echo '```' >> "$REPORT_FILE"
    
    local rand_write_output=$(fio --name=rand-write \
        --filename=$test_file \
        --size=512M \
        --bs=4k \
        --rw=randwrite \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=32 \
        --group_reporting \
        --output-format=normal 2>&1 | tee /dev/tty)
    
    echo "$rand_write_output" | grep -E "WRITE:|write:" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    add_to_report ""
    
    # Parse random write results
    local rand_write_results=$(parse_fio_output "$rand_write_output" "write")
    IFS='|' read -r rand_write_bw rand_write_iops rand_write_lat <<< "$rand_write_results"
    DEVICE_RESULTS["${device}_rand_write_bw"]=$rand_write_bw
    DEVICE_RESULTS["${device}_rand_write_iops"]=$rand_write_iops
    DEVICE_RESULTS["${device}_rand_write_lat"]=$rand_write_lat
    
    echo -e "\n${YELLOW}Running random read test (4K blocks)...${NC}"
    
    add_to_report "### Random Read (512MB, 4K blocks, QD=32)"
    add_to_report ""
    echo '```' >> "$REPORT_FILE"
    
    local rand_read_output=$(fio --name=rand-read \
        --filename=$test_file \
        --size=512M \
        --bs=4k \
        --rw=randread \
        --direct=1 \
        --numjobs=1 \
        --ioengine=libaio \
        --iodepth=32 \
        --group_reporting \
        --output-format=normal 2>&1 | tee /dev/tty)
    
    echo "$rand_read_output" | grep -E "READ:|read:" >> "$REPORT_FILE"
    echo '```' >> "$REPORT_FILE"
    add_to_report ""
    
    # Parse random read results
    local rand_read_results=$(parse_fio_output "$rand_read_output" "read")
    IFS='|' read -r rand_read_bw rand_read_iops rand_read_lat <<< "$rand_read_results"
    DEVICE_RESULTS["${device}_rand_read_bw"]=$rand_read_bw
    DEVICE_RESULTS["${device}_rand_read_iops"]=$rand_read_iops
    DEVICE_RESULTS["${device}_rand_read_lat"]=$rand_read_lat
    
    rm -f $test_file
    echo ""
}

# Function to perform hdparm test
hdparm_test() {
    local device=$1
    
    echo -e "${BLUE}=== HDParm Buffered Disk Read Test ===${NC}"
    echo -e "${YELLOW}Running hdparm test (3 passes)...${NC}"
    
    add_to_report "## HDParm Buffered Read Test"
    add_to_report ""
    echo '```' >> "$REPORT_FILE"
    
    local hdparm_full_output=""
    for i in {1..3}; do
        local hdparm_output=$(hdparm -t /dev/$device 2>&1 | tee /dev/tty)
        echo "$hdparm_output" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        hdparm_full_output+="$hdparm_output"$'\n'
    done
    
    echo '```' >> "$REPORT_FILE"
    add_to_report ""
    
    # Parse hdparm results
    local hdparm_speed=$(parse_hdparm_output "$hdparm_full_output")
    DEVICE_RESULTS["${device}_hdparm_read"]=$hdparm_speed
    
    echo ""
}

# Function to perform ioping latency test
ioping_test() {
    local device=$1
    local mount_point=$2
    
    echo -e "${BLUE}=== IOPing Latency Test ===${NC}"
    echo -e "${YELLOW}Testing I/O latency (20 requests)...${NC}"
    
    add_to_report "## I/O Latency Test"
    add_to_report ""
    echo '```' >> "$REPORT_FILE"
    
    local ioping_output=$(ioping -c 20 $mount_point 2>&1 | tee /dev/tty)
    echo "$ioping_output" >> "$REPORT_FILE"
    
    echo '```' >> "$REPORT_FILE"
    add_to_report ""
    
    # Parse ioping results
    local ioping_results=$(parse_ioping_output "$ioping_output")
    IFS='|' read -r ioping_lat ioping_iops <<< "$ioping_results"
    DEVICE_RESULTS["${device}_ioping_lat"]=$ioping_lat
    DEVICE_RESULTS["${device}_ioping_iops"]=$ioping_iops
    
    echo ""
}

# Function to add device-specific summary
add_device_summary() {
    local device=$1
    
    add_to_report "---"
    add_to_report ""
    add_to_report "## Test Summary for /dev/$device"
    add_to_report ""
    
    # Get device info for summary
    local model=$(lsblk -d -n -o MODEL /dev/$device 2>/dev/null | xargs)
    local size=$(lsblk -d -n -o SIZE /dev/$device 2>/dev/null | xargs)
    local tran=$(lsblk -d -n -o TRAN /dev/$device 2>/dev/null | xargs)
    
    add_to_report "**Device:** /dev/$device ($model, $size, $tran)"
    add_to_report ""
    
    # Create visual performance table
    add_to_report "### Performance Metrics"
    add_to_report ""
    add_to_report "| Metric | Sequential Read | Sequential Write | Random Read (4K) | Random Write (4K) |"
    add_to_report "|--------|-----------------|------------------|------------------|-------------------|"
    
    # Throughput row
    local seq_read_bw=${DEVICE_RESULTS["${device}_seq_read_bw"]:-0}
    local seq_write_bw=${DEVICE_RESULTS["${device}_seq_write_bw"]:-0}
    local rand_read_bw=${DEVICE_RESULTS["${device}_rand_read_bw"]:-0}
    local rand_write_bw=${DEVICE_RESULTS["${device}_rand_write_bw"]:-0}
    
    add_to_report "| **Throughput (MB/s)** | $seq_read_bw | $seq_write_bw | $rand_read_bw | $rand_write_bw |"
    
    # IOPS row
    local seq_read_iops=${DEVICE_RESULTS["${device}_seq_read_iops"]:-0}
    local seq_write_iops=${DEVICE_RESULTS["${device}_seq_write_iops"]:-0}
    local rand_read_iops=${DEVICE_RESULTS["${device}_rand_read_iops"]:-0}
    local rand_write_iops=${DEVICE_RESULTS["${device}_rand_write_iops"]:-0}
    
    # Format IOPS with K suffix if > 1000
    local seq_read_iops_fmt=$seq_read_iops
    local seq_write_iops_fmt=$seq_write_iops
    local rand_read_iops_fmt=$rand_read_iops
    local rand_write_iops_fmt=$rand_write_iops
    
    if (( $(echo "$seq_read_iops > 1000" | bc -l) )); then
        seq_read_iops_fmt="$(echo "scale=1; $seq_read_iops / 1000" | bc)K"
    fi
    if (( $(echo "$seq_write_iops > 1000" | bc -l) )); then
        seq_write_iops_fmt="$(echo "scale=1; $seq_write_iops / 1000" | bc)K"
    fi
    if (( $(echo "$rand_read_iops > 1000" | bc -l) )); then
        rand_read_iops_fmt="$(echo "scale=1; $rand_read_iops / 1000" | bc)K"
    fi
    if (( $(echo "$rand_write_iops > 1000" | bc -l) )); then
        rand_write_iops_fmt="$(echo "scale=1; $rand_write_iops / 1000" | bc)K"
    fi
    
    add_to_report "| **IOPS** | $seq_read_iops_fmt | $seq_write_iops_fmt | $rand_read_iops_fmt | $rand_write_iops_fmt |"
    
    # Latency row
    local seq_read_lat=${DEVICE_RESULTS["${device}_seq_read_lat"]:-0}
    local seq_write_lat=${DEVICE_RESULTS["${device}_seq_write_lat"]:-0}
    local rand_read_lat=${DEVICE_RESULTS["${device}_rand_read_lat"]:-0}
    local rand_write_lat=${DEVICE_RESULTS["${device}_rand_write_lat"]:-0}
    
    add_to_report "| **Latency (ms)** | $seq_read_lat | $seq_write_lat | $rand_read_lat | $rand_write_lat |"
    
    # Queue depth row
    add_to_report "| **Queue Depth** | 4 | 4 | 32 | 32 |"
    add_to_report ""
    
    # Additional metrics
    add_to_report "### Additional Metrics"
    add_to_report ""
    
    local hdparm_read=${DEVICE_RESULTS["${device}_hdparm_read"]:-0}
    local ioping_lat=${DEVICE_RESULTS["${device}_ioping_lat"]:-0}
    local ioping_iops=${DEVICE_RESULTS["${device}_ioping_iops"]:-0}
    
    add_to_report "- **HDParm Buffered Read:** ${hdparm_read} MB/s"
    add_to_report "- **IOPing Latency:** ${ioping_lat} ms"
    if [ "$ioping_iops" != "0" ]; then
        add_to_report "- **IOPing IOPS:** ${ioping_iops}"
    fi
    add_to_report ""
    
    # Performance rating
    add_to_report "### Performance Rating"
    add_to_report ""
    
    # Determine device type based on performance
    local rating=""
    local device_type=""
    
    if (( $(echo "$seq_read_bw > 4000" | bc -l) )); then
        device_type="NVMe Gen4 SSD"
        rating="Excellent (5/5 stars)"
    elif (( $(echo "$seq_read_bw > 2500" | bc -l) )); then
        device_type="NVMe Gen3 SSD"
        rating="Very Good (4/5 stars)"
    elif (( $(echo "$seq_read_bw > 400" | bc -l) )); then
        device_type="SATA SSD"
        rating="Good (3/5 stars)"
    elif (( $(echo "$seq_read_bw > 100" | bc -l) )); then
        device_type="7200 RPM HDD or USB 3.0"
        rating="Moderate (2/5 stars)"
    else
        device_type="Older HDD or USB 2.0"
        rating="Basic (1/5 stars)"
    fi
    
    add_to_report "**Detected Type:** $device_type  "
    add_to_report "**Overall Rating:** $rating"
    add_to_report ""
    
    # Visual performance bars
    add_to_report "### Visual Performance Comparison"
    add_to_report ""
    
    # Create bars using ASCII characters that LaTeX supports
    local seq_read_bar=""
    local width=50
    local filled=$(echo "scale=0; ($seq_read_bw * $width) / 7000" | bc)
    if (( filled > width )); then filled=$width; fi
    if (( filled < 0 )); then filled=0; fi
    for ((i=0; i<filled; i++)); do seq_read_bar+="#"; done
    for ((i=filled; i<width; i++)); do seq_read_bar+="-"; done
    
    add_to_report "**Sequential Read Speed:**  "
    add_to_report "\`$seq_read_bar\` ${seq_read_bw} MB/s"
    add_to_report ""
    
    local seq_write_bar=""
    filled=$(echo "scale=0; ($seq_write_bw * $width) / 7000" | bc)
    if (( filled > width )); then filled=$width; fi
    if (( filled < 0 )); then filled=0; fi
    for ((i=0; i<filled; i++)); do seq_write_bar+="#"; done
    for ((i=filled; i<width; i++)); do seq_write_bar+="-"; done
    
    add_to_report "**Sequential Write Speed:**  "
    add_to_report "\`$seq_write_bar\` ${seq_write_bw} MB/s"
    add_to_report ""
    
    local rand_read_bar=""
    filled=$(echo "scale=0; ($rand_read_iops * $width) / 1000000" | bc)
    if (( filled > width )); then filled=$width; fi
    if (( filled < 0 )); then filled=0; fi
    for ((i=0; i<filled; i++)); do rand_read_bar+="#"; done
    for ((i=filled; i<width; i++)); do rand_read_bar+="-"; done
    
    add_to_report "**Random Read IOPS:**  "
    add_to_report "\`$rand_read_bar\` ${rand_read_iops_fmt}"
    add_to_report ""
    
    local rand_write_bar=""
    filled=$(echo "scale=0; ($rand_write_iops * $width) / 1000000" | bc)
    if (( filled > width )); then filled=$width; fi
    if (( filled < 0 )); then filled=0; fi
    for ((i=0; i<filled; i++)); do rand_write_bar+="#"; done
    for ((i=filled; i<width; i++)); do rand_write_bar+="-"; done
    
    add_to_report "**Random Write IOPS:**  "
    add_to_report "\`$rand_write_bar\` ${rand_write_iops_fmt}"
    add_to_report ""
}

# Function to run complete benchmark suite
run_benchmark() {
    local device=$1
    local mount_point=$2
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Starting benchmark for /dev/$device${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    add_to_report "---"
    add_to_report ""
    add_to_report "\\newpage"
    add_to_report ""
    
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
        ioping_test $device $temp_mount
        
        # Change to the mount point for fio tests
        cd $temp_mount
        fio_sequential_test $device
        fio_random_test $device
        cd - > /dev/null
    else
        echo -e "${RED}Cannot write to mount point. Skipping fio and ioping tests.${NC}\n"
        add_to_report "*Note: Write tests skipped - insufficient permissions on mount point*"
        add_to_report ""
    fi
    
    # Add device summary to report
    add_device_summary $device
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Benchmark completed for /dev/$device${NC}"
    echo -e "${GREEN}========================================${NC}\n"
}

# Function to generate PDF report
generate_pdf_report() {
    local output_dir="${1:-$HOME}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    REPORT_PDF="$output_dir/storage_benchmark_report_$timestamp.pdf"
    
    echo -e "${YELLOW}Generating PDF report...${NC}"
    
    # Add final summary comparing all devices at the end
    add_to_report "---"
    add_to_report ""
    add_to_report "\\newpage"
    add_to_report ""
    add_to_report "# Overall Summary"
    add_to_report ""
    add_to_report "## All Devices Performance Comparison"
    add_to_report ""
    
    # Create comparison table for all tested devices
    add_to_report "| Device | Sequential Read | Sequential Write | Random Read (4K) | Random Write (4K) | Rating |"
    add_to_report "|--------|-----------------|------------------|------------------|-------------------|--------|"
    
    for dev in "${test_devices[@]}"; do
        local seq_read_bw=${DEVICE_RESULTS["${dev}_seq_read_bw"]:-0}
        local seq_write_bw=${DEVICE_RESULTS["${dev}_seq_write_bw"]:-0}
        local rand_read_iops=${DEVICE_RESULTS["${dev}_rand_read_iops"]:-0}
        local rand_write_iops=${DEVICE_RESULTS["${dev}_rand_write_iops"]:-0}
        
        # Format IOPS
        local rand_read_display=$rand_read_iops
        local rand_write_display=$rand_write_iops
        
        if (( $(echo "$rand_read_iops > 1000" | bc -l) )); then
            rand_read_display="$(echo "scale=1; $rand_read_iops / 1000" | bc)K IOPS"
        else
            rand_read_display="$rand_read_iops IOPS"
        fi
        
        if (( $(echo "$rand_write_iops > 1000" | bc -l) )); then
            rand_write_display="$(echo "scale=1; $rand_write_iops / 1000" | bc)K IOPS"
        else
            rand_write_display="$rand_write_iops IOPS"
        fi
        
        # Determine rating
        local stars=""
        if (( $(echo "$seq_read_bw > 4000" | bc -l) )); then
            stars="5/5"
        elif (( $(echo "$seq_read_bw > 2500" | bc -l) )); then
            stars="4/5"
        elif (( $(echo "$seq_read_bw > 400" | bc -l) )); then
            stars="3/5"
        elif (( $(echo "$seq_read_bw > 100" | bc -l) )); then
            stars="2/5"
        else
            stars="1/5"
        fi
        
        add_to_report "| /dev/$dev | ${seq_read_bw} MB/s | ${seq_write_bw} MB/s | ${rand_read_display} | ${rand_write_display} | $stars |"
    done
    
    add_to_report ""
    add_to_report "## Performance Interpretation Guide"
    add_to_report ""
    add_to_report "| Device Type | Sequential Read | Random 4K Read | Typical Latency |"
    add_to_report "|------------|----------------|----------------|-----------------|"
    add_to_report "| 7200 RPM HDD | 150-200 MB/s | 100-200 IOPS | 10-20ms |"
    add_to_report "| SATA SSD | 500-550 MB/s | 80K-100K IOPS | 0.1-0.5ms |"
    add_to_report "| NVMe Gen3 | 3000-3500 MB/s | 400K-600K IOPS | 0.05-0.1ms |"
    add_to_report "| NVMe Gen4 | 5000-7000 MB/s | 700K-1M IOPS | 0.02-0.05ms |"
    add_to_report "| USB 3.0 Flash | 100-400 MB/s | 1K-10K IOPS | 1-10ms |"
    add_to_report ""
    add_to_report "## Test Parameters"
    add_to_report ""
    add_to_report "- **Sequential Tests:** 1GB file size, 1MB block size, queue depth 4"
    add_to_report "- **Random Tests:** 512MB file size, 4KB block size, queue depth 32"
    add_to_report "- **Latency Tests:** 20 I/O operations"
    add_to_report "- **HDParm Tests:** 3 consecutive buffered read tests"
    add_to_report ""
    
    # Generate PDF using pandoc
    echo -e "${YELLOW}Converting markdown to PDF...${NC}"
    
    local pandoc_error=$(mktemp)
    if pandoc "$REPORT_FILE" -o "$REPORT_PDF" --pdf-engine=pdflatex 2>"$pandoc_error"; then
        echo -e "${GREEN}✓ PDF report generated successfully!${NC}"
        echo -e "${GREEN}Location: $REPORT_PDF${NC}\n"
        
        # Try to open the PDF
        if command -v xdg-open &> /dev/null; then
            read -p "Would you like to open the report now? (yes/no): " open_pdf
            if [ "$open_pdf" == "yes" ]; then
                xdg-open "$REPORT_PDF" 2>/dev/null &
            fi
        fi
        rm -f "$pandoc_error"
    else
        echo -e "${RED}Failed to generate PDF.${NC}"
        echo -e "${YELLOW}Error details:${NC}"
        cat "$pandoc_error"
        echo ""
        echo -e "${YELLOW}Markdown report available at: $REPORT_FILE${NC}"
        echo -e "${YELLOW}You can manually convert it with: pandoc $REPORT_FILE -o output.pdf${NC}\n"
        
        # Keep the markdown file for debugging
        local markdown_backup="$output_dir/storage_benchmark_report_$timestamp.md"
        cp "$REPORT_FILE" "$markdown_backup"
        echo -e "${GREEN}Markdown backup saved to: $markdown_backup${NC}\n"
        
        rm -f "$pandoc_error"
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "$REPORT_DIR"
}

# Main script execution
main() {
    # Install required packages
    install_packages
    
    # Initialize report
    init_report
    
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
    
    # Ask for output directory
    echo ""
    read -p "Enter output directory for PDF report [default: $HOME]: " output_dir
    output_dir="${output_dir:-$HOME}"
    
    # Validate output directory
    if [ ! -d "$output_dir" ]; then
        echo -e "${RED}Directory does not exist: $output_dir${NC}"
        exit 1
    fi
    
    if [ ! -w "$output_dir" ]; then
        echo -e "${RED}Cannot write to directory: $output_dir${NC}"
        exit 1
    fi
    
    echo ""
    
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
    
    echo -e "${GREEN}All benchmarks completed!${NC}\n"
    
    # Generate PDF report
    generate_pdf_report "$output_dir"
}

# Run main function
main
