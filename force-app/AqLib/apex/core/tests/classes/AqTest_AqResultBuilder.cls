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

@IsTest
private inherited sharing class AqTest_AqResultBuilder {

    private static final String TEST_TYPE = 'TestResultType';
    private static final String TEST_MESSAGE = 'Test message.';
    private static final String TEST_CODE = 'TestCode';
    private static final String TEST_SCOPE_TYPE = 'TestScopeType';
    private static final String TEST_SCOPE = 'Test.Scope';
    private static final String TEST_SOURCE = 'Test Source';
    private static final String TEST_DETAIL = 'Test Detail';
    private static final String TEST_RETURN_VALUE = 'Test Return Value';

    @IsTest
    private static void testSetException() {
        try {
            TestObject__c testRecord = new TestObject__c();
            insert testRecord;
            System.assert(false, 'Should get exception');
        } catch (System.Exception e) {

            Test.startTest();
            AqResult result = new AqResultBuilder().setException(e).createAqResult();
            Test.stopTest();

            System.assertEquals('System.DmlException', result.Type, 'Type should contain System.DmlException');
            System.assertEquals(e.getMessage(), result.Message, 'Message should contain dml\'s exception message');
            System.assertEquals(AqEnv.today(), result.ResultDate.date(), 'Result Date should contain today\'s day');
            System.assertEquals(AqResult.LEVEL_INTERNAL, result.Level, 'Level should contain ' + AqResult.LEVEL_INTERNAL);
            System.assert(result.Detail != null, 'Detail should be populated after dml exception');

            for (AqResult subResult : result.SubResults) {
                System.assertEquals(AqResult.RESULT_TYPE_DML_ROW_DETAIL, subResult.Type,
                    'SubResult\'s Type should contain System.DmlException');
                System.assertEquals(AqResult.SEVERITY_ERROR, subResult.Severity,
                    'SubResult\'s Severity should contain Error after dml exception');
                System.assert(subResult.Detail != null, 'Detail should be populated for subResult after dml exception');
            }
        }
    }

    @IsTest
    private static void testSetSaveResult() {
        TestObject__c testRecord = new TestObject__c();
        Database.SaveResult saveResult = Database.insert(testRecord, false);
        System.assertEquals(false, saveResult.isSuccess());

        Test.startTest();
        AqResult result = new AqResultBuilder()
            .setSaveResult(saveResult, TestObject__c.SObjectType)
            .setScope(TEST_SCOPE)
            .createAqResult();
        Test.stopTest();

        System.assertEquals(AqResult.RESULT_TYPE_SAVE, result.Type, 'Type should contain ' + AqResult.RESULT_TYPE_SAVE);
        System.assertEquals(AqResult.SEVERITY_ERROR, result.Severity, 'Severity should contain ' + AqResult.SEVERITY_ERROR);
        System.assertEquals(AqResult.SCOPE_TYPE_RECORD, result.ScopeType, 'Scope type should contain ' + AqResult.SCOPE_TYPE_RECORD);
        System.assertEquals(AqResult.LEVEL_BUSINESS, result.Level, 'Level should contain ' + AqResult.LEVEL_BUSINESS);
        System.assertEquals(AqResultBuilder.SAVE_ERROR_MESSAGE, result.Message,
            'Message should contain ' + AqResultBuilder.SAVE_ERROR_MESSAGE);
        System.assert(result.Scope != null, 'Scope should not be null');

        for (AqResult subResult : result.SubResults) {
            System.assertEquals(AqResult.RESULT_TYPE_DATABASE_ERROR, subResult.Type,
                'SubResult\'s type should contain ' + AqResult.RESULT_TYPE_DATABASE_ERROR);
            System.assertEquals(AqResult.SEVERITY_ERROR, subResult.Severity,
                'SubResult\'s severity should contain ' + AqResult.SEVERITY_ERROR);
            System.assertEquals(AqResult.SCOPE_TYPE_FIELD, subResult.ScopeType,
                'SubResult\'s scope type should contain ' + AqResult.SCOPE_TYPE_FIELD);
            System.assertEquals(AqResult.LEVEL_INTERNAL, subResult.Level,
                'SubResult\'s level should contain ' + AqResult.LEVEL_INTERNAL);
            System.assert(subResult.Message != null, 'SubResult\'s message should not be null');
            System.assert(subResult.Code != null, 'SubResult\'s code should not be null');
        }
    }

    @IsTest
    private static void testSetUpsertResult() {
        TestObject__c testRecord = new TestObject__c();
        Database.UpsertResult saveResult = Database.upsert(testRecord, false);
        System.assertEquals(false, saveResult.isSuccess());

        Test.startTest();
        AqResult result = new AqResultBuilder()
            .setUpsertResult(saveResult, TestObject__c.SObjectType)
            .setScope(TEST_SCOPE)
            .createAqResult();
        Test.stopTest();

        System.assertEquals(
            AqResult.RESULT_TYPE_UPSERT, result.Type, 'Type should contain ' + AqResult.RESULT_TYPE_UPSERT
        );
        System.assertEquals(
            AqResult.SEVERITY_ERROR, result.Severity,
            'Severity should contain ' + AqResult.SEVERITY_ERROR
        );
        System.assertEquals(
            AqResult.SCOPE_TYPE_RECORD, result.ScopeType, 'Scope type should contain ' + AqResult.SCOPE_TYPE_RECORD
        );
        System.assertEquals(
            AqResult.LEVEL_BUSINESS, result.Level, 'Level should contain ' + AqResult.LEVEL_BUSINESS
        );
        System.assertEquals(TEST_SCOPE, result.Scope, 'Scope should contain ' + TEST_SCOPE);
        System.assertEquals(
            AqResultBuilder.UPSERT_ERROR_MESSAGE, result.Message,
            'Message should contain ' + AqResultBuilder.UPSERT_ERROR_MESSAGE
        );

        for (AqResult subResult : result.SubResults) {
            System.assertEquals(
                AqResult.RESULT_TYPE_DATABASE_ERROR, subResult.Type,
                'SubResult\'s type should contain ' + AqResult.RESULT_TYPE_DATABASE_ERROR);
            System.assertEquals(AqResult.SEVERITY_ERROR, subResult.Severity,
                'SubResult\'s severity should contain ' + AqResult.SEVERITY_ERROR);
            System.assertEquals(AqResult.SCOPE_TYPE_FIELD, subResult.ScopeType,
                'SubResult\'s scope type should contain ' + AqResult.SCOPE_TYPE_FIELD);
            System.assertEquals(AqResult.LEVEL_INTERNAL, subResult.Level,
                'SubResult\'s level should contain ' + AqResult.LEVEL_INTERNAL);
            System.assert(subResult.Message != null, 'SubResult\'s message should not be null');
            System.assert(subResult.Code != null, 'SubResult\'s code should not be null');
        }
    }

    @IsTest
    private static void testSetAqException() {
        AqException testAqException = new AqException(TEST_CODE, TEST_SCOPE_TYPE, TEST_SCOPE);

        Test.startTest();
        AqResult result = new AqResultBuilder()
            .setException(testAqException)
            .createAqResult();
        Test.stopTest();

        System.assertEquals(testAqException.getTypeName(), result.Type, 'Type should contain AqException');
        System.assertEquals(testAqException.getMessage(), result.Message, 'Message should contain dml\'s exception message');
        System.assertEquals(AqEnv.today(), result.ResultDate.date(), 'Result Date should contain today\'s day');
        System.assertEquals(AqResult.LEVEL_BUSINESS, result.Level, 'Level should contain ' + AqResult.LEVEL_BUSINESS);
        System.assertEquals(TEST_CODE, result.Code, 'Code should contain ' + TEST_CODE);
        System.assertEquals(TEST_SCOPE_TYPE, result.ScopeType, ' Scope Type should contain ' + TEST_SCOPE_TYPE);
        System.assertEquals(TEST_SCOPE, result.Scope, 'Scope ' + TEST_SCOPE);
        System.assert(result.Detail != null, 'Detail should be populated after dml exception');
    }

    @IsTest
    private static void testSetEmailResult() {
        Messaging.SingleEmailMessage newEmail = new Messaging.SingleEmailMessage();
        newEmail.setTargetObjectId(UserInfo.getUserId());

        //Will fail because sending to user requires setting flag to not create activity
        Messaging.SendEmailResult[] results =
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ newEmail }, false);
        System.assertEquals(false, results[0].isSuccess());

        Test.startTest();
        AqResult result = new AqResultBuilder()
            .setSendEmailResult(results[0], TEST_SCOPE)
            .createAqResult();
        Test.stopTest();

        System.assertEquals(AqResult.RESULT_TYPE_EMAIL, result.Type, 'Type should contain ' + AqResult.RESULT_TYPE_EMAIL);
        System.assertEquals(AqResult.SEVERITY_ERROR, result.Severity, 'Severity should contain ' + AqResult.SEVERITY_ERROR);
        System.assertEquals(AqResult.SCOPE_TYPE_EMAIL, result.ScopeType, 'Scope type should contain ' + AqResult.SCOPE_TYPE_RECORD);
        System.assertEquals(AqResult.LEVEL_BUSINESS, result.Level, 'Level should contain ' + AqResult.LEVEL_BUSINESS);
        System.assertEquals(TEST_SCOPE, result.Scope, 'Scope should contain ' + TEST_SCOPE);
        System.assertEquals(AqResultBuilder.EMAIL_ERROR_MESSAGE, result.Message,
            'Message should contain ' + AqResultBuilder.EMAIL_ERROR_MESSAGE);

        for (AqResult subResult : result.SubResults) {
            System.assertEquals(AqResult.RESULT_TYPE_EMAIL_ERROR, subResult.Type,
                'SubResult\'s type should contain ' + AqResult.RESULT_TYPE_EMAIL_ERROR);
            System.assertEquals(AqResult.SEVERITY_ERROR, subResult.Severity,
                'SubResult\'s severity should contain ' + AqResult.SEVERITY_ERROR);
            System.assertEquals(AqResult.SCOPE_TYPE_EMAIL, subResult.ScopeType,
                'SubResult\'s scope type should contain ' + AqResult.SCOPE_TYPE_EMAIL);
            System.assertEquals(AqResult.LEVEL_INTERNAL, subResult.Level,
                'SubResult\'s level should contain ' + AqResult.LEVEL_INTERNAL);
            System.assert(subResult.Message != null, 'SubResult\'s message should not be null');
            System.assert(subResult.Code != null, 'SubResult\'s code should not be null');
        }
    }

    @IsTest
    private static void testDifferentSets() {
        Test.startTest();
        AqResult result = new AqResultBuilder()
            .setType(TEST_TYPE)
            .setCode(TEST_CODE)
            .setLevel(AqResult.LEVEL_USER)
            .setScope(TEST_SCOPE)
            .setScopeType(TEST_SCOPE_TYPE)
            .setSeverity(AqResult.SEVERITY_PARTIAL_ERROR)
            .setMessage(TEST_MESSAGE)
            .setSource(TEST_SOURCE)
            .setDetail(TEST_DETAIL)
            .setResultDate(AqEnv.today())
            .setReturnValue(TEST_RETURN_VALUE)
            .addSubResults(new List<AqResult>{ new AqResultBuilder().createAqResult() })
            .createAqResult();
        Test.stopTest();

        System.assertEquals(TEST_TYPE, result.Type, 'Type should contain ' + TEST_TYPE);
        System.assertEquals(TEST_CODE, result.Code, 'Code should contain ' + TEST_CODE);
        System.assertEquals(AqResult.LEVEL_USER, result.Level, 'Level should contain ' + AqResult.LEVEL_USER);
        System.assertEquals(TEST_SCOPE, result.Scope, 'Scope should contain ' + TEST_SCOPE);
        System.assertEquals(TEST_SCOPE_TYPE, result.ScopeType, 'Scope Type should contain ' + TEST_SCOPE_TYPE);
        System.assertEquals(TEST_MESSAGE, result.Message, 'Message should contain ' + TEST_MESSAGE);
        System.assertEquals(TEST_SOURCE, result.Source, 'Source should contain ' + TEST_SOURCE);
        System.assertEquals(TEST_DETAIL, result.Detail, 'Detail should contain ' + TEST_DETAIL);
        System.assertEquals(AqEnv.today(), result.ResultDate, 'ResultDate should contain ' + AqEnv.today());
        System.assertEquals(TEST_RETURN_VALUE, result.ReturnValue, 'Return value should contain ' + TEST_RETURN_VALUE);
        System.assertEquals(AqResult.SEVERITY_PARTIAL_ERROR, result.Severity,
            'Severity should contain ' + AqResult.SEVERITY_PARTIAL_ERROR);
        System.assert(result.SubResults != null, 'SubResults should not be null');
    }
}
