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

//Unit tests for AqObj.cls
@isTest
private with sharing class AqTest_AqObj {

    //This just provides coverage for empty virtual methods when not overridden
    private class Nop extends AqObj {

        public Nop() {
            this.preValidate(null);
            this.preValidateDelete(null);
            this.initialize(null);
            this.calculate(null);
            this.validate(null);
            this.postInsert(null);
            this.postUpdate(null);
            this.postUpsert(null);
            this.postDelete(null);
        }

    }

    //Test that the correct methods are called for each kind of operation
    @isTest
    private static void testOperationOrder() {

        //Cover case where no overrides are present
        Nop theNop = new Nop();

        //Insert
        AqObjAqTestObject.clearOperations();
        TestObject__c testObject = new TestObject__c(RequiredText__c = 'Foo');
        insert testObject;
        System.assertEquals(new List<String>{'preValidate', 'initialize', 'calculate', 'validate', 'postInsert', 'postUpsert'}, AqObjAqTestObject.Operations);

        //Update
        AqObjAqTestObject.clearOperations();
        update testObject;
        System.assertEquals(new List<String>{'preValidate', 'calculate', 'validate', 'postUpdate', 'postUpsert'}, AqObjAqTestObject.Operations);

        //Delete
        AqObjAqTestObject.clearOperations();
        delete testObject;
        System.assertEquals(new List<String>{'preValidateDelete', 'postDelete'}, AqObjAqTestObject.Operations);

        //Undelete
        AqObjAqTestObject.clearOperations();
        undelete testObject;
        System.assertEquals(new List<String>{'postInsert', 'postUpsert'}, AqObjAqTestObject.Operations);

    }

    //oldRecords(), oldRecord(), oldValue()
    @isTest
    private static void testOld() {

        //Insert
        AqObjAqTestObject.clearOperations();
        TestObject__c testObject = new TestObject__c(RequiredText__c = 'Foo', Picklist__c = 'Value One', Checkbox__c = true);
        insert testObject;
        System.assertEquals(null, AqObjAqTestObject.oldRecords);

        //Update
        AqObjAqTestObject.clearOperations();
        testObject.RequiredText__c = 'Bar';
        testObject.Picklist__c = null;
        update testObject;
        System.assertEquals(1, AqObjAqTestObject.oldRecords.size());
        System.assertEquals(testObject.Id, AqObjAqTestObject.oldRecord.Id);
        System.assertEquals('Value One', ((TestObject__c)AqObjAqTestObject.oldRecord).Picklist__c);
        System.assertEquals('Foo', (String)AqObjAqTestObject.oldValue);

        //Delete
        AqObjAqTestObject.clearOperations();
        delete testObject;
        System.assertEquals(1, AqObjAqTestObject.oldRecords.size());

    }

    @isTest
    private static void testRequire() {

        AqObjAqTestObject.FailRequirement = true;
        TestObject__c willFailObject = new TestObject__c(RequiredText__c = 'Foo');
        Database.SaveResult saveResult = Database.insert(willFailObject, false);
        AqTest.assertCustomValidationError(saveResult);
        System.assertEquals('Failed', saveResult.getErrors()[0].getMessage());

    }

    @isTest
    private static void testRequireField() {

        AqObjAqTestObject.RequiredField = TestObject__c.Email__c;
        TestObject__c badObject = new TestObject__c(RequiredText__c = 'Foo', Email__c = '');
        Database.SaveResult saveResult = Database.insert(badObject, false);
        AqTest.assertCustomValidationError(saveResult);

    }

    @isTest
    private static void testRequireFields() {

        AqObjAqTestObject.RequiredFields = new Set<SObjectField>{TestObject__c.Email__c, TestObject__c.Date__c};
        TestObject__c goodObject = new TestObject__c(RequiredText__c = 'Foo', Email__c = 'foo@bar.com', Date__c = Date.newInstance(2017, 1, 1));
        TestObject__c badObject1 = new TestObject__c(RequiredText__c = 'Foo', Email__c = 'foo@bar.com');
        TestObject__c badObject2 = new TestObject__c(RequiredText__c = 'Foo', Email__c = '');

        Database.SaveResult[] saveResults = Database.insert(new List<sObject>{goodObject, badObject1, badObject2}, false);
        AqTest.assertSuccess(saveResults[0]);
        AqTest.assertCustomValidationError(saveResults[1]);
        AqTest.assertCustomValidationError(saveResults[2]);

    }

    @isTest
    private static  void testRequireTogether() {

        AqObjAqTestObject.RequiredTogether = new Set<SObjectField>{TestObject__c.Email__c, TestObject__c.Date__c};
        TestObject__c goodObject1 = new TestObject__c(RequiredText__c = 'Foo', Email__c = 'foo@bar.com', Date__c = Date.newInstance(2017, 1, 1));	//Both
        TestObject__c goodObject2 = new TestObject__c(RequiredText__c = 'Foo'); //Neither
        TestObject__c badObject1 = new TestObject__c(RequiredText__c = 'Foo', Email__c = 'foo@bar.com');
        TestObject__c badObject2 = new TestObject__c(RequiredText__c = 'Foo', Date__c = Date.newInstance(2017, 1, 1));

        Database.SaveResult[] saveResults = Database.insert(new List<sObject>{goodObject1, goodObject2, badObject1, badObject2}, false);
        AqTest.assertSuccess(saveResults[0]);
        AqTest.assertSuccess(saveResults[1]);
        AqTest.assertCustomValidationError(saveResults[2]);
        AqTest.assertCustomValidationError(saveResults[3]);

    }

    @isTest
    private static void testValidateString() {

        AqObjAqTestObject.ValidateStringField = TestObject__c.Text__c;
        AqObjAqTestObject.ValidateStringDatatype = AqTypes.DATATYPE_SSN;

        TestObject__c goodObject1 = new TestObject__c(RequiredText__c = 'Foo', Text__c = '123-45-6789');
        TestObject__c goodObject2 = new TestObject__c(RequiredText__c = 'Foo', Text__c = '123456789');
        TestObject__c badObject = new TestObject__c(RequiredText__c = 'Foo', Text__c = 'NotAnSSN');

        Database.SaveResult[] saveResults = Database.insert(new List<sObject>{goodObject1, goodObject2, badObject}, false);
        AqTest.assertSuccess(saveResults[0]);
        AqTest.assertSuccess(saveResults[1]);
        AqTest.assertCustomValidationError(saveResults[2]);

    }

    @isTest
    private static void testValidateString2() {

        AqObjAqTestObject.ValidateStringField = TestObject__c.Text__c;
        AqObjAqTestObject.ValidateStringDatatype = AqTypes.DATATYPE_STRING;
        AqObjAqTestObject.ValidateStringRequired = true;

        TestObject__c goodObject = new TestObject__c(RequiredText__c = 'Foo', Text__c = 'ABCDEFG');
        TestObject__c badObject1 = new TestObject__c(RequiredText__c = 'Foo');
        TestObject__c badObject2 = new TestObject__c(RequiredText__c = 'Foo', Text__c = '');

        Database.SaveResult[] saveResults = Database.insert(new List<sObject>{goodObject, badObject1, badObject2}, false);
        AqTest.assertSuccess(saveResults[0]);
        AqTest.assertCustomValidationError(saveResults[1]);
        AqTest.assertCustomValidationError(saveResults[2]);

    }

    @isTest
    private static void testValidateString3() {

        AqObjAqTestObject.ValidateStringField = TestObject__c.Text__c;
        AqObjAqTestObject.ValidateStringDatatype = AqTypes.DATATYPE_STRING;
        AqObjAqTestObject.ValidateStringRequired = false;
        AqObjAqTestObject.ValidateStringLength = 10;

        TestObject__c goodObject = new TestObject__c(RequiredText__c = 'Foo', Text__c = 'ABCDEFG');
        TestObject__c badObject = new TestObject__c(RequiredText__c = 'Foo', Text__c = '12345678932343');

        Database.SaveResult[] saveResults = Database.insert(new List<sObject>{goodObject, badObject}, false);
        AqTest.assertSuccess(saveResults[0]);
        AqTest.assertCustomValidationError(saveResults[1]);

    }

    @isTest
    private static void testValidatePattern() {

        AqObjAqTestObject.ValidatePatternField = TestObject__c.Text__c;
        AqObjAqTestObject.ValidatePatternRequired = true;
        AqObjAqTestObject.ValidatePatternRegex = '\\d{3}.\\d{3}-\\d{3}';
        AqObjAqTestObject.ValidatePatternLabel = '###.###-###';

        TestObject__c goodObject = new TestObject__c(RequiredText__c = 'Foo', Text__c = '123.456-789');
        TestObject__c badObject = new TestObject__c(RequiredText__c = 'Foo', Text__c = 'NotThePattern');

        Database.SaveResult[] saveResults = Database.insert(new List<sObject>{goodObject, badObject}, false);
        AqTest.assertSuccess(saveResults[0]);
        AqTest.assertCustomValidationError(saveResults[1]);

    }

    @isTest
    private static void testValidateInteger() {

        AqObjAqTestObject.ValidateIntegerField = TestObject__c.Integer__c;

        AqObjAqTestObject.ValidateIntegerRequired = true;
        AqObjAqTestObject.ValidateIntegerMin = 128;
        AqObjAqTestObject.ValidateIntegerMax = 255;

        TestObject__c goodObject = new TestObject__c(RequiredText__c = 'Foo', Integer__c = 200);
        TestObject__c badObject1 = new TestObject__c(RequiredText__c = 'Foo', Integer__c = null);
        TestObject__c badObject2 = new TestObject__c(RequiredText__c = 'Foo', Integer__c = 10);
        TestObject__c badObject3 = new TestObject__c(RequiredText__c = 'Foo', Integer__c = 900);

        Database.SaveResult[] saveResults = Database.insert(new List<sObject>{goodObject, badObject1, badObject2, badObject3}, false);
        AqTest.assertSuccess(saveResults[0]);
        AqTest.assertCustomValidationError(saveResults[1]);
        AqTest.assertCustomValidationError(saveResults[2]);
        AqTest.assertCustomValidationError(saveResults[3]);
    }

    @isTest
    private static void testChangedFields() {

        //Insert
        AqObjAqTestObject.clearOperations();
        AqObjAqTestObject.CaptureChangedFields = true;
        AqObjAqTestObject.ChangedAnyFields = new Set<SObjectField>{TestObject__c.RequiredText__c, TestObject__c.Picklist__c};
        AqObjAqTestObject.ChangedFromToField = TestObject__c.Text__c;
        AqObjAqTestObject.ChangedToValue = 'Bar';
        TestObject__c testObject = new TestObject__c(RequiredText__c = 'Foo', Picklist__c = 'Value One', Checkbox__c = true, Text__c = 'Bar');
        insert testObject;
        System.assertEquals(1, AqObjAqTestObject.ChangedFields.size());
        Set<SObjectField> changedFields = AqObjAqTestObject.ChangedFields[0];
        System.assertEquals(4, changedFields.size());
        System.assert(changedFields.contains(TestObject__c.RequiredText__c));
        System.assert(changedFields.contains(TestObject__c.Picklist__c));
        System.assert(changedFields.contains(TestObject__c.Checkbox__c));
        System.assert(changedFields.contains(TestObject__c.Text__c));
        System.assertEquals(true, AqObjAqTestObject.IsChangedAnyFields);
        System.assertEquals(true, AqObjAqTestObject.IsChangedTo);
        System.assertEquals(true, AqObjAqTestObject.IsChangedToNonNull);

        //Update
        AqObjAqTestObject.clearOperations();
        AqObjAqTestObject.CaptureChangedFields = true;
        AqObjAqTestObject.ChangedAnyFields = new Set<SObjectField>{TestObject__c.Checkbox__c};
        AqObjAqTestObject.ChangedFromToField = TestObject__c.Text__c;
        AqObjAqTestObject.ChangedFromValue = 'Bar';
        AqObjAqTestObject.ChangedToValue = 'Nope';
        testObject.Picklist__c = null;
        testObject.Text__c = null;
        update testObject;
        System.assertEquals(1, AqObjAqTestObject.ChangedFields.size());
        changedFields = AqObjAqTestObject.ChangedFields[0];
        System.assertEquals(2, changedFields.size());
        System.assert(changedFields.contains(TestObject__c.Picklist__c));
        System.assert(changedFields.contains(TestObject__c.Text__c));
        System.assertEquals(false, AqObjAqTestObject.IsChangedAnyFields);
        System.assertEquals(true, AqObjAqTestObject.IsChangedFrom);
        System.assertEquals(false, AqObjAqTestObject.IsChangedToNonNull);
        System.assertEquals(false, AqObjAqTestObject.IsChangedTo);

        //Delete
        AqObjAqTestObject.clearOperations();
        AqObjAqTestObject.CaptureChangedFields = true;
        delete testObject;
        System.assertEquals(1, AqObjAqTestObject.ChangedFields.size());
        changedFields = AqObjAqTestObject.ChangedFields[0];
        System.assertEquals(2, changedFields.size());	//All non-null fields are considered changed upon delete

    }
}
