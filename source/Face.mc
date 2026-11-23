import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class MarsFace extends WatchUi.WatchFace {
    var _background as WatchUi.BitmapResource or Null = null;
    var _phase as Lang.Number = -1;
    var _bigFont as Graphics.FontType;
    var _smallFont as Graphics.FontType;
    var _sleeping as Lang.Boolean = false;
    var _width as Lang.Number = 466;
    var _compact as Lang.Boolean = false;
    var _ink as Lang.Number = 0xf6e7c8;
    var _accent as Lang.Number = 0xff7a1e;
    var _dateInk as Lang.Number = 0x8fe0d6;
    var _shadow as Lang.Number = 0x080c18;

    function initialize() {
        WatchFace.initialize();
        _bigFont = WatchUi.loadResource(Rez.Fonts.TimeFont) as Graphics.FontType;
        _smallFont = WatchUi.loadResource(Rez.Fonts.SmallFont) as Graphics.FontType;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _width = dc.getWidth();
        _compact = _width < 300;
    }

    function onHide() as Void {
        _background = null;
        _phase = -1;
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleeping = false;
        WatchUi.requestUpdate();
    }

    function px(value as Lang.Numeric) as Lang.Number {
        return Math.round(value * _width).toNumber();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var hours = hour.format("%02d");
        var minutes = clock.min.format("%02d");

        if (self has :handleDisplayMode) {
            if (handleDisplayMode(dc, hours + ":" + minutes, clock.min)) { return; }
        }

        var phase = sceneForHour(clock.hour);
        var setting = Application.Properties.getValue("Scene");
        if (setting instanceof Lang.Number && setting >= 1 && setting <= 4) {
            phase = setting - 1;
        }
        if (phase != _phase || _background == null) {
            // Drop the old bitmap before loading another into the 5X's small heap.
            _background = null;
            var scenes = [Rez.Drawables.Dawn, Rez.Drawables.Day,
                          Rez.Drawables.Dusk, Rez.Drawables.Night];
            _background = WatchUi.loadResource(scenes[phase]) as WatchUi.BitmapResource;
            _phase = phase;
        }
        dc.drawBitmap(0, 0, _background as WatchUi.BitmapResource);
        setInks(phase);
        drawClock(dc, hours, minutes);
        drawBadges(dc);
        drawLadder(dc, clock.hour);
    }

    function sceneForHour(hour as Lang.Number) as Lang.Number {
        if (hour >= 5 && hour < 8) { return 0; }
        if (hour >= 8 && hour < 17) { return 1; }
        if (hour >= 17 && hour < 20) { return 2; }
        return 3;
    }

    function setInks(phase as Lang.Number) as Void {
        _ink = phase == 1 ? 0x3b1a10 : 0xf6e7c8;
        _accent = phase == 1 ? 0xb0340a : 0xff7a1e;
        _dateInk = phase == 1 ? 0x2c4042 : 0x8fe0d6;
        _shadow = phase == 1 ? 0xf0d6b4 : 0x080c18;
    }

    function text(dc as Graphics.Dc, value as Lang.String, x as Lang.Numeric,
                  y as Lang.Numeric, font as Graphics.FontType,
                  color as Lang.Number, shadow as Lang.Number) as Void {
        if (shadow > 0) {
            dc.setColor(_shadow, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + shadow, y + shadow, font, value, Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, value, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function drawClock(dc as Graphics.Dc, hours as Lang.String, minutes as Lang.String) as Void {
        var whole = hours + ":" + minutes;
        var tw = dc.getTextWidthInPixels(whole, _bigFont);
        var x = px(0.33) - tw / 2;
        var y = px(0.285);
        var prefix = hours + ":";
        text(dc, prefix, x, y, _bigFont, _ink, _compact ? 1 : 2);
        x += dc.getTextWidthInPixels(prefix, _bigFont);
        text(dc, minutes, x, y, _bigFont, _accent, _compact ? 1 : 2);

        var date = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var label = (date.day_of_week as Lang.String).toUpper() + " " +
                    (date.month as Lang.String).toUpper() + " " + date.day.format("%02d");
        var dw = dc.getTextWidthInPixels(label, _smallFont);
        x = px(0.33) - dw / 2;
        y += dc.getFontHeight(_bigFont) + px(0.02);
        text(dc, label, x, y, _smallFont, _dateInk, 1);
        var lineY = y + dc.getFontHeight(_smallFont) / 2;
        dc.setColor(_dateInk, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(_compact ? 1 : 2);
        if (x - px(0.025) > px(0.085)) {
            dc.drawLine(px(0.085), lineY, x - px(0.025), lineY);
        }
        if (x + dw + px(0.025) < px(0.575)) {
            dc.drawLine(x + dw + px(0.025), lineY, px(0.575), lineY);
        }
    }

    function drawBadges(dc as Graphics.Dc) as Void {
        var info = ActivityMonitor.getInfo();
        var count = info.steps;
        var steps = count == null ? "--" : formatSteps(count);
        var hr = "--";
        var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
        var heartRate = sample == null ? null : sample.heartRate;
        if (heartRate != null && heartRate != ActivityMonitor.INVALID_HR_SAMPLE && heartRate > 0) {
            hr = heartRate.toNumber().toString();
        }
        var battery = Math.round(System.getSystemStats().battery).toNumber();
        var y = px(0.285) + dc.getFontHeight(_bigFont) + px(0.02)
                + dc.getFontHeight(_smallFont) + px(0.022);
        var h = dc.getFontHeight(_smallFont) + 2 * px(0.0125);
        badge(dc, y, "^", steps, 0x8fe0d6, false, battery);
        y += h + px(0.01);
        if (_compact) {
            badge(dc, y, "<", hr + "  " + battery + "%", 0xff7a1e, false, battery);
        } else {
            badge(dc, y, "<", hr, 0xff7a1e, false, battery);
            badge(dc, y + h + px(0.01), "", battery + "%", 0x8fe0d6, true, battery);
        }
    }

    function formatSteps(steps as Lang.Number) as Lang.String {
        if (steps < 1000) { return steps.toString(); }
        return (steps / 1000).toNumber().toString() + "," + (steps % 1000).format("%03d");
    }

    function badge(dc as Graphics.Dc, y as Lang.Number, icon as Lang.String,
                   value as Lang.String, iconColor as Lang.Number,
                   isBattery as Lang.Boolean, battery as Lang.Number) as Void {
        var scale = 2;
        var x = px(0.075);
        var h = dc.getFontHeight(_smallFont) + 2 * px(0.0125);
        var pad = px(0.02);
        var iconWidth = isBattery ? 10 * scale : dc.getTextWidthInPixels(icon, _smallFont);
        var valueX = x + pad + iconWidth + px(0.016);
        var right = valueX + dc.getTextWidthInPixels(value, _smallFont) + pad + h / 2;
        var points = [[x + h / 4, y], [right, y], [right, y + h / 2],
                      [right - h / 2, y + h], [x, y + h], [x, y + h / 4]];
        dc.setColor(0x0d1a2b, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
        dc.setColor(0x8fe0d6, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(_compact ? 1 : 2);
        for (var i = 0; i < points.size(); i++) {
            var next = (i + 1) % points.size();
            dc.drawLine(points[i][0], points[i][1], points[next][0], points[next][1]);
        }
        var textY = y + (h - dc.getFontHeight(_smallFont)) / 2;
        if (isBattery) {
            var bx = x + pad;
            var by = y + (h - 5 * scale) / 2;
            dc.setColor(0xf6e7c8, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(bx, by, 9 * scale, 5 * scale);
            dc.fillRectangle(bx + 9 * scale, by + scale, scale, 3 * scale);
            dc.setColor(0x8fe0d6, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + 2 * scale, by + 2 * scale, Math.round(5 * scale * battery / 100.0), scale);
        } else {
            text(dc, icon, x + pad, textY, _smallFont, iconColor, 0);
        }
        text(dc, value, valueX, textY, _smallFont, 0xf6e7c8, 0);
    }

    function drawLadder(dc as Graphics.Dc, hour as Lang.Number) as Void {
        var levels = [0.700, 0.637, 0.573, 0.510, 0.447, 0.383, 0.320];
        var positions = [0.745, 0.775, 0.800, 0.845, 0.905, 0.905, 0.895];
        var is24Hour = System.getDeviceSettings().is24Hour;
        for (var i = 0; i < levels.size(); i++) {
            var rung = (hour + i - 3 + 24) % 24;
            if (!is24Hour) {
                rung = rung % 12;
                if (rung == 0) { rung = 12; }
            }
            var label = rung.toString();
            var y = px(levels[i]);
            var edge = _width / 2 + Math.sqrt(Math.pow(_width / 2.0, 2) - Math.pow(y - _width / 2.0, 2)) - 6;
            var x = px(positions[i]);
            var maxX = (edge - dc.getTextWidthInPixels(label, _smallFont)).toNumber();
            if (x > maxX) { x = maxX; }
            var current = i == 3;
            var color = current ? (_phase == 1 ? 0xffd64a : 0xff7a1e) : 0xf6e7c8;
            var end = x - (current ? 14 : 4);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(_compact ? 1 : 2);
            dc.drawLine(end - px(0.03), y, end, y);
            var textY = y - dc.getFontHeight(_smallFont) / 2;
            if (current) { text(dc, "*", x - 12, textY + 2, _smallFont, color, 0); }
            if (!_compact || i % 2 == 1) {
                var oldShadow = _shadow;
                _shadow = 0x080c18;
                text(dc, label, x, textY, _smallFont, color, 1);
                _shadow = oldShadow;
            }
        }
    }

    (:amoled)
    function handleDisplayMode(dc as Graphics.Dc, value as Lang.String,
                               minute as Lang.Number) as Lang.Boolean {
        var mode = System.getDisplayMode();
        if (mode == System.DISPLAY_MODE_OFF) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            return true;
        }
        if (_sleeping || mode == System.DISPLAY_MODE_LOW_POWER) {
            drawAlwaysOn(dc, value, minute);
            return true;
        }
        return false;
    }

    (:amoled)
    function drawAlwaysOn(dc as Graphics.Dc, value as Lang.String, minute as Lang.Number) as Void {
        _background = null;
        _phase = -1;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // Four disjoint positions prevent a lit pixel persisting for three minutes.
        var slot = minute % 4;
        var x = px(slot % 2 == 0 ? 0.28 : 0.55);
        var y = px(slot < 2 ? 0.42 : 0.58);
        text(dc, value, x, y, _smallFont, 0x555555, 0);
    }
}
