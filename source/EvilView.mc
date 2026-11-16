import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// EVIL - tactical data face for fenix 6X Pro / Sapphire (280x280 MIP, 64 colors).
//
// Only pure palette colors are used (each channel 0x00/0x55/0xAA/0xFF) so nothing
// is dithered. Anything that has to be readable without the backlight is white;
// red is kept for large or bold elements, where a MIP panel can still carry it.
class EvilView extends WatchUi.WatchFace {

    // ---- Colors ----
    private const C_BG    = 0x000000;
    private const C_WHITE = 0xFFFFFF;
    private const C_RED   = 0xFF0000;
    private const C_AMBER = 0xFFAA00;
    private const C_LABEL = 0xAAAAAA;
    private const C_DIM   = 0x555555;

    // ---- Layout (y values are the top of the capitals) ----
    private const CX        = 140;
    private const CY        = 140;
    private const FONT_PAD  = 2;     // blank rows above the capitals in every custom font
    private const DATE_Y    = 31;
    private const ROW1_Y    = 53;
    private const TIME_Y    = 91;
    private const DIVIDER_Y = 157;
    private const ROW2_Y    = 166;
    private const ROW3_Y    = 203;
    private const PLATE_Y   = 236;
    private const COL_L     = 72;
    private const COL_R     = 208;
    private const COL3_L    = 80;    // bottom row is narrower because of the round screen
    private const COL3_R    = 200;
    private const NAME      = "EVIL";

