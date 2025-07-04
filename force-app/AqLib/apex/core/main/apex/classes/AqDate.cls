/**
 * Copyright (c) 2020, Aquiva Labs LLC. All rights reserved.
 *
 *
 * Redistribution and use in source and binary forms, with or without modification,
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * - Neither the name of the Aquiva Labs LLC nor the names of its contributors
 *     may be used to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/
/**
 * @group apex/core
 */
public class AqDate {

    private static final String TIME_REGEX = '(\\d{1,2}):(\\d{1,2}) ([PA]M)';

    public static final Date MIN_DATE_TIME = DateTime.newInstance(0).date();	    //January 1, 1970 00:00
    public static final Date MAX_DATE_TIME = DATE_TODAY.addYears(100);

    public static Date DATE_TODAY {
        get {
            return AqEnv.today();
        }
    }

    public static Date DATE_TODAY_GMT {
        get {
            return AqEnv.todayGmt();
        }
    }

    public static DateTime DATE_TIME_TODAY_GMT {
        get {
            return todayGmtAsDateTime();
        }
    }

    public static DateTime todayGmtAsDateTime() {
        return DateTime.newInstanceGmt(AqEnv.now().dateGmt(), Time.newInstance(0, 0, 0, 0));
    }

    public static Time createTime(Integer hh, Integer mm) {
        return Time.newInstance(hh, mm, 0, 0);
    }

    public static DateTime combine(Date day, Time timeInCompanyTimeZone) {

        Aq.requireValue('day', day);
        Aq.requireValue('time', timeInCompanyTimeZone);

        return DateTime.newInstanceGmt(day, timeInCompanyTimeZone).addMinutes(-1 * AqEnv.TimeZoneOffsetCompanyInMinutes);
    }

    public static Time toTime(String timeAsString) {

        Aq.requireValue('timeAsString', timeAsString);

        Pattern p = Pattern.compile(TIME_REGEX);
        Matcher m = p.matcher(timeAsString);

        if (!m.matches()) {
            throw new Aq.ValidationException(AqString.format(Label.Aq_M_UnsupportedTimeFormat, timeAsString));
        }
        Integer hh = Integer.valueOf(m.group(1));
        Integer mm = Integer.valueOf(m.group(2));
        Integer pmShift = m.group(3) == 'PM' ? 12 : 0;

        if (hh == 12 && pmShift == 0) {
            hh = 0;
        } else if (hh == 12 && pmShift == 12) {
            hh = 12;
        } else {
            hh = hh + PmShift;
        }
        return Time.newInstance(hh, mm, 0, 0);
    }

    public static Integer getDiffInMinutes(Datetime dateA, Datetime dateB) {

        Aq.requireValue('dateA', dateA);
        Aq.requireValue('dateB', dateB);
        return Integer.valueOf (
            (dateA.getTime() - dateB.getTime()) / 60000
        );
    }

    public static Date getTodayDateInCompanyTimeZone() {
        return AqEnv.now().addMinutes(AqEnv.TimeZoneOffsetCompanyInMinutes).dateGmt();
    }
}
