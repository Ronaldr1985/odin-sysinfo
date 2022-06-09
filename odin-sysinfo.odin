package main

import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:unicode"


read_entire_file_from_filename :: proc(name: string, allocator := context.allocator) -> (data: []byte, success: bool) {
    context.allocator = allocator

    fd, err := os.open(name, os.O_RDONLY, 0)
    if err != 0 {
        return nil, false
    }
    defer os.close(fd)

    return read_entire_file_from_handle(fd, allocator)
}

read_entire_file_from_handle :: proc(fd: os.Handle, allocator := context.allocator) -> (data: []byte, success: bool) {
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

before :: proc(str, substr: string, index: int) -> (output: string, ok: bool) {
	pos: int = 0
	test_str := str

	if strings.count(str, substr) < index {
		return "", false
	}

	for counter := 0; counter < index; counter += 1 {
		pos = strings.index(test_str, substr)
		test_str, _ = strings.remove(str, substr, counter)
	}
	fmt.printf("Test: \"%s\"\n", test_str[:pos])

	return str[:pos+1], true
}

get_key :: proc(s: string) -> (res: string, ok: bool) {
    if len(s) > 1 && s[len(s) - 1] == ':' {
        // Yes, this ends in a colon and is a key
        return s[:len(s) - 1], true
    }
    return s, false
}

parse_meminfo :: proc(meminfo: string) -> (meminfo_map: map[string]f64, ok: bool) {
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

write_version :: proc() {
	fmt.printf("dof 0.1\nLicense BSD-2-Clause\n\nWritten by Ronald 1985.\n")

    os.exit(0)
}

main :: proc() {
	mem_usage_perc: f64
	ok: bool
	str2: string
	str := "Test\nPrint this\nRemove"

	str2, ok = before(str, "\n", 2)

	if ok {
		fmt.println("\nAfter function")
		fmt.printf("\"%s\"\n", str2)
	}


	// for {
	// 	if mem_usage_perc, ok = get_ram_usage_perc(); !ok {
	// 		fmt.fprintln(os.stderr, "Failed to read memory usage")
	// 	}
	// 	time.accurate_sleep(1000000000)
	// 	fmt.printf("mem perc: %.1f%%\n", mem_usage_perc)

	// 	time.accurate_sleep(1000000000)

	// }
}

