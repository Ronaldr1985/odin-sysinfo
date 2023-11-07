package sysinfo

import c "core:c/libc"

Sys_statvfs :: struct {
	f_bsize:    c.ulong,
	f_frsize:   c.ulong,
	f_blocks:   c.ulong,
	f_bfree:    c.ulong,
	f_bavail:   c.ulong,

	f_files:    c.ulong,
	f_ffree:    c.ulong,
	f_favail:   c.ulong,

	f_fsid:     c.ulong,
	f_flag:     c.ulong,
	f_namemax:  c.ulong,

	__f_spare:  [6]c.int
}

Partition :: struct {
	major: int,
	minor: int,
	blocks: f64,
	name: string
}

Process :: struct {
	name: string,
	command: string,
	pid: int,
	cpu_usage: int,
	memory_usage: int,
}
