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

// PMD False Positive: Internal libs are ok to have many public classes and a huge class complexity.
// Sharing is not required for a test class.
@SuppressWarnings('PMD.StdCyclomaticComplexity, PMD.CyclomaticComplexity, PMD.SpecifySharingModel, PMD.NcssMethodCount')
//Unit tests for Aq.cls
@IsTest
private class AqTest_Aq {

    public static final String TEST_RESOURCE_NAME = 'AqTestResource';

    private static final String TEST_RESULT_TYPE = 'ResultType';
    private static final String TEST_MESSAGE = 'The message.';
    private static final String TEST_SCOPE_TYPE = 'Scope Type';
    private static final String TEST_SCOPE = 'Scope';
    private static final String TEST_CODE = 'Code';

    //Exception constructors
    @IsTest
    private static void testExceptionConstructors() {

        AqResult testResult = new AqResultBuilder()
            .setType(TEST_RESULT_TYPE)
            .setSeverity(AqResult.SEVERITY_ERROR)
            .setLevel(AqResult.LEVEL_BUSINESS)
            .setMessage(TEST_MESSAGE)
            .setScopeType(TEST_SCOPE_TYPE)
            .setScope(TEST_SCOPE)
            .createAqResult();

        verifyFullTestException(new Aq.BusinessException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.BusinessException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.BusinessException(testResult).Result);

        verifyFullTestException(new Aq.ValidationException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.ValidationException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.ValidationException(testResult).Result);

        verifyFullTestException(new Aq.UserException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.UserException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.UserException(testResult).Result);

        verifyFullTestException(new Aq.NotFoundException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.NotFoundException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.NotFoundException(testResult).Result);

        verifyFullTestException(new Aq.RecordCountException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.RecordCountException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.RecordCountException(testResult).Result);

        verifyFullTestException(new Aq.PermissionException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.PermissionException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.PermissionException(testResult).Result);

        verifyFullTestException(new Aq.QueryPermissionException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.QueryPermissionException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.QueryPermissionException(testResult).Result,
                'AqResult instance should be same.');
        Assert.isInstanceOfType(new Aq.QueryPermissionException(new QueryException()), Aq.QueryPermissionException.class,
                'Should successfully create instance of Aq.QueryPermissionException');

        verifyFullTestException(new Aq.DuplicateException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE, TEST_CODE));
        verifyNoCodeTestException(new Aq.DuplicateException(TEST_MESSAGE, TEST_SCOPE_TYPE, TEST_SCOPE));
        System.assertEquals(testResult, new Aq.DuplicateException(testResult).Result);

    }

    @IsTest
    private static void testQueryPermissionExceptionMessageBuilder() {
        Env__c testEnv = new Env__c(DebugMode__c = true);
        insert testEnv;

        Profile minimumAccessProfile = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'];
        User minimumAccessUser = new User(
                Alias = 'minAcc',
                Email = 'minimumaccessuser@testorg.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Testing',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = minimumAccessProfile.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = 'minimumaccessuser@testorg.com' + Datetime.now().getTime());
        Aq.QueryPermissionException queryPermissionException;

        System.runAs(minimumAccessUser) {
            try {
                Database.query('SELECT Id, Name, AccountNumber FROM Account WITH USER_MODE');
                Assert.fail('Should throw missing permission to AccountNumber field');
            } catch (QueryException e) {
                System.assert(true, 'Should throw missing permission to AccountNumber field');
                queryPermissionException = new Aq.QueryPermissionException(e);
            }
        }

        Assert.isTrue(queryPermissionException.getMessage().startsWith(Label.Aq_M_InsufficientPrivilege),
                'Message should begin with text from label Aq_M_InsufficientPrivilege');
        Assert.isTrue(queryPermissionException.getMessage().containsIgnoreCase('AccountNumber'),
                'Message should contain info about inaccessible field');

    }

    private static void verifyFullTestException(AqException actual) {
        System.assertEquals(TEST_MESSAGE, actual.getMessage());
        System.assertEquals(TEST_SCOPE_TYPE, actual.ScopeType);
        System.assertEquals(TEST_SCOPE, actual.Scope);
        System.assertEquals(TEST_CODE, actual.Code);
    }

    private static void verifyNoCodeTestException(AqException actual) {
        System.assertEquals(TEST_MESSAGE, actual.getMessage());
        System.assertEquals(TEST_SCOPE_TYPE, actual.ScopeType);
        System.assertEquals(TEST_SCOPE, actual.Scope);
        System.assertEquals(null, actual.Code);
    }

    //All validation methods
    @IsTest
    private static void testValidationMethods() {

        //validate()
        try {
            TestValue tv = new TestValue(null);
            Aq.validate(tv);
            System.assert(false, 'Expected ValidationException');
        }
        catch (Aq.ValidationException e) {
            System.assert(true);
        }

         //validate() with type
        try {
            TestValue tv = new TestValue(null);
            Aq.validate(tv, TEST_RESULT_TYPE);
            System.assert(false, 'Expected ValidationException');
        }
        catch (Aq.ValidationException e) {
            System.assert(true);
        }

        //requireValue()
        Aq.requireValue('testArg', 'hasvalue');

        try {
            Aq.requireValue('testArg', null);
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.ValidationException e) {
            System.assert(true);
        }

        //requireNonemptyList()
        Aq.requireNonemptyList('testArg', new List<String>{'foo'});

        try {
            Aq.requireNonemptyList('testArg', null);
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.ValidationException e) {
            System.assert(true);
        }
        try {
            Aq.requireNonemptyList('testArg', new List<String>());
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.ValidationException e) {
            System.assert(true);
        }

        //requireInSet()
        Set<String> theSet = new Set<String>{'One', 'Two', 'Three'};

        Aq.requireValueInSet('testArg', 'One', theSet);

        try {
            Aq.requireValueInSet('testArg', 'foo', theSet);
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.ValidationException e) {
            System.assert(true);
        }

        try {
            Aq.requireValueInSet('testArg', null, theSet);
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.ValidationException e) {
            System.assert(true);
        }

        //exists()
        System.assertEquals(true, Aq.exists(new List<SObject>{new TestObject__c()}));
        System.assertEquals(false, Aq.exists(new List<SObject>()));

        //atLeastOne
        Aq.atLeastOne(TestObject__c.SObjectType, new List<SObject>{new TestObject__c()});
        Aq.atLeastOne(TestObject__c.SObjectType, new List<SObject>{new TestObject__c(), new TestObject__c()});
        try {
            Aq.atLeastOne(TestObject__c.SObjectType, new List<SObject>());
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.NotFoundException e) {
            System.assert(true);
        }

        //exactlyOne()
        Aq.exactlyOne(TestObject__c.SObjectType, new List<SObject>{new TestObject__c()});
        try {
            Aq.exactlyOne(TestObject__c.SObjectType, new List<SObject>());
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.NotFoundException e) {
            System.assert(true);
        }
        try {
            Aq.exactlyOne(TestObject__c.SObjectType, new List<SObject>{new TestObject__c(), new TestObject__c()});
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.RecordCountException e) {
            System.assert(true);
        }

        //atMostOne()
        Aq.atMostOne(TestObject__c.SObjectType, new List<SObject>());
        Aq.atMostOne(TestObject__c.SObjectType, new List<SObject>{new TestObject__c()});
        try {
            Aq.atMostOne(TestObject__c.SObjectType, new List<SObject>{new TestObject__c(), new TestObject__c()});
            System.assert(false, 'Exception not thrown.');
        }
        catch (Aq.RecordCountException e) {
            System.assert(true);
        }

    }

    //getIdSet(), getObjectList
    @IsTest
    private static void testListMethods() {

        //getIdSet()
        List<User> users = [SELECT Id FROM User LIMIT 500];
        Set<Id> userIds = Aq.getIdSet(users, User.Id);
        System.assertEquals(users.size(), userIds.size());
        System.assertEquals(0, Aq.getIdSet(null, User.Id).size(), 'Null value for records should return empty list');

        //getObjectList
        Set<SObjectField> objSet = new Set<SObjectField> {TestObject__c.Name, TestObject__c.Id};
        List<Object> objList = Aq.getObjectList(objSet);
        System.assertEquals(2, objList.size());
        System.assertEquals(TestObject__c.Name, objList[0]);
        System.assertEquals(TestObject__c.Id, objList[1]);

    }

    //All Resource methods
    @IsTest
    private static void testResourceMethods() {

        //getStringFromResource
        String resourceString = Aq.getStringFromResource(TEST_RESOURCE_NAME);
        System.assert(!String.isEmpty(resourceString));

        //getObjectFromResource
        AqResult resourceObject = (AqResult)Aq.getObjectFromResource(TEST_RESOURCE_NAME, AqResult.class);
        System.assert(resourceObject != null);

    }

    //All Record Type methods
    @IsTest
    private static void testRecordTypeMethods() {

        //getRecordTypeByName()
        RecordType rt1 = Aq.getRecordTypeByName(TestObject__c.SObjectType, AqObjAqTestObject.RECORD_TYPE_1);
        System.assert(rt1 != null);
        System.assertEquals(AqObjAqTestObject.RECORD_TYPE_1, rt1.DeveloperName);

        //getRecordTypeId()
        Id rt1Id = Aq.getRecordTypeId(TestObject__c.SObjectType, AqObjAqTestObject.RECORD_TYPE_1);
        System.assert(rt1Id != null);
        System.assertEquals(rt1.Id, rt1Id);
        System.assertEquals(null, Aq.getRecordTypeId(TestObject__c.SObjectType, 'NonExistent'));

        //getRecordTypeLabel()
        System.assertEquals('Record Type 1', Aq.getRecordTypeLabel(TestObject__c.SObjectType, AqObjAqTestObject.RECORD_TYPE_1));
        System.assertEquals(null, Aq.getRecordTypeLabel(TestObject__c.SObjectType, 'NonExistent'));

        //hasRecordType(), isRecordType()
        List<TestObject__c> testRecords = new List<TestObject__c> {
            new TestObject__c(Name = 'Test1', RequiredText__c = 'Foo', RecordTypeId = Aq.getRecordTypeId(TestObject__c.SObjectType, AqObjAqTestObject.RECORD_TYPE_1)),
            new TestObject__c(Name = 'Test2', RequiredText__c = 'Foo', RecordTypeId = Aq.getRecordTypeId(TestObject__c.SObjectType, AqObjAqTestObject.RECORD_TYPE_2))
        };
        insert testRecords;
        System.assertEquals(true, Aq.hasRecordType(testRecords[0], new Set<String>{AqObjAqTestObject.RECORD_TYPE_1}));
        System.assertEquals(false, Aq.hasRecordType(testRecords[1], new Set<String>{AqObjAqTestObject.RECORD_TYPE_1}));
        System.assertEquals(false, Aq.hasRecordType(null, new Set<String>{AqObjAqTestObject.RECORD_TYPE_1}));
        System.assertEquals(true, Aq.isRecordType(testRecords[0], AqObjAqTestObject.RECORD_TYPE_1));
        System.assertEquals(false, Aq.isRecordType(testRecords[1], AqObjAqTestObject.RECORD_TYPE_1));

    }

    //ifNull()
    @IsTest
    private static void testIfNull() {

        String notNullString = 'NOTNULL';
        String nullString = null;
        String emptyString = '';
        Integer nullInteger = null;
        Integer notNullInteger = 123;

        System.assertEquals('Foo', Aq.ifNull(nullString, 'Foo'));
        System.assertEquals('Foo', Aq.ifNull(emptyString, 'Foo'));
        System.assertEquals(notNullString, Aq.ifNull(notNullString, 'Foo'));
        System.assertEquals(999, Aq.ifNull(nullInteger, 999));
        System.assertEquals(notNullInteger, Aq.ifNull(notNullInteger, 999));

    }

    //For testing abstract Aq.Value class
    private class TestValue extends Aq.Value implements Validatable {

        private Integer valueField;
        private String aqResultType = 'ValidateResult';

        public TestValue(Integer valueField) {
            this.valueField = valueField;
        }

        public AqResult validate() {
            if (this.valueField == null){
                return new AqResultBuilder()
                    .setType(aqResultType)
                    .setSeverity(AqResult.SEVERITY_ERROR)
                    .createAqResult();
            } else {
                return new AqResultBuilder()
                    .setType(aqResultType)
                    .setSeverity(AqResult.SEVERITY_SUCCESS)
                    .createAqResult();
            }
        }

    }

    //Aq.Value methods
    @IsTest
    private static void testValueClass() {

        TestValue tv1 = new TestValue(1);
        TestValue tv2 = new TestValue(1);
        TestValue tv3 = new TestValue(2);

        System.assert(tv1 == tv2);
        System.assert(tv1 != tv3);
        System.assertEquals(false, tv1.equals(null));
        System.assert(tv1.hashCode() != null);
    }

    @IsTest
    private static void testNamespacePrefixWithActualOrgNamespace () {
        // depending on environment the appendPrefix will return different values
        // so just make sure it won`t return null for non-null input
        String envClassName = AqEnv.class.getName();
        String actualOrgNamespacePrefix = envClassName.contains('.')
            ? envClassName.substringBefore('.') + '__'
            : '';
        System.assertEquals(actualOrgNamespacePrefix + 'someValueToPrefix__c', Aq.appendPrefix('someValueToPrefix__c'));
    }

    @IsTest
    private static void testNamespacePrefixWithOverriddenNamespace () {
        String namespaceOverride = 'testNamespace';
        AqEnv.NamespaceOverride = namespaceOverride;
        System.assertEquals(namespaceOverride, AqEnv.namespace);
        System.assertEquals(namespaceOverride + '__', AqEnv.namespacePrefix);

        System.assertEquals('testNamespace__someValueToPrefix__c', Aq.appendPrefix('someValueToPrefix__c'));
        System.assertEquals('Standard', Aq.appendPrefix('Standard'));
        System.assertEquals('testNamespace__Custom__mdt', Aq.appendPrefix('Custom__mdt'));
        System.assertEquals('customPrefix__Custom__mdt', Aq.appendPrefix('customPrefix__Custom__mdt'));
        System.assertEquals('testNamespace__relation__r', Aq.appendPrefix('relation__r'));
    }

    @IsTest
    private static void testIsEmptyList () {

        System.assertEquals(true, Aq.isEmptyList(null));
        System.assertEquals(true, Aq.isEmptyList(new List<Integer>()));
        System.assertEquals(false, Aq.isEmptyList(new List<Integer>{1}));
    }

    @IsTest
    private static void testConcatObjectStringFields() {
        String testStr = '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
        TestObject__c testObj = new TestObject__c();
        testObj.Text__c = testStr;
        testObj.RequiredText__c = testStr;
        testObj.AddressStreet__c = testStr;

        List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
            TestObject__c.Text__c,
            TestObject__c.RequiredText__c,
            TestObject__c.AddressStreet__c
        };

        System.assertEquals(testStr + testStr + testStr, Aq.concatObjectStringFields(testObj, fields));

        testObj.AddressStreet__c = null;
        System.assertEquals(testStr + testStr, Aq.concatObjectStringFields(testObj, fields));
    }

    @IsTest
    private static void testSplitStringIntoSObjectFields() {
        String testStr = '0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
        TestObject__c testObj = new TestObject__c();
        testObj.RequiredText__c = 'this string should be nullified';
        testObj.AddressStreet__c = 'this string should be nullified';

        // all fields are 255 chars long
        List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
            TestObject__c.Text__c,
            TestObject__c.RequiredText__c,
            TestObject__c.AddressStreet__c
        };

        Aq.splitStringIntoSObjectFields(testObj, fields, testStr);

        System.assertEquals(testStr, testObj.Text__c, 'full text should be placed in the first field');
        System.assertEquals('', testObj.RequiredText__c, 'field should be nullified as full text fit in the first field');
        System.assertEquals('', testObj.AddressStreet__c, 'field should be nullified as full text fit in the first field');

        String longString = '';

        for (Integer i = 0; i < 7; i++) {
            longString += testStr;
        }
        System.assertEquals(700, longString.length());

        Aq.splitStringIntoSObjectFields(testObj, fields, longString);
        System.assertEquals(
            longString.left(255),
            testObj.Text__c,
            'first 255 chars of string should be placed in the first field'
        );
        System.assertEquals(
            longString.right(700 - 255).left(255),
            testObj.RequiredText__c,
            'second 255 chars of string should be placed in the second field'
        );
        System.assertEquals(
            longString.right(700 - 510),
            testObj.AddressStreet__c,
            'last chars of string should be placed in the third field'
        );

        String tooLongString = longString + testStr;
        System.assertEquals(800, tooLongString.length());
        try {
            Aq.splitStringIntoSObjectFields(testObj, fields, tooLongString);
            System.assert(false, 'exception should be thrown as the text length is greater that fields length summary');
        } catch (Exception e) {
            System.assert(e.getMessage().containsIgnoreCase(Label.Aq_Value_Wont_FitInFields), 'unexpected error message');
        }

        List<Schema.SObjectField> fieldsWithUnsupportedType = new List<Schema.SObjectField>{
            TestObject__c.Text__c,
            TestObject__c.MultiPicklist__c
        };
        try {
            Aq.splitStringIntoSObjectFields(testObj, fieldsWithUnsupportedType, testStr);
            System.assert(false, 'exception should be thrown as the field list contain unsupported field type');
        } catch (Exception e) {
            System.assert(e.getMessage().containsIgnoreCase(Label.Aq_Unsupported_Field_Type), 'unexpected error message');
        }
    }
}
