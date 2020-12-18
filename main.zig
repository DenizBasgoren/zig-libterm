
usingnamespace @import("libterm.zig");
const std = @import("std");

// to compile:
// zig build-exe main.zig -lc


pub fn main() !void {

    init();
    makeCursorInvisible();

    var tick: u8 = 0;

    mainloop: while(true) {
        
        clearScreen();

        try populateEvents();

        while( popEvent() ) |ev| {
            switch(ev) {
                Event.CTRL_C => {
                    break :mainloop;
                },

                Event.UP,
                Event.DOWN,
                Event.RIGHT,
                Event.LEFT => {
                    var x: u8 = @enumToInt(ev)-250;
                    const letters = [_]u8{'_','U','D','R','L'};

                    setCursorPosition(x, 5);
                    addToBuffer( &[_:0]u8{ letters[x] } );

                },

                else => {
                    var ch: u8 = @enumToInt(ev);
                    if (ch < 'a' or ch > 'z') break;

                    var x: u8 = ch - 'a' + 1;

                    setCursorPosition(x, 4);
                    addToBuffer( &[_:0]u8{ ch } );
                }
            }
        }
        else |er| {
            // nop
        }

        setCursorPosition(1, 1);
        setTextColor(Color.yellow);
        addToBuffer("Test by deniz basgoren");

        setCursorPosition(1, 2);
        setTextColor(Color.green);
        addToBuffer( &[_:0]u8{tick+'0'} );
        flushBuffer();


        std.time.sleep(1000 * 1000 * 1000 );
        tick = 1 - tick;
    
    }

    deinit();
}

