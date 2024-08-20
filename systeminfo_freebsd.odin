package systeminfo

import "core:fmt"
import c "core:c/libc"
import "core:strings"
import "core:sys/unix"

get_hostname :: proc() -> (hostname: string, ok: bool) #optional_ok {
	ok = true

	hostname_array: [1024]u8
	err := gethostname(&hostname_array, i32(1023))
	if err != 0 {
		ok = false
		return
	}

	hostname = strings.clone(string(hostname_array[:]))

	return
}

get_system_uptime_in_seconds :: proc() -> (int, bool) {
	tp: unix.timespec

	result := unix.clock_gettime(unix.CLOCK_MONOTONIC_RAW, &tp)
	if result != 0 {
		return 0, false
	}

	return int(tp.tv_sec), true
}

