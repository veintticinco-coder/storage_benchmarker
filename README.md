# Storage Device Benchmark Script

A comprehensive benchmarking tool for testing the performance of storage devices (SD cards, NVMe drives, USB drives, SSDs, and HDDs) on Debian-based Linux systems.

## Overview

This script automates the installation of benchmarking tools and performs a complete suite of tests to measure storage device performance, including sequential and random I/O operations, read/write speeds, IOPS, and latency.

## Features

- **Automatic Dependency Installation** - Installs all required benchmarking tools automatically
- **Device Auto-Detection** - Scans and lists all available storage devices with detailed information
- **Multiple Benchmark Tests**:
  - HDParm buffered disk read tests
  - IOPing latency measurements
  - FIO sequential read/write (large blocks)
  - FIO random 4K read/write (real-world simulation)
- **Interactive Device Selection** - Choose specific devices or test all at once
- **Detailed Device Information** - Shows model, serial, connection type, size, and SMART health status
- **Safe Operation** - Uses temporary test files without modifying existing data

## Requirements

- **Operating System**: Debian, Ubuntu, or other Debian-based distributions
- **Privileges**: Root access (sudo)
- **Disk Space**: At least 2GB free space on the device being tested
- **Time**: 5-15 minutes per device depending on device speed

## Installation

### Download and Setup

```bash
# Download the script
wget https://your-url/storage_benchmark.sh
# Or create it manually with your text editor

# Make it executable
chmod +x storage_benchmark.sh
```

### Dependencies

The script will automatically install these packages if not present:

- `fio` - Flexible I/O Tester for comprehensive benchmarking
- `hdparm` - Get/set hard disk parameters
- `ioping` - Simple disk I/O latency monitoring tool
- `sysstat` - Performance monitoring tools
- `smartmontools` - Control and monitor storage systems using SMART
- `lshw` - Hardware lister
- `util-linux` - Miscellaneous system utilities

## Usage

### Basic Usage

```bash
sudo ./storage_benchmark.sh
```

### Step-by-Step Process

1. **Package Installation**: The script checks and installs required tools
2. **Device List**: All detected storage devices are displayed with details
3. **Device Selection**: Choose which devices to benchmark:
   - Enter `0` to test all devices
   - Enter specific numbers (e.g., `1,3,5`) to test selected devices
4. **Confirmation**: Review selections and confirm to proceed
5. **Benchmarking**: Tests run automatically with progress indicators
6. **Results**: Performance metrics are displayed for each test

### Example Session

```
=== Available Storage Devices ===

NAME   SIZE   TYPE MOUNTPOINT MODEL              TRAN
sda    1.8T   disk            WDC WD20EZRZ       sata
sdb    500G   disk /          Samsung SSD 860    sata
nvme0n1 1T    disk /home      Samsung SSD 980    nvme

Select devices to benchmark:
0) All devices
1) sda - 1.8T WDC WD20EZRZ sata
2) sdb - 500G Samsung SSD 860 sata
3) nvme0n1 - 1T Samsung SSD 980 nvme

Enter selection: 2,3
```

## Benchmark Tests Explained

### 1. HDParm Test
- **Purpose**: Measures buffered disk read performance
- **Method**: Three consecutive read tests
- **Typical Results**: 
  - HDD: 80-200 MB/s
  - SATA SSD: 400-550 MB/s
  - NVMe SSD: 1500-7000 MB/s

### 2. IOPing Test
- **Purpose**: Measures disk I/O latency
- **Duration**: 20 requests
- **Typical Results**:
  - HDD: 10-20ms
  - SATA SSD: 0.1-0.5ms
  - NVMe SSD: 0.02-0.1ms

### 3. FIO Sequential Test
- **Purpose**: Tests large file read/write performance
- **Parameters**: 1GB file, 1MB block size
- **Use Case**: Video editing, large file transfers
- **Typical Results**:
  - HDD: 100-200 MB/s
  - SATA SSD: 450-550 MB/s
  - NVMe SSD: 2000-7000 MB/s

### 4. FIO Random 4K Test
- **Purpose**: Tests real-world random access performance
- **Parameters**: 512MB file, 4KB blocks, queue depth 32
- **Use Case**: Database operations, OS responsiveness
- **Typical Results** (IOPS):
  - HDD: 100-200 IOPS
  - SATA SSD: 50,000-100,000 IOPS
  - NVMe SSD: 300,000-1,000,000+ IOPS

