package sysinfo

import c "core:c/libc"

@(default_calling_convention = "c")
foreign {
	statvfs :: proc(path: cstring, stat: ^Sys_statvfs) -> c.int ---
}
