const std = @import("std");

const c = @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("ctype.h");
    @cInclude("sys/ioctl.h");
});

var orig_termios: c.struct_termios = undefined;

fn disableRawMode() void {
    if (c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &orig_termios) != 0 ) {
        std.debug.warn("Couldn't reset terminal settings. Restart the terminal \n", .{});
        std.os.exit(1);
    }
}

fn enableRawMode() void {
    if (c.tcgetattr(c.STDIN_FILENO, &orig_termios) != 0) {
        std.debug.warn("This terminal doesn't support ANSI raw mode\n", .{});
        std.os.exit(1);
    }

    var raw: c.struct_termios = orig_termios;
    const ICRNL: c_uint = c.ICRNL;
    const IXON: c_uint = c.IXON;
    const OPOST: c_uint = c.OPOST;
    const ECHO: c_uint = c.ECHO;
    const ICANON: c_uint = c.ICANON;
    const IEXTEN: c_uint = c.IEXTEN;

    raw.c_iflag &= ~(ICRNL | IXON);
    raw.c_oflag &= ~(OPOST);
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN);

    // uncomment if you want ctrl+c and ctrl+z be ignored
    const ISIG: c_uint = c.ISIG;
    raw.c_lflag &= ~(ISIG);

    // non-blocking reads
    raw.c_cc[c.VMIN] = 0;
    raw.c_cc[c.VTIME] = 0;

    if ( c.tcsetattr(c.STDIN_FILENO, c.TCSAFLUSH, &raw) != 0) {
        std.debug.warn("This terminal doesn't support ANSI raw mode\n", .{});
        std.os.exit(1);
    }
}


// about 1 mb buffer
var buffer: [1000 * 1000]u8 = undefined;
var bufferLen: u32 = 0;

pub fn addToBuffer( chars: [:0]const u8 ) void {
    for (chars) |char| {
        buffer[bufferLen] = char;
        bufferLen+=1;
    }
}


pub fn flushBuffer( ) void {
    if (bufferLen == 0) return;
    _ = c.write(c.STDOUT_FILENO, &buffer[0], @intCast(c_ulong, bufferLen));
    bufferLen = 0;
}

pub const Color = enum(u8) {
    default = 9, black = 0, red, green, yellow, blue, purple, lightblue, white
};

pub const Style = enum(u8) {
    default, bold, faint, italic, underlined, blinking
};


pub fn setTextColor( color: Color ) void {
    var cmd = "\x1b[3.m".*;
    cmd[3] = @enumToInt(color)+'0';
    addToBuffer(&cmd);
}

pub fn setBackgroundColor( color: Color ) void {
    var cmd = "\x1b[4.m".*;
    cmd[3] = @enumToInt(color)+'0';
    addToBuffer(&cmd);
}

pub fn setTextStyle( style: Style ) void {
    var cmd = "\x1b[.m".*;
    cmd[2] = @enumToInt(style)+'0';
    addToBuffer(&cmd);
}

pub fn makeCursorVisible() void {
    addToBuffer("\x1b[?25h");
}

pub fn makeCursorInvisible() void {
    addToBuffer("\x1b[?25l");
}

pub fn setCursorPosition(x: u8, y: u8) void {
    var cmd = "\x1b[...;...H".*;
    cmd[2] = y/100 + '0';
    cmd[3] = y%100/10  + '0';
    cmd[4] = y%10 + '0';
    cmd[6] = x/100 + '0';
    cmd[7] = x%100/10 + '0';
    cmd[8] = x%10 + '0';
    addToBuffer(&cmd);
}

pub fn init () void {
    // save cursor position
    std.debug.print("\x1b7", .{} );
    // enter altern screen
    std.debug.print("\x1b[?47h", .{});
    // clear screen
    std.debug.print("\x1b[2J\x1b[3J", .{});
    // move to 1,1
    std.debug.print("\x1b[1;1H", .{});

    enableRawMode();
}

pub fn deinit() void {
    // clear screen
    std.debug.print("\x1b[2J\x1b[3J", .{});
    // leave altern screen
    std.debug.print("\x1b[?47l", .{});
    // restore cursor position
    std.debug.print("\x1b8", .{});
    // make cursor visible
    std.debug.print("\x1b[?25h", .{});

    disableRawMode();
}

pub fn clearScreen() void {
    addToBuffer("\x1b[2J\x1b[3J");
}


pub const Event = packed enum(u8) {
    UP=251, DOWN, RIGHT, LEFT,
    BACKSPACE=8, TAB, ENTER, CTRL_C=3,
    DELETE=127, SPACE=32, ESC=27, _,
};

// event queue. implemented as an array ring buffer
var evQu: [1000 * 1000]Event = undefined;
var evQuLen: u32 = 0;
var evQuCur: u32 = 0;

const evQuError = error {
    Full, Empty
};

fn pushEvent(ev: Event) !void {
    if (evQuLen >= evQu.len) return evQuError.Full;

    var indToPush: usize = evQuCur + evQuLen;
    if (indToPush >= evQu.len ) {
        indToPush %= evQu.len;
    }

    evQu[ indToPush ] = ev;
    evQuLen += 1;
}

pub fn popEvent( ) !Event {
    if (evQuLen == 0) return evQuError.Empty;
    var evToReturn = evQu[ evQuCur ];

    evQuCur += 1;
    if ( evQuCur == evQu.len ) {
        evQuCur = 0;
    }

    evQuLen -= 1;
    return evToReturn;
}


pub fn populateEvents() !void {
    const r = std.io.getStdIn().reader();
    var ch: u8 = undefined;

    outer: while( true) {

        ch = r.readByte() catch {
            return;
        };

        while(true) {
            if (ch != 27) { // 'escape'
                try pushEvent(@intToEnum(Event, ch));
                continue :outer;
            }

            ch = r.readByte() catch {
                try pushEvent(Event.ESC);
                return;
            };

            if (ch != '[') {
                try pushEvent(Event.ESC);
                continue;
            }

            break;
        }

        ch = r.readByte() catch {
            try pushEvent(@intToEnum(Event, '['));
            return;
        };

        if (ch == 65) { try pushEvent(Event.UP); }
        else if (ch == 66) { try pushEvent(Event.DOWN); }
        else if (ch == 67) { try pushEvent(Event.RIGHT); }
        else if (ch == 68) { try pushEvent(Event.LEFT); }
        else {
            try pushEvent(Event.ESC);
            try pushEvent(@intToEnum(Event, '['));
            try pushEvent(@intToEnum(Event, ch));
        }

    }

}
