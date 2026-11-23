//! Fallback selection and residency, using only generated fonts.
const std = @import("std");
const font = @import("font.zig");
const fontdb = @import("fontdb.zig");
const testfont = @import("testfont.zig");
const testing = std.testing;

fn add(db: *fontdb.Db, bytes: []const u8) !u32 {
    const parsed = try font.Font.init(bytes, 0);
    const path = try db.gpa.dupe(u8, "");
    errdefer db.gpa.free(path);
    try db.faces.append(db.gpa, .{ .path = path, .index = 0, .style = parsed.style, .memory = bytes });
    return @intCast(db.faces.items.len - 1);
}

test "fallback checks do not retain rejected or selected font bytes" {
    const gpa = testing.allocator;
    const cjk = try testfont.build(gpa, .{ .family = "Microsoft YaHei", .ranges = &.{.{ 0x4e00, 0x4e00 }} });
    defer gpa.free(cjk);
    const symbols = try testfont.build(gpa, .{ .family = "Segoe UI Symbol", .ranges = &.{.{ 0x21bb, 0x21bb }} });
    defer gpa.free(symbols);
    var db = fontdb.Db.init(gpa, testing.io);
    defer db.deinit();
    db.scanned = true;
    _ = try add(&db, cjk);
    const selected = try add(&db, symbols);

    // Neither a hit nor a miss should populate the resident font cache.
    try testing.expectEqual(selected, db.fallback(0x21bb, 400).?);
    try testing.expect(db.fallback(0x2715, 400) == null);
    try testing.expectEqual(@as(usize, 0), db.loaded.count());
    try testing.expectEqual(selected, db.fallback(0x21bb, 400).?);
    try testing.expectEqual(@as(usize, 0), db.loaded.count());
    // Only actually using the selected face makes it resident.
    try testing.expect(db.load(selected).?.glyphIndex(0x21bb) != 0);
    try testing.expectEqual(@as(usize, 1), db.loaded.count());
    try testing.expect(db.fallback(0x2715, 400) == null);
    try testing.expectEqual(@as(usize, 1), db.loaded.count());
}

test "fallback prefers symbols for symbols and CJK fonts for hanzi" {
    const gpa = testing.allocator;
    const ranges: []const [2]u16 = &.{ .{ 0x21bb, 0x21bb }, .{ 0x4e00, 0x4e00 } };
    const cjk = try testfont.build(gpa, .{ .family = "Microsoft YaHei", .ranges = ranges });
    defer gpa.free(cjk);
    const symbols = try testfont.build(gpa, .{ .family = "Segoe UI Symbol", .ranges = ranges });
    defer gpa.free(symbols);
    var db = fontdb.Db.init(gpa, testing.io);
    defer db.deinit();
    db.scanned = true;
    const hanzi = try add(&db, cjk);
    const symbol = try add(&db, symbols);

    try testing.expectEqual(symbol, db.fallback(0x21bb, 400).?);
    try testing.expectEqual(hanzi, db.fallback(0x4e00, 400).?);
    try testing.expectEqual(@as(usize, 0), db.loaded.count());
}
