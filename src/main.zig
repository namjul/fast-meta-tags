const std = @import("std");
const mvzr = @import("mvzr");
const heap = std.heap;

const testing = std.testing;
const ascii = std.ascii;
const unicode = std.unicode;
const ArrayList = std.ArrayList;
const test_allocator = testing.allocator;

// just something generic
const defaultUserAgent = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/122.0";

// Some values
const headers_max_size = 4096;
const body_max_size = 265536;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    if (args.len < 2) return error.ExpectedArgument;

    const ref_url = args[1];

    const url = try std.Uri.parse(ref_url);

    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const maybe_parseResult = fetchAndParse(allocator, url) catch |err| {
        std.debug.print("ERROR: {any} \n", .{err});
        return;
    };
    if (maybe_parseResult) |parseResult| {
        try stdout.print("{?s}\n", .{parseResult.title});
    }
}

pub fn fetchAndParse(allocator: std.mem.Allocator, url: std.Uri) !?ParseResult {

    // Create a general purpose allocator
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create a HTTP client
    var client = std.http.Client{ .allocator = gpa.allocator() };
    defer client.deinit();

    const headers = std.http.Client.Request.Headers{ .user_agent = .{ .override = defaultUserAgent } };

    // Allocate a buffer for server headers
    var hbuffer: [headers_max_size]u8 = undefined;
    const options = std.http.Client.RequestOptions{ .server_header_buffer = &hbuffer, .headers = headers };

    // Start the HTTP request
    var request = try client.open(.GET, url, options);
    defer request.deinit();

    // Send the HTTP request headers
    try request.send();
    // Finish the body of a request
    try request.finish();

    // Waits for a response from the server and parses any headers that are sent
    try request.wait();

    // Check the HTTP return code
    if (request.response.status != std.http.Status.ok) {
        return error.WrongStatusResponse;
    }

    // Read the body
    var bbuffer: [body_max_size]u8 = undefined;
    // const hlength = request.response.parser.header_bytes_len;
    _ = try request.readAll(&bbuffer);

    // TODO make orelse branch work
    const html = blk: {
        if (request.response.content_length != null) {
            break :blk bbuffer[0..request.response.content_length.?];
        } else {}
        break :blk &bbuffer;
    };

    return parse(allocator, html, url);
}

const MetaData = struct { name: ?[]const u8, property: ?[]const u8, content: ?[]const u8 };
const ParseResult = struct { url: std.Uri, title: ?[]const u8, meta: ?[]MetaData };

fn parse(allocator: std.mem.Allocator, html: []u8, url: std.Uri) ?ParseResult {
    const head = getHead(html);

    if (head == null) return null;

    const title = getTitle(allocator, head orelse "");
    const meta = getMeta(allocator, head orelse "");

    return ParseResult{ .url = url, .title = title, .meta = meta };
}

test "getHead" {
    const head = "asdf";
    const result = getHead("xxx<head>" ++ head ++ "</head>xxx");
    try testing.expect(std.mem.eql(u8, (result orelse ""), head));
}

fn getHead(html: []const u8) ?[]const u8 {
    var name = "head";

    var index = std.mem.indexOf(u8, html, "<" ++ name);
    if (index == null) {
        name = "HEAD";
        index = std.mem.indexOf(u8, html, "<" ++ name);
    }

    if (index == null) return null;

    index = std.mem.indexOfPos(u8, html, (index orelse 0) + 5, ">");
    if (index == null) return null;
    index = (index orelse 0) + 1;

    const end = std.mem.indexOfPos(u8, html, (index orelse 0), "</" ++ name);
    if (end == null) return null;

    return html[(index orelse 0)..(end orelse 0)];
}

test "getMeta" {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const meta = "<meta name=\"author\" content=\"John Doe\"> <meta property=\"og:type\" content=\"website\"> ";
    const result = getMeta(allocator, meta);
    try testing.expect(result.?.len == 2);
    try testing.expect(std.mem.eql(u8, result.?[0].name.?, "author"));
    try testing.expect(result.?[1].name == null);
}

