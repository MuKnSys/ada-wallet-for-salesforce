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

//Unit tests for AqRestResource.cls
@isTest
private with sharing class AqTest_AqRestResource {

    //Resources for testing the abstract base class AqRestResource
    private static final Integer TOTAL_SUBRESULTS = 20;
    private class TestResource extends AqRestResource {

        //Control
        public Boolean skipValidate = false;

        //Properties
        public String Id {get;set;}
        public String Name {get;set;}
        public String RequiredText {get;set;}
        public List<TestResource> TestResources {get;set;}

        //Types
        public override Type getResourceType() {return TestResource.class;}
        public override Type getResourceListType() {return List<TestResource>.class;}
        public override sObjectType getSObjectType() {return TestObject__c.getSObjectType();}
        public override Type getSObjectListType() {return List<TestObject__c>.class;}

        //Put properties into record fields
        public override void put(sObject record) {

            record.Id = this.Id;
            AqField.put(record, TestObject__c.Name, this.Name);
            AqField.put(record, TestObject__c.RequiredText__c, this.RequiredText);

        }

        //Get record fields into properties
        public override void get(sObject record) {

            TestObject__c typedRecord = (TestObject__c)record;

            this.Id = record.Id;
            this.Name = AqField.getString(record, TestObject__c.Name);
            this.RequiredText = AqField.getString(record, TestObject__c.RequiredText__c);

            //Avoid endless recursion, only do for top level
            if (typedRecord.Lookup__c == null)
                this.TestResources = (List<TestResource>)getList(record, 'AquivaTestObjects__r', TestResource.class, true);

        }

        protected override void doValidate() {

            //Exercise all validations
            if (this.skipValidate == true)
                return;

            //String
            validateString('OKString', 'OK', true, 5);		//OK
            requireProperty('RequiredField', '');				//Subresult 0
            validateString('TooLongString', 'This is longer than 5.', true, 5);		//Subresult 1

            //Id
            validateId('OKId', '', false);	//OK
            validateId('OKId', '0034100000OavRe', true);	//OK
            validateId('BadId', 'NotValidId', true);		//Subresult 2

            //Time
            validateTime('OKTime', '', false); //OK
            validateTime('OKTime', '09:25', true); //OK
            validateTime('BadTime', '25:25', true); //Subresult 3

            //Email
            validateEmail('OKEmail', '', false); //OK
            validateEmail('OKEmail', 'bart@simpsons.gov', true); //OK
            validateEmail('BadEmail', 'this@that@another', true); //Subresult 4

            //ZIP code
            validateZipCode('OKZip', '', false); //OK
            validateZipCode('OKZip', '03905', true); //OK
            validateZipCode('BadZip', '1234', true); //Subresult 5

            //SSN
            validateSsn('OKSSN', '', false); //OK
            validateSsn('OKSSN', '123-45-7683', true); //OK
            validateSsn('OKSSN', '123457683', true); //OK
            validateSsn('BadSSN', '1234', true); //Subresult 6

            //Object
            validateResource('OKObject', null, false);
            validateResource('MissingObject', null, true);	//Subresult 7
            validateResource('OKObject', new SubResource(true), false);
            validateResource('BadObject', new SubResource(false), true);	//Subresult 8

            //List
            validateResourceList('MissingList', null, true, null, null);	//Subresult 9
            validateResourceList('OkList', null, false, null, null);	//OK
            validateResourceList('TooSmallList', new object[1], true, 2, null); 	//Subresult 10
            validateResourceList('TooBigList', new object[3], true, null, 2); 	//Subresult 11
            validateResourceList('PartialList', new List<SubResource>{new SubResource(true), new SubResource(false)}, true, null, null); 	//Subresult 12

            //In set
            requirePropertyInSet('OKSet', '', false, new Set<String>());
            requirePropertyInSet('MissingSet', '', true, new Set<String>()); //Subresult 13
            requirePropertyInSet('OKSet', 'One', true, new Set<String>{'One', 'Two'});
            requirePropertyInSet('BadSet', 'Foo', true, new Set<String>{'One', 'Two'}); //Subresult 14

            //Integer
            validateInteger('OKInteger', 1, true, null, null);
            validateInteger('MissingInteger', null, true, null, null); //Subresult 15
            validateInteger('TooLowInteger', 1, true, 10, 100); //Subresult 16
            validateInteger('TooHighInteger', 200, true, 10, 100); //Subresult 17

            //Pattern
            validatePattern('OKPattern', '123.456-789', true, '\\d{3}.\\d{3}-\\d{3}', '###.###-###');
            validatePattern('MissingPattern', '', true, '\\d{3}.\\d{3}-\\d{3}', '###.###-###'); //Subresult 18
            validatePattern('WrongPattern', 'Foo', false, '\\d{3}.\\d{3}-\\d{3}', '###.###-###');  //Subresult 19

        }

    }

    private class SubResource extends AqRestResource {

        public Boolean IsOK {get;set;}

        public SubResource(Boolean isOk) {
            this.IsOk = isOk;
        }

        protected override void doValidate() {

            if (!this.IsOk) {
                requireProperty('SubProperty', null);
            }

        }

    }

    //Just to cover non-override of virtual method
    private class SubResource2 extends AqRestResource {}

    //Verifies that the result of validation result is as expected.
    private static void verifyValidationResult(AqResult result, Integer subResultIndex, String expectedScope, String expectedSeverity, object expectedReturnValue) {

        System.assert(result != null, 'Result is null.');
        System.assert(subResultIndex < result.SubResults.size(), 'subResultIndex index out of range, SubResults size is ' + String.valueOf(result.SubResults.size()));

        AqResult subResult = result.SubResults[subResultIndex];
        System.assertEquals(expectedScope, subResult.Scope, subResult);
        System.assertEquals(expectedSeverity, subResult.Severity, subResult);
        System.assertEquals(expectedReturnValue, subResult.ReturnValue, subResult);

    }

    //This method works in cooperation with the above TestResource class
    //getResources()
    @isTest
    private static void testGetResources() {

        TestObject__c record = new TestObject__c(Name = 'TestName', RequiredText__c = 'Bar');
        insert record;

        List<TestObject__c> subRecords = new List<TestObject__c> {
            new TestObject__c(Lookup__c = record.Id, Name = 'Sub1', RequiredText__c = 'Qux1'),
            new TestObject__c(Lookup__c = record.Id, Name = 'Sub2', RequiredText__c = 'Qux2')
        };
        insert subRecords;

        List<TestObject__c> records = [
            SELECT Id, Name, Lookup__c, RequiredText__c,
            (SELECT Id, Name, Lookup__c, RequiredText__c FROM AquivaTestObjects__r)
            FROM TestObject__c
            WHERE Id = :record.Id
        ];

        List<TestResource> resources = (List<TestResource>)AqRestResource.getResources(records, TestResource.class);
        System.assertEquals(1, resources.size());
        System.assertEquals(record.Id, resources[0].Id);
        System.assertEquals('TestName', resources[0].Name);
        System.assertEquals('Bar', resources[0].RequiredText);

        System.assertEquals(2, resources[0].TestResources.size());
        System.assertEquals('Sub1', resources[0].TestResources[0].Name);
        System.assertEquals('Qux1', resources[0].TestResources[0].RequiredText);
        System.assertEquals('Sub2', resources[0].TestResources[1].Name);
        System.assertEquals('Qux2', resources[0].TestResources[1].RequiredText);

    }

    //This method works in cooperation with the above TestResource class
    //upsertResources()
    @isTest
    private static void testUpsertResources() {

        //Valid record
        TestResource res1 = new TestResource();
        res1.Name = 'TestName';
        res1.RequiredText = 'Bar';
        res1.SkipValidate = true;

        //Will fail validate
        TestResource res2 = new TestResource();
        res2.SkipValidate = false;

        //Will fail insert
        TestResource res3 = new TestResource();
        res3.Name = 'TestName';
        res3.SkipValidate = true;

        //All or nothing
        AqResult result = AqRestResource.upsertResources(new List<TestResource>{res1, res2, res3}, true);
        System.assertEquals(3, result.SubResults.size());
        System.assertEquals(false , result.SubResults[0].hasError());
        System.assertEquals(true , result.SubResults[1].hasError());
        System.assertEquals(true , result.SubResults[2].hasError());
        System.assertEquals(0, [SELECT Id FROM TestObject__c].size(), 'Record should not have been saved.');

        //Not all-or-nothing
        result = AqRestResource.upsertResources(new List<TestResource>{res1, res2, res3}, false);
        System.assertEquals(3, result.SubResults.size());
        System.assertEquals(false , result.SubResults[0].hasError());
        System.assertEquals(true , result.SubResults[1].hasError());
        System.assertEquals(true , result.SubResults[2].hasError());
        System.assertEquals(1, [SELECT Id FROM TestObject__c].size(), 'Record should have been saved.');

    }

    //This method works in cooperation with the above TestResource class
    @isTest
    private static void testValidation() {

        TestResource testRes = new TestResource();

        //Validate and do basic asserts on result
        AqResult result = testRes.validate();
        System.assertEquals(AqResult.SEVERITY_ERROR, result.Severity, result);
        System.assertEquals(TOTAL_SUBRESULTS, result.SubResults.size(), result);

        //Verify expected subresults
        verifyValidationResult(result, 0, 'RequiredField', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 1, 'TooLongString', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 2, 'BadId', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 3, 'BadTime', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 4, 'BadEmail', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 5, 'BadZip', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 6, 'BadSSN', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 7, 'MissingObject', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 8, 'BadObject.SubProperty', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 9, 'MissingList', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 10, 'TooSmallList', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 11, 'TooBigList', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 12, 'PartialList[1].SubProperty', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 13, 'MissingSet', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 14, 'BadSet', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 15, 'MissingInteger', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 16, 'TooLowInteger', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 17, 'TooHighInteger', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 18, 'MissingPattern', AqResult.SEVERITY_ERROR, null);
        verifyValidationResult(result, 19, 'WrongPattern', AqResult.SEVERITY_ERROR, null);

        SubResource2 subRes2 = new SubResource2();
        System.assertEquals(null, subRes2.validate());

        //Exercise not-overridden type methods
        subRes2.put(null);
        subRes2.get(null);
        System.assertEquals(null, subRes2.getResourceType());
        System.assertEquals(null, subRes2.getResourceListType());
        System.assertEquals(null, subRes2.getSObjectType());
        System.assertEquals(null, subRes2.getSObjectListType());

    }

    //fieldForProperty()
    @isTest
    private static void testFieldForProperty() {

        TestResource res = new TestResource();

        //Standard field
        System.assertEquals('Name', res.fieldForProperty('Name'));

        //Custom field
        System.assertEquals(Aq.appendPrefix('Lookup__c'), res.fieldForProperty('Lookup'));

        //Doesn't exist
        try {
            System.assertEquals(null, res.fieldForProperty('FooBar'));
            System.assert(false, 'Expected NotFoundException');
        }
        catch (Aq.NotFoundException e) {
            System.assert(true);
        }

    }

}
