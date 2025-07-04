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

//Unit tests for AqField.cls
@isTest
private with sharing class AqTest_AqField {

    private static final String ACCESS_MESSAGE = 'Verify user running tests has full CRUD and FLS access to TestObject__c';

    @TestSetup
    private static void setup() {
        AqTest.setup();
    }

    @isTest
    static void testGetType() {
        System.assertEquals(TestObject__c.Name.getDescribe().getSOAPType(), AqField.getSOAPType('TestObject__c', 'Name'));
        System.assertEquals(TestObject__c.Name.getDescribe().getType(), AqField.getType('TestObject__c', 'Name'));
        System.assertEquals(
            true,
            AqField.isEmailField(AqField.getFieldDescribe('TestObject__c', 'Email__c'))
        );
        System.assertEquals(
            false,
            AqField.isEmailField(AqField.getFieldDescribe('User', 'Username'))
        );
        System.assertEquals(
            true,
            AqField.isUsernameField(AqField.getFieldDescribe('User', 'Username'))
        );
        System.assertEquals(
            true,
            AqField.isStringSOAPType(AqField.getFieldDescribe('TestObject__c', 'Picklist__c'))
        );
        System.assertEquals(
            true,
            AqField.isBooleanSOAPType(AqField.getFieldDescribe('TestObject__c', 'Checkbox__c'))
        );
        System.assertEquals(
            true,
            AqField.isRequiredField(AqField.getFieldDescribe('TestObject__c', 'RequiredText__c'))
        );
    }

    @isTest
    static void testGetToken() {

        System.assertEquals(TestObject__c.Name, AqField.getToken(new TestObject__c(), 'Name'));
        System.assertEquals(TestObject__c.Name, AqField.getToken(TestObject__c.getSObjectType(), 'Name'));

        try {

            AqField.getToken(TestObject__c.getSObjectType(), 'Foo');
            System.assert(false, 'Expected NotFoundException');

        } catch (Aq.NotFoundException e) {
            System.assert(true);
        }

        //Relationship
        System.assertEquals(TestObject__c.Name, AqField.getToken(TestObject__c.getSObjectType(), 'Lookup__r.Name'));

        try {

            AqField.getToken(TestObject__c.getSObjectType(), 'LookupFoo__r.FooNotExist__c');
            System.assert(false, 'Expected NotFoundException');

        } catch (Aq.NotFoundException e) {
            System.assert(true);
        }

        try {

            //Not relationship field
            AqField.getToken(TestObject__c.getSObjectType(), 'Date__r.FooNotExist__c');
            System.assert(false, 'Expected NotFoundException');

        } catch (Aq.NotFoundException e) {
            System.assert(true);
        }

    }

    //Current user must have full access to TestObject__c
    @isTest
    static void testFlsMethods() {

        System.assertEquals(true, AqField.isAccessible('TestObject__c', 'Lookup__r.Name'), ACCESS_MESSAGE);
        System.assertEquals(true, AqField.isCreateable('TestObject__c', 'Lookup__r.Name'), ACCESS_MESSAGE);
        System.assertEquals(true, AqField.isUpdateable('TestObject__c', 'Lookup__r.Name'), ACCESS_MESSAGE);

        //Cannot test failure without a known profile that doesn't have access [todo]
        AqField.requireAccessible('TestObject__c', new Set<String>{'Lookup__r.Name'});
        AqField.requireCreateable('TestObject__c', new Set<String>{'Lookup__r.Name'});
        AqField.requireUpdateable('TestObject__c', new Set<String>{'Lookup__r.Name'});


        System.assertEquals(true, AqField.isAccessible(TestObject__c.Name), ACCESS_MESSAGE);
        System.assertEquals(true, AqField.isCreateable(TestObject__c.Name), ACCESS_MESSAGE);
        System.assertEquals(true, AqField.isUpdateable(TestObject__c.Name), ACCESS_MESSAGE);

        //Cannot test failure without a known profile that doesn't have access [todo]
        AqField.requireAccessible(TestObject__c.Name);
        AqField.requireCreateable(TestObject__c.Name);
        AqField.requireUpdateable(TestObject__c.Name);

    }

    //Current user must have full access to TestObject__c
    @isTest
    static void testGets() {
        System.runAs(AqTest.adminUser) {
            TestObject__c testRecord = AqTest.getFullTestRecord();

            System.assertEquals(null, AqField.getString(null, TestObject__c.Name), ACCESS_MESSAGE);

            System.assertEquals(testRecord.Name, AqField.getString(testRecord, TestObject__c.Name), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Checkbox__c, AqField.getBoolean(testRecord, TestObject__c.Checkbox__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Currency__c, AqField.getDecimal(testRecord, TestObject__c.Currency__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Date__c, AqField.getDate(testRecord, TestObject__c.Date__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.DateTime__c, AqField.getDatetime(testRecord, TestObject__c.DateTime__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Email__c, AqField.getString(testRecord, TestObject__c.Email__c), ACCESS_MESSAGE);
            System.assertEquals((Integer) testRecord.Integer__c, AqField.getInteger(testRecord, TestObject__c.Integer__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.LongText__c, AqField.getString(testRecord, TestObject__c.LongText__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Percent__c, AqField.getDecimal(testRecord, TestObject__c.Percent__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Phone__c, AqField.getString(testRecord, TestObject__c.Phone__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Picklist__c, AqField.getString(testRecord, TestObject__c.Picklist__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.RequiredText__c, AqField.getString(testRecord, TestObject__c.RequiredText__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.RichText__c, AqField.getString(testRecord, TestObject__c.RichText__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Text__c, AqField.getString(testRecord, TestObject__c.Text__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.TextArea__c, AqField.getString(testRecord, TestObject__c.TextArea__c), ACCESS_MESSAGE);
            System.assertEquals(testRecord.Url__c, AqField.getString(testRecord, TestObject__c.Url__c), ACCESS_MESSAGE);

            //Multi-select picklist
            System.assertEquals(new List<String>{
                    'Value One', 'Value Two'
            }, AqField.getMultiSelectPicklist(testRecord, TestObject__c.MultiPicklist__c), ACCESS_MESSAGE);
            testRecord.MultiPicklist__c = null;
            System.assertEquals(new List<String>(), AqField.getMultiSelectPicklist(testRecord, TestObject__c.MultiPicklist__c), ACCESS_MESSAGE);

            //Date-time local
            Datetime now = AqEnv.now();
            testRecord.DateTime__c = now;
            System.assertEquals(now, AqField.getDatetime(testRecord, TestObject__c.DateTime__c), ACCESS_MESSAGE);

            Datetime localNow = AqField.getDatetimeLocal(testRecord, TestObject__c.DateTime__c);
            System.assertEquals(now.addSeconds(UserInfo.getTimeZone().getOffset(now.date()) / 1000), localNow);

            testRecord.DateTime__c = null;
            System.assertEquals(null, AqField.getDatetimeLocal(testRecord, TestObject__c.DateTime__c));
        }
    }

    //getChildRecords()
    @isTest
    static void testGetChildRecords() {

        //Build parent/child records
        TestObject__c parentRecord = new TestObject__c(Name = 'Parent', RequiredText__c = 'Req');
        insert parentRecord;

        TestObject__c childRecord1 = new TestObject__c(Name = 'Child1', RequiredText__c = 'Req', Lookup__c = parentRecord.Id);
        TestObject__c childRecord2 = new TestObject__c(Name = 'Child2', RequiredText__c = 'Req', Lookup__c = parentRecord.Id);
        insert new List<TestObject__c>{childRecord1, childRecord2};

        //Select with sub-select
        parentRecord = [
            SELECT Id,
                (SELECT Id, Name, Lookup__c FROM AquivaTestObjects__r)
            FROM TestObject__c
            WHERE Id = :parentRecord.Id
        ];

        //Get the child records
        sObject[] results = AqField.getChildRecords(parentRecord, 'AquivaTestObjects__r', TestObject__c.getSObjectType(), true);
        System.assertEquals(2, results.size());
        System.assertEquals(childRecord1.Id, results[0].Id);
        System.assertEquals(childRecord2.Id, results[1].Id);

        //Null case
        System.assertEquals(
            0,
            AqField.getChildRecords(null, 'AquivaTestObjects__r', TestObject__c.getSObjectType(), true).size()
        );

    }

    //Current user must have full access to TestObject__c
    @isTest
    static void testPuts() {
        System.runAs(AqTest.adminUser) {
            TestObject__c testRecord = AqTest.getFullTestRecord();

            AqField.put(testRecord, TestObject__c.Name, 'NewName');
            System.assertEquals('NewName', testRecord.Name, ACCESS_MESSAGE);

            AqField.putBoolean(testRecord, TestObject__c.Checkbox__c, false);
            System.assertEquals(false, testRecord.Checkbox__c, ACCESS_MESSAGE);

            testRecord.MultiPicklist__c = null;
            AqField.putMultiSelectPicklist(testRecord, TestObject__c.MultiPicklist__c, new List<String>{
                    'Value One', 'Value Two'
            });
            System.assertEquals('Value One;Value Two', testRecord.MultiPicklist__c, ACCESS_MESSAGE);

            //Test for updating
            insert testRecord;

            AqField.put(testRecord, TestObject__c.Name, 'NewName2');
            System.assertEquals('NewName2', testRecord.Name, ACCESS_MESSAGE);

            AqField.putBoolean(testRecord, TestObject__c.Checkbox__c, true);
            System.assertEquals(true, testRecord.Checkbox__c, ACCESS_MESSAGE);
        }
    }

    //getSoqlLiteral()
    @isTest
    static void testGetSoqlLiteral() {

        System.assertEquals('null', AqField.getSoqlLiteral(TestObject__c.Checkbox__c, null));
        System.assertEquals('true', AqField.getSoqlLiteral(TestObject__c.Checkbox__c, 'true'));
        System.assertEquals('false', AqField.getSoqlLiteral(TestObject__c.Checkbox__c, 'false'));
        System.assertEquals('123.45', AqField.getSoqlLiteral(TestObject__c.Currency__c, '123.45'));
        System.assertEquals('123', AqField.getSoqlLiteral(TestObject__c.Integer__c, '123'));
        System.assertEquals('2017-06-14', AqField.getSoqlLiteral(TestObject__c.Date__c, '2017-06-14'));
        System.assertEquals('2017-06-14T01:02:03Z', AqField.getSoqlLiteral(TestObject__c.DateTime__c, '2017-06-14T01:02:03Z'));
        System.assertEquals('\'The \\\'Text\\\' Value\'', AqField.getSoqlLiteral(TestObject__c.Text__c, 'The \'Text\' Value'));
    }

    //getPicklistLabel()
    @isTest
    static void testGetPicklistLabel() {

        System.assertEquals('Value One', AqField.getPicklistLabel(TestObject__c.Picklist__c, 'Value One'));

        try {
            String label = AqField.getPicklistLabel(TestObject__c.Picklist__c, 'Not Exists');
            System.assert(false, 'Expected NotFoundException');
        } catch (Aq.NotFoundException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testGetDescribe () {
        System.assertEquals(
            TestObject__c.Name.getDescribe(), AqField.getFieldDescribe('TestObject__c', 'Lookup__r.Name')
        );

        try {
            AqField.getFieldDescribe('TestObject__c', 'DoesNotExist__r.Name');
            system.assert(false, 'fiend not found exception should be thrown');
        } catch (Exception e) {}
    }

    @isTest 
    static void testGetSObjectFieldValue() {

        Account account = new Account(Name = 'Test Account');
        insert account;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = account.Id,
            StageName = 'Open',
            CloseDate = Date.today().addDays(10)
        );
        insert opp;

        opp = [SELECT Name, Account.Owner.Name, Contract.Owner.Name FROM Opportunity LIMIT 1];

        System.assertEquals(opp.Name, AqField.getSObjectFieldValue(opp, 'Name'));
        System.assertEquals(UserInfo.getName(), AqField.getSObjectFieldValue(opp, 'Account.Owner.Name'));
        System.assertEquals(null, AqField.getSObjectFieldValue(opp, 'Contract.Owner.Name'));
        System.assertEquals(null, AqField.getSObjectFieldValue(opp, null));
    }

    @isTest
    private static void getGetPicklistEntries() {

        //Empty constructor
        AqPicklistEntry pe = new AqPicklistEntry();

        List<AqPicklistEntry> picklistEntries = AqField.getPicklistEntries(TestObject__c.Picklist__c);
        System.assertEquals(3, picklistEntries.size());
        System.assertEquals('Value One', picklistEntries[0].Label);
        System.assertEquals('Value Two', picklistEntries[1].Label);
        System.assertEquals('Value Three', picklistEntries[2].Label);

        //Not picklist
        try {
            System.assertEquals(0, AqField.getPicklistEntries(TestObject__c.Name).size());
            System.assert(false, 'Expected AqException.');
        }
        catch (AqException e) {
            System.assert(true);
        }

    }
}
