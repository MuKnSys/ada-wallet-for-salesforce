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

//Unit tests for AqString.cls
@isTest
private with sharing class AqTest_AqString {

    @isTest
    private static void testMisc() {

        //left()
        System.assertEquals(null, AqString.left(null, 10));
        System.assertEquals('12345', AqString.left('1234567890', 5));

        //parseId()
        System.assertEquals(null, AqString.parseId(''));
        System.assertEquals(null, AqString.parseId(null));
        System.assertEquals(Id.valueOf('0014100000Jf7qF'), AqString.parseId('0014100000Jf7qF'));

        try {
            String testId = AqString.parseId('NotAnId');
            System.assert(false, 'Exception not thrown for invalid Id.');
        } catch (Aq.ValidationException e) {
            //Expected
            System.assert(true);
        }
    }

    //valueOf()
    @isTest
    private static void testValueOf() {

        System.assertEquals(null, AqString.valueOf(null));
        System.assertEquals('123', AqString.valueOf('123'));
        System.assertEquals(Date.newInstance(2000, 1, 1).format(), AqString.valueOf(Date.newInstance(2000, 1, 1)));
        System.assertEquals(DateTime.newInstance(2000, 1, 1, 1, 1, 1).format(), AqString.valueOf(DateTime.newInstance(2000, 1, 1, 1, 1, 1)));
        System.assertEquals(TestObject__c.SObjectType.getDescribe().getLabel(), AqString.valueOf(TestObject__c.SObjectType));
        System.assertEquals(TestObject__c.Name.getDescribe().getLabel(), AqString.valueOf(TestObject__c.Name));
        System.assertEquals(String.valueOf(5), AqString.valueOf(5));
    }

    //format methods
    @isTest
    private static void testFormat() {

        object[] args = new object[] {'Foo', 5, true, Date.newInstance(2000, 1, 1), DateTime.newInstance(2000, 1, 1, 1, 1, 1)};

        System.assertEquals(AqString.valueOf(args[0]), AqString.format('{0}', args[0]));
        System.assertEquals(AqString.valueOf(args[0]) + AqString.valueOf(args[1]), AqString.format('{0}{1}', args[0], args[1]));
        System.assertEquals(AqString.valueOf(args[0]) + AqString.valueOf(args[1]) + AqString.valueOf(args[2]), AqString.format('{0}{1}{2}', args[0], args[1], args[2]));
        System.assertEquals(AqString.valueOf(args[0]) + AqString.valueOf(args[1]) + AqString.valueOf(args[2]) + AqString.valueOf(args[3]), AqString.format('{0}{1}{2}{3}', args[0], args[1], args[2], args[3]));
        System.assertEquals(AqString.valueOf(args[0]) + AqString.valueOf(args[1]) + AqString.valueOf(args[2]) + AqString.valueOf(args[3]) + AqString.valueOf(args[4]), AqString.format('{0}{1}{2}{3}{4}', args[0], args[1], args[2], args[3], args[4]));

        System.assertEquals('Let\'s try quotes: \'Foo\'.', AqString.format('Let\'s try {0}: \'{1}\'.', 'quotes', 'Foo'));

        List<object> theList = new List<object>{'Foo', true};
        Set<object> theSet = new Set<object>(theList);
        System.assertEquals(AqString.valueOf(theList[0]) + ', ' + AqString.valueOf(theList[1]), AqString.formatList(theList));
        System.assertEquals(AqString.valueOf(theList[0]) + ', ' + AqString.valueOf(theList[1]), AqString.formatSet(theSet));
        System.assertEquals('One, two', AqString.formatList(new List<String>{'One, two'}));
        System.assertEquals('One, two', AqString.formatSet(new Set<String>{'One, two'}));
        System.assertEquals('Name, Record ID', AqString.formatSet(new Set<SObjectField>{TestObject__c.Name, TestObject__c.Id}));
    }

    @isTest
    private static void testGetRandomString() {
        System.assertNotEquals(null, AqString.getRandomString(10));
        System.assertEquals(5, AqString.getRandomString(5).length());

        try {
            String a = AqString.getRandomString(null);
            System.assert(false, 'Validation exception should be thrown');
        } catch (Exception e) {}
    }

    @IsTest
    static void testGenerateFakeId() {
        String fakeAccountId = AqString.generateFakeSalesforceId(Account.SObjectType);
        String anotherFakeAccountId = AqString.generateFakeSalesforceId(Account.SObjectType);

        System.assert(fakeAccountId.startsWith('001000000000000'), 'Valid account fake id is expected');
        System.assert(anotherFakeAccountId.startsWith('001000000000001'), 'Another valid account fake id is expected');
    }
}
