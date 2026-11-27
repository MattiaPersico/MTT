// mtt_FmodSync drag helper (macOS), started by mtt_FmodSync.lua:
//   osascript -l JavaScript mtt_fmodsync_drag.js <command file> <ack file>
// REAPER scripts cannot start a drag to another app; this process can. It
// keeps a small borderless window that the script places exactly over the
// drag handle under the mouse, so the press lands here and drags the files
// (file URLs, as from the Finder) into e.g. FMOD Studio in one gesture.
// The command file (rewritten by the script at least every second):
//   <sequence number>
//   show | hide
//   <x> <y> <w> <h>       window rect, Cocoa screen coordinates
//   <bg RRGGBB> <accent RRGGBB>
//   <label>
//   <file> ...            one per line
// Every 0.5 s the time (seconds) is written to the ack file. With no new
// command for 3 s (the script stopped) this process quits.
// Only plain calls are used: overriding methods whose types JXA cannot
// match, layers (CGColor) and attributed strings failed or crashed here.
ObjC.import('AppKit');

function run(argv) {
  var cmdPath = argv[0], ackPath = argv[1];
  if (!cmdPath || !ackPath) { return; }
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
  function quit() { app.terminate(null); }

  var paths = [];
  var dragging = false, dragStart = 0;
  function readCommand() {
    var s = $.NSString.stringWithContentsOfFileEncodingError(cmdPath, $.NSUTF8StringEncoding, null);
    return (s && !s.isNil()) ? s.js : null;
  }
  function commandPaths() {
    var text = readCommand();
    if (text === null) { return null; }
    var lines = text.split('\n');
    if (lines[1] !== 'show' || lines.length < 6) { return null; }
    return lines.slice(5).filter(function (p) { return p !== ''; });
  }
  ObjC.registerSubclass({
    name: 'MTTFmodSyncDragHandle',
    superclass: 'NSButton',
    protocols: ['NSDraggingSource'],
    methods: {
      'mouseDown:': {
        types: ['void', ['id']],
        implementation: function (ev) {
          // The files are read again now: the ones of the last hover, so a
          // new selection is never dragged with older files.
          var fresh = commandPaths();
          if (fresh) { paths = fresh; }
          if (paths.length === 0) { return; }
          dragStart = Date.now();
          var items = $.NSMutableArray.array;
          var ws = $.NSWorkspace.sharedWorkspace;
          for (var i = 0; i < paths.length; i++) {
            var item = $.NSDraggingItem.alloc.initWithPasteboardWriter($.NSURL.fileURLWithPath(paths[i]));
            item.setDraggingFrameContents($.NSMakeRect(i * 4, i * 4, 32, 32), ws.iconForFile(paths[i]));
            items.addObject(item);
          }
          dragging = true;
          this.beginDraggingSessionWithItemsEventSource(items, ev, this);
        }
      },
      'draggingSession:sourceOperationMaskForDraggingContext:': {
        types: ['unsigned long', ['id', 'long']],
        implementation: function () { return 1; } // NSDragOperationCopy
      }
    }
  });

  var panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(0, 0, 18, 18),
    $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel, $.NSBackingStoreBuffered, false);
  panel.setLevel($.NSFloatingWindowLevel);
  panel.setHasShadow(false);
  panel.setHidesOnDeactivate(false);
  // Invisible: the user sees REAPER's handle under it. A clear window still
  // takes the clicks because it is told to.
  panel.setOpaque(false);
  panel.setBackgroundColor($.NSColor.clearColor);
  panel.setIgnoresMouseEvents(false);
  var handle = $.MTTFmodSyncDragHandle.alloc.initWithFrame($.NSMakeRect(0, 0, 18, 18));
  handle.setBordered(false);
  handle.setTitle('');
  handle.setImagePosition($.NSNoImage);
  handle.setTransparent(true);
  panel.setContentView(handle);

  var lastSeq = null, lastChange = Date.now(), lastAck = 0, shown = false, shownKey = null;
  var rect = null; // where the window is (numbers kept here: panel.frame is not read back reliably)
  var quietUntil = 0;
  function hide() { panel.orderOut(null); shown = false; }
  function tick() {
    var now = Date.now();
    if (now - lastAck > 500) {
      lastAck = now;
      $(String(Math.floor(now / 1000)) + (dragging ? '\ndragging' : '')).writeToFileAtomicallyEncodingError(ackPath, true, $.NSUTF8StringEncoding, null);
    }
    if (dragging) {
      // Number(): the value may come back wrapped; a value that is not a
      // number counts as released, and a drag never lasts over 2 minutes.
      var buttons = Number($.NSEvent.pressedMouseButtons);
      if (!(buttons & 1) || now - dragStart > 120000) { dragging = false; hide(); quietUntil = now + 300; }
      else { return; }
    }
    var text = readCommand();
    if (text === null) { if (now - lastChange > 3000) { quit(); } return; }
    var lines = text.split('\n');
    if (lines[0] !== lastSeq) { lastSeq = lines[0]; lastChange = now; }
    else if (now - lastChange > 3000) { quit(); return; }
    var m = $.NSEvent.mouseLocation;
    // Hidden as soon as the mouse leaves it.
    if (shown && (!rect || m.x < rect[0] || m.x > rect[0] + rect[2] || m.y < rect[1] || m.y > rect[1] + rect[3])) { hide(); }
    if (now < quietUntil) { return; }
    if (lines[1] === 'show' && lines.length >= 6) {
      var r = lines[2].split(' ').map(Number);
      var key = lines.slice(2).join('\n');
      var inside = m.x >= r[0] && m.x <= r[0] + r[2] && m.y >= r[1] && m.y <= r[1] + r[3];
      if (inside && (!shown || key !== shownKey)) {
        shownKey = key;
        paths = lines.slice(5).filter(function (p) { return p !== ''; });
        rect = r;
        panel.setFrameDisplay($.NSMakeRect(r[0], r[1], r[2], r[3]), true);
        handle.setFrame($.NSMakeRect(0, 0, r[2], r[3]));
        handle.setToolTip(lines[4] + ' to FMOD');
        panel.orderFrontRegardless;
        shown = true;
      }
    } else if (lines[1] === 'hide' && shown) {
      hide();
    }
  }
  // In the common modes, so that it also runs while a drag is tracked; an
  // error is logged next to the ack file and never stops the timer.
  var timer = $.NSTimer.timerWithTimeIntervalRepeatsBlock(0.03, true, function () {
    try { tick(); } catch (e) {
      $(String(e)).writeToFileAtomicallyEncodingError(ackPath + '.log', true, $.NSUTF8StringEncoding, null);
    }
  });
  $.NSRunLoop.currentRunLoop.addTimerForMode(timer, $.NSRunLoopCommonModes);
  app.run;
}
