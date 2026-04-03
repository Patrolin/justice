package lib
import "base:intrinsics"
import "core:bytes"

// ascii, NOTE: we need to be able to run this on utf8 strings!
@(private)
_AsciiBitset :: distinct [4]u64
make_ascii_bitset :: #force_inline proc "c" (ascii_chars: string) -> (set: _AsciiBitset) {
	for i in 0 ..< len(ascii_chars) {
		c := ascii_chars[i]
		set[c >> 6] |= 1 << uint(c & 63)
	}
	return
}

index_ascii_char :: proc "c" (str: string, start: int, ascii_char: byte) -> (middle: int) {
	i := start
	for i < len(str) && str[i] != ascii_char {i += 1}
	return i
}
index_not_ascii_char :: proc "c" (str: string, start: int, ascii_char: byte) -> (middle: int) {
	i := start
	for i < len(str) && str[i] == ascii_char {i += 1}
	return i
}
last_index_ascii_char :: proc "c" (str: string, ascii_char: byte) -> (start: int) {
	i := len(str)
	for i >= 0 && str[i] != ascii_char {i += 1}
	return i
}
index_ascii :: proc "c" (str: string, start: int, ascii_chars: string) -> (middle: int) {
	set := make_ascii_bitset(ascii_chars)
	for i in start ..< len(str) {
		c := str[i]
		if set[c >> 6] & (1 << (c & 63)) != 0 {return i}
	}
	return len(str)
}
index_not_ascii :: proc "c" (str: string, start: int, ascii_chars: string) -> (middle: int) {
	set := make_ascii_bitset(ascii_chars)
	for i in start ..< len(str) {
		c := str[i]
		if set[c >> 6] & (1 << (c & 63)) == 0 {return i}
	}
	return len(str)
}

// newlines
index_newline :: proc "c" (str: string, start: int) -> (end: int) {
	return index_ascii(str, start, "\r\n")
}
index_ignore_newline :: proc "c" (str: string, start: int) -> (end: int) {
	j := start
	if j < len(str) && str[j] == '\r' {j += 1}
	if j < len(str) && str[j] == '\n' {j += 1}
	return j
}
index_ignore_newlines :: proc "c" (str: string, start: int) -> (end: int) {
	j := start
	for j < len(str) && (str[j] == '\r' || str[j] == '\n') {j += 1}
	return j
}

// strings
starts_with :: proc "c" (str, prefix: string) -> bool {
	return len(str) >= len(prefix) && str[0:len(prefix)] == prefix
}
ends_with :: proc "c" (str, suffix: string) -> bool {
	return len(str) >= len(suffix) && str[len(str) - len(suffix):] == suffix
}
trim_prefix :: proc "c" (str, suffix: string) -> string {
	return ends_with(str, suffix) ? str[:len(str) - len(suffix)] : str
}
trim_suffix :: proc "c" (str, suffix: string) -> string {
	return ends_with(str, suffix) ? str[:len(str) - len(suffix)] : str
}

@(private)
PRIME_RABIN_KARP: u32 : 16777619
/* returns the first byte offset of the first `substring` in the `str`, or `len(str)` when not found. */
@(private)
hash_rabin_karp :: #force_inline proc "c" (hash, value: u32) -> u32 {
	return hash * PRIME_RABIN_KARP + value
}
index :: proc "c" (str: string, start: int, substring: string) -> (middle: int) {
	slice := str[start:]
	N := len(slice)
	M := len(substring)
	if intrinsics.expect(M == 0, false) {return start}
	if intrinsics.expect(M == 1, false) {return index_ascii_char(str, start, substring[0])}
	if intrinsics.expect(M > N, false) {return len(str)}
	// setup
	hash, str_hash: u32
	for i := 0; i < M; i += 1 {
		hash = hash_rabin_karp(hash, u32(substring[i]))
	}
	for i := 0; i < M; i += 1 {
		str_hash = hash_rabin_karp(str_hash, u32(slice[i]))
	}
	if str_hash == hash && slice[:M] == substring {
		return start
	}
	// rolling hash
	pow: u32 = 1
	sq := u32(PRIME_RABIN_KARP)
	for i := M; i > 0; i >>= 1 {
		if (i & 1) != 0 {pow *= sq}
		sq *= sq
	}
	for i := M; i < len(slice); {
		str_hash = hash_rabin_karp(str_hash, u32(slice[i])) - pow * u32(slice[i - M])
		i += 1
		if str_hash == hash && slice[i - M:i] == substring {
			return start + i - M
		}
	}
	return len(str)
}
index_after :: proc "c" (str: string, start: int, substr: string) -> (middle: int) {
	j := index(str, start, substr) + len(substr)
	return min(j, len(str))
}
/* returns the first byte offset of the first `substring` in the `str`, or `len(str)` when not found. */
index_multi :: proc "c" (
	str: string,
	start: int,
	substrings: ..string,
) -> (
	middle, substr_index: int,
) {
	slice := str[start:]
	N := len(slice)
	// find smallest substring
	smallest_substring := substrings[0]
	for substr in substrings[1:] {
		if len(substr) < len(smallest_substring) {
			smallest_substring = substr
		}
	}
	M := len(smallest_substring)
	assert_contextless(M > 0)
	if M > N {return len(str), 0}
	// setup
	hashes: [16]u32
	K := len(substrings)
	assert_contextless(K <= len(hashes))
	for k in 0 ..< K {
		substr := substrings[k]
		hash: u32
		for i := 0; i < M; i += 1 {
			hash = hash_rabin_karp(hash, u32(substr[i]))
		}
		hashes[k] = hash
	}
	str_hash: u32
	for i := 0; i < M; i += 1 {
		str_hash = hash_rabin_karp(str_hash, u32(slice[i]))
	}
	for k in 0 ..< K {
		if str_hash != hashes[k] {continue}
		substr := substrings[k]
		j := min(len(substr), N)
		if slice[:j] == substr {return start, k}
	}
	// rolling hash
	pow: u32 = 1
	sq := u32(PRIME_RABIN_KARP)
	for i := M; i > 0; i >>= 1 {
		if (i & 1) != 0 {pow *= sq}
		sq *= sq
	}
	for i := M; i < N; {
		str_hash = hash_rabin_karp(str_hash, u32(slice[i])) - pow * u32(slice[i - M])
		i += 1
		for k in 0 ..< K {
			if str_hash != hashes[k] {continue}
			substr := substrings[k]
			j := min(i - M + len(substr), N)
			if slice[i - M:j] == substr {return start + i - M, k}
		}
	}
	return len(str), 0
}
index_multi_after :: proc "c" (
	str: string,
	start: int,
	substrings: ..string,
) -> (
	middle, end, k: int,
) {
	middle, k = index_multi(str, start, ..substrings)
	end = min(middle + len(substrings[k]), len(str))
	return
}