fn getMeta(allocator: std.mem.Allocator, html: []const u8) ?[]MetaData {
    var index: ?usize = 0;
    var meta = std.ArrayList(MetaData).init(allocator);

    while (true) {
        const offset = index;
        index = std.mem.indexOfPos(u8, html, (offset orelse 0), "<meta");

        if (index == null) {
            index = std.mem.indexOf(u8, html, "<META");
        }

        if (index == null) {
            break;
        }

        if (index) |*value| {
            value.* += 5;
        }

        const end = std.mem.indexOfPos(u8, html, (index orelse 0), ">");
        if (end == null) {
            break;
        }

        var next = MetaData{ .name = null, .property = null, .content = null };

        var tag = html[(index orelse 0)..(end orelse 0)];

        const maybe_regex = mvzr.compile("\\s*(name|property|content)\\s*=\\s*\"[^\"]*\"?").?;

        while (true) {
            const match = maybe_regex.match(tag);

            if (match != null) {
                var tokens = std.mem.split(u8, match.?.slice, "=");
                const k = std.mem.trim(u8, tokens.first(), " ");
                const v = std.mem.trim(u8, tokens.peek().?, "\" ");

                if (std.mem.eql(u8, k, "name")) {
                    next.name = v;
                }
                if (std.mem.eql(u8, k, "property")) {
                    next.property = v;
                }
                if (std.mem.eql(u8, k, "content")) {
                    next.content = normalize(allocator, v) catch "";
                }

                tag = tag[match.?.end..];
            } else {
                break;
            }
        }

        if (next.content != null) {
            if (next.name != null or next.property != null) {
                meta.append(next) catch |err| {
                    std.debug.print("Encountered error: {}\n", .{err});
                };
            }
        }

        index = (end orelse 0) + 1;
    }

    return if (meta.items.len > 0) meta.items else null;
}

test "getTitle" {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const title = "asdf&#33;&amp;";
    const result = getTitle(allocator, "xxx<title>" ++ title ++ "</title>xxx");
    try testing.expect(std.mem.eql(u8, (result orelse ""), "asdf!&"));
}

fn getTitle(allocator: std.mem.Allocator, html: []const u8) ?[]const u8 {
    var name = "title";

    var index = std.mem.indexOf(u8, html, "<" ++ name);
    if (index == null) {
        name = "TITLE";
        index = std.mem.indexOf(u8, html, "<" ++ name);
    }

    if (index == null) return null;

    index = std.mem.indexOfPos(u8, html, (index orelse 0) + 6, ">");
    if (index == null) return null;
    index = (index orelse 0) + 1;

    const end = std.mem.indexOfPos(u8, html, (index orelse 0), "</" ++ name);
    if (end == null) return null;

    const slice = html[(index orelse 0)..(end orelse 0)];

    const result = normalize(allocator, slice) catch null;
    return result;
}

fn normalize(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    const numericEntityRegex = mvzr.compile("&#\\d+;").?;
    const match = numericEntityRegex.match(text);

    var current_text = text;

    if (match != null) {
        const numericEntity = try inlineNumericEntity(allocator, match.?.slice);
        const new_text = try std.mem.replaceOwned(u8, allocator, current_text, match.?.slice, numericEntity);
        current_text = new_text;
    }

    current_text = try inlineEntity(allocator, current_text);

    return current_text;
}

fn inlineNumericEntity(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const integer = try std.fmt.parseInt(i32, s[2 .. s.len - 1], 10);
    const codepoint: u21 = @intCast(integer);
    var buffer: [1:0]u8 = undefined;

    _ = try std.unicode.utf8Encode(codepoint, &buffer);

    return try std.fmt.allocPrint(allocator, "{s}", .{buffer});
}

fn inlineEntity(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var current_text = s;
    const replacements = [_]struct {
        needle: []const u8,
        replacement: []const u8,
    }{
        .{ .needle = "&amp;", .replacement = "&" },
        .{ .needle = "&nbsp;", .replacement = " " },
        .{ .needle = "&lt;", .replacement = "<" },
        .{ .needle = "&gt;", .replacement = ">" },
        .{ .needle = "&quot;", .replacement = "\"" },
    };

    for (replacements) |pair| {
        const new_text = try std.mem.replaceOwned(u8, allocator, current_text, pair.needle, pair.replacement);
        current_text = new_text;
    }
    return current_text;
}

test "inlineEntity" {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try testing.expect(std.mem.eql(u8, inlineEntity(allocator, "&amp;") catch "", "&"));
    try testing.expect(std.mem.eql(u8, inlineEntity(allocator, "&nbsp;") catch "", " "));
}

test "inlineNumericEntity" {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const numericEntity = try inlineNumericEntity(allocator, "&#33;");
    try testing.expect(std.mem.eql(u8, numericEntity, "!"));
    defer allocator.free(numericEntity);
}

test "normalize" {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const result = normalize(allocator, "asdfasd&#33;sdfs&#33;df&amp;") catch "";
    try testing.expect(std.mem.eql(u8, result, "asdfasd!sdfs!df&"));
}
