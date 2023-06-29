package sysinfo

foreign {
	statvfs :: proc(path: cstring, stat: ^Sys_statvfs) ---
}
