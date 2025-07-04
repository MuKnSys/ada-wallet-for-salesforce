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

//Unit tests for AqLog.cls
@isTest
private with sharing class AqTest_AqLog {

    private static final String TEST_TYPE = 'Type';
    private static final String TEST_SCOPE_TYPE = 'ScopeType';
    private static final String TEST_SCOPE = 'Scope';
    private static final String TEST_SOURCE = 'Source';
    private static final String TEST_CODE = 'Code';
    private static final String TEST_MESSAGE = 'Test message.';
    private static final String TEST_DETAIL = 'Test details.';

    @TestSetup
    private static void setup() {
        AqTest.setup();
    }

    //logResult(), getMostRecent()
    @isTest
    private static void testLogResult() {
        System.runAs(AqTest.adminUser) {
            System.assertEquals(null, AqLog.getMostRecent());

            AqResult result = new AqResultBuilder()
                    .setType(TEST_TYPE)
                    .setSeverity(AqResult.SEVERITY_ERROR)
                    .setLevel(AqResult.LEVEL_BUSINESS)
                    .setMessage(TEST_MESSAGE)
                    .setScopeType(TEST_SCOPE_TYPE)
                    .setScope(TEST_SCOPE)
                    .setResultDate(AqEnv.now())
                    .setDetail(TEST_DETAIL)
                    .setCode(TEST_CODE)
                    .setSource(TEST_SOURCE)
                    .createAqResult();

            AqLog.logResult(result);

            LogDgt__c log = AqLog.getMostRecent();
            compareLogWithResult(log, result);

            log = AqLog.retrieve(log.Id);
            compareLogWithResult(log, result);

            //Test with non-string detail value for JSON serialization
            result.Detail = Date.newInstance(2017, 1, 1);
            AqLog.logResult(result);
            log = AqLog.getMostRecent();
            compareLogWithResult(log, result);
        }
    }

    //logException()
    @isTest
    private static void testLogException() {

        try {

            Integer i = 1/0;
            System.assert(false, 'Excepted exception.');

        }
        catch (System.Exception e) {

            LogDgt__c log = AqLog.logException(e, 'Source');
            System.assertNotEquals(null, log.Id);
            System.assertEquals('Source', log.Source__c);

            LogDgt__c log2 = AqLog.logException(e, 'Source', 'ScopeType', 'Scope');
            System.assertNotEquals(null, log.Id);
            System.assertEquals('Source', log2.Source__c);
            System.assertEquals('ScopeType', log2.ScopeType__c);
            System.assertEquals('Scope', log2.Scope__c);

        }

    }

    private static void compareLogWithResult(LogDgt__c log, AqResult result) {
        System.assertEquals(result.Type, log.ResultType__c);
        System.assertEquals(result.Severity, log.Severity__c);
        System.assertEquals(result.Level, log.Level__c);
        System.assertEquals(result.Message, log.Message__c);
        System.assertEquals(result.ScopeType, log.ScopeType__c);
        System.assertEquals(result.Scope, log.Scope__c);
        System.assertEquals(result.Source, log.Source__c);
        System.assertEquals(result.Code, log.Code__c);
        System.assertEquals(result.Detail instanceof String ? result.Detail : JSON.serialize(result.Detail), log.Detail__c);
        System.assertEquals(result.ResultDate, log.LogDate__c);
    }

}
