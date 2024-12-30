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
        try stdout.print("{?s}\n", .{parseResult.title});
    }
}
