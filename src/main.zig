const std = @import("std");
const fastMetaTags = @import("./root.zig");

const heap = std.heap;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    if (args.len < 2) return error.ExpectedArgument;

    const ref_url = args[1];

    const url = try std.Uri.parse(ref_url);

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const maybe_parseResult = fastMetaTags.fetchAndParse(allocator, url) catch |err| {
        std.debug.print("ERROR: {any} \n", .{err});
        return;
    };
    if (maybe_parseResult) |parseResult| {
        var buf: [1000]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        var string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(parseResult, .{}, string.writer());
        try stdout.print("{?s}\n", .{string.items});
    }
}