## Understanding the Results

### Key Metrics

- **Bandwidth (MB/s)**: Amount of data transferred per second
- **IOPS**: Input/Output Operations Per Second - critical for random access
- **Latency**: Time delay for each I/O operation
- **Sequential vs Random**: Sequential is for large files, random mimics real usage

### Performance Expectations

| Device Type | Sequential Read | Random 4K Read | Latency |
|------------|----------------|----------------|---------|
| 7200 RPM HDD | 150-200 MB/s | 100-200 IOPS | 10-20ms |
| SATA SSD | 500-550 MB/s | 80K-100K IOPS | 0.1-0.5ms |
| NVMe Gen3 | 3000-3500 MB/s | 400K-600K IOPS | 0.05-0.1ms |
| NVMe Gen4 | 5000-7000 MB/s | 700K-1M IOPS | 0.02-0.05ms |
| USB 3.0 Flash | 100-400 MB/s | 1K-10K IOPS | 1-10ms |

## Safety and Warnings

### Safe Operations
- ✅ Script creates temporary test files only
- ✅ No modification of existing data
- ✅ Test files are automatically cleaned up
- ✅ Requires explicit user confirmation

### Cautions
- ⚠️ Intensive I/O operations may temporarily slow system
- ⚠️ Tests generate heat - ensure adequate cooling
- ⚠️ Not recommended on devices near failure (check SMART status first)
- ⚠️ USB devices on slow controllers may take longer

### Recommendations
- Close other applications during testing
- Don't benchmark your system drive while running critical applications
- Ensure at least 2GB free space on test devices
- Let the device cool between multiple test runs

## Troubleshooting

### Permission Denied
```bash
# Make sure to run with sudo
sudo ./storage_benchmark.sh
```

### Device Not Found
- Verify device is properly connected
- Check if device is recognized: `lsblk`
- For USB devices, try replugging

### fio Errors
```bash
# Ensure you have write permissions on mount point
# or test an unmounted device (script uses /tmp)
```

### SMART Not Available
- Some USB adapters don't pass through SMART data
- Virtual machines may not support SMART
- This is informational only and doesn't affect benchmarks

## Output Interpretation

### Good Performance Indicators
- Sequential read/write speeds match manufacturer specifications
- Low latency (< 1ms for SSDs, < 20ms for HDDs)
- High IOPS for random operations (SSDs)
- Consistent results across multiple runs

### Performance Issues
- Speeds significantly below specifications (> 30% lower)
- High latency spikes
- Decreasing performance during test
- SMART health warnings

### Next Steps for Poor Performance
1. Check SMART status for drive health issues
2. Verify proper connection (SATA cable, USB port)
3. Update firmware if available
4. Check for thermal throttling
5. Test with different cables/ports

## Advanced Usage

### Testing Specific Partitions
The script tests entire devices. To test specific partitions:
```bash
# Manually run fio on a partition
fio --name=test --filename=/path/to/testfile --size=1G --rw=write --bs=1M --direct=1
```

### Custom Test Parameters
Edit the script's fio commands to adjust:
- `--size`: Test file size
- `--bs`: Block size
- `--iodepth`: Queue depth
- `--numjobs`: Number of parallel jobs

### Automated Testing
```bash
# Run with automatic "yes" confirmation (use with caution)
yes "yes" | sudo ./storage_benchmark.sh
```

## Contributing

Suggestions and improvements are welcome! Common enhancement ideas:
- Additional benchmark tools (bonnie++, dd)
- CSV/JSON output format
- Graphical result visualization
- Historical comparison tracking

## License

This script is provided as-is for educational and diagnostic purposes. Use at your own risk.

## Changelog

### Version 1.0
- Initial release
- Support for HDDs, SSDs, NVMe, USB, and SD cards
- Automatic package installation
- Interactive device selection
- Comprehensive benchmark suite

## Support

For issues or questions:
1. Check the Troubleshooting section above
2. Verify all dependencies are installed correctly
3. Ensure you have sufficient permissions and disk space
4. Review system logs: `dmesg` and `/var/log/syslog`

## References

- [fio Documentation](https://fio.readthedocs.io/)
- [hdparm Manual](https://linux.die.net/man/8/hdparm)
- [Understanding IOPS](https://en.wikipedia.org/wiki/IOPS)
- [SMART Monitoring](https://www.smartmontools.org/)
