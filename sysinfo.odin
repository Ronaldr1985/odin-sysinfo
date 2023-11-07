package sysinfo

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:runtime"
import "core:time"
import "core:unicode"

@(private)
__read_entire_file_from_filename :: proc(name: string, allocator := context.allocator) -> ([]byte, bool) {
	context.allocator = allocator

	fd, err := os.open(name, os.O_RDONLY, 0)
	if err != 0 {
	    return nil, false
	}
	defer os.close(fd)

	return __read_entire_file_from_handle(fd, allocator)
}

@(private)
__read_entire_file_from_handle :: proc(fd: os.Handle, allocator := context.allocator) -> ([]byte, bool) {
	context.allocator = allocator

	length: i64
	err: os.Errno
	if length, err = os.file_size(fd); err != 0 {
	    return nil, false
	}

	BLOCK_SIZE :: 4096

	length = max(length, BLOCK_SIZE)

	_data: [dynamic]byte
	read_err:   os.Errno
	bytes_read, bytes_total: int

	resize(&_data, int(length))

	for {
		bytes_read, read_err = os.read(fd, _data[bytes_total:])
		if bytes_read == 0 {
			break
		}

		bytes_total += bytes_read
		resize(&_data, bytes_total + BLOCK_SIZE)
	}

	return _data[:bytes_total], true
}

@(private)
__get_key :: proc(s: string) -> (string, bool) {
	if len(s) > 1 && s[len(s) - 1] == ':' {
		// Yes, this ends in a colon and is a key
		return s[:len(s) - 1], true
	}
	return s, false
}

parse_meminfo :: proc(meminfo: string) -> (map[string]f64, bool) {
	s := strings.fields(meminfo)
	orig := s
	defer delete(orig)

	values: map[string]f64

	last_key := ""

	for len(s) > 0 {
		key, key_ok := __get_key(s[0])
		if !key_ok {
			// Must've been a suffix, so let's multiply the last value
			switch key {
			case "kB":
			    values[last_key] *= 1024

			}
			s = s[1:]
			continue
		}
		s = s[1:] // Advance

		if val, val_ok := strconv.parse_f64(s[0]); !val_ok {
			break
		} else {
			values[key] = val
			s = s[1:]
		}
		last_key = key
	}
	return values, true
}

get_ram_usage_perc :: proc() -> (f64, bool) {
	meminfo_bytes: []byte
	ok: bool

	if meminfo_bytes, ok = __read_entire_file_from_filename("/proc/meminfo"); !ok {
		fmt.fprintln(os.stderr, "Failed to open file, meminfo")
		os.exit(1)
	}
	defer delete(meminfo_bytes)

	meminfo_map, parse_meminfo_ok := parse_meminfo(string(meminfo_bytes))
	if !parse_meminfo_ok {
		fmt.fprintln(os.stderr, "Issue whilst parsing data from meminfo")
		os.exit(1)
	}
	defer delete(meminfo_map)

	total := meminfo_map["MemTotal"]
	free := meminfo_map["MemFree"]
	buffers := meminfo_map["Buffers"]
	cached := meminfo_map["Cached"]
	used := total - free
	buffers_and_cached := buffers + cached

	return 100 * (((total - free) - (buffers + cached)) / total), true
}

get_hostname :: proc() -> (string, bool) {
	data, ok := __read_entire_file_from_filename("/proc/sys/kernel/hostname")

	hostname: string
	hostname, ok = strings.remove_all(string(data), "\n")

	return hostname, ok
}

@(private)
parse_cpuinfo :: proc(cpuinfo: string) -> (map[string]string, bool) {
	cpuinfo_string: string = cpuinfo
    values: map[string]string
	key, value: string

	for line in strings.split_lines_iterator(&cpuinfo_string) {
		key, _, value = strings.partition(line, ":")
		values[strings.trim_space(key)] = strings.trim_space(value)
	}

	return values, true
}

// FIXME: This is a bodge
get_cpu_name_and_socket_number :: proc() -> (string, int, bool) {
	cpuinfo_bytes: []byte
	ok: bool

	if cpuinfo_bytes, ok = __read_entire_file_from_filename("/proc/cpuinfo"); !ok {
		return "", 0, false
	}
	defer delete(cpuinfo_bytes)

	cpuinfo_map, parse_cpuinfo_ok := parse_cpuinfo(string(cpuinfo_bytes))
	if !parse_cpuinfo_ok {
		return "", 0, false
	}
	defer delete(cpuinfo_map)

	return cpuinfo_map["model name"], strconv.atoi(cpuinfo_map["physical id"]), true
}

get_cpu_name :: proc() -> (string, bool) {
	cpuinfo_bytes: []byte
	ok: bool

	if cpuinfo_bytes, ok = __read_entire_file_from_filename("/proc/cpuinfo"); !ok {
		fmt.fprintln(os.stderr, "Failed to open file, cpuinfo")
		os.exit(1)
	}
	defer delete(cpuinfo_bytes)

	cpuinfo_map, parse_cpuinfo_ok := parse_cpuinfo(string(cpuinfo_bytes))
	if !parse_cpuinfo_ok {
		fmt.fprintln(os.stderr, "Issue whilst parsing data from cpuinfo")
		os.exit(1)
	}
	defer delete(cpuinfo_map)

	return cpuinfo_map["model name"], true
}

