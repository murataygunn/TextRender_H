; Script:    TextRender.ahk
; License:   MIT License
; Author:    Edison Hua (iseahound)
; Date:      2021-04-19
; Version:   v1.00

#Requires AutoHotkey v1.1.33+
#Persistent

; a := TextRender("i love strong & cute girls!", "r:1 c:none", "c:None d:(blur:1px opacity:100% color:0xFF00FF00)")


TextRender(text:="", background_style:="", text_style:="") {
   return TextRender.call(text, background_style, text_style)
}

; TextRender() - Display custom text on screen.
class TextRender {

   call(terms*) {
      return (this.hwnd) ? this.Render(terms*) : (new this).Render(terms*)
   }

   __New(title := "") {
      this.gdiplusStartup()

      this.IO()

      this.hwnd := this.CreateWindow()
      DllCall("ShowWindow", "ptr", this.hwnd, "int", 4) ; SW_SHOWNOACTIVATE

      ; LoadMemory() is called when Draw() is invoked to save memory.

      this.history := {}
      this.layers := {}
      this.drawing := true
      this.gfx := this.obm := this.pBits := this.hbm := this.hdc := ""

      return this
   }

   __Delete() {
      ; FreeMemory() is called by DestroyWindow().
      this.DestroyWindow()
      this.gdiplusShutdown()
   }

   Render(terms*) {
      ; Check the terms to avoid drawing a default square.
      if (terms.1 != "" || terms.2 != "" || terms.3 != "") {
         this.Draw(terms*)
      }

      ; Allow Render() to commit when previous Draw() has happened.
      if this.layers.length() > 0 {
         ; Render: Off-Screen areas are not rendered. Clip objects that reside off screen.
         this.WindowLeft   := (this.BitmapLeft   > this.x)  ? this.BitmapLeft   : this.x
         this.WindowTop    := (this.BitmapTop    > this.y)  ? this.BitmapTop    : this.y
         this.WindowRight  := (this.BitmapRight  < this.x2) ? this.BitmapRight  : this.x2
         this.WindowBottom := (this.BitmapBottom < this.y2) ? this.BitmapBottom : this.y2
         this.WindowWidth  := this.WindowRight - this.WindowLeft
         this.WindowHeight := this.WindowBottom - this.WindowTop
         ; Only the visible screen area will be rendered.
         ; Objects that reside partly off screen will not have those areas rendered.
         this.UpdateLayeredWindow(this.WindowLeft, this.WindowTop, this.WindowWidth, this.WindowHeight)
      }

      ; Create a timer that eventually clears the canvas.
      if (this.t > 0) {
         ; Create a reference to the object held by a timer.
         blank := ObjBindMethod(this, "blank", this.GUID) ; Calls Blank()
         SetTimer % blank, % -this.t ; Calls __Delete.
      }

      ; Ensure that Flush() will be called at the start of a new drawing.
      ; This approach keeps this.layers and the underlying graphics intact,
      ; so that calls to Save() and Screenshot() will not encounter a blank canvas.
      this.drawing := false
      return this
   }

   Blank(GUID) {
      ; Check to see if the state of the canvas has changed before clearing and updating.
      if (this.GUID = GUID) {
         DllCall("gdiplus\GdipGraphicsClear", "ptr", this.gfx, "uint", 0x00FFFFFF)
         this.GUID := ComObjCreate("Scriptlet.TypeLib").GUID ; canvas changed.
         this.UpdateLayeredWindow(this.BitmapLeft, this.BitmapTop, this.BitmapWidth, this.BitmapHeight)
      }
   }

   Draw(data := "", styles*) {
      ; If the drawing flag is false then a render to screen operation has occurred.
      if (this.drawing = false)
         this.Flush() ; Clear the internal canvas.

      this.UpdateMemory()

      if styles[1] = "" && styles[2] = ""
         styles := this.styles
      this.data := data
      this.styles := styles
      this.layers.push([data, styles*])

      ; Drawing
      obj := this.DrawOnGraphics(this.gfx, data, styles*)

      ; Create a unique signature for each call to Draw().
      this.GUID := ComObjCreate("Scriptlet.TypeLib").GUID

      ; Set canvas coordinates.
      this.t  := (this.t  == "") ? obj.t  : (this.t  > obj.t)  ? this.t  : obj.t
      this.x  := (this.x  == "") ? obj.x  : (this.x  < obj.x)  ? this.x  : obj.x
      this.y  := (this.y  == "") ? obj.y  : (this.y  < obj.y)  ? this.y  : obj.y
      this.x2 := (this.x2 == "") ? obj.x2 : (this.x2 > obj.x2) ? this.x2 : obj.x2
      this.y2 := (this.y2 == "") ? obj.y2 : (this.y2 > obj.y2) ? this.y2 : obj.y2
      this.w  := this.x2 - this.x
      this.h  := this.y2 - this.y
      this.chars := obj.chars
      this.lines := obj.lines

      return this
   }

   Flush() {
      this.drawing := true
      this.history.push(this.layers)

      this.PreciseTime := DllCall("QueryPerformanceCounter", "int64*", A_PreciseTime:=0) ? A_PreciseTime : false
      this.TickCount := A_TickCount
      this.layers := {}
      this.x := this.y := this.x2 := this.y2 := this.w := this.h := ""
      DllCall("gdiplus\GdipGraphicsClear", "ptr", this.gfx, "uint", 0x00FFFFFF)
      this.GUID := ComObjCreate("Scriptlet.TypeLib").GUID ; canvas changed.
      return this
   }

   Clear() {
      this.Flush()
      this.UpdateLayeredWindow(this.BitmapLeft, this.BitmapTop, this.BitmapWidth, this.BitmapHeight)
      this.drawing := false
      return this
   }

   Sleep(milliseconds := 0) {
      this.Clear()
      if (milliseconds)
         Sleep % milliseconds
      return this
   }