    private var mDays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
    private var mMonths = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
    private var mDaysBefore = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];

    private var mTimeFont;
    private var mValueFont;
    private var mDateFont;
    private var mLabelFont;
    private var mAwake = true;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
        mTimeFont = WatchUi.loadResource(Rez.Fonts.TimeFont);
        mValueFont = WatchUi.loadResource(Rez.Fonts.ValueFont);
        mDateFont = WatchUi.loadResource(Rez.Fonts.DateFont);
        mLabelFont = WatchUi.loadResource(Rez.Fonts.LabelFont);
    }

    function onExitSleep() {
        mAwake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() {
        mAwake = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        dc.setColor(C_BG, C_BG);
        dc.clear();

        var clock = System.getClockTime();
        var settings = System.getDeviceSettings();
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var activity = ActivityMonitor.getInfo();

        drawBezel(dc);
        if (mAwake) {
            drawSecondsHand(dc, clock.sec);
        }

        // date
        var date = mDays[today.day_of_week - 1] + " " + today.day.format("%02d") + " " + mMonths[today.month - 1];
        text(dc, CX, DATE_Y, mDateFont, date, C_WHITE, Graphics.TEXT_JUSTIFY_CENTER);

        // row 1: heart rate, ISO week, notifications
        var hr = getHeartRate();
        var hrColor = C_WHITE;
        if (hr != null && hr >= 140) {
            hrColor = C_RED;
        } else if (hr != null && hr >= 100) {
            hrColor = C_AMBER;
        }
        var msgs = settings.notificationCount;
        cell(dc, COL_L, ROW1_Y, "HR", hr != null ? hr.toString() : "--", hrColor);
        cell(dc, CX, ROW1_Y, "WEEK", isoWeek(today).toString(), C_WHITE);
        cell(dc, COL_R, ROW1_Y, "MSG", msgs.toString(), msgs > 0 ? C_RED : C_WHITE);
        separators(dc, ROW1_Y, (COL_L + CX) / 2, (CX + COL_R) / 2);

        drawTime(dc, clock, settings.is24Hour);

        // divider
        dc.setColor(C_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(36, DIVIDER_Y, 8, 3);
        dc.fillRectangle(48, DIVIDER_Y + 1, 184, 1);
        dc.fillRectangle(236, DIVIDER_Y, 8, 3);

        // row 2: battery, steps, step goal
        var stats = System.getSystemStats();
        var battery = (stats.battery + 0.5).toNumber();
        var charging = (stats has :charging) && stats.charging;
        var steps = activity.steps != null ? activity.steps : 0;
        var goal = (activity.stepGoal != null && activity.stepGoal > 0) ? activity.stepGoal : 10000;
        cell(dc, COL_L, ROW2_Y, charging ? "CHG" : "BAT", battery.toString() + "%", battery <= 20 ? C_RED : C_WHITE);
        cell(dc, CX, ROW2_Y, "STEPS", steps.toString(), C_WHITE);
        cell(dc, COL_R, ROW2_Y, "GOAL", (steps * 100 / goal).toString() + "%", C_RED);
        separators(dc, ROW2_Y, (COL_L + CX) / 2, (CX + COL_R) / 2);

        // row 3: temperature, chance of rain, distance
        var metric = settings.distanceUnits == System.UNIT_METRIC;
        var temp = "--";
        var rain = "--";
        if (Toybox has :Weather) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null) {
                if (conditions.temperature != null) {
                    var t = conditions.temperature;
                    if (settings.temperatureUnits == System.UNIT_STATUTE) {
                        temp = (t * 9.0 / 5.0 + 32.0).format("%d") + "°F";
                    } else {
                        temp = t.format("%d") + "°C";
                    }
                }
                if (conditions.precipitationChance != null) {
                    rain = conditions.precipitationChance.format("%d") + "%";
                }
            }
        }
        var dist = (activity.distance != null ? activity.distance : 0) / (metric ? 100000.0 : 160934.4);
        cell(dc, COL3_L, ROW3_Y, "TEMP", temp, C_WHITE);
        cell(dc, CX, ROW3_Y, "RAIN", rain, C_WHITE);
        cell(dc, COL3_R, ROW3_Y, metric ? "KM" : "MI", dist.format(dist < 100 ? "%.1f" : "%d"), C_RED);
        separators(dc, ROW3_Y, (COL3_L + CX) / 2, (CX + COL3_R) / 2);

        // name plate
        dc.setColor(C_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(CX - 30, PLATE_Y, 60, 17);
        text(dc, CX, PLATE_Y + 2, mDateFont, NAME, C_BG, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ---------------------------------------------------------------- bezel

    private function drawBezel(dc) {
        for (var m = 0; m < 60; m++) {
            var a = Math.toRadians(m * 6);
            var sin = Math.sin(a);
            var cos = Math.cos(a);
            if (m == 0) {
                dc.setColor(C_RED, Graphics.COLOR_TRANSPARENT);
                dc.fillPolygon([[CX - 8, 1], [CX + 8, 1], [CX, 14]]);
            } else if (m % 5 == 0) {
                dc.setColor(C_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                dc.drawLine(CX + 131 * sin, CY - 131 * cos, CX + 140 * sin, CY - 140 * cos);
                dc.setPenWidth(1);
                // 55 and 5 would collide with the date
                if (m != 5 && m != 55) {
                    text(dc, CX + 120 * sin, CY - 120 * cos - 4, mLabelFont, m.toString(), C_LABEL, Graphics.TEXT_JUSTIFY_CENTER);
                }
            } else {
                dc.setColor(C_LABEL, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(CX + 135 * sin, CY - 135 * cos, CX + 140 * sin, CY - 140 * cos);
            }
        }
    }

    // Red chronograph marker on the bezel; only drawn while the watch is awake
    private function drawSecondsHand(dc, sec) {
        var a = Math.toRadians(sec * 6);
        var side = Math.toRadians(3);
        dc.setColor(C_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [CX + 114 * Math.sin(a), CY - 114 * Math.cos(a)],
            [CX + 140 * Math.sin(a - side), CY - 140 * Math.cos(a - side)],
            [CX + 140 * Math.sin(a + side), CY - 140 * Math.cos(a + side)]
        ]);
    }

    // ----------------------------------------------------------------- time

    private function drawTime(dc, clock, is24Hour) {
        var hour = clock.hour;
        if (!is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        var hours = hour.format("%02d");
        var minutes = clock.min.format("%02d");
        var wHours = dc.getTextWidthInPixels(hours, mTimeFont);
        var wColon = dc.getTextWidthInPixels(":", mTimeFont);
        var x = CX - (wHours + wColon + dc.getTextWidthInPixels(minutes, mTimeFont) - 3) / 2;

        text(dc, x, TIME_Y, mTimeFont, hours, C_WHITE, Graphics.TEXT_JUSTIFY_LEFT);
        text(dc, x + wHours, TIME_Y, mTimeFont, ":", C_RED, Graphics.TEXT_JUSTIFY_LEFT);
        text(dc, x + wHours + wColon, TIME_Y, mTimeFont, minutes, C_RED, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // -------------------------------------------------------------- helpers

    // Draws text so that the top of its capitals lands exactly on y
    private function text(dc, x, y, font, str, color, justify) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y - FONT_PAD, font, str, justify);
    }

    // Small grey label with the value underneath
    private function cell(dc, cx, y, label, value, color) {
        text(dc, cx, y, mLabelFont, label, C_LABEL, Graphics.TEXT_JUSTIFY_CENTER);
        text(dc, cx, y + 13, mValueFont, value, color, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function separators(dc, y, x1, x2) {
        dc.setColor(C_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x1, y + 1, x1, y + 29);
        dc.drawLine(x2, y + 1, x2, y + 29);
    }

    private function getHeartRate() {
        var hr = null;
        var info = Activity.getActivityInfo();
        if (info != null) {
            hr = info.currentHeartRate;
        }
        if (hr == null && (ActivityMonitor has :getHeartRateHistory)) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }
        return hr;
    }

    private function isLeap(year) {
        return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    }

    // 53 if the ISO year has a week 53, else 52
    private function weeksInYear(year) {
        var p = (year + year / 4 - year / 100 + year / 400) % 7;
        var y = year - 1;
        var q = (y + y / 4 - y / 100 + y / 400) % 7;
        return (p == 4 || q == 3) ? 53 : 52;
    }

    private function isoWeek(today) {
        var dayOfYear = mDaysBefore[today.month - 1] + today.day;
        if (today.month > 2 && isLeap(today.year)) {
            dayOfYear += 1;
        }
        var weekday = (today.day_of_week + 5) % 7 + 1;   // Monday = 1 ... Sunday = 7
        var week = (dayOfYear - weekday + 10) / 7;
        if (week < 1) {
            return weeksInYear(today.year - 1);
        }
        if (week > weeksInYear(today.year)) {
            return 1;
        }
        return week;
    }
}
