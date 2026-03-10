const std = @import("std");
const gl = @import("gl");
var procs: gl.ProcTable = undefined;
const glfw = @import("glfw");

fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{error_code, description});
}

pub fn main() !void {
    glfw.setErrorCallback(errorCallback);
    if(!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        return error.GlfwInitFailed;
    }
    defer glfw.terminate();

    const window = glfw.Window.create(600, 600, "test", null, null, .{}) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        return error.WindowCreationFailed;
    };
    defer window.destroy();
    
    glfw.makeContextCurrent(window);
    defer glfw.makeContextCurrent(null);

    if(!procs.init(glfw.getProcAddress)) {
        std.log.err("failed to initialize OpenGL bindings\n", .{});
        return error.InitFailed;
    }
    gl.makeProcTableCurrent(&procs);
    defer gl.makeProcTableCurrent(null);

    while(!window.shouldClose()) {
        processInput(&window);

        gl.ClearColor(0.2, 0.3, 0.3, 1.0);
        gl.Clear(gl.COLOR_BUFFER_BIT);

        //stuff

        glfw.pollEvents();
        window.swapBuffers();
    }
}

fn processInput(window: *const glfw.Window) void {
    if(window.getKey(glfw.Key.escape) == glfw.Action.press) {
        window.setShouldClose(true);
    }
}
