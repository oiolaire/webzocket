# webzocket

A very dumb websocket client, but it works! And not only it works, it even works with TLS and has a simple API.

## Installation

Add this to the `.dependencies` section in your `build.zig.zon` file:


```zig
.webzocket = .{
  .url = "https://github.com/trailriver/webzocket/archive/refs/tags/v0.0.1.tar.gz",
  .hash = "1220653b2f726203cd07c1b9a5ce8adc07a1358f1658a26a7b1362384887143dad7a"
}
```

And something like this to your `build.zig` file:

```zig
const webzocket = b.dependency("webzocket", .{
    .target = target,
    .optimize = optimize,
});

// ...

exe.addModule("webzocket", webzocket.module("webzocket"))
```

## Usage

```zig
const std = @import("std");
const wz = @import("webzocket");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var client = wz.client.init(gpa.allocator());
    defer client.deinit();

    var conn = try client.connect("wss://ws.ifelse.io"); // an echo server
    defer conn.deinit();

    try conn.send("hello");
    try conn.send("world");

    var hello = try conn.receive();
    var world = try conn.receive();

    std.debug.print("{} {}\n", .{hello, world});
}
```
