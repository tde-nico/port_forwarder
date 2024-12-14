const std = @import("std");

var stdin: std.fs.File.Reader = undefined;
var stdout: std.fs.File.Writer = undefined;

fn forwardPort(port: []const u8) !void {
    const is_valid = std.fmt.parseInt(i32, port, 10) catch |err| {
        try stdout.print("Error parsing port {s} as i32: {?}\n", .{ port, err });
        return;
    };

    if (is_valid < 0 or is_valid > 65535) {
        try stdout.print("Port {s} is not a valid port number\n", .{port});
        return;
    }

    const listenport = try std.fmt.allocPrint(std.heap.page_allocator, "listenport={s}", .{port});
    defer std.heap.page_allocator.free(listenport);

    const connectport = try std.fmt.allocPrint(std.heap.page_allocator, "connectport={s}", .{port});
    defer std.heap.page_allocator.free(connectport);

    var child = std.process.Child.init(
        &[_][]const u8{
            "netsh",
            "interface",
            "portproxy",
            "add",
            "v4tov4",
            listenport,
            "listenaddress=0.0.0.0",
            connectport,
            "connectaddress=172.20.46.85",
        },
        std.heap.page_allocator,
    );

    child.stdout_behavior = std.process.Child.StdIo.Pipe;

    child.spawn() catch |err| {
        try stdout.print("Error spawning child process for {s} port: {?}\n", .{ port, err });
        return;
    };

    var stdout_stream = child.stdout.?.reader();
    var buffer: [1024]u8 = undefined;
    var runned_error: bool = false;
    while (true) {
        const n = try stdout_stream.read(&buffer);
        if (n <= 2)
            break;
        runned_error = true;
        try stdout.writeAll(buffer[0..n]);
    }

    const status = child.wait() catch |err| {
        try stdout.print("Error waiting for child process for {s} port: {?}\n", .{ port, err });
        return;
    };

    if (runned_error) {
        return;
    }

    switch (status) {
        .Exited => try stdout.print("Forwarding port: {s}\n", .{port}),
        else => try stdout.print("Child process for {s} port exited with status {?}\n", .{ port, status }),
    }
}

fn forwardMultiplePorts(data: []const u8) !bool {
    defer std.heap.page_allocator.free(data);

    var stripped = data;
    if (data.len > 0 and data[data.len - 1] == '\n') {
        stripped = data[0 .. data.len - 1];
    }
    if (data.len > 0 and data[data.len - 1] == '\r') {
        stripped = data[0 .. data.len - 1];
    }

    if (stripped.len == 0) {
        return false;
    }

    var it = std.mem.splitAny(u8, stripped, " ");
    while (it.next()) |port| {
        try forwardPort(port);
    }

    return true;
}

fn turnFirewallOff() !void {
    var child = std.process.Child.init(
        &[_][]const u8{
            "netsh",
            "advfirewall",
            "set",
            "allprofiles",
            "state",
            "off",
        },
        std.heap.page_allocator,
    );

    child.stdout_behavior = std.process.Child.StdIo.Pipe;

    child.spawn() catch |err| {
        try stdout.print("Error spawning child process for turning firewall off: {?}\n", .{err});
        return;
    };

    var stdout_stream = child.stdout.?.reader();
    var buffer: [1024]u8 = undefined;
    var runned_error: bool = false;
    while (true) {
        const n = try stdout_stream.read(&buffer);
        if (n <= 5)
            break;
        runned_error = true;
        try stdout.writeAll(buffer[0..n]);
    }

    const status = child.wait() catch |err| {
        try stdout.print("Error waiting for child process for turning firewall off: {?}\n", .{err});
        return;
    };

    if (runned_error) {
        return;
    }

    switch (status) {
        .Exited => try stdout.print("Firewall turned off\n", .{}),
        else => try stdout.print("Child process for turning firewall off exited with status {?}\n", .{status}),
    }
}

pub fn main() !void {
    stdin = std.io.getStdIn().reader();
    stdout = std.io.getStdOut().writer();

    try turnFirewallOff();

    while (true) {
        const input = try stdin.readUntilDelimiterOrEofAlloc(
            std.heap.page_allocator,
            '\n',
            std.math.maxInt(usize),
        );

        if (input) |data| {
            if (!try forwardMultiplePorts(data)) {
                break;
            }
        } else {
            break;
        }
    }
}