   DrawOnGraphics(gfx, text := "", style1 := "", style2 := "", CanvasWidth := "", CanvasHeight := "") {
      ; Get Graphics Width and Height.
      CanvasWidth := (CanvasWidth != "") ? CanvasWidth : NumGet(gfx + 28, "uint")
      CanvasHeight := (CanvasHeight != "") ? CanvasHeight : NumGet(gfx + 32, "uint")

      ; Remove excess whitespace for proper RegEx detection.
      style1 := !IsObject(style1) ? RegExReplace(style1, "\s+", " ") : style1
      style2 := !IsObject(style2) ? RegExReplace(style2, "\s+", " ") : style2

      ; RegEx help? https://regex101.com/r/xLzZzO/2
      static q1 := "(?i)^.*?\b(?<!:|:\s)\b"
      static q2 := "(?!(?>\([^()]*\)|[^()]*)*\))(:\s*)?\(?(?<value>(?<=\()([\s:#%_a-z\-\.\d]+|\([\s:#%_a-z\-\.\d]*\))*(?=\))|[#%_a-z\-\.\d]+).*$"

      ; Extract styles to variables.
      if IsObject(style1) {
         _t  := (style1.time != "")     ? style1.time     : style1.t
         _a  := (style1.anchor != "")   ? style1.anchor   : style1.a
         _x  := (style1.left != "")     ? style1.left     : style1.x
         _y  := (style1.top != "")      ? style1.top      : style1.y
         _w  := (style1.width != "")    ? style1.width    : style1.w
         _h  := (style1.height != "")   ? style1.height   : style1.h
         _r  := (style1.radius != "")   ? style1.radius   : style1.r
         _c  := (style1.color != "")    ? style1.color    : style1.c
         _m  := (style1.margin != "")   ? style1.margin   : style1.m
         _q  := (style1.quality != "")  ? style1.quality  : (style1.q) ? style1.q : style1.SmoothingMode
      } else {
         _t  := ((___ := RegExReplace(style1, q1    "(t(ime)?)"          q2, "${value}")) != style1) ? ___ : ""
         _a  := ((___ := RegExReplace(style1, q1    "(a(nchor)?)"        q2, "${value}")) != style1) ? ___ : ""
         _x  := ((___ := RegExReplace(style1, q1    "(x|left)"           q2, "${value}")) != style1) ? ___ : ""
         _y  := ((___ := RegExReplace(style1, q1    "(y|top)"            q2, "${value}")) != style1) ? ___ : ""
         _w  := ((___ := RegExReplace(style1, q1    "(w(idth)?)"         q2, "${value}")) != style1) ? ___ : ""
         _h  := ((___ := RegExReplace(style1, q1    "(h(eight)?)"        q2, "${value}")) != style1) ? ___ : ""
         _r  := ((___ := RegExReplace(style1, q1    "(r(adius)?)"        q2, "${value}")) != style1) ? ___ : ""
         _c  := ((___ := RegExReplace(style1, q1    "(c(olor)?)"         q2, "${value}")) != style1) ? ___ : ""
         _m  := ((___ := RegExReplace(style1, q1    "(m(argin)?)"        q2, "${value}")) != style1) ? ___ : ""
         _q  := ((___ := RegExReplace(style1, q1    "(q(uality)?)"       q2, "${value}")) != style1) ? ___ : ""
      }

      if IsObject(style2) {
         t  := (style2.time != "")        ? style2.time        : style2.t
         a  := (style2.anchor != "")      ? style2.anchor      : style2.a
         x  := (style2.left != "")        ? style2.left        : style2.x
         y  := (style2.top != "")         ? style2.top         : style2.y
         w  := (style2.width != "")       ? style2.width       : style2.w
         h  := (style2.height != "")      ? style2.height      : style2.h
         m  := (style2.margin != "")      ? style2.margin      : style2.m
         f  := (style2.font != "")        ? style2.font        : style2.f
         s  := (style2.size != "")        ? style2.size        : style2.s
         c  := (style2.color != "")       ? style2.color       : style2.c
         b  := (style2.bold != "")        ? style2.bold        : style2.b
         i  := (style2.italic != "")      ? style2.italic      : style2.i
         u  := (style2.underline != "")   ? style2.underline   : style2.u
         j  := (style2.justify != "")     ? style2.justify     : style2.j
         n  := (style2.noWrap != "")      ? style2.noWrap      : style2.n
         z  := (style2.condensed != "")   ? style2.condensed   : style2.z
         d  := (style2.dropShadow != "")  ? style2.dropShadow  : style2.d
         o  := (style2.outline != "")     ? style2.outline     : style2.o
         q  := (style2.quality != "")     ? style2.quality     : (style2.q) ? style2.q : style2.TextRenderingHint
      } else {
         t  := ((___ := RegExReplace(style2, q1    "(t(ime)?)"          q2, "${value}")) != style2) ? ___ : ""
         a  := ((___ := RegExReplace(style2, q1    "(a(nchor)?)"        q2, "${value}")) != style2) ? ___ : ""
         x  := ((___ := RegExReplace(style2, q1    "(x|left)"           q2, "${value}")) != style2) ? ___ : ""
         y  := ((___ := RegExReplace(style2, q1    "(y|top)"            q2, "${value}")) != style2) ? ___ : ""
         w  := ((___ := RegExReplace(style2, q1    "(w(idth)?)"         q2, "${value}")) != style2) ? ___ : ""
         h  := ((___ := RegExReplace(style2, q1    "(h(eight)?)"        q2, "${value}")) != style2) ? ___ : ""
         m  := ((___ := RegExReplace(style2, q1    "(m(argin)?)"        q2, "${value}")) != style2) ? ___ : ""
         f  := ((___ := RegExReplace(style2, q1    "(f(ont)?)"          q2, "${value}")) != style2) ? ___ : ""
         s  := ((___ := RegExReplace(style2, q1    "(s(ize)?)"          q2, "${value}")) != style2) ? ___ : ""
         c  := ((___ := RegExReplace(style2, q1    "(c(olor)?)"         q2, "${value}")) != style2) ? ___ : ""
         b  := ((___ := RegExReplace(style2, q1    "(b(old)?)"          q2, "${value}")) != style2) ? ___ : ""
         i  := ((___ := RegExReplace(style2, q1    "(i(talic)?)"        q2, "${value}")) != style2) ? ___ : ""
         u  := ((___ := RegExReplace(style2, q1    "(u(nderline)?)"     q2, "${value}")) != style2) ? ___ : ""
         j  := ((___ := RegExReplace(style2, q1    "(j(ustify)?)"       q2, "${value}")) != style2) ? ___ : ""
         n  := ((___ := RegExReplace(style2, q1    "(n(oWrap)?)"        q2, "${value}")) != style2) ? ___ : ""
         z  := ((___ := RegExReplace(style2, q1    "(z|condensed)"      q2, "${value}")) != style2) ? ___ : ""
         d  := ((___ := RegExReplace(style2, q1    "(d(ropShadow)?)"    q2, "${value}")) != style2) ? ___ : ""
         o  := ((___ := RegExReplace(style2, q1    "(o(utline)?)"       q2, "${value}")) != style2) ? ___ : ""
         q  := ((___ := RegExReplace(style2, q1    "(q(uality)?)"       q2, "${value}")) != style2) ? ___ : ""
      }

      ; Extract the time variable and save it for a later when we Render() everything.
      static times := "(?i)^\s*(\d+)\s*(ms|mil(li(second)?)?|s(ec(ond)?)?|m(in(ute)?)?|h(our)?|d(ay)?)?s?\s*$"
      t  := (_t) ? _t : t
      t  := ( t ~= times) ? RegExReplace( t, "\s", "") : 0 ; Default time is zero.
      t  := ((___ := RegExReplace( t, "i)(\d+)(ms|mil(li(second)?)?)s?$", "$1")) !=  t) ? ___ *        1 : t
      t  := ((___ := RegExReplace( t, "i)(\d+)s(ec(ond)?)?s?$"          , "$1")) !=  t) ? ___ *     1000 : t
      t  := ((___ := RegExReplace( t, "i)(\d+)m(in(ute)?)?s?$"          , "$1")) !=  t) ? ___ *    60000 : t
      t  := ((___ := RegExReplace( t, "i)(\d+)h(our)?s?$"               , "$1")) !=  t) ? ___ *  3600000 : t
      t  := ((___ := RegExReplace( t, "i)(\d+)d(ay)?s?$"                , "$1")) !=  t) ? ___ * 86400000 : t

      ; These are the type checkers.
      static valid := "(?i)^\s*(\-?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+)))\s*(%|pt|px|vh|vmin|vw)?\s*$"
      static valid_positive := "(?i)^\s*((?:(?:\d+(?:\.\d*)?)|(?:\.\d+)))\s*(%|pt|px|vh|vmin|vw)?\s*$"

      ; Define viewport width and height. This is the visible canvas area.
      vw := 0.01 * CanvasWidth         ; 1% of viewport width.
      vh := 0.01 * CanvasHeight        ; 1% of viewport height.
      vmin := (vw < vh) ? vw : vh      ; 1vw or 1vh, whichever is smaller.
      vr := CanvasWidth / CanvasHeight ; Aspect ratio of the viewport.

      ; Get background width and height.
      _w := (_w ~= valid_positive) ? RegExReplace(_w, "\s", "") : ""
      _w := (_w ~= "i)(pt|px)$") ? SubStr(_w, 1, -2) : _w
      _w := (_w ~= "i)(%|vw)$") ? RegExReplace(_w, "i)(%|vw)$", "") * vw : _w
      _w := (_w ~= "i)vh$") ? RegExReplace(_w, "i)vh$", "") * vh : _w
      _w := (_w ~= "i)vmin$") ? RegExReplace(_w, "i)vmin$", "") * vmin : _w

      _h := (_h ~= valid_positive) ? RegExReplace(_h, "\s", "") : ""
      _h := (_h ~= "i)(pt|px)$") ? SubStr(_h, 1, -2) : _h
      _h := (_h ~= "i)vw$") ? RegExReplace(_h, "i)vw$", "") * vw : _h
      _h := (_h ~= "i)(%|vh)$") ? RegExReplace(_h, "i)(%|vh)$", "") * vh : _h
      _h := (_h ~= "i)vmin$") ? RegExReplace(_h, "i)vmin$", "") * vmin : _h

      ; Save original Graphics settings.
      DllCall("gdiplus\GdipGetPixelOffsetMode",    "ptr", gfx, "int*", PixelOffsetMode:=0)
      DllCall("gdiplus\GdipGetCompositingMode",    "ptr", gfx, "int*", CompositingMode:=0)
      DllCall("gdiplus\GdipGetCompositingQuality", "ptr", gfx, "int*", CompositingQuality:=0)
      DllCall("gdiplus\GdipGetSmoothingMode",      "ptr", gfx, "int*", SmoothingMode:=0)
      DllCall("gdiplus\GdipGetInterpolationMode",  "ptr", gfx, "int*", InterpolationMode:=0)
      DllCall("gdiplus\GdipGetTextRenderingHint",  "ptr", gfx, "int*", TextRenderingHint:=0)

      ; Get Rendering Quality.
      _q := (_q >= 0 && _q <= 4) ? _q : 4          ; Default SmoothingMode is 4 if radius is set. See Draw 1.
      q  := (q >= 0 && q <= 5) ? q : 4             ; Default TextRenderingHint is 4 (antialias).
                                                   ; Anti-Alias = 4, Cleartype = 5 (and gives weird effects.)

      ; Set Graphics settings.
      DllCall("gdiplus\GdipSetPixelOffsetMode",    "ptr", gfx, "int", 2) ; Half pixel offset.
      ;DllCall("gdiplus\GdipSetCompositingMode",    "ptr", gfx, "int", 1) ; Overwrite/SourceCopy.
      DllCall("gdiplus\GdipSetCompositingQuality", "ptr", gfx, "int", 0) ; AssumeLinear
      DllCall("gdiplus\GdipSetSmoothingMode",      "ptr", gfx, "int", _q)
      DllCall("gdiplus\GdipSetInterpolationMode",  "ptr", gfx, "int", 7) ; HighQualityBicubic
      DllCall("gdiplus\GdipSetTextRenderingHint",  "ptr", gfx, "int", q)

      ; Get Font size.
      s  := (s ~= valid_positive) ? RegExReplace(s, "\s", "") : "2.23vh"          ; Default font size is 2.23vh.
      s  := (s ~= "i)(pt|px)$") ? SubStr(s, 1, -2) : s                            ; Strip spaces, px, and pt.
      s  := (s ~= "i)vh$") ? RegExReplace(s, "i)vh$", "") * vh : s                ; Relative to viewport height.
      s  := (s ~= "i)vw$") ? RegExReplace(s, "i)vw$", "") * vw : s                ; Relative to viewport width.
      s  := (s ~= "i)(%|vmin)$") ? RegExReplace(s, "i)(%|vmin)$", "") * vmin : s  ; Relative to viewport minimum.

      ; Get Bold, Italic, Underline, NoWrap, and Justification of text.
      style := (b) ? 1 : 0         ; bold
      style += (i) ? 2 : 0         ; italic
      style += (u) ? 4 : 0         ; underline
      style += (strikeout) ? 8 : 0 ; strikeout, not implemented.
      n  := (n) ? 0x4000 | 0x1000 : 0x4000 ; Defaults to text wrapping.
      j  := (j ~= "i)cent(er|re)") ? 1 : (j ~= "i)(far|right)") ? 2 : 1 ; Defaults to center justification.

      ; Later when text x and w are finalized and it is found that x + width exceeds the screen,
      ; then the _redrawBecauseOfCondensedFont flag is set to true.
      static _redrawBecauseOfCondensedFont
      if (_redrawBecauseOfCondensedFont == true)
         f:=z, z:=0, _redrawBecauseOfCondensedFont := false

      ; Create Font. Defaults to Segoe UI and Tahoma on older systems.
      if DllCall("gdiplus\GdipCreateFontFamilyFromName", "str",          f, "uint", 0, "ptr*", hFamily:=0)
      if DllCall("gdiplus\GdipCreateFontFamilyFromName", "str", "Segoe UI", "uint", 0, "ptr*", hFamily:=0)
         DllCall("gdiplus\GdipCreateFontFamilyFromName", "str",   "Tahoma", "uint", 0, "ptr*", hFamily:=0)

      DllCall("gdiplus\GdipCreateFont", "ptr", hFamily, "float", s, "int", style, "int", 0, "ptr*", hFont:=0)
      DllCall("gdiplus\GdipCreateStringFormat", "int", n, "int", 0, "ptr*", hFormat:=0)
      DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", hFormat, "int", j) ; Left = 0, Center = 1, Right = 2


      ; Use the declared width and height of the text box if given.
      VarSetCapacity(RectF, 16, 0)                         ; sizeof(RectF) = 16
         (_w != "") ? NumPut(_w, RectF,  8,  "float") : "" ; Width
         (_h != "") ? NumPut(_h, RectF, 12,  "float") : "" ; Height

      ; Otherwise simulate the drawing...
      DllCall("gdiplus\GdipMeasureString"
               ,    "ptr", gfx
               ,   "wstr", text
               ,    "int", -1                 ; string length is null terminated.
               ,    "ptr", hFont
               ,    "ptr", &RectF             ; (in) layout RectF that bounds the string.
               ,    "ptr", hFormat
               ,    "ptr", &RectF             ; (out) simulated RectF that bounds the string.
               ,  "uint*", chars:=0
               ,  "uint*", lines:=0)

      ; Extract the simulated width and height of the text string's bounding box...
      width := NumGet(RectF, 8, "float")
      height := NumGet(RectF, 12, "float")
      minimum := (width < height) ? width : height
      aspect := (height != 0) ? width / height : 0

      ; And use those values for the background width and height.
      (_w == "") ? _w := width : ""
      (_h == "") ? _h := height : ""


      ; Get background anchor. This is where the origin of the image is located.
      _a := RegExReplace(_a, "\s", "")
      _a := (_a ~= "i)top" && _a ~= "i)left") ? 1 : (_a ~= "i)top" && _a ~= "i)cent(er|re)") ? 2
         : (_a ~= "i)top" && _a ~= "i)right") ? 3 : (_a ~= "i)cent(er|re)" && _a ~= "i)left") ? 4
         : (_a ~= "i)cent(er|re)" && _a ~= "i)right") ? 6 : (_a ~= "i)bottom" && _a ~= "i)left") ? 7
         : (_a ~= "i)bottom" && _a ~= "i)cent(er|re)") ? 8 : (_a ~= "i)bottom" && _a ~= "i)right") ? 9
         : (_a ~= "i)top") ? 2 : (_a ~= "i)left") ? 4 : (_a ~= "i)right") ? 6 : (_a ~= "i)bottom") ? 8
         : (_a ~= "i)cent(er|re)") ? 5 : (_a ~= "^[1-9]$") ? _a : 1 ; Default anchor is top-left.

      ; The anchor can be implied from _x and _y (left, center, right, top, bottom).
      _a := (_x ~= "i)left") ? 1+(((_a-1)//3)*3) : (_x ~= "i)cent(er|re)") ? 2+(((_a-1)//3)*3) : (_x ~= "i)right") ? 3+(((_a-1)//3)*3) : _a
      _a := (_y ~= "i)top") ? 1+(mod(_a-1,3)) : (_y ~= "i)cent(er|re)") ? 4+(mod(_a-1,3)) : (_y ~= "i)bottom") ? 7+(mod(_a-1,3)) : _a

      ; Convert English words to numbers. Don't mess with these values any further.
      _x := (_x ~= "i)left") ? 0 : (_x ~= "i)cent(er|re)") ? 0.5*CanvasWidth : (_x ~= "i)right") ? CanvasWidth : _x
      _y := (_y ~= "i)top") ? 0 : (_y ~= "i)cent(er|re)") ? 0.5*CanvasHeight : (_y ~= "i)bottom") ? CanvasHeight : _y

      ; Get _x and _y.
      _x := (_x ~= valid) ? RegExReplace(_x, "\s", "") : ""
      _x := (_x ~= "i)(pt|px)$") ? SubStr(_x, 1, -2) : _x
      _x := (_x ~= "i)(%|vw)$") ? RegExReplace(_x, "i)(%|vw)$", "") * vw : _x
      _x := (_x ~= "i)vh$") ? RegExReplace(_x, "i)vh$", "") * vh : _x
      _x := (_x ~= "i)vmin$") ? RegExReplace(_x, "i)vmin$", "") * vmin : _x

      _y := (_y ~= valid) ? RegExReplace(_y, "\s", "") : ""
      _y := (_y ~= "i)(pt|px)$") ? SubStr(_y, 1, -2) : _y
      _y := (_y ~= "i)vw$") ? RegExReplace(_y, "i)vw$", "") * vw : _y
      _y := (_y ~= "i)(%|vh)$") ? RegExReplace(_y, "i)(%|vh)$", "") * vh : _y
      _y := (_y ~= "i)vmin$") ? RegExReplace(_y, "i)vmin$", "") * vmin : _y

      ; Default x and y to center of the canvas. Default anchor to horizontal center and vertical center.
      if (_x == "")
         _x := 0.5*CanvasWidth, _a := 2+(((_a-1)//3)*3)
      if (_y == "")
         _y := 0.5*CanvasHeight, _a := 4+(mod(_a-1,3))

      ; Now let's modify the _x and _y values with the _anchor, so that the image has a new point of origin.
      ; We need our calculated _width and _height for this!
      _x -= (mod(_a-1,3) == 0) ? 0 : (mod(_a-1,3) == 1) ? _w/2 : (mod(_a-1,3) == 2) ? _w : 0
      _y -= (((_a-1)//3) == 0) ? 0 : (((_a-1)//3) == 1) ? _h/2 : (((_a-1)//3) == 2) ? _h : 0

      ; Prevent half-pixel rendering and keep image sharp.
      _w := Round(_x + _w) - Round(_x) ; Use real x2 coordinate to determine width.
      _h := Round(_y + _h) - Round(_y) ; Use real y2 coordinate to determine height.
      _x := Round(_x)                  ; NOTE: simple Floor(w) or Round(w) will NOT work.
      _y := Round(_y)                  ; The float values need to be added up and then rounded!

      ; Get the text width and text height.
      w  := ( w ~= valid_positive) ? RegExReplace( w, "\s", "") : width ; Default is simulated text width.
      w  := ( w ~= "i)(pt|px)$") ? SubStr( w, 1, -2) :  w
      w  := ( w ~= "i)vw$") ? RegExReplace( w, "i)vw$", "") * vw :  w
      w  := ( w ~= "i)vh$") ? RegExReplace( w, "i)vh$", "") * vh :  w
      w  := ( w ~= "i)vmin$") ? RegExReplace( w, "i)vmin$", "") * vmin :  w
      w  := ( w ~= "%$") ? RegExReplace( w, "%$", "") * 0.01 * _w :  w

      h  := ( h ~= valid_positive) ? RegExReplace( h, "\s", "") : height ; Default is simulated text height.
      h  := ( h ~= "i)(pt|px)$") ? SubStr( h, 1, -2) :  h
      h  := ( h ~= "i)vw$") ? RegExReplace( h, "i)vw$", "") * vw :  h
      h  := ( h ~= "i)vh$") ? RegExReplace( h, "i)vh$", "") * vh :  h
      h  := ( h ~= "i)vmin$") ? RegExReplace( h, "i)vmin$", "") * vmin :  h
      h  := ( h ~= "%$") ? RegExReplace( h, "%$", "") * 0.01 * _h :  h

      ; If text justification is set but x is not, align the justified text relative to the center
      ; or right of the backgound, after taking into account the text width.
      if (x == "")
         x  := (j = 1) ? _x + (_w/2) - (w/2) : (j = 2) ? _x + _w - w : x

      ; Get anchor.
      a  := RegExReplace( a, "\s", "")
      a  := (a ~= "i)top" && a ~= "i)left") ? 1 : (a ~= "i)top" && a ~= "i)cent(er|re)") ? 2
         : (a ~= "i)top" && a ~= "i)right") ? 3 : (a ~= "i)cent(er|re)" && a ~= "i)left") ? 4
         : (a ~= "i)cent(er|re)" && a ~= "i)right") ? 6 : (a ~= "i)bottom" && a ~= "i)left") ? 7
         : (a ~= "i)bottom" && a ~= "i)cent(er|re)") ? 8 : (a ~= "i)bottom" && a ~= "i)right") ? 9
         : (a ~= "i)top") ? 2 : (a ~= "i)left") ? 4 : (a ~= "i)right") ? 6 : (a ~= "i)bottom") ? 8
         : (a ~= "i)cent(er|re)") ? 5 : (a ~= "^[1-9]$") ? a : 1 ; Default anchor is top-left.

      ; Text x and text y can be specified as locations (left, center, right, top, bottom).
      ; These location words in text x and text y take precedence over the values in the text anchor.
      a  := ( x ~= "i)left") ? 1+((( a-1)//3)*3) : ( x ~= "i)cent(er|re)") ? 2+((( a-1)//3)*3) : ( x ~= "i)right") ? 3+((( a-1)//3)*3) :  a
      a  := ( y ~= "i)top") ? 1+(mod( a-1,3)) : ( y ~= "i)cent(er|re)") ? 4+(mod( a-1,3)) : ( y ~= "i)bottom") ? 7+(mod( a-1,3)) :  a

      ; Convert English words to numbers. Don't mess with these values any further.
      ; Also, these values are relative to the background.
      x  := ( x ~= "i)left") ? _x : (x ~= "i)cent(er|re)") ? _x + 0.5*_w : (x ~= "i)right") ? _x + _w : x
      y  := ( y ~= "i)top") ? _y : (y ~= "i)cent(er|re)") ? _y + 0.5*_h : (y ~= "i)bottom") ? _y + _h : y

      ; Get text x and y.
      x  := ( x ~= valid) ? RegExReplace( x, "\s", "") : _x ; Default text x is background x.
      x  := ( x ~= "i)(pt|px)$") ? SubStr( x, 1, -2) :  x
      x  := ( x ~= "i)vw$") ? RegExReplace( x, "i)vw$", "") * vw :  x
      x  := ( x ~= "i)vh$") ? RegExReplace( x, "i)vh$", "") * vh :  x
      x  := ( x ~= "i)vmin$") ? RegExReplace( x, "i)vmin$", "") * vmin :  x
      x  := ( x ~= "%$") ? RegExReplace( x, "%$", "") * 0.01 * _w :  x

      y  := ( y ~= valid) ? RegExReplace( y, "\s", "") : _y ; Default text y is background y.
      y  := ( y ~= "i)(pt|px)$") ? SubStr( y, 1, -2) :  y
      y  := ( y ~= "i)vw$") ? RegExReplace( y, "i)vw$", "") * vw :  y
      y  := ( y ~= "i)vh$") ? RegExReplace( y, "i)vh$", "") * vh :  y
      y  := ( y ~= "i)vmin$") ? RegExReplace( y, "i)vmin$", "") * vmin :  y
      y  := ( y ~= "%$") ? RegExReplace( y, "%$", "") * 0.01 * _h :  y

      ; Modify text x and text y values with the anchor, so that the text has a new point of origin.
      ; The text anchor is relative to the text width and height before margin/padding.
      ; This is NOT relative to the background width and height.
      x  -= (mod(a-1,3) == 0) ? 0 : (mod(a-1,3) == 1) ? w/2 : (mod(a-1,3) == 2) ? w : 0
      y  -= (((a-1)//3) == 0) ? 0 : (((a-1)//3) == 1) ? h/2 : (((a-1)//3) == 2) ? h : 0

      ; Get margin. Default margin is 1vmin.
      m  := this.parse.margin_and_padding( m, vw, vh)
      _m := this.parse.margin_and_padding(_m, vw, vh, (m.void && _w > 0 && _h > 0) ? "1vmin" : "")

      ; Modify _x, _y, _w, _h with margin and padding, increasing the size of the background.
      _w += Round(_m.2) + Round(_m.4) + Round(m.2) + Round(m.4)
      _h += Round(_m.1) + Round(_m.3) + Round(m.1) + Round(m.3)
      _x -= Round(_m.4)
      _y -= Round(_m.1)

      ; If margin/padding are defined in the text parameter, shift the position of the text.
      x  += Round(m.4)
      y  += Round(m.1)

      ; Re-run: Condense Text using a Condensed Font if simulated text width exceeds screen width.
      if (z) {
         if (width + x > CanvasWidth) {
            _redrawBecauseOfCondensedFont := true
            return this.DrawOnGraphics(gfx, text, style1, style2)
         }
      }

      ; Define radius of rounded corners.
      _r := (_r ~= valid_positive) ? RegExReplace(_r, "\s", "") : 0  ; Default radius is 0, or square corners.
      _r := (_r ~= "i)(pt|px)$") ? SubStr(_r, 1, -2) : _r
      _r := (_r ~= "i)vw$") ? RegExReplace(_r, "i)vw$", "") * vw : _r
      _r := (_r ~= "i)vh$") ? RegExReplace(_r, "i)vh$", "") * vh : _r
      _r := (_r ~= "i)vmin$") ? RegExReplace(_r, "i)vmin$", "") * vmin : _r
      ; percentage is defined as a percentage of the smaller background width/height.
      _r := (_r ~= "%$") ? RegExReplace(_r, "%$", "") * 0.01 * ((_w > _h) ? _h : _w) : _r
      ; the radius cannot exceed the half width or half height, whichever is smaller.
      _r := (_r <= ((_w > _h) ? _h : _w) / 2) ? _r : 0

      ; Define color.
      _c := this.parse.color(_c, 0xDD212121) ; Default background color is transparent gray.
      SourceCopy := (c ~= "i)(delete|eraser?|overwrite|sourceCopy)") ? 1 : 0 ; Eraser brush for text.
      if (!c) ; Default text color changes between white and black.
         c := (this.parse.grayscale(_c) < 128) ? 0xFFFFFFFF : 0xFF000000
      c  := (SourceCopy) ? 0x00000000 : this.parse.color( c)

      ; Define outline and dropShadow.
      o := this.parse.outline(o, vw, vh, s, c)
      d := this.parse.dropShadow(d, vw, vh, width, height, s)



      ; Draw 1 - Background
      if (_w && _h && (_c & 0xFF000000)) {
         ; Create background solid brush.
         DllCall("gdiplus\GdipCreateSolidFill", "uint", _c, "ptr*", pBrush:=0)

         ; Fill a rectangle with a solid brush.
         if (_r == 0) {
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gfx, "int",  1) ; Turn antialiasing off if not a rounded rectangle.
            DllCall("gdiplus\GdipFillRectangle", "ptr", gfx, "ptr", pBrush, "float", _x, "float", _y, "float", _w, "float", _h) ; DRAWING!
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gfx, "int", _q) ; Turn antialiasing on for text rendering.
         }

         ; Fill a rounded rectangle with a solid brush.
         else {
            _r2 := (_r * 2) ; Calculate diameter
            DllCall("gdiplus\GdipCreatePath", "uint", 0, "ptr*", pPath:=0) ; GraphicsPath
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", _x           , "float", _y           , "float", _r2, "float", _r2, "float", 180, "float", 90)
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", _x + _w - _r2, "float", _y           , "float", _r2, "float", _r2, "float", 270, "float", 90)
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", _x + _w - _r2, "float", _y + _h - _r2, "float", _r2, "float", _r2, "float",   0, "float", 90)
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", _x           , "float", _y + _h - _r2, "float", _r2, "float", _r2, "float",  90, "float", 90)
            DllCall("gdiplus\GdipClosePathFigure", "ptr", pPath) ; Connect existing arc segments into a rounded rectangle.
            DllCall("gdiplus\GdipFillPath", "ptr", gfx, "ptr", pBrush, "ptr", pPath) ; DRAWING!
            DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
        }

         ; Delete background solid brush.
         DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
      }

      ; Draw 2 - DropShadow
      if (!d.void) {
         offset2 := d.3 + d.6 + Ceil(0.5*o.1)

         ; If blur is present, a second canvas must be seperately processed to apply the Gaussian Blur effect.
         if (true) {
            ;DropShadow := Gdip_CreateBitmap(w + 2*offset2, h + 2*offset2)
            ;DropShadow := Gdip_CreateBitmap(A_ScreenWidth, A_ScreenHeight, 0xE200B)
            DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", A_ScreenWidth, "int", A_ScreenHeight
               , "uint", 0, "uint", 0xE200B, "ptr", 0, "ptr*", DropShadow:=0)
            DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", DropShadow, "ptr*", DropShadowG:=0)
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", DropShadowG, "int", 3)
            DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", DropShadowG, "int", 1)
            DllCall("gdiplus\GdipGraphicsClear", "ptr", gfx, "uint", d.4 & 0xFFFFFF)
            VarSetCapacity(RectF, 16, 0)          ; sizeof(RectF) = 16
               NumPut(d.1+x, RectF,  0,  "float") ; Left
               NumPut(d.2+y, RectF,  4,  "float") ; Top
               NumPut(    w, RectF,  8,  "float") ; Width
               NumPut(    h, RectF, 12,  "float") ; Height

            ;CreateRectF(RC, offset2, offset2, w + 2*offset2, h + 2*offset2)
         } else {
            ;CreateRectF(RC, x + d.1, y + d.2, w, h)
            VarSetCapacity(RectF, 16, 0)          ; sizeof(RectF) = 16
               NumPut(d.1+x, RectF,  0,  "float") ; Left
               NumPut(d.2+y, RectF,  4,  "float") ; Top
               NumPut(    w, RectF,  8,  "float") ; Width
               NumPut(    h, RectF, 12,  "float") ; Height
            DropShadowG := gfx
         }

         ; Use Gdip_DrawString if and only if there is a horizontal/vertical offset.
         if (o.void && d.6 == 0)
         {
            ; Use shadow solid brush.
            DllCall("gdiplus\GdipCreateSolidFill", "uint", d.4, "ptr*", pBrush:=0)
            DllCall("gdiplus\GdipDrawString"
                     ,    "ptr", DropShadowG
                     ,   "wstr", text
                     ,    "int", -1
                     ,    "ptr", hFont
                     ,    "ptr", &RectF
                     ,    "ptr", hFormat
                     ,    "ptr", pBrush)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
         }
         else ; Otherwise, use the below code if blur, size, and opacity are set.
         {
            ; Draw the outer edge of the text string.
            DllCall("gdiplus\GdipCreatePath", "int",1, "ptr*",pPath:=0)
            DllCall("gdiplus\GdipAddPathString"
                     ,    "ptr", pPath
                     ,   "wstr", text
                     ,    "int", -1
                     ,    "ptr", hFamily
                     ,    "int", style
                     ,  "float", s
                     ,    "ptr", &RectF
                     ,    "ptr", hFormat)
            DllCall("gdiplus\GdipCreatePen1", "uint", d.4, "float", 2*d.6 + o.1, "int", 2, "ptr*", pPen:=0)
            DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "uint", 2)
            DllCall("gdiplus\GdipDrawPath", "ptr", DropShadowG, "ptr", pPen, "ptr", pPath)
            DllCall("gdiplus\GdipDeletePen", "ptr", pPen)

            ; Fill in the outline. Turn off antialiasing and alpha blending so the gaps are 100% filled.
            DllCall("gdiplus\GdipCreateSolidFill", "uint", d.4, "ptr*", pBrush:=0)
            DllCall("gdiplus\GdipSetCompositingMode", "ptr", DropShadowG, "int", 1) ; Turn off alpha blending
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", DropShadowG, "int", 3) ; Turn off anti-aliasing
            DllCall("gdiplus\GdipFillPath", "ptr", DropShadowG, "ptr", pBrush, "ptr", pPath) ; DRAWING!
            DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
            DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
            DllCall("gdiplus\GdipSetCompositingMode", "ptr", DropShadowG, "int", 0)
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", DropShadowG, "int", _q)
         }

         if (true) {
            DllCall("gdiplus\GdipDeleteGraphics", "ptr", DropShadowG)
            this.filter.GaussianBlur(DropShadow, d.3, d.5)
            DllCall("gdiplus\GdipSetInterpolationMode", "ptr", gfx, "int", 5) ; NearestNeighbor
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gfx, "int", 3) ; Turn off anti-aliasing
            ;Gdip_DrawImage(gfx, DropShadow, x + d.1 - offset2, y + d.2 - offset2, w + 2*offset2, h + 2*offset2) ; DRAWING!
            ;Gdip_DrawImage(gfx, DropShadow, 0, 0, A_Screenwidth, A_ScreenHeight) ; DRAWING!
            DllCall("gdiplus\GdipDrawImageRectRectI" ; DRAWING!
                     ,    "ptr", gfx
                     ,    "ptr", DropShadow
                     ,    "int", 0, "int", 0, "int", A_Screenwidth, "int", A_Screenwidth ; destination rectangle
                     ,    "int", 0, "int", 0, "int", A_Screenwidth, "int", A_Screenwidth ; source rectangle
                     ,    "int", 2  ; UnitPixel
                     ,    "ptr", 0  ; imageAttributes
                     ,    "ptr", 0  ; callback
                     ,    "ptr", 0) ; callbackData
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gfx, "int", _q)
            DllCall("gdiplus\GdipDisposeImage", "ptr", DropShadow)
         }
      }


      ; Draw 3 - Text Outline
      if (!o.void) {
         ; Convert our text to a path.
         VarSetCapacity(RectF, 16, 0)          ; sizeof(RectF) = 16
            NumPut(    x, RectF,  0,  "float") ; Left
            NumPut(    y, RectF,  4,  "float") ; Top
            NumPut(    w, RectF,  8,  "float") ; Width
            NumPut(    h, RectF, 12,  "float") ; Height
         DllCall("gdiplus\GdipCreatePath", "int", 1, "ptr*", pPath:=0)
         DllCall("gdiplus\GdipAddPathString"
                  ,    "ptr", pPath
                  ,   "wstr", text
                  ,    "int", -1
                  ,    "ptr", hFamily
                  ,    "int", style
                  ,  "float", s
                  ,    "ptr", &RectF
                  ,    "ptr", hFormat)

         ; Create a glow effect around the edges.
         if (o.3) {
            DllCall("gdiplus\GdipSetClipPath", "ptr", gfx, "ptr", pPath, "int", 3) ; Exclude original text region from being drawn on.
            ARGB := Format("0x{:02X}",((o.4 & 0xFF000000) >> 24)/o.3) . Format("{:06X}",(o.4 & 0x00FFFFFF))
            ; width := 1, unit is 2,
            DllCall("gdiplus\GdipCreatePen1", "uint", ARGB, "float", 1, "int", 2, "ptr*", pPenGlow:=0)
            DllCall("gdiplus\GdipSetPenLineJoin", "ptr",pPenGlow, "uint",2)

            Loop % o.3
            {
               DllCall("gdiplus\GdipSetPenWidth", "ptr", pPenGlow, "float", o.1 + 2*A_Index)
               DllCall("gdiplus\GdipDrawPath", "ptr", gfx, "ptr", pPenGlow, "ptr", pPath) ; DRAWING!
            }
            DllCall("gdiplus\GdipDeletePen", "ptr", pPenGlow)
            DllCall("gdiplus\GdipResetClip", "ptr", gfx)
         }

         ; Draw outline text.
         if (o.1) {
            DllCall("gdiplus\GdipCreatePen1", "uint", o.2, "float", o.1, "int", 2, "ptr*", pPen:=0)
            DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "uint", 2)
            DllCall("gdiplus\GdipDrawPath", "ptr", gfx, "ptr", pPen, "ptr", pPath) ; DRAWING!
            DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
         }

         ; Fill outline text.
         DllCall("gdiplus\GdipCreateSolidFill", "uint", c, "ptr*", pBrush:=0)
         DllCall("gdiplus\GdipSetCompositingMode", "ptr", gfx, "int", SourceCopy)
         DllCall("gdiplus\GdipFillPath", "ptr", gfx, "ptr", pBrush, "ptr", pPath) ; DRAWING!
         DllCall("gdiplus\GdipSetCompositingMode", "ptr", gfx, "int", 0)
         DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
         DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
      }

      ; Draw text only when outline has not filled in the text.
      if (text != "" && o.void) {
         DllCall("gdiplus\GdipSetCompositingMode", "ptr", gfx, "int", SourceCopy)

         VarSetCapacity(RectF, 16, 0)          ; sizeof(RectF) = 16
            NumPut(    x, RectF,  0,  "float") ; Left
            NumPut(    y, RectF,  4,  "float") ; Top
            NumPut(    w, RectF,  8,  "float") ; Width
            NumPut(    h, RectF, 12,  "float") ; Height

         DllCall("gdiplus\GdipMeasureString"
                  ,    "ptr", gfx
                  ,   "wstr", text
                  ,    "int", -1                 ; string length.
                  ,    "ptr", hFont
                  ,    "ptr", &RectF             ; (in) layout RectF that bounds the string.
                  ,    "ptr", hFormat
                  ,    "ptr", &RectF             ; (out) simulated RectF that bounds the string.
                  ,  "uint*", chars:=0
                  ,  "uint*", lines:=0)

         DllCall("gdiplus\GdipCreateSolidFill", "uint", c, "ptr*", pBrush:=0)
         DllCall("gdiplus\GdipDrawString"
                  ,    "ptr", gfx
                  ,   "wstr", text
                  ,    "int", -1
                  ,    "ptr", hFont
                  ,    "ptr", &RectF
                  ,    "ptr", hFormat
                  ,    "ptr", pBrush)
         DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)

         x := NumGet(RectF,  0, "float")
         y := NumGet(RectF,  4, "float")
         w := NumGet(RectF,  8, "float")
         h := NumGet(RectF, 12, "float")
      }

      ; Delete Font Objects.
      DllCall("gdiplus\GdipDeleteStringFormat", "ptr", hFormat)
      DllCall("gdiplus\GdipDeleteFont", "ptr", hFont)
      DllCall("gdiplus\GdipDeleteFontFamily", "ptr", hFamily)

      ; Restore original Graphics settings.
      DllCall("gdiplus\GdipSetPixelOffsetMode",    "ptr", gfx, "int", PixelOffsetMode)
      DllCall("gdiplus\GdipSetCompositingMode",    "ptr", gfx, "int", CompositingMode)
      DllCall("gdiplus\GdipSetCompositingQuality", "ptr", gfx, "int", CompositingQuality)
      DllCall("gdiplus\GdipSetSmoothingMode",      "ptr", gfx, "int", SmoothingMode)
      DllCall("gdiplus\GdipSetInterpolationMode",  "ptr", gfx, "int", InterpolationMode)
      DllCall("gdiplus\GdipSetTextRenderingHint",  "ptr", gfx, "int", TextRenderingHint)

      ; Define canvas coordinates.
      t_bound :=  t                              ; string/background boundary.
      x_bound := (_c & 0xFF000000) ? _x : x
      y_bound := (_c & 0xFF000000) ? _y : y
      w_bound := (_c & 0xFF000000) ? _w : w
      h_bound := (_c & 0xFF000000) ? _h : h

      o_bound := Ceil(0.5 * o.1 + o.3)                     ; outline boundary.
      x_bound := (x - o_bound < x_bound)        ? x - o_bound        : x_bound
      y_bound := (y - o_bound < y_bound)        ? y - o_bound        : y_bound
      w_bound := (w + 2 * o_bound > w_bound)    ? w + 2 * o_bound    : w_bound
      h_bound := (h + 2 * o_bound > h_bound)    ? h + 2 * o_bound    : h_bound
      ; Tooltip % x_bound ", " y_bound ", " w_bound ", " h_bound
      d_bound := Ceil(0.5 * o.1 + d.3 + d.6)            ; dropShadow boundary.
      x_bound := (x + d.1 - d_bound < x_bound)  ? x + d.1 - d_bound  : x_bound
      y_bound := (y + d.2 - d_bound < y_bound)  ? y + d.2 - d_bound  : y_bound
      w_bound := (w + 2 * d_bound > w_bound)    ? w + 2 * d_bound    : w_bound
      h_bound := (h + 2 * d_bound > h_bound)    ? h + 2 * d_bound    : h_bound

      return {t:t_bound, x:x_bound, y:y_bound, w:w_bound, h:h_bound
            , x2:x_bound+w_bound, y2:y_bound+h_bound, chars:chars, lines:lines}
   }

   DrawOnBitmap(pBitmap, text := "", style1 := "", style2 := "") {
      DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr*", gfx:=0)
      obj := this.DrawOnGraphics(gfx, text, style1, style2)
      DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
      return obj
   }

   DrawOnHDC(hdc, text := "", style1 := "", style2 := "") {
      DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc, "ptr*", gfx:=0)
      obj := this.DrawOnGraphics(gfx, text, style1, style2)
      DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
      return obj
   }

   class parse {

      color(c, default := 0xDD424242) {
         static xARGB := "^0x([0-9A-Fa-f]{8})$"
         static xRGB  := "^0x([0-9A-Fa-f]{6})$"
         static ARGB  :=   "^([0-9A-Fa-f]{8})$"
         static RGB   :=   "^([0-9A-Fa-f]{6})$"

         if ObjGetCapacity([c], 1) {
            c  := (c ~= "^#") ? SubStr(c, 2) : c
            c  := ((___ := this.colormap(c)) != "") ? ___ : c
            c  := (c ~= xRGB) ? "0xFF" RegExReplace(c, xRGB, "$1") : (c ~= ARGB) ? "0x" c : (c ~= RGB) ? "0xFF" c : c
            c  := (c ~= xARGB) ? c : default
         }

         return (c != "") ? c : default
      }

      colormap(c) {
         static colors1 :=
         ( LTrim Join
         {
            "Clear"                 : "0x00000000",
            "None"                  : "0x00000000",
            "Off"                   : "0x00000000",
            "Transparent"           : "0x00000000",
            "AliceBlue"             : "0xFFF0F8FF",
            "AntiqueWhite"          : "0xFFFAEBD7",
            "Aqua"                  : "0xFF00FFFF",
            "Aquamarine"            : "0xFF7FFFD4",
            "Azure"                 : "0xFFF0FFFF",
            "Beige"                 : "0xFFF5F5DC",
            "Bisque"                : "0xFFFFE4C4",
            "Black"                 : "0xFF000000",
            "BlanchedAlmond"        : "0xFFFFEBCD",
            "Blue"                  : "0xFF0000FF",
            "BlueViolet"            : "0xFF8A2BE2",
            "Brown"                 : "0xFFA52A2A",
            "BurlyWood"             : "0xFFDEB887",
            "CadetBlue"             : "0xFF5F9EA0",
            "Chartreuse"            : "0xFF7FFF00",
            "Chocolate"             : "0xFFD2691E",
            "Coral"                 : "0xFFFF7F50",
            "CornflowerBlue"        : "0xFF6495ED",
            "Cornsilk"              : "0xFFFFF8DC",
            "Crimson"               : "0xFFDC143C",
            "Cyan"                  : "0xFF00FFFF",
            "DarkBlue"              : "0xFF00008B",
            "DarkCyan"              : "0xFF008B8B",
            "DarkGoldenRod"         : "0xFFB8860B",
            "DarkGray"              : "0xFFA9A9A9",
            "DarkGrey"              : "0xFFA9A9A9",
            "DarkGreen"             : "0xFF006400",
            "DarkKhaki"             : "0xFFBDB76B",
            "DarkMagenta"           : "0xFF8B008B",
            "DarkOliveGreen"        : "0xFF556B2F",
            "DarkOrange"            : "0xFFFF8C00",
            "DarkOrchid"            : "0xFF9932CC",
            "DarkRed"               : "0xFF8B0000",
            "DarkSalmon"            : "0xFFE9967A",
            "DarkSeaGreen"          : "0xFF8FBC8F",
            "DarkSlateBlue"         : "0xFF483D8B",
            "DarkSlateGray"         : "0xFF2F4F4F",
            "DarkSlateGrey"         : "0xFF2F4F4F",
            "DarkTurquoise"         : "0xFF00CED1",
            "DarkViolet"            : "0xFF9400D3",
            "DeepPink"              : "0xFFFF1493",
            "DeepSkyBlue"           : "0xFF00BFFF",
            "DimGray"               : "0xFF696969",
            "DimGrey"               : "0xFF696969",
            "DodgerBlue"            : "0xFF1E90FF",
            "FireBrick"             : "0xFFB22222",
            "FloralWhite"           : "0xFFFFFAF0",
            "ForestGreen"           : "0xFF228B22",
            "Fuchsia"               : "0xFFFF00FF",
            "Gainsboro"             : "0xFFDCDCDC",
            "GhostWhite"            : "0xFFF8F8FF",
            "Gold"                  : "0xFFFFD700",
            "GoldenRod"             : "0xFFDAA520",
            "Gray"                  : "0xFF808080",
            "Grey"                  : "0xFF808080",
            "Green"                 : "0xFF008000",
            "GreenYellow"           : "0xFFADFF2F",
            "HoneyDew"              : "0xFFF0FFF0",
            "HotPink"               : "0xFFFF69B4",
            "IndianRed"             : "0xFFCD5C5C",
            "Indigo"                : "0xFF4B0082",
            "Ivory"                 : "0xFFFFFFF0",
            "Khaki"                 : "0xFFF0E68C",
            "Lavender"              : "0xFFE6E6FA",
            "LavenderBlush"         : "0xFFFFF0F5",
            "LawnGreen"             : "0xFF7CFC00",
            "LemonChiffon"          : "0xFFFFFACD",
            "LightBlue"             : "0xFFADD8E6",
            "LightCoral"            : "0xFFF08080",
            "LightCyan"             : "0xFFE0FFFF",
            "LightGoldenRodYellow"  : "0xFFFAFAD2",
            "LightGray"             : "0xFFD3D3D3",
            "LightGrey"             : "0xFFD3D3D3",
            "LightGreen"            : "0xFF90EE90",
            "LightPink"             : "0xFFFFB6C1",
            "LightSalmon"           : "0xFFFFA07A",
            "LightSeaGreen"         : "0xFF20B2AA",
            "LightSkyBlue"          : "0xFF87CEFA",
            "LightSlateGray"        : "0xFF778899",
            "LightSlateGrey"        : "0xFF778899",
            "LightSteelBlue"        : "0xFFB0C4DE",
            "LightYellow"           : "0xFFFFFFE0",
            "Lime"                  : "0xFF00FF00",
            "LimeGreen"             : "0xFF32CD32",
            "Linen"                 : "0xFFFAF0E6"
         }
         )
         static colors2 :=
         ( LTrim Join
         {
            "Magenta"               : "0xFFFF00FF",
            "Maroon"                : "0xFF800000",
            "MediumAquaMarine"      : "0xFF66CDAA",
            "MediumBlue"            : "0xFF0000CD",
            "MediumOrchid"          : "0xFFBA55D3",
            "MediumPurple"          : "0xFF9370DB",
            "MediumSeaGreen"        : "0xFF3CB371",
            "MediumSlateBlue"       : "0xFF7B68EE",
            "MediumSpringGreen"     : "0xFF00FA9A",
            "MediumTurquoise"       : "0xFF48D1CC",
            "MediumVioletRed"       : "0xFFC71585",
            "MidnightBlue"          : "0xFF191970",
            "MintCream"             : "0xFFF5FFFA",
            "MistyRose"             : "0xFFFFE4E1",
            "Moccasin"              : "0xFFFFE4B5",
            "NavajoWhite"           : "0xFFFFDEAD",
            "Navy"                  : "0xFF000080",
            "OldLace"               : "0xFFFDF5E6",
            "Olive"                 : "0xFF808000",
            "OliveDrab"             : "0xFF6B8E23",
            "Orange"                : "0xFFFFA500",
            "OrangeRed"             : "0xFFFF4500",
            "Orchid"                : "0xFFDA70D6",
            "PaleGoldenRod"         : "0xFFEEE8AA",
            "PaleGreen"             : "0xFF98FB98",
            "PaleTurquoise"         : "0xFFAFEEEE",
            "PaleVioletRed"         : "0xFFDB7093",
            "PapayaWhip"            : "0xFFFFEFD5",
            "PeachPuff"             : "0xFFFFDAB9",
            "Peru"                  : "0xFFCD853F",
            "Pink"                  : "0xFFFFC0CB",
            "Plum"                  : "0xFFDDA0DD",
            "PowderBlue"            : "0xFFB0E0E6",
            "Purple"                : "0xFF800080",
            "RebeccaPurple"         : "0xFF663399",
            "Red"                   : "0xFFFF0000",
            "RosyBrown"             : "0xFFBC8F8F",
            "RoyalBlue"             : "0xFF4169E1",
            "SaddleBrown"           : "0xFF8B4513",
            "Salmon"                : "0xFFFA8072",
            "SandyBrown"            : "0xFFF4A460",
            "SeaGreen"              : "0xFF2E8B57",
            "SeaShell"              : "0xFFFFF5EE",
            "Sienna"                : "0xFFA0522D",
            "Silver"                : "0xFFC0C0C0",
            "SkyBlue"               : "0xFF87CEEB",
            "SlateBlue"             : "0xFF6A5ACD",
            "SlateGray"             : "0xFF708090",
            "SlateGrey"             : "0xFF708090",
            "Snow"                  : "0xFFFFFAFA",
            "SpringGreen"           : "0xFF00FF7F",
            "SteelBlue"             : "0xFF4682B4",
            "Tan"                   : "0xFFD2B48C",
            "Teal"                  : "0xFF008080",
            "Thistle"               : "0xFFD8BFD8",
            "Tomato"                : "0xFFFF6347",
            "Turquoise"             : "0xFF40E0D0",
            "Violet"                : "0xFFEE82EE",
            "Wheat"                 : "0xFFF5DEB3",
            "White"                 : "0xFFFFFFFF",
            "WhiteSmoke"            : "0xFFF5F5F5",
            "Yellow"                : "0xFFFFFF00",
            "YellowGreen"           : "0xFF9ACD32"
         }
         )
         return colors1.HasKey(c) ? colors1[c] : colors2[c]
      }

      dropShadow(d, vw, vh, width, height, font_size) {
         static q1 := "(?i)^.*?\b(?<!:|:\s)\b"
         static q2 := "(?!(?>\([^()]*\)|[^()]*)*\))(:\s*)?\(?(?<value>(?<=\()([\s:#%_a-z\-\.\d]+|\([\s:#%_a-z\-\.\d]*\))*(?=\))|[#%_a-z\-\.\d]+).*$"
         static valid := "(?i)^\s*(\-?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+)))\s*(%|pt|px|vh|vmin|vw)?\s*$"
         vmin := (vw < vh) ? vw : vh

         if IsObject(d) {
            d.1 := (d.horizontal != "") ? d.horizontal : (d.h != "") ? d.h : d.1
            d.2 := (d.vertical   != "") ? d.vertical   : (d.v != "") ? d.h : d.2
            d.3 := (d.blur       != "") ? d.blur       : (d.b != "") ? d.h : d.3
            d.4 := (d.color      != "") ? d.color      : (d.c != "") ? d.h : d.4
            d.5 := (d.opacity    != "") ? d.opacity    : (d.o != "") ? d.h : d.5
            d.6 := (d.size       != "") ? d.size       : (d.s != "") ? d.h : d.6
         } else if (d != "") {
            _ := RegExReplace(d, ":\s+", ":")
            _ := RegExReplace(_, "\s+", " ")
            _ := StrSplit(_, " ")
            _.1 := ((___ := RegExReplace(d, q1    "(h(orizontal)?)"    q2, "${value}")) != d) ? ___ : _.1
            _.2 := ((___ := RegExReplace(d, q1    "(v(ertical)?)"      q2, "${value}")) != d) ? ___ : _.2
            _.3 := ((___ := RegExReplace(d, q1    "(b(lur)?)"          q2, "${value}")) != d) ? ___ : _.3
            _.4 := ((___ := RegExReplace(d, q1    "(c(olor)?)"         q2, "${value}")) != d) ? ___ : _.4
            _.5 := ((___ := RegExReplace(d, q1    "(o(pacity)?)"       q2, "${value}")) != d) ? ___ : _.5
            _.6 := ((___ := RegExReplace(d, q1    "(s(ize)?)"          q2, "${value}")) != d) ? ___ : _.6
            d := _
         }
         else return {"void":true, 1:0, 2:0, 3:0, 4:0, 5:0, 6:0}

         for key, value in d {
            if (key = 4) ; Don't mess with color data.
               continue
            d[key] := (d[key] ~= valid) ? RegExReplace(d[key], "\s", "") : 0 ; Default for everything is 0.
            d[key] := (d[key] ~= "i)(pt|px)$") ? SubStr(d[key], 1, -2) : d[key]
            d[key] := (d[key] ~= "i)vw$") ? RegExReplace(d[key], "i)vw$", "") * vw : d[key]
            d[key] := (d[key] ~= "i)vh$") ? RegExReplace(d[key], "i)vh$", "") * vh : d[key]
            d[key] := (d[key] ~= "i)vmin$") ? RegExReplace(d[key], "i)vmin$", "") * vmin : d[key]
         }

         d.1 := (d.1 ~= "%$") ? SubStr(d.1, 1, -1) * 0.01 * width : d.1
         d.2 := (d.2 ~= "%$") ? SubStr(d.2, 1, -1) * 0.01 * height : d.2
         d.3 := (d.3 ~= "%$") ? SubStr(d.3, 1, -1) * 0.01 * font_size : d.3
         d.4 := this.color(d.4, 0xFFFF0000) ; Default color is red.
         d.5 := (d.5 ~= "%$") ? SubStr(d.5, 1, -1) / 100 : d.5
         d.5 := (d.5 <= 0 || d.5 > 1) ? 1 : d.5 ; Range Opacity is a float from 0-1.
         d.6 := (d.6 ~= "%$") ? SubStr(d.6, 1, -1) * 0.01 * font_size : d.6
         return d
      }

      font(f, default := "Arial"){

      }

      grayscale(sRGB) {
         static rY := 0.212655
         static gY := 0.715158
         static bY := 0.072187

         c1 := 255 & ( sRGB >> 16 )
         c2 := 255 & ( sRGB >> 8 )
         c3 := 255 & ( sRGB )

         loop 3 {
            c%A_Index% := c%A_Index% / 255
            c%A_Index% := (c%A_Index% <= 0.04045) ? c%A_Index%/12.92 : ((c%A_Index%+0.055)/(1.055))**2.4
         }

         v := rY*c1 + gY*c2 + bY*c3
         v := (v <= 0.0031308) ? v * 12.92 : 1.055*(v**(1.0/2.4))-0.055
         return Round(v*255)
      }

      margin_and_padding(m, vw, vh, default := "") {
         static q1 := "(?i)^.*?\b(?<!:|:\s)\b"
         static q2 := "(?!(?>\([^()]*\)|[^()]*)*\))(:\s*)?\(?(?<value>(?<=\()([\s:#%_a-z\-\.\d]+|\([\s:#%_a-z\-\.\d]*\))*(?=\))|[#%_a-z\-\.\d]+).*$"
         static valid := "(?i)^\s*(\-?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+)))\s*(%|pt|px|vh|vmin|vw)?\s*$"
         vmin := (vw < vh) ? vw : vh

         if IsObject(m) {
            m.1 := (m.top    != "") ? m.top    : (m.t != "") ? m.t : m.1
            m.2 := (m.right  != "") ? m.right  : (m.r != "") ? m.r : m.2
            m.3 := (m.bottom != "") ? m.bottom : (m.b != "") ? m.b : m.3
            m.4 := (m.left   != "") ? m.left   : (m.l != "") ? m.l : m.4
         } else if (m != "") {
            _ := RegExReplace(m, ":\s+", ":")
            _ := RegExReplace(_, "\s+", " ")
            _ := StrSplit(_, " ")
            _.1 := ((___ := RegExReplace(m, q1    "(t(op)?)"           q2, "${value}")) != m) ? ___ : _.1
            _.2 := ((___ := RegExReplace(m, q1    "(r(ight)?)"         q2, "${value}")) != m) ? ___ : _.2
            _.3 := ((___ := RegExReplace(m, q1    "(b(ottom)?)"        q2, "${value}")) != m) ? ___ : _.3
            _.4 := ((___ := RegExReplace(m, q1    "(l(eft)?)"          q2, "${value}")) != m) ? ___ : _.4
            m := _
         } else if (default != "")
            m := {1:default, 2:default, 3:default, 4:default}
         else return {"void":true, 1:0, 2:0, 3:0, 4:0}

         ; Follow CSS guidelines for margin!
         if (m.2 == "" && m.3 == "" && m.4 == "")
            m.4 := m.3 := m.2 := m.1, exception := true
         if (m.3 == "" && m.4 == "")
            m.4 := m.2, m.3 := m.1
         if (m.4 == "")
            m.4 := m.2

         for key, value in m {
            m[key] := (m[key] ~= valid) ? RegExReplace(m[key], "\s", "") : default
            m[key] := (m[key] ~= "i)(pt|px)$") ? SubStr(m[key], 1, -2) : m[key]
            m[key] := (m[key] ~= "i)vw$") ? RegExReplace(m[key], "i)vw$", "") * vw : m[key]
            m[key] := (m[key] ~= "i)vh$") ? RegExReplace(m[key], "i)vh$", "") * vh : m[key]
            m[key] := (m[key] ~= "i)vmin$") ? RegExReplace(m[key], "i)vmin$", "") * vmin : m[key]
         }
         m.1 := (m.1 ~= "%$") ? SubStr(m.1, 1, -1) * vh : m.1
         m.2 := (m.2 ~= "%$") ? SubStr(m.2, 1, -1) * (exception ? vh : vw) : m.2
         m.3 := (m.3 ~= "%$") ? SubStr(m.3, 1, -1) * vh : m.3
         m.4 := (m.4 ~= "%$") ? SubStr(m.4, 1, -1) * (exception ? vh : vw) : m.4
         return m
      }

      outline(o, vw, vh, font_size, font_color) {
         static q1 := "(?i)^.*?\b(?<!:|:\s)\b"
         static q2 := "(?!(?>\([^()]*\)|[^()]*)*\))(:\s*)?\(?(?<value>(?<=\()([\s:#%_a-z\-\.\d]+|\([\s:#%_a-z\-\.\d]*\))*(?=\))|[#%_a-z\-\.\d]+).*$"
         static valid_positive := "(?i)^\s*((?:(?:\d+(?:\.\d*)?)|(?:\.\d+)))\s*(%|pt|px|vh|vmin|vw)?\s*$"
         vmin := (vw < vh) ? vw : vh

         if IsObject(o) {
            o.1 := (o.stroke != "") ? o.stroke : (o.s != "") ? o.s : o.1
            o.2 := (o.color  != "") ? o.color  : (o.c != "") ? o.c : o.2
            o.3 := (o.glow   != "") ? o.glow   : (o.g != "") ? o.g : o.3
            o.4 := (o.tint   != "") ? o.tint   : (o.t != "") ? o.t : o.4
         } else if (o != "") {
            _ := RegExReplace(o, ":\s+", ":")
            _ := RegExReplace(_, "\s+", " ")
            _ := StrSplit(_, " ")
            _.1 := ((___ := RegExReplace(o, q1    "(s(troke)?)"        q2, "${value}")) != o) ? ___ : _.1
            _.2 := ((___ := RegExReplace(o, q1    "(c(olor)?)"         q2, "${value}")) != o) ? ___ : _.2
            _.3 := ((___ := RegExReplace(o, q1    "(g(low)?)"          q2, "${value}")) != o) ? ___ : _.3
            _.4 := ((___ := RegExReplace(o, q1    "(t(int)?)"          q2, "${value}")) != o) ? ___ : _.4
            o := _
         }
         else return {"void":true, 1:0, 2:0, 3:0, 4:0}

         for key, value in o {
            if (key = 2) || (key = 4) ; Don't mess with color data.
               continue
            o[key] := (o[key] ~= valid_positive) ? RegExReplace(o[key], "\s", "") : 0 ; Default for everything is 0.
            o[key] := (o[key] ~= "i)(pt|px)$") ? SubStr(o[key], 1, -2) : o[key]
            o[key] := (o[key] ~= "i)vw$") ? RegExReplace(o[key], "i)vw$", "") * vw : o[key]
            o[key] := (o[key] ~= "i)vh$") ? RegExReplace(o[key], "i)vh$", "") * vh : o[key]
            o[key] := (o[key] ~= "i)vmin$") ? RegExReplace(o[key], "i)vmin$", "") * vmin : o[key]
         }

         o.1 := (o.1 ~= "%$") ? SubStr(o.1, 1, -1) * 0.01 * font_size : o.1
         o.2 := this.color(o.2, font_color) ; Default color is the text font color.
         o.3 := (o.3 ~= "%$") ? SubStr(o.3, 1, -1) * 0.01 * font_size : o.3
         o.4 := this.color(o.4, o.2) ; Default color is outline color.
         return o
      }
   }

   class filter {

      GaussianBlur(pBitmap, radius, opacity := 1) {
         static code := (A_PtrSize == 4)
            ? "
            ( LTrim                                    ; 32-bit machine code
            VYnlV1ZTg+xci0Uci30c2UUgx0WsAwAAAI1EAAGJRdiLRRAPr0UYicOJRdSLRRwP
            r/sPr0UYiX2ki30UiUWoi0UQjVf/i30YSA+vRRgDRQgPr9ONPL0SAAAAiUWci0Uc
            iX3Eg2XE8ECJVbCJRcCLRcSJZbToAAAAACnEi0XEiWXk6AAAAAApxItFxIllzOgA
            AAAAKcSLRaiJZcjHRdwAAAAAx0W8AAAAAIlF0ItFvDtFFA+NcAEAAItV3DHAi12c
            i3XQiVXgAdOLfQiLVdw7RRiNDDp9IQ+2FAGLTcyLfciJFIEPtgwDD69VwIkMh4tN
            5IkUgUDr0THSO1UcfBKLXdwDXQzHRbgAAAAAK13Q6yAxwDtFGH0Ni33kD7YcAQEc
            h0Dr7kIDTRjrz/9FuAN1GItF3CtF0AHwiceLRbg7RRx/LDHJO00YfeGLRQiLfcwB
            8A+2BAgrBI+LfeQDBI+ZiQSPjTwz933YiAQPQevWi0UIK0Xci03AAfCJRbiLXRCJ
            /itdHCt13AN14DnZfAgDdQwrdeDrSot1DDHbK3XcAf4DdeA7XRh9KItV4ItFuAHQ
            A1UID7YEGA+2FBop0ItV5AMEmokEmpn3fdiIBB5D69OLRRhBAUXg66OLRRhDAUXg
            O10QfTIxyTtNGH3ti33Ii0XgA0UID7YUCIsEjynQi1XkAwSKiQSKi1XgjTwWmfd9
            2IgED0Hr0ItF1P9FvAFF3AFF0OmE/v//i0Wkx0XcAAAAAMdFvAAAAACJRdCLRbAD
            RQyJRaCLRbw7RRAPjXABAACLTdwxwItdoIt10IlN4AHLi30Mi1XcO0UYjQw6fSEP
            thQBi33MD7YMA4kUh4t9yA+vVcCJDIeLTeSJFIFA69Ex0jtVHHwSi13cA10Ix0W4
            AAAAACtd0OsgMcA7RRh9DYt95A+2HAEBHIdA6+5CA03U68//RbgDddSLRdwrRdAB
            8InHi0W4O0UcfywxyTtNGH3hi0UMi33MAfAPtgQIKwSPi33kAwSPmYkEj408M/d9
            2IgED0Hr1otFDCtF3ItNwAHwiUW4i10Uif4rXRwrddwDdeA52XwIA3UIK3Xg60qL
            dQgx2yt13AH+A3XgO10YfSiLVeCLRbgB0ANVDA+2BBgPthQaKdCLVeQDBJqJBJqZ
            933YiAQeQ+vTi0XUQQFF4Ouji0XUQwFF4DtdFH0yMck7TRh97Yt9yItF4ANFDA+2
            FAiLBI+LfeQp0ItV4AMEj4kEj408Fpn3fdiIBA9B69CLRRj/RbwBRdwBRdDphP7/
            //9NrItltA+Fofz//9no3+l2PzHJMds7XRR9OotFGIt9CA+vwY1EBwMx/zt9EH0c
            D7Yw2cBHVtoMJFrZXeTzDyx15InyiBADRRjr30MDTRDrxd3Y6wLd2I1l9DHAW15f
            XcM=
            )" : "
            ( LTrim                                    ; 64-bit machine code
            VUFXQVZBVUFUV1ZTSIHsqAAAAEiNrCSAAAAARIutkAAAAIuFmAAAAESJxkiJVRhB
            jVH/SYnPi42YAAAARInHQQ+v9Y1EAAErvZgAAABEiUUARIlN2IlFFEljxcdFtAMA
            AABIY96LtZgAAABIiUUID6/TiV0ESIld4A+vy4udmAAAAIl9qPMPEI2gAAAAiVXQ
            SI0UhRIAAABBD6/1/8OJTbBIiVXoSINl6PCJXdxBifaJdbxBjXD/SWPGQQ+v9UiJ
            RZhIY8FIiUWQiXW4RInOK7WYAAAAiXWMSItF6EiJZcDoAAAAAEgpxEiLRehIieHo
            AAAAAEgpxEiLRehIiWX46AAAAABIKcRIi0UYTYn6SIll8MdFEAAAAADHRdQAAAAA
            SIlFyItF2DlF1A+NqgEAAESLTRAxwEWJyEQDTbhNY8lNAflBOcV+JUEPthQCSIt9
            +EUPthwBSItd8IkUhw+vVdxEiRyDiRSBSP/A69aLVRBFMclEO42YAAAAfA9Ii0WY
            RTHbMdtNjSQC6ytMY9oxwE0B+0E5xX4NQQ+2HAMBHIFI/8Dr7kH/wUQB6uvGTANd
            CP/DRQHoO52YAAAAi0W8Ro00AH82SItFyEuNPCNFMclJjTQDRTnNftRIi1X4Qg+2
            BA9CKwSKQgMEiZlCiQSJ930UQogEDkn/wevZi0UQSWP4SAN9GItd3E1j9kUx200B
            /kQpwIlFrEiJfaCLdaiLRaxEAcA580GJ8XwRSGP4TWPAMdtMAf9MA0UY60tIi0Wg
            S408Hk+NJBNFMclKjTQYRTnNfiFDD7YUDEIPtgQPKdBCAwSJmUKJBIn3fRRCiAQO
            Sf/B69r/w0UB6EwDXQjrm0gDXQhB/8FEO00AfTRMjSQfSY00GEUx20U53X7jSItF
            8EMPthQcQosEmCnQQgMEmZlCiQSZ930UQogEHkn/w+vXi0UEAUUQSItF4P9F1EgB
            RchJAcLpSv7//0yLVRhMiX3Ix0UQAAAAAMdF1AAAAACLRQA5RdQPja0BAABEi00Q
            McBFichEA03QTWPJTANNGEE5xX4lQQ+2FAJIi3X4RQ+2HAFIi33wiRSGD69V3ESJ
            HIeJFIFI/8Dr1otVEEUxyUQ7jZgAAAB8D0iLRZBFMdsx202NJALrLUxj2kwDXRgx
            wEE5xX4NQQ+2HAMBHIFI/8Dr7kH/wQNVBOvFRANFBEwDXeD/wzudmAAAAItFsEaN
            NAB/NkiLRchLjTwjRTHJSY00A0U5zX7TSItV+EIPtgQPQisEikIDBImZQokEifd9
            FEKIBA5J/8Hr2YtFEE1j9klj+EwDdRiLXdxFMdtEKcCJRaxJjQQ/SIlFoIt1jItF
            rEQBwDnzQYnxfBFNY8BIY/gx20gDfRhNAfjrTEiLRaBLjTweT40kE0UxyUqNNBhF
            Oc1+IUMPthQMQg+2BA8p0EIDBImZQokEifd9FEKIBA5J/8Hr2v/DRANFBEwDXeDr
            mkgDXeBB/8FEO03YfTRMjSQfSY00GEUx20U53X7jSItF8EMPthQcQosEmCnQQgME
            mZlCiQSZ930UQogEHkn/w+vXSItFCP9F1EQBbRBIAUXISQHC6Uf+////TbRIi2XA
            D4Ui/P//8w8QBQAAAAAPLsF2TTHJRTHARDtF2H1Cicgx0kEPr8VImEgrRQhNjQwH
            McBIA0UIO1UAfR1FD7ZUAQP/wvNBDyrC8w9ZwfNEDyzQRYhUAQPr2kH/wANNAOu4
            McBIjWUoW15fQVxBXUFeQV9dw5CQkJCQkJCQkJCQkJAAAIA/
            )"

         ; Get width and height.
         DllCall("gdiplus\GdipGetImageWidth", "ptr", pBitmap, "uint*", width:=0)
         DllCall("gdiplus\GdipGetImageHeight", "ptr", pBitmap, "uint*", height:=0)

         ; Create a buffer of raw 32-bit ARGB pixel data.
         VarSetCapacity(Rect, 16, 0)            ; sizeof(Rect) = 16
            NumPut(  width, Rect,  8,   "uint") ; Width
            NumPut( height, Rect, 12,   "uint") ; Height
         VarSetCapacity(BitmapData, 16+2*A_PtrSize, 0) ; sizeof(BitmapData) = 24, 32
         DllCall("gdiplus\GdipBitmapLockBits", "ptr", pBitmap, "ptr", &Rect, "uint", 3, "int", 0x26200A, "ptr", &BitmapData)

         ; Get the Scan0 of the pixel data. Create a working buffer of the exact same size.
         stride := NumGet(BitmapData,  8, "int")
         Scan01 := NumGet(BitmapData, 16, "ptr")
         Scan02 := DllCall("GlobalAlloc", "uint", 0x40, "uptr", stride * height, "ptr")

         ; Call machine code function.
         DllCall("crypt32\CryptStringToBinary", "str", code, "uint", 0, "uint", 0x1, "ptr", 0, "uint*", size:=0, "ptr", 0, "ptr", 0)
         p := DllCall("GlobalAlloc", "uint", 0, "uptr", size, "ptr")
         DllCall("VirtualProtect", "ptr", p, "ptr", size, "uint", 0x40, "uint*", op) ; Allow execution from memory.
         DllCall("crypt32\CryptStringToBinary", "str", code, "uint", 0, "uint", 0x1, "ptr", p, "uint*", size, "ptr", 0, "ptr", 0)
         e := DllCall(p, "ptr", Scan01, "ptr", Scan02, "uint", width, "uint", height, "uint", 4, "uint", radius, "float", opacity)
         DllCall("GlobalFree", "ptr", p)

         ; Free resources.
         DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", pBitmap, "ptr", &BitmapData)
         DllCall("GlobalFree", "ptr", Scan02)

         return e
      }
   }

   ; IO - Capture input and internalize environmental data.
   IO(terms*) {
      static A_Frequency, f := DllCall("QueryPerformanceFrequency", "int64*", A_Frequency:=0)
      DllCall("QueryPerformanceCounter", "int64*", A_PreciseTime:=0)

      this.PreciseTime := A_PreciseTime
      this.TickCount := A_TickCount
      this.Frequency := A_Frequency
      this.ScreenWidth := A_ScreenWidth
      this.ScreenHeight := A_ScreenHeight
      this.IsAdmin := A_IsAdmin
      return this.arg := terms
   }

   WindowProc(uMsg, wParam, lParam) {
      hwnd:=this

      ; WM_LBUTTONDOWN
      if (uMsg = 0x201) {
         PostMessage 0xA1, 2,,, % "ahk_id" hwnd
         return
      }
      return DllCall("DefWindowProc", "ptr", hwnd, "uint", uMsg, "uptr", wParam, "ptr", lParam, "ptr")
   }

   RegisterClass(vWinClass) {
      pWndProc := RegisterCallback(this.WindowProc, "Fast",, &this)
      hCursor := DllCall("LoadCursor", "ptr", 0, "ptr", 32512, "ptr") ; IDC_ARROW

      ; struct tagWNDCLASSEXA - https://docs.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-wndclassexa
      ; struct tagWNDCLASSEXW - https://docs.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-wndclassexw
      _ := (A_PtrSize == 8)
      VarSetCapacity(WNDCLASSEX, size := _ ? 80:48, 0)        ; sizeof(WNDCLASSEX) = 48, 80
         NumPut(       size, WNDCLASSEX,         0,   "uint") ; cbSize
         NumPut(          3, WNDCLASSEX,         4,   "uint") ; style
         NumPut(   pWndProc, WNDCLASSEX,         8,    "ptr") ; lpfnWndProc
         NumPut(          0, WNDCLASSEX, _ ? 16:12,    "int") ; cbClsExtra
         NumPut(          0, WNDCLASSEX, _ ? 20:16,    "int") ; cbWndExtra
         NumPut(          0, WNDCLASSEX, _ ? 24:20,    "ptr") ; hInstance
         NumPut(          0, WNDCLASSEX, _ ? 32:24,    "ptr") ; hIcon
         NumPut(    hCursor, WNDCLASSEX, _ ? 40:28,    "ptr") ; hCursor
         NumPut(         16, WNDCLASSEX, _ ? 48:32,    "ptr") ; hbrBackground
         NumPut(          0, WNDCLASSEX, _ ? 56:36,    "ptr") ; lpszMenuName
         NumPut( &vWinClass, WNDCLASSEX, _ ? 64:40,    "ptr") ; lpszClassName
         NumPut(          0, WNDCLASSEX, _ ? 72:44,    "ptr") ; hIconSm

      ; Registers a window class for subsequent use in calls to the CreateWindow or CreateWindowEx function.
      if !(value := DllCall("RegisterClassEx", "ptr", &WNDCLASSEX, "ushort"))
         throw Exception("RegisterClassEx failed.")
      return value
   }

   UnregisterClass(vWinClass) {
      return DllCall("UnregisterClass", "str", vWinClass, "ptr", 0)
   }

   CreateWindow(title := "") {
      ; Window Styles - https://docs.microsoft.com/en-us/windows/win32/winmsg/window-styles
      WS_POPUP                  := 0x80000000
      WS_SYSMENU                :=    0x80000

      ; Extended Window Styles - https://docs.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles
      WS_EX_TOPMOST             :=        0x8
      WS_EX_TOOLWINDOW          :=       0x80
      WS_EX_LAYERED             :=    0x80000
      WS_EX_NOACTIVATE          :=  0x8000000

      WindowStyle := WS_POPUP | WS_SYSMENU ; start off hidden with WS_VISIBLE off
      WindowExStyle := WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED ; WS_EX_NOACTIVATE

      return DllCall("CreateWindowEx"
         ,   "uint", WindowExStyle                     ; dwExStyle
         , "ushort", this.RegisterClass("TextRender")  ; lpClassName
         ,    "str", title                             ; lpWindowName
         ,   "uint", WindowStyle                       ; dwStyle
         ,    "int", 0                                 ; X
         ,    "int", 0                                 ; Y
         ,    "int", 0                                 ; nWidth
         ,    "int", 0                                 ; nHeight
         ,    "ptr", 0                                 ; hWndParent
         ,    "ptr", 0                                 ; hMenu
         ,    "ptr", 0                                 ; hInstance
         ,    "ptr", 0                                 ; lpParam
         ,    "ptr")
   }

   ; Duality #2 - Destroys a window.
   DestroyWindow() {
      if (!this.hwnd)
         return this

      this.FreeMemory()
      DllCall("DestroyWindow", "ptr", this.hwnd)
      this.hwnd := ""
      return this
   }

   ; Duality #3 - Allocates the memory buffer.
   LoadMemory() {
      width := this.BitmapWidth, height := this.BitmapHeight

      ; struct BITMAPINFOHEADER - https://docs.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapinfoheader
      hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
      VarSetCapacity(bi, 40, 0)              ; sizeof(bi) = 40
         NumPut(       40, bi,  0,   "uint") ; Size
         NumPut(    width, bi,  4,   "uint") ; Width
         NumPut(  -height, bi,  8,    "int") ; Height - Negative so (0, 0) is top-left.
         NumPut(        1, bi, 12, "ushort") ; Planes
         NumPut(       32, bi, 14, "ushort") ; BitCount / BitsPerPixel
      hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", &bi, "uint", 0, "ptr*", pBits:=0, "ptr", 0, "uint", 0, "ptr")
      obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
      gfx := DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc , "ptr*", gfx:=0) ? false : gfx

      this.hdc := hdc
      this.hbm := hbm
      this.obm := obm
      this.gfx := gfx
      this.pBits := pBits
      this.BitmapStride := 4 * width
      this.BitmapSize := this.BitmapStride * height

      return this
   }

