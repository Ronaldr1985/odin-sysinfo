package sysinfo

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"

read_entire_file_from_filename :: proc(name: string, allocator := context.allocator) -> ([]byte, bool) {
	context.allocator = allocator

	fd, err := os.open(name, os.O_RDONLY, 0)
	if err != 0 {
	    return nil, false
	}
	defer os.close(fd)

	return read_entire_file_from_handle(fd, allocator)
}

read_entire_file_from_handle :: proc(fd: os.Handle, allocator := context.allocator) -> ([]byte, bool) {
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

get_hostname :: proc() -> (string, bool) {
	data, ok := read_entire_file_from_filename("/proc/sys/kernel/hostname")

	return string(data), ok
}

get_key :: proc(s: string) -> (string, bool) {
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
		key, key_ok := get_key(s[0])
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

	if meminfo_bytes, ok = read_entire_file_from_filename("/proc/meminfo"); !ok {
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

get_total_physical_memory_bytes :: proc() -> (total_physical_memory: f64, ok: bool) {
	meminfo_bytes: []byte

	if meminfo_bytes, ok = read_entire_file_from_filename("/proc/meminfo"); !ok {
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

get_cpu_name :: proc() -> (string, bool) {
	cpuinfo_bytes: []byte
	ok: bool

	if cpuinfo_bytes, ok = read_entire_file_from_filename("/proc/cpuinfo"); !ok {
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
	data, ok := read_entire_file_from_filename("/proc/cpuinfo")
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
	data, ok := read_entire_file_from_filename("/proc/stat")
	if !ok {
		fmt.fprintln(os.stderr, "Issue whilst passing /proc/stat")
		return 0, false
	}

	a, b: [4]f64
	i: int = 0
	fields: []string
	data_str := string(data)

	for line in strings.split_lines_iterator(&data_str) {
		fields = strings.fields(line)
		if i < 4 {
			a[i] = strconv.atof(fields[i])
		} else if i >= 4 {
			b[i-4] = strconv.atof(fields[i-4])
		}
		i+=1
	}

	fmt.println("a: ", a)
	fmt.println("b: ", b)

	return (100 * ((b[0]+b[1]+b[2]) - (a[0]+a[1]+a[2])) / ((b[0]+b[1]+b[2]+b[3]) - (a[0]+a[1]+a[2]+a[3]))), true
}

get_mountpoint_total_gb(mountpoint: string) -> (total: f64, ok: bool) {


	return
}
