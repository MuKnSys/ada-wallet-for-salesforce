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
 * @description Helpers for testing
 * @group apex/core
**/
@isTest
public inherited sharing class AqTest {

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Addional asserts

    //Assert that a list of strings is equivalent to expected multi-select picklist colon-separated string
    public static void assertMultiSelectPicklistEquals(String expected, List<String> actual) {

        String actualString = actual == null ? '' : String.join(actual, ';');
        System.assertEquals(expected, actualString);
    }

    //Assert that a colon-separate string value is equal to corresponding list of strings
    public static void assertMultiSelectPicklistEquals(List<String> expected, String actual) {

        String expectedString = expected == null ? '' : String.join(expected, ';');
        System.assertEquals(expectedString, actual);
    }


    //Same as System.assertEquals except consider null == false
    public static void assertBooleanEquals(Boolean expected, Boolean actual) {

        Boolean expectedNotNull = expected == null ? false : expected;
        Boolean actualNotNull = actual == null ? false : actual;
        System.assertEquals(expectedNotNull, actualNotNull);
    }

    //Assure no LogDgt__c with Error severity was inserted
    public static void assertNoErrorLogs() {

        List<LogDgt__c> errorLogs = [
            SELECT Id, LogDate__c, Level__c, Severity__c, Code__c, Source__c, ResultType__c, ScopeType__c, Scope__c, Message__c, Detail__c
            FROM LogDgt__c WHERE Severity__c IN :AqResult.SEVERITIES_ERROR];

        if (!errorLogs.isEmpty()) {
            System.assert(false, JSON.serializePretty(errorLogs));
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //AqResult helpers

    public static void assertSuccess(AqResult result) {
        //Null is always considered successful result
        if (result == null) {
            System.assert(true);
        } else {
            System.assertEquals(true, result.Severity == AqResult.SEVERITY_SUCCESS, result);
        }
    }

    public static void assertAborted(AqResult result) {
        System.assertEquals(AqResult.SEVERITY_ABORTED, result.Severity, result);
    }

    public static void assertError(AqResult result) {
        System.assertEquals(AqResult.SEVERITY_ERROR, result.Severity, result);
    }

    public static void assertError(Type resultType, AqResult result) {
        assertError(result);
        System.assertEquals(resultType.getName(), result.Type, result);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Database result helpers

    public static void assertSuccess(Database.SaveResult saveResult) {
        System.assertEquals(true, saveResult.isSuccess(), saveResult);
    }

    //Assert database save result has expected error code.
    public static void assertDatabaseError(Database.SaveResult saveResult, String expectedStatusCode) {
        System.assert(saveResult != null, 'Null SaveResult');
        System.assertEquals(false, saveResult.isSuccess(), 'SaveResult is success.');
        System.assertEquals(expectedStatusCode, String.valueOf(saveResult.getErrors()[0].getStatusCode()));
    }

    //Assert database save result has FIELD_CUSTOM_VALIDATION_EXCEPTION error code.
    public static void assertCustomValidationError(Database.SaveResult saveResult) {
        assertDatabaseError(saveResult, 'FIELD_CUSTOM_VALIDATION_EXCEPTION');
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Visualforce helpers

    //Convenience for setting a query parameter for the current page
    public static void setQueryParameter(String name, String value) {
        ApexPages.currentPage().getParameters().put(name, value);
    }

    //Assert page currently has no messages
    public static void assertNoPageMessages() {
        System.assert(!ApexPages.hasMessages(), 'Unexpected page messages were found: ' + ApexPages.getMessages());
    }

    //Assert page currently has no messages
    public static void assertNoPageErrors() {
        System.assert(!
            ApexPages.hasMessages(ApexPages.Severity.ERROR) && !ApexPages.hasMessages(ApexPages.Severity.FATAL),
            'Unexpected error messages were found: ' + ApexPages.getMessages()
        );
    }

    //Assert page currently has confirmation message
    public static void assertConfirmMessage() {
        System.assert(
            ApexPages.hasMessages(ApexPages.Severity.CONFIRM),
            'Expected CONFIRM message not found: ' + ApexPages.getMessages()
        );
    }

    //Assert page currently has warning message
    public static void assertWarningMessage() {
        System.assert(
            ApexPages.hasMessages(ApexPages.Severity.WARNING),
            'Expected WARNING message not found: ' + ApexPages.getMessages()
        );
    }

    //Assert page currently has error message
    public static void assertErrorMessage() {
        System.assert(
            ApexPages.hasMessages(ApexPages.Severity.ERROR),
            'Expected ERROR message not found: ' + ApexPages.getMessages()
        );
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Email helpers

    //Asserts that email with subject like the expectedSubjectLike pattern was sent to all the expectedWhoIds
    //This only works for emails for contacts or leads that are added as activities.
    public static void assertEmailsSent(String expectedSubjectLike, Set<ID> expectedWhoIds) {
        assertEmailsSent(true, expectedSubjectLike, expectedWhoIds);
    }

    //Asserts that email with subject like the expectedSubjectLike pattern was NOT sent to all the expectedWhoIds
    //This only works for emails for contacts or leads that are added as activities.
    public static void assertEmailsNotSent(String expectedSubjectLike, Set<ID> expectedWhoIds) {
        assertEmailsSent(false, expectedSubjectLike, expectedWhoIds);
    }

    private static void assertEmailsSent(Boolean isExpected, String expectedSubjectLike, Set<ID> expectedWhoIds) {

        System.assert(expectedWhoIds != null && !expectedWhoIds.isEmpty(), 'expectedWhoIds must not be null or empty.');

        List<EmailMessageRelation> relations = [
            SELECT Id, RelationId
            FROM EmailMessageRelation
            WHERE EmailMessage.Subject LIKE :expectedSubjectLike
                AND RelationId IN :expectedWhoIds
                AND RelationType = 'ToAddress'
        ];

        Set<Id> actualWhoIds = Aq.getIdSet(relations, EmailMessageRelation.RelationId);
        for (Id expectedWhoId : expectedWhoIds) {
            if (isExpected == true && !actualWhoIds.contains(expectedWhoId)) {
                System.assert(false, AqString.format('No {0} email found for who ID {1}', expectedSubjectLike, expectedWhoId));
                return;
            } else if (isExpected != true && actualWhoIds.contains(expectedWhoId)) {
                System.assert(false, AqString.format('Unexpected {0} email found for who ID {1}', expectedSubjectLike, expectedWhoId));
                return;
            }
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Misc helpers

    //Return a valid picklist value from the specific picklist field
    public static String getPicklistValue(SObjectField field, Integer index) {
        return field.getDescribe().getPicklistValues()[index].getValue();
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Test object

    //Return test record will all values populated, not inserted
    public static TestObject__c getFullTestRecord() {

        TestObject__c testRecord = new TestObject__c(
            RecordTypeId = Aq.getRecordTypeId(TestObject__c.SObjectType, AqObjAqTestObject.RECORD_TYPE_1),
            Name = 'Test1',
            Checkbox__c = true,
            Currency__c = 9.99,
            Date__c = Date.newInstance(2017, 5, 9),
            DateTime__c = Datetime.newInstance(2017, 5, 9, 12, 0, 0),
            Email__c = 'test@testy.com',
            Integer__c = 123,
            LongText__c = 'Long text value\r\n'.repeat(100),
            MultiPicklist__c = 'Value One;Value Two',
            Percent__c = 66.5,
            Phone__c = '603-555-1212',
            Picklist__c = 'Value One',
            RequiredText__c = 'Required text value',
            RichText__c = 'Rich text value',
            Text__c = 'Text value',
            TextArea__c = 'Text area value',
            Url__c = 'https://www.aquivalabs.com'
        );

        return testRecord;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Run As

    public static final User adminUser = new User (Id = UserInfo.getUserId());

    public static void setup() {
        insert new PermissionSetAssignment (
                AssigneeId = adminUser.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'AqLibAdmin' LIMIT 1].Id
        );
    }

}