get_numb_cpu_cores :: proc() -> (int, bool) {
	data, ok := __read_entire_file_from_filename("/proc/cpuinfo")
	if !ok {
		fmt.fprintln(os.stderr, "Failed to open file, cpuinfo")
		os.exit(1)
	}
	defer delete(data)

	cpuinfo_map, parse_cpuinfo_ok := parse_cpuinfo(string(data))
	if !parse_cpuinfo_ok {
		fmt.fprintln(os.stderr, "Issue whilst parsing data from cpuinfo")
		os.exit(1)
	}
	defer delete(cpuinfo_map)

	return strconv.parse_int(cpuinfo_map["cpu cores"])
}

get_cpu_usage_perc :: proc() -> (f64, bool) {
	a, b: [10]f64
	i := 0
	fields: []string

	data, ok := __read_entire_file_from_filename("/proc/stat")
	if !ok {
		fmt.fprintln(os.stderr, "Issue whilst passing /proc/stat")
		return 0, false
	}

	data_str := string(data)

	fields = strings.fields(data_str[:strings.index(data_str, "\n")])
	for field in fields {
		if !strings.contains(field, "cpu") {
			a[i] = strconv.atof(field)
			i += 1
		}
	}

	time.sleep(time.Millisecond * 200)

	i = 0
	data, ok = __read_entire_file_from_filename("/proc/stat")
	if !ok {
		fmt.fprintln(os.stderr, "Issue whilst passing /proc/stat")
		return 0, false
	}
	data_str = string(data)

	fields = strings.fields(data_str[:strings.index(data_str, "\n")])
	for field in fields {
		if !strings.contains(field, "cpu") {
			b[i] = strconv.atof(field)
			i += 1
		}
	}

	return (100 * ((b[0]+b[1]+b[2]) - (a[0]+a[1]+a[2])) / ((b[0]+b[1]+b[2]+b[3]) - (a[0]+a[1]+a[2]+a[3]))), true
}

get_total_physical_memory_bytes :: proc() -> (total_physical_memory: f64, ok: bool) {
	meminfo_bytes: []byte

	if meminfo_bytes, ok = __read_entire_file_from_filename("/proc/meminfo"); !ok {
		fmt.fprintln(os.stderr, "Failed to open file, meminfo")
		os.exit(1)
	}
	defer delete(meminfo_bytes)

	meminfo_map, parse_meminfo_ok := parse_meminfo(string(meminfo_bytes))
	if !parse_meminfo_ok {
		fmt.fprintln(os.stderr, "Issue whilst parsing data from meminfo")
		os.exit(1)
	}
	defer delete(meminfo_map)

	total_physical_memory = meminfo_map["MemTotal"]

	return
}

get_mountpoint_total_gb :: proc(mountpoint: string) -> f64 {
	mountpoint_statvfs: Sys_statvfs

	mountpoint_cstr := strings.clone_to_cstring(mountpoint, context.temp_allocator)

	err := statvfs(mountpoint_cstr, &mountpoint_statvfs)
	if err != 0 {
		return 0
	}

	return (f64(mountpoint_statvfs.f_blocks) * f64(mountpoint_statvfs.f_bsize)) / 1073741824
}

get_mountpoint_available_gb :: proc(mountpoint: string) -> f64 {
	mountpoint_statvfs: Sys_statvfs

	mountpoint_cstr := strings.clone_to_cstring(mountpoint, context.temp_allocator)

	statvfs(mountpoint_cstr, &mountpoint_statvfs)

	return (f64(mountpoint_statvfs.f_bfree) * f64(mountpoint_statvfs.f_bsize)) / 1073741824
}

get_mountpoint_used_gb :: proc(mountpoint: string) -> f64 {
	mountpoint_statvfs: Sys_statvfs

	mountpoint_cstr := strings.clone_to_cstring(mountpoint, context.temp_allocator)

	statvfs(mountpoint_cstr, &mountpoint_statvfs)

	return (f64(mountpoint_statvfs.f_blocks) * f64(mountpoint_statvfs.f_bsize) - (f64(mountpoint_statvfs.f_bfree) * f64(mountpoint_statvfs.f_bsize))) / 1073741824
}

get_mountpoint_available_perc :: proc(mountpoint: string) -> f64 {
	return (get_mountpoint_available_gb(mountpoint)/get_mountpoint_total_gb(mountpoint)) * 100
}

get_mountpoint_used_perc :: proc(mountpoint: string) -> f64 {
	return (get_mountpoint_used_gb(mountpoint)/get_mountpoint_total_gb(mountpoint)) * 100
}

@(private)
__parse_partitions :: proc(partitions: string) -> (map[string]Partition, bool) {
	err: runtime.Allocator_Error
	fields: []string
	ok: bool
	partition: Partition
    values: map[string]Partition
	partitions_string := partitions

	for line in strings.split_lines_iterator(&partitions_string) {
		if len(line) > 0 && !strings.contains(line, "major") {
			fields = strings.fields(line)
			defer delete(fields)

			partition.major = strconv.atoi(fields[0])
			partition.minor = strconv.atoi(fields[1])
			partition.blocks, ok = strconv.parse_f64(fields[2])
			if !ok {
				return nil, false
			}
			partition.name = fields[3]

			values[fields[3]] = partition
		}
	}

	return values, true
}

get_disk_size_bytes :: proc(disk_name: string) -> (f64, bool) {
	partitions_bytes: []byte
	ok: bool

	if partitions_bytes, ok = __read_entire_file_from_filename("/proc/partitions"); !ok {
		return 0, false
	}
	defer delete(partitions_bytes)

	partitions_map, parse_partitions_ok := __parse_partitions(string(partitions_bytes))
	if !parse_partitions_ok {
		return 0, false
	}
	defer delete(partitions_map)

	return partitions_map[disk_name].blocks / 1024, true
}
