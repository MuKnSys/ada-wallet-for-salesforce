/*
 * Copyright (c) 2022, Aquiva Labs LLC. All rights reserved.
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
 * @description Centralizes all custom type conversion and validation
 * @group apex/core
 */
public inherited sharing class AqTypes {

    //Datatypes that can be validated and converted from a string
    public static final String DATATYPE_STRING = 'String';
    public static final String DATATYPE_ID = 'Id';
    public static final String DATATYPE_DATE = 'Date';
    public static final String DATATYPE_TIME = 'Time';
    public static final String DATATYPE_DATETIME = 'Datetime';
    public static final String DATATYPE_EMAIL = 'Email';
    public static final String DATATYPE_BOOLEAN = 'Boolean';
    public static final String DATATYPE_INTEGER = 'Integer';
    public static final String DATATYPE_DECIMAL = 'Decimal';
    public static final String DATATYPE_ZIP = 'ZipCode';
    public static final String DATATYPE_SSN = 'SSN';
    public static final Set<String> DATATYPES_ALL =
        new Set<String> {
            DATATYPE_STRING, DATATYPE_ID, DATATYPE_DATE, DATATYPE_TIME, DATATYPE_DATETIME,
            DATATYPE_EMAIL, DATATYPE_BOOLEAN, DATATYPE_INTEGER, DATATYPE_DECIMAL, DATATYPE_ZIP, DATATYPE_SSN
        };

    public static final Set<String> DATATYPES_PRIMITIVE = new Set<String>{
            DATATYPE_STRING, DATATYPE_DATE, DATATYPE_DATETIME, DATATYPE_DECIMAL, DATATYPE_INTEGER,
            DATATYPE_TIME, DATATYPE_BOOLEAN
    };

    //Boolean string values
    public static final Set<String> TRUE_VALUES = new Set<String>{ 'y', 'true', '1' };
    public static final Set<String> FALSE_VALUES = new Set<String>{ 'n', 'false', '0' };

    private static final String emailRegex = '^[^@]+@[^@]+\\.[^@]+$';
    public static Boolean isValidEmail(String stringValue) {
        return Pattern.matches(emailRegex, stringValue);
    }

    //Indicates whether the string is a valid zip or zip+4 code
    private static final String zipCodeRegex = '^[0-9]{5}(?:-[0-9]{4})?$';
    public static Boolean isValidZipCode(String stringValue) {
        return Pattern.matches(zipCodeRegex, stringValue);
    }

    //Indicates whether the string is a valid SSN (without dashes)
    private static final String ssnRegex = '(^\\d{3}-?\\d{2}-?\\d{4}$|^XXX-XX-XXXX$)';
    public static Boolean isValidSsn(String stringValue) {
        return Pattern.matches(ssnRegex, stringValue);
    }

    //Parse 24-hour time string into Time
    public static Time parseTime(String timeString) {

        return Time.newInstance(Integer.valueOf(timeString.left(2)), Integer.valueOf(timeString.right(2)), 0, 0);
    }

    //Validates and converts a string value to the specified type
    public static AqResult validateAndConvert(String resultScopeType, String resultScope, String dataType, String stringValue, Boolean required, Integer maxLength) {

        //Required?
        if (String.isEmpty(stringValue)) {
            if (required == true) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueRequired, resultScope));
            } else if (dataType == DATATYPE_STRING) {
                return getSuccessResult(stringValue);
            } else {
                return getSuccessResult(null);
            }
        } else if (dataType == DATATYPE_STRING) {

            if (maxLength != null && stringValue.length() > maxLength) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueTooLong, resultScope, maxLength));
            } else {
                return getSuccessResult(stringValue);
            }
        } else if (dataType == DATATYPE_ID) {

            try {
                return getSuccessResult(Id.valueOf(stringValue));
            } catch (System.Exception e) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueIdInvalid, resultScope));
            }

        } else if (dataType == DATATYPE_DATE) {

            try {
                return getSuccessResult(Date.parse(stringValue));
            } catch (System.TypeException e) {
                //Empty on purpose, TypeException means invalid format
            }

            Integer year = null;
            Integer month = null;
            Integer day = null;

            String sep = '-';
            if (pattern.matches('^[0-9]{4}-[0-9]{2}-[0-9]{2}$', stringValue)) {
                //Try YYYY-MM-DD
                year = Integer.valueOf(stringValue.left(4));
                month = Integer.valueOf(stringValue.mid(5, 2));
                day = Integer.valueOf(stringValue.mid(8, 2));
            } else if (pattern.matches('^[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4}$', stringValue)) {
                //Try MM-DD-YYYY
                if (stringValue.contains('/')) {
                    sep = '/';
                }
                List<String> splitted = stringValue.split(sep);
                year = Integer.valueOf(splitted[2]);
                month = Integer.valueOf(splitted[0]);
                day = Integer.valueOf(splitted[1]);
            } else if (pattern.matches('^[0-9]{1,2}\\.[0-9]{2}\\.[0-9]{4}$', stringValue)) {
                //Try DD.MM.YYYY
                if (stringValue.contains('.')) {
                    sep = '\\.';
                }
                List<String> splitted = stringValue.split(sep);
                year = Integer.valueOf(splitted[2]);
                month = Integer.valueOf(splitted[1]);
                day = Integer.valueOf(splitted[0]);
            }

            try {

                Date dateResult = Date.newInstance(year, month, day);

                //newInstance does weird things with months > 12, make sure it converted it right
                if (dateResult.year() != year || dateResult.month() != month || dateResult.day() != day) {
                    return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueDateInvalid, resultScope));
                } else {
                    return getSuccessResult(dateResult);
                }

            } catch (System.Exception e) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueDateInvalid, resultScope));
            }

        } else if (dataType == DATATYPE_TIME) {

            try {
                //Must be HH:mm
                if (stringValue.length() != 5 || stringValue.mid(2, 1) != ':')
                    return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueTimeInvalid, resultScope));

                Integer hour = Integer.valueOf(stringValue.left(2));
                Integer minute = Integer.valueOf(stringValue.right(2));
                Integer second = 0;
                if (hour > 24 || hour < 0 || minute > 59 || minute < 0 || second > 59 || second < 0) {
                    return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueTimeInvalid, resultScope));
                } else {
                    return getSuccessResult(Time.newInstance(hour, minute, second, 0));
                }
            } catch (System.Exception e) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueTimeInvalid, resultScope));
            }

        } else if (dataType == DATATYPE_DATETIME) {

            try {
                return getSuccessResult((DateTime)JSON.deserialize('"' + stringValue + '"', DateTime.class));
            } catch (System.Exception e) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueDatetimeInvalid, resultScope));
            }
        } else if (dataType == DATATYPE_EMAIL) {

            if (!isValidEmail(stringValue)) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueEmailInvalid, resultScope));
            } else {
                return getSuccessResult(stringValue);
            }
        } else if (dataType == DATATYPE_BOOLEAN) {

            if (AqTypes.TRUE_VALUES.contains(stringValue.toLowerCase())) {
                return getSuccessResult(true);
            } else if (AqTypes.FALSE_VALUES.contains(stringValue.toLowerCase())) {
                return getSuccessResult(false);
            } else {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueBooleanInvalid, resultScope));
            }
        } else if (dataType == DATATYPE_INTEGER) {

            try {
                return getSuccessResult(Integer.valueOf(stringValue));
            } catch (System.Exception e) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueIntegerInvalid, resultScope));
            }
        } else if (dataType == DATATYPE_DECIMAL) {

            try {
                return getSuccessResult(Decimal.valueOf(stringValue));
            } catch (System.Exception e) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueDecimalInvalid, resultScope));
            }
        } else if (dataType == DATATYPE_ZIP) {

            if (isValidZipCode(stringValue)) {
                return getSuccessResult(stringValue);
            } else {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueZipInvalid, resultScope));
            }

        } else if (dataType == DATATYPE_SSN) {

            if (isValidSsn(stringValue)) {
                return getSuccessResult(stringValue);
            } else {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueSsnInvalid, resultScope));
            }

        } else {
            throw new Aq.ValidationException(AqString.format(Label.Aq_M_ValueTypeUnknown, dataType));
        }

    }

    //Validate string to match any Regex pattern
    public static AqResult validatePattern(String resultScopeType, String resultScope, String value, Boolean required, String regEx, String patternLabel) {

        if (String.isEmpty(value)) {

            if (required == true) {
                return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValueRequired, resultScope));
            } else {
                return getSuccessResult(value);
            }
        }

        if (!System.Pattern.matches(regEx, value)) {
            return getErrorResult(resultScopeType, resultScope, AqString.format(Label.Aq_M_ValuePatternInvalid, resultScope, patternLabel));
        } else {
            return getSuccessResult(value);
        }
    }

    private static AqResult getSuccessResult(object value) {

        return new AqResultBuilder()
            .setType('ValidationResult')
            .setSeverity(AqResult.SEVERITY_SUCCESS)
            .setReturnValue(value)
            .setLevel(AqResult.LEVEL_BUSINESS)
            .createAqResult();
    }

    private static AqResult getErrorResult(String resultScopeType, String resultScope, String message) {

        return new AqResultBuilder()
            .setType(Aq.ValidationException.class.getName())
            .setSeverity(AqResult.SEVERITY_ERROR)
            .setScopeType(resultScopeType)
            .setScope(resultScope)
            .setMessage(message)
            .setLevel(AqResult.LEVEL_BUSINESS)
            .createAqResult();
    }

}