   ; Duality #3 - Frees the memory buffer.
   FreeMemory() {
      if (!this.hdc)
         return this

      DllCall("gdiplus\GdipDeleteGraphics", "ptr", this.gfx)
      DllCall("SelectObject", "ptr", this.hdc, "ptr", this.obm)
      DllCall("DeleteObject", "ptr", this.hbm)
      DllCall("DeleteDC",     "ptr", this.hdc)
      this.gfx := this.obm := this.pBits := this.hbm := this.hdc := ""
      return this
   }

   ; BROKEN - create a fixed size flag.
   UpdateMemory() {
      if (A_ScreenWidth == this.BitmapWidth && A_ScreenHeight == this.BitmapHeight)
         return this

      this.BitmapLeft := 0
      this.BitmapTop := 0
      this.BitmapRight := A_ScreenWidth
      this.BitmapBottom := A_ScreenHeight
      this.BitmapWidth := A_ScreenWidth
      this.BitmapHeight := A_ScreenHeight
      this.FreeMemory()
      this.LoadMemory()

      ; Redraw graphics with new scaling from BitmapWidth and BitmapHeight.
      for i, layer in this.layers
         this.DrawOnGraphics(this.gfx, layer[1], layer[2], layer[3])

      return this
   }

   DebugMemory() {
      x := this.WindowLeft
      y := this.WindowTop
      w := Round(this.WindowWidth)
      h := Round(this.WindowHeight)

      ; Allocate buffer.
      VarSetCapacity(buffer, 4 * w * h, 0)

      ; Create a Bitmap with 32-bit pre-multiplied ARGB. (Owned by this object!)
      DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", this.BitmapWidth, "int", this.BitmapHeight
         , "uint", this.BitmapStride, "uint", 0xE200B, "ptr", this.pBits, "ptr*", pBitmap:=0)

