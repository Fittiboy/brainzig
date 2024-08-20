pub fn contains(haystack: []const u8, needle: u8) bool {
    for (haystack) |h| if (h == needle) return true;
    return false;
}
