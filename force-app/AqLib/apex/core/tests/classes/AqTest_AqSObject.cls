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

//Unit tests for AqSObject.cls
@isTest
private with sharing class AqTest_AqSObject {

    private static final String ACCESS_MESSAGE = 'Verify user running tests has full CRUD and FLS access to TestObject__c';

    @isTest
    static void testGetToken() {
        System.assertEquals(TestObject__c.getSObjectType(), AqSObject.getToken('TestObject__c'));
    }

    @isTest
    static void testGetDescribe() {
        System.assertEquals(TestObject__c.getSObjectType().getDescribe(), AqSObject.getObjectDescribe('TestObject__c'));

        try {
            AqSObject.getObjectDescribe('DoesNotExist');
            System.assert(false, 'object not found exception should be thrown');
        } catch (Exception e) {}
    }

    //These cannot be properly verified here without introducing multiple test profiles
    @isTest
    static void testCRUDPermissions() {

        System.assertEquals(true, AqSObject.isAccessible(TestObject__c.getSObjectType()), ACCESS_MESSAGE);
        System.assertEquals(true, AqSObject.isCreateable(TestObject__c.getSObjectType()), ACCESS_MESSAGE);
        System.assertEquals(true, AqSObject.isUpdateable(TestObject__c.getSObjectType()), ACCESS_MESSAGE);
        System.assertEquals(true, AqSObject.isDeletable(TestObject__c.getSObjectType()), ACCESS_MESSAGE);

        AqSObject.requireAccessible(TestObject__c.getSObjectType());
        AqSObject.requireCreateable(TestObject__c.getSObjectType());
        AqSObject.requireUpdateable(TestObject__c.getSObjectType());
        AqSObject.requireDeletable(TestObject__c.getSObjectType());


        System.assertEquals(true, AqSObject.isAccessible('TestObject__c'), ACCESS_MESSAGE);
        System.assertEquals(true, AqSObject.isCreateable('TestObject__c'), ACCESS_MESSAGE);
        System.assertEquals(true, AqSObject.isUpdateable('TestObject__c'), ACCESS_MESSAGE);
        System.assertEquals(true, AqSObject.isDeletable('TestObject__c'), ACCESS_MESSAGE);

        AqSObject.requireAccessible('TestObject__c');
        AqSObject.requireCreateable('TestObject__c');
        AqSObject.requireUpdateable('TestObject__c');
        AqSObject.requireDeletable('TestObject__c');

    }

}