      ; Crop the bitmap.
      VarSetCapacity(Rect, 16, 0)            ; sizeof(Rect) = 16
         NumPut(      x, Rect,  0,    "int") ; X
         NumPut(      y, Rect,  4,    "int") ; Y
         NumPut(      w, Rect,  8,   "uint") ; Width
         NumPut(      h, Rect, 12,   "uint") ; Height
      VarSetCapacity(BitmapData, 16+2*A_PtrSize, 0)   ; sizeof(BitmapData) = 24, 32
         NumPut(       4*w, BitmapData,  8,    "int") ; Stride
         NumPut(   &buffer, BitmapData, 16,    "ptr") ; Scan0

      ; Use LockBits to create a writable buffer that converts pARGB to ARGB.
      DllCall("gdiplus\GdipBitmapLockBits"
               ,    "ptr", pBitmap
               ,    "ptr", &Rect
               ,   "uint", 5            ; ImageLockMode.UserInputBuffer | ImageLockMode.ReadOnly
               ,    "int", 0x26200A     ; Format32bppArgb
               ,    "ptr", &BitmapData) ; Contains the buffer.
      DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", pBitmap, "ptr", &BitmapData)

      DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)

      loop % h {
      _h := A_Index-1
         if _h*70 > A_ScreenHeight
            break
      loop % w {
      _w := A_Index-1
         if _w*70 > A_ScreenWidth
            continue
         formula := _h*w + _w
         pixel := Format("{:08X}", NumGet(buffer, 4*formula, "uint"))
            this.Draw(pixel, "x" _w*70 " y"  70*(_h) " w70 h70 m0 c" pixel)
      }
      }
      this.Render()
      return this
   }

   RenderOffScreen() {
      ; Use the default rendering when the canvas coordinates fall within the bitmap area.
      if this.BitmapLeft <= this.x && this.BitmapTop <= this.y
      && this.BitmapRight >= this.x2 && this.BitmapBottom >= this.y2
         return this.UpdateLayeredWindow(this.x, this.y, this.w, this.h)

      ; Render objects that reside off screen.
      ; Create a new bitmap using the width and height of the canvas object.
      hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
      VarSetCapacity(bi, 40, 0)              ; sizeof(bi) = 40
         NumPut(       40, bi,  0,   "uint") ; Size
         NumPut(   this.w, bi,  4,   "uint") ; Width
         NumPut(  -this.h, bi,  8,    "int") ; Height - Negative so (0, 0) is top-left.
         NumPut(        1, bi, 12, "ushort") ; Planes
         NumPut(       32, bi, 14, "ushort") ; BitCount / BitsPerPixel
      hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", &bi, "uint", 0, "ptr*", pBits:=0, "ptr", 0, "uint", 0, "ptr")
      obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
      gfx := DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc , "ptr*", gfx:=0) ? false : gfx

      ; Set the origin to this.x and this.y
      DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", gfx, "float", -this.x, "float", -this.y, "int", 0)

      ; Draw on the canvas.
      for i, layer in this.layers
         this.DrawOnGraphics(gfx, layer[1], layer[2], layer[3], this.BitmapWidth, this.BitmapHeight)

      ; Show the objects on screen.
      ; This suffers from a windows limitation in that windows will appear in places that do not match the intended coordinates.
      ; Therefore this is not the default rendering approach as style commands are not respected.
      DllCall("UpdateLayeredWindow"
               ,    "ptr", this.hwnd                                  ; hWnd
               ,    "ptr", 0                                          ; hdcDst
               ,"uint64*", this.x | this.y << 32     ; *pptDst
               ,"uint64*", this.w | this.h << 32 ; this.BitmapWidth | this.BitmapHeight << 32 ; *psize
               ,    "ptr", hdc                                   ; hdcSrc
               ,"uint64*", 0                                          ; *pptSrc
               ,   "uint", 0                                          ; crKey
               ,  "uint*", 0xFF << 16 | 0x01 << 24                    ; *pblend
               ,   "uint", 2)                                         ; dwFlags

      ; Cleanup
      DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
      DllCall("SelectObject", "ptr", hdc, "ptr", obm)
      DllCall("DeleteObject", "ptr", hbm)
      DllCall("DeleteDC",     "ptr", hdc)
   }

   Hash() {
      return Format("{:08x}", DllCall("ntdll\RtlComputeCrc32", "uint", 0, "ptr", this.pBits, "uint", this.BitmapSize, "uint"))
   }

   CopyToBuffer() {
      ; Allocate buffer.
      buffer := DllCall("GlobalAlloc", "uint", 0, "uptr", 4 * this.w * this.h, "ptr")

      ; Create a Bitmap with 32-bit pre-multiplied ARGB. (Owned by this object!)
      DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", this.BitmapWidth, "int", this.BitmapHeight
         , "uint", this.BitmapStride, "uint", 0xE200B, "ptr", this.pBits, "ptr*", pBitmap:=0)

      ; Crop the bitmap.
      VarSetCapacity(Rect, 16, 0)            ; sizeof(Rect) = 16
         NumPut( this.x, Rect,  0,    "int") ; X
         NumPut( this.y, Rect,  4,    "int") ; Y
         NumPut( this.w, Rect,  8,   "uint") ; Width
         NumPut( this.h, Rect, 12,   "uint") ; Height
      VarSetCapacity(BitmapData, 16+2*A_PtrSize, 0)   ; sizeof(BitmapData) = 24, 32
         NumPut(  4*this.w, BitmapData,  8,    "int") ; Stride
         NumPut(    buffer, BitmapData, 16,    "ptr") ; Scan0

      ; Use LockBits to create a writable buffer that converts pARGB to ARGB.
      DllCall("gdiplus\GdipBitmapLockBits"
               ,    "ptr", pBitmap
               ,    "ptr", &Rect
               ,   "uint", 5            ; ImageLockMode.UserInputBuffer | ImageLockMode.ReadOnly
               ,    "int", 0x26200A     ; Format32bppArgb
               ,    "ptr", &BitmapData) ; Contains the buffer.
      DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", pBitmap, "ptr", &BitmapData)

      DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)

      return buffer
   }

   CopyToHBitmap() {
      ; struct BITMAPINFOHEADER - https://docs.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapinfoheader
      hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
      VarSetCapacity(bi, 40, 0)              ; sizeof(bi) = 40
         NumPut(       40, bi,  0,   "uint") ; Size
         NumPut(   this.w, bi,  4,   "uint") ; Width
         NumPut(  -this.h, bi,  8,    "int") ; Height - Negative so (0, 0) is top-left.
         NumPut(        1, bi, 12, "ushort") ; Planes
         NumPut(       32, bi, 14, "ushort") ; BitCount / BitsPerPixel
      hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", &bi, "uint", 0, "ptr*", pBits:=0, "ptr", 0, "uint", 0, "ptr")
      obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")

      DllCall("gdi32\BitBlt"
               , "ptr", hdc, "int", 0, "int", 0, "int", this.w, "int", this.h
               , "ptr", this.hdc, "int", this.x, "int", this.y, "uint", 0x00CC0020) ; SRCCOPY

      DllCall("SelectObject", "ptr", hdc, "ptr", obm)
      DllCall("DeleteDC",     "ptr", hdc)

      return hbm
   }

   RenderToHBitmap() {
      ; struct BITMAPINFOHEADER - https://docs.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapinfoheader
      hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
      VarSetCapacity(bi, 40, 0)              ; sizeof(bi) = 40
         NumPut(       40, bi,  0,   "uint") ; Size
         NumPut(   this.w, bi,  4,   "uint") ; Width
         NumPut(  -this.h, bi,  8,    "int") ; Height - Negative so (0, 0) is top-left.
         NumPut(        1, bi, 12, "ushort") ; Planes
         NumPut(       32, bi, 14, "ushort") ; BitCount / BitsPerPixel
      hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", &bi, "uint", 0, "ptr*", pBits:=0, "ptr", 0, "uint", 0, "ptr")
      obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
      gfx := DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc , "ptr*", gfx:=0) ? false : gfx

      ; Set the origin to this.x and this.y
      DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", gfx, "float", -this.x, "float", -this.y, "int", 0)

      for i, layer in this.layers
         this.DrawOnGraphics(gfx, layer[1], layer[2], layer[3], this.BitmapWidth, this.BitmapHeight)

      DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
      DllCall("SelectObject", "ptr", hdc, "ptr", obm)
      DllCall("DeleteDC",     "ptr", hdc)

      return hbm
   }

   CopyToBitmap() {
      ; Create a Bitmap with 32-bit pre-multiplied ARGB. (Owned by this object!)
      DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", this.BitmapWidth, "int", this.BitmapHeight
         , "uint", this.BitmapStride, "uint", 0xE200B, "ptr", this.pBits, "ptr*", pBitmap:=0)

      ; Crop to fit and convert to 32-bit ARGB. (Managed impartially by GDI+)
      DllCall("gdiplus\GdipCloneBitmapAreaI", "int", this.x, "int", this.y, "int", this.w, "int", this.h
         , "uint", 0x26200A, "ptr", pBitmap, "ptr*", pBitmapCrop:=0)

      DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)

      return pBitmapCrop
   }

   RenderToBitmap() {
      DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", this.w, "int", this.h
         , "uint", 0, "uint", 0x26200A, "ptr", 0, "ptr*", pBitmap:=0)
   	DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr*", gfx:=0)
      DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", gfx, "float", -this.x, "float", -this.y, "int", 0)
      for i, layer in this.layers
         this.DrawOnGraphics(gfx, layer[1], layer[2], layer[3], this.BitmapWidth, this.BitmapHeight)
      DllCall("gdiplus\GdipDeleteGraphics", "ptr", gfx)
      return pBitmap
   }

   Save(filename := "", quality := "") {
      pBitmap := this.InBounds() ? this.CopyToBitmap() : this.RenderToBitmap()
      filepath := this.SaveImageToFile(pBitmap, filename, quality)
      DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
      return filepath
   }

   Screenshot(filename := "", quality := "") {
      pBitmap := this.GetImageFromScreen([this.x, this.y, this.w, this.h])
      filepath := this.SaveImageToFile(pBitmap, filename, quality)
      DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
      return filepath
   }

   SaveImageToFile(pBitmap, filepath := "", quality := "") {
      ; Thanks tic - https://www.autohotkey.com/boards/viewtopic.php?t=6517

      ; Remove whitespace. Seperate the filepath. Adjust for directories.
      filepath := Trim(filepath)
      SplitPath filepath,, directory, extension, filename
      if InStr(FileExist(filepath), "D")
         directory .= "\" filename, filename := ""
      if (directory != "" && !InStr(FileExist(directory), "D"))
         FileCreateDir % directory
      directory := (directory != "") ? directory : "."

      ; Validate filepath, defaulting to PNG. https://stackoverflow.com/a/6804755
      if !(extension ~= "^(?i:bmp|dib|rle|jpg|jpeg|jpe|jfif|gif|tif|tiff|png)$") {
         if (extension != "")
            filename .= "." extension
         extension := "png"
      }
      filename := RegExReplace(filename, "S)(?i:^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$|[<>:|?*\x00-\x1F\x22\/\\])")
      if (filename == "")
         FormatTime, filename,, % "yyyy-MM-dd HH꞉mm꞉ss"
      filepath := directory "\" filename "." extension

      ; Fill a buffer with the available encoders.
      DllCall("gdiplus\GdipGetImageEncodersSize", "uint*", count:=0, "uint*", size:=0)
      VarSetCapacity(ci, size)
      DllCall("gdiplus\GdipGetImageEncoders", "uint", count, "uint", size, "ptr", &ci)
      if !(count && size)
         throw Exception("Could not get a list of image codec encoders on this system.")

      ; Search for an encoder with a matching extension.
      Loop % count
         EncoderExtensions := StrGet(NumGet(ci, (idx:=(48+7*A_PtrSize)*(A_Index-1))+32+3*A_PtrSize, "uptr"), "UTF-16")
      until InStr(EncoderExtensions, "*." extension)

      ; Get the pointer to the index/offset of the matching encoder.
      if !(pCodec := &ci + idx)
         throw Exception("Could not find a matching encoder for the specified file format.")

      ; JPEG is a lossy image format that requires a quality value from 0-100. Default quality is 75.
      if (extension ~= "^(?i:jpg|jpeg|jpe|jfif)$"
      && 0 <= quality && quality <= 100 && quality != 75) {
         DllCall("gdiplus\GdipGetEncoderParameterListSize", "ptr", pBitmap, "ptr", pCodec, "uint*", size:=0)
         VarSetCapacity(EncoderParameters, size, 0)
         DllCall("gdiplus\GdipGetEncoderParameterList", "ptr", pBitmap, "ptr", pCodec, "uint", size, "ptr", &EncoderParameters)

         ; Search for an encoder parameter with 1 value of type 6.
         Loop % NumGet(EncoderParameters, "uint")
            elem := (24+A_PtrSize)*(A_Index-1) + A_PtrSize
         until (NumGet(EncoderParameters, elem+16, "uint") = 1) && (NumGet(EncoderParameters, elem+20, "uint") = 6)

         ; struct EncoderParameter - http://www.jose.it-berater.org/gdiplus/reference/structures/encoderparameter.htm
         ep := &EncoderParameters + elem - A_PtrSize                     ; sizeof(EncoderParameter) = 28, 32
            , NumPut(      1, ep+0,            0,   "uptr")              ; Must be 1.
            , NumPut(      4, ep+0, 20+A_PtrSize,   "uint")              ; Type
            , NumPut(quality, NumGet(ep+24+A_PtrSize, "uptr"), "uint")   ; Value (pointer)
      }

      ; Write the file to disk using the specified encoder and encoding parameters.
      Loop 6 ; Try this 6 times.
         if (A_Index > 1)
            Sleep % (2**(A_Index-2) * 30)
      until (result := !DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBitmap, "wstr", filepath, "ptr", pCodec, "uint", (ep) ? ep : 0))
      if !(result)
         throw Exception("Could not save file to disk.")

      return filepath
   }

   GetImageFromScreen(image) {
      ; Thanks tic - https://www.autohotkey.com/boards/viewtopic.php?t=6517

      ; struct BITMAPINFOHEADER - https://docs.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-bitmapinfoheader
      hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
      VarSetCapacity(bi, 40, 0)                ; sizeof(bi) = 40
         , NumPut(       40, bi,  0,   "uint") ; Size
         , NumPut( image[3], bi,  4,   "uint") ; Width
         , NumPut(-image[4], bi,  8,    "int") ; Height - Negative so (0, 0) is top-left.
         , NumPut(        1, bi, 12, "ushort") ; Planes
         , NumPut(       32, bi, 14, "ushort") ; BitCount / BitsPerPixel
      hbm := DllCall("CreateDIBSection", "ptr", hdc, "ptr", &bi, "uint", 0, "ptr*", pBits:=0, "ptr", 0, "uint", 0, "ptr")
      obm := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")

      ; Retrieve the device context for the screen.
      sdc := DllCall("GetDC", "ptr", 0, "ptr")

      ; Copies a portion of the screen to a new device context.
      DllCall("gdi32\BitBlt"
               , "ptr", hdc, "int", 0, "int", 0, "int", image[3], "int", image[4]
               , "ptr", sdc, "int", image[1], "int", image[2], "uint", 0x00CC0020 | 0x40000000) ; SRCCOPY | CAPTUREBLT

      ; Release the device context to the screen.
      DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)

      ; Convert the hBitmap to a Bitmap using a built in function as there is no transparency.
      DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", pBitmap:=0)

      ; Cleanup the hBitmap and device contexts.
      DllCall("SelectObject", "ptr", hdc, "ptr", obm)
      DllCall("DeleteObject", "ptr", hbm)
      DllCall("DeleteDC",     "ptr", hdc)

      return pBitmap
   }

   UpdateLayeredWindow(x, y, w, h) {
      return DllCall("UpdateLayeredWindow"
               ,    "ptr", this.hwnd                ; hWnd
               ,    "ptr", 0                        ; hdcDst
               ,"uint64*", x | y << 32              ; *pptDst
               ,"uint64*", w | h << 32              ; *psize
               ,    "ptr", this.hdc                 ; hdcSrc
               ,"uint64*", x | y << 32              ; *pptSrc
               ,   "uint", 0                        ; crKey
               ,  "uint*", 0xFF << 16 | 0x01 << 24  ; *pblend
               ,   "uint", 2)                       ; dwFlags
   }

   InBounds() { ; Check if canvas coordinates are inside bitmap coordinates.
      return this.x >= this.BitmapLeft
         and this.y >= this.BitmapTop
         and this.x2 <= this.BitmapRight
         and this.y2 <= this.BitmapBottom
   }

   Bounds(default := "") {
      return (this.x2 > this.x && this.y2 > this.y) ? [this.x, this.y, this.x2, this.y2] : default
   }

   Rect(default := "") {
      return (this.x2 > this.x && this.y2 > this.y) ? [this.x, this.y, this.w, this.h] : default
   }

   ; All references to gdiplus and pToken must be absolute!
   static gdiplus := 0, pToken := 0

   gdiplusStartup() {
      TextRender.gdiplus++

      ; Startup gdiplus when counter goes from 0 -> 1.
      if (TextRender.gdiplus == 1) {

         ; Startup gdiplus.
         DllCall("LoadLibrary", "str", "gdiplus")
         VarSetCapacity(si, A_PtrSize = 8 ? 24 : 16, 0) ; sizeof(GdiplusStartupInput) = 16, 24
            , NumPut(0x1, si, "uint")
         DllCall("gdiplus\GdiplusStartup", "ptr*", pToken:=0, "ptr", &si, "ptr", 0)

         TextRender.pToken := pToken
      }
   }

   gdiplusShutdown(cotype := "", pBitmap := "") {
      TextRender.gdiplus--

      ; When a buffer object is deleted a bitmap is sent here for disposal.
      if (cotype == "smart_pointer")
         if DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
            throw Exception("The bitmap of this buffer object has already been deleted.")

      ; Check for unpaired calls of gdiplusShutdown.
      if (TextRender.gdiplus < 0)
         throw Exception("Missing TextRender.gdiplusStartup().")

      ; Shutdown gdiplus when counter goes from 1 -> 0.
      if (TextRender.gdiplus == 0) {
         pToken := TextRender.pToken

         ; Shutdown gdiplus.
         DllCall("gdiplus\GdiplusShutdown", "ptr", pToken)
         DllCall("FreeLibrary", "ptr", DllCall("GetModuleHandle", "str", "gdiplus", "ptr"))

         ; Exit if GDI+ is still loaded. GdiplusNotInitialized = 18
         if (18 != DllCall("gdiplus\GdipCreateImageAttributes", "ptr*", ImageAttr:=0)) {
            DllCall("gdiplus\GdipDisposeImageAttributes", "ptr", ImageAttr)
            return
         }

         ; Otherwise GDI+ has been truly unloaded from the script and objects are out of scope.
         if (cotype = "bitmap")
            throw Exception("Out of scope error. `n`nIf you wish to handle raw pointers to GDI+ bitmaps, add the line"
               . "`n`n`t`t" this.__class ".gdiplusStartup()`n`nor 'pToken := Gdip_Startup()' to the top of your script."
               . "`nAlternatively, use 'obj := ImagePutBuffer()' with 'obj.pBitmap'."
               . "`nYou can copy this message by pressing Ctrl + C.")
      }
   }
} ; End of TextRender class.

; |‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|
; | Double click TextRender.ahk or .exe to show GUI. |
; |__________________________________________________|
if (A_LineFile == A_ScriptFullPath) {
   MsgBox heehee GUI
}

/*
; Check for previous FreeMemory() call.
if (!this.gfx)
   throw Exception("The underlying graphics object and associated bitmaps have been freed.")
*/
