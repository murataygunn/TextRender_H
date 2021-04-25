# TextRender

* Simple way to draw text on the screen.
* Interactive GUI that generates code.
* Background color, text outline, and drop shadow.
* Supports events such as OnClick.
* Standalone library.

## Call

TextRender(Text, BackgroundStyle, TextStyle) - Shows the completed render on screen.

## Methods

Render(Text, BackgroundStyle, TextStyle) - Shows the completed render on screen.

Draw(Text, BackgroundStyle, TextStyle) - Draws on a separate layer. Call Render() with no parameters to display on screen.

Flush() - Mimic the effects of Render() without drawing to the screen. 

Clear() - Display a blank screen. 

Sleep(milliseconds) - Shows a blank screen for the specified number of milliseconds.

Queue(Text, BackgroundStyles, TextStyles) - Queue multiple commands by including the time parameter in each one.

FreeMemory() - Frees the drawing canvas while unaffecting the current display on screen. Reduces memory usage by ~60%. For performance reasons, this is not done at the end of every operation. 

## Export

Save() - Saves render to PNG. Returns the file path.

Screenshot() - Saves image on screen to PNG. Returns the file path.

CopyToBuffer() - Raw pointer to pixel values. On AutoHotkey v1 call GlobalFree to release. 

CopyToHBitmap() / RenderToHBitmap() - Gets a handle to a bitmap in 32-bit pre-multiplied alpha RGB.

CopyToBitmap() / RenderToBitmap() - Gets a GDI+ bitmap in 32-bit ARGB.

Hash() - Generates a CRC32 hash of the internal canvas. Use ```.GUID``` to check if the canvas state changed. 

DrawOnGraphics() / DrawOnBitmap() / DrawOnHDC() - 1st parameter is Graphics/Bitmap/hdc followed by Text, BackgroundStyle, TextStyle

## Coordinates

x, y, w, h, x2, y2 as in ```obj.x```

Rect() - [x,y,w,h] array. 

Bounds() - [x, y, x2, y2] array.

# Callbacks

OnEvent("Click", func), OnEvent("DoubleClick", func), OnEvent("RightClick", func), OnEvent("Hover", func)
