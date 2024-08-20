package systeminfo

import c "core:c/libc"

@(default_calling_convention = "c")
foreign {
	gethostname :: proc(hostname: ^[1024]u8, namelen: c.int) -> c.int ---
}
