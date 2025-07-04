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

//Unit tests for AqTypes.cls
@isTest
private with sharing class AqTest_AqTypes {

    private static final String TEST_RESULT_TYPE = 'TestResultType';
    private static final String TEST_SCOPE = 'TestScope';

    @isTest
    private static void testValidateAndConvert() {

        //Required/not required
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_STRING, null, true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_STRING, '', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_STRING, null, false, null, AqResult.SEVERITY_SUCCESS, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_STRING, '', false, null, AqResult.SEVERITY_SUCCESS, '');
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_INTEGER, '', false, null, AqResult.SEVERITY_SUCCESS, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_STRING, 'Foo', true, null, AqResult.SEVERITY_SUCCESS, 'Foo');

        //Max string length
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_STRING, 'LongerThan5', true, 5, AqResult.SEVERITY_ERROR, null);

        //Id
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_ID, 'Not an Id', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_ID, '0034100000OavRe', true, null, AqResult.SEVERITY_SUCCESS, Id.valueOf('0034100000OavRe'));
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_ID, '0034100000OavE2AAJ', true, null, AqResult.SEVERITY_SUCCESS, Id.valueOf('0034100000OavE2AAJ'));

        //Date
        Date targetDate = Date.newInstance(2017, 6, 14);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATE, 'NotADate', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATE, '2017-13-14', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATE, '13-13-2014', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATE, '2017-06-14', true, null, AqResult.SEVERITY_SUCCESS, targetDate);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATE, '6/14/2017', true, null, AqResult.SEVERITY_SUCCESS, targetDate);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATE, '06-14-2017', true, null, AqResult.SEVERITY_SUCCESS, targetDate);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATE, '14.06.2017', true, null, AqResult.SEVERITY_SUCCESS, targetDate);

        //Time
        Time targetTime = Time.newInstance(13, 30, 0, 0);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_TIME, 'NotATime', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_TIME, '25:30', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_TIME, '13:60', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_TIME, '13:30', true, null, AqResult.SEVERITY_SUCCESS, targetTime);

        //DateTime
        DateTime targetDateTime = DateTime.newInstanceGmt(2017, 6, 14, 8, 0, 0);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATETIME, 'NotADateTime', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DATETIME, '2017-06-14T08:00:00Z', true, null, AqResult.SEVERITY_SUCCESS, targetDateTime);

        //Email
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_EMAIL, 'not@valid', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_EMAIL, 'test@test.com', true, null, AqResult.SEVERITY_SUCCESS, 'test@test.com');

        //Boolean
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'NotBoolean', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'true', true, null, AqResult.SEVERITY_SUCCESS, true);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'TRUE', true, null, AqResult.SEVERITY_SUCCESS, true);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'Y', true, null, AqResult.SEVERITY_SUCCESS, true);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'y', true, null, AqResult.SEVERITY_SUCCESS, true);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, '1', true, null, AqResult.SEVERITY_SUCCESS, true);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'false', true, null, AqResult.SEVERITY_SUCCESS, false);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'FALSE', true, null, AqResult.SEVERITY_SUCCESS, false);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'N', true, null, AqResult.SEVERITY_SUCCESS, false);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, 'n', true, null, AqResult.SEVERITY_SUCCESS, false);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_BOOLEAN, '0', true, null, AqResult.SEVERITY_SUCCESS, false);

        //Integer
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_INTEGER, 'NotInteger', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_INTEGER, '12345', true, null, AqResult.SEVERITY_SUCCESS, 12345);

        //Decimal
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DECIMAL, 'NotDecimal', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_DECIMAL, '123.45', true, null, AqResult.SEVERITY_SUCCESS, 123.45);

        //Zip
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_ZIP, '1234', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_ZIP, '03904-1234', true, null, AqResult.SEVERITY_SUCCESS, '03904-1234');
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_ZIP, '03038', true, null, AqResult.SEVERITY_SUCCESS, '03038');

        //Ssn
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_SSN, '1234', true, null, AqResult.SEVERITY_ERROR, null);
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_SSN, '123-45-3728', true, null, AqResult.SEVERITY_SUCCESS, '123-45-3728');
        verifyValidateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, AqTypes.DATATYPE_SSN, '123456372', true, null, AqResult.SEVERITY_SUCCESS, '123456372');

        //Bad type
        try {
            AqResult result = AqTypes.validateAndConvert(TEST_RESULT_TYPE, TEST_SCOPE, 'BAD_TYPE', 'foo', false, null);
            System.assert(false, 'Expected ValidationException.');
        } catch (Aq.ValidationException e) {
            System.assert(true);
        }
    }

    //Verify one call to validateAndConvert
    private static void verifyValidateAndConvert(
        String resultType, String resultScope, String dataType, String stringValue, Boolean required,
        Integer maxLength, String expectedSeverity, object expectedReturnValue
    ) {

        AqResult result = AqTypes.validateAndConvert(resultType, resultScope, dataType, stringValue, required, maxLength);
        System.assertEquals(expectedSeverity, result.Severity);
        System.assertEquals(expectedReturnValue, result.ReturnValue);

    }

    @isTest
    private static void testValidatePattern() {

        String regEx = '\\d{3}.\\d{3}-\\d{3}';
        String patternLabel = '###.###-###';

        //Test required
        AqTest.assertError(Aq.ValidationException.class, AqTypes.validatePattern('MyScopeType', 'MyScope', null, true, regEx, patternLabel));
        AqTest.assertError(Aq.ValidationException.class, AqTypes.validatePattern('MyScopeType', 'MyScope', '', true, regEx, patternLabel));
        AqTest.assertError(Aq.ValidationException.class, AqTypes.validatePattern('MyScopeType', 'MyScope', 'foobar', true, regEx, patternLabel));
        AqTest.assertSuccess(AqTypes.validatePattern('MyScopeType', 'MyScope', '123.456-789', true, regEx, patternLabel));
    }

    @isTest
    private static void testParse() {

        Time theTime = AqTypes.parseTime('13:17');
        System.assertEquals(13, theTime.hour());
        System.assertEquals(17, theTime.minute());
        System.assertEquals(0, theTime.second());
        System.assertEquals(0, theTime.millisecond());
    }

}
