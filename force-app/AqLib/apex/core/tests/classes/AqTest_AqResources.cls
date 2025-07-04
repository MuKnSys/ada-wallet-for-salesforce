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

//Unit tests for AqResources.cls
@isTest
private with sharing class AqTest_AqResources {

    @TestSetup
    private static void setup() {
        AqTest.setup();
    }

    //Address resource
    @isTest
    private static void testAddress() {
        System.runAs(AqTest.adminUser) {
            AqResources.Address address = new AqResources.Address();
            address = new AqResources.Address();
            address = new AqResources.Address('Mailing', '131 Donut Road', 'Kitteredge', 'MO', '12345', 'US');
            AqResult result = address.validate();
            System.assertEquals(null, result);

            TestObject__c testObject = new TestObject__c(
                    Name = 'Test',
                    RequiredText__c = 'Foo',
                    AddressStreet__c = address.Street,
                    AddressCity__c = address.City,
                    AddressStateCode__c = address.State,
                    AddressState__c = address.State,
                    AddressPostalCode__c = address.PostalCode,
                    AddressCountryCode__c = address.Country,
                    AddressCountry__c = address.Country);

            //Construct from record
            AqResources.Address newAddress = new AqResources.Address(testObject, 'Mailing', 'Address', true);
            System.assertEquals(address, newAddress);

            //Put to record
            testObject = new TestObject__c();
            newAddress.put(testObject, 'Address', true);
            System.assertEquals(address.Street, testObject.AddressStreet__c);
            System.assertEquals(address.City, testObject.AddressCity__c);
            System.assertEquals(address.State, AqEnv.IsUsingStateCountryPicklists == true ? testObject.AddressStateCode__c : testObject.AddressState__c);
            System.assertEquals(address.PostalCode, testObject.AddressPostalCode__c);
            System.assertEquals(address.Country, AqEnv.IsUsingStateCountryPicklists == true ? testObject.AddressCountryCode__c : testObject.AddressCountry__c);
        }
    }

    //Phone resource
    @isTest
    private static void testPhone() {

        AqResources.Phone phone = new AqResources.Phone();
        phone = new AqResources.Phone('Home', '603-555-1212');
        AqResult result = phone.validate();
        System.assertEquals(null, result);

    }

    //Email resource
    @isTest
    private static void testEmail() {

        AqResources.Email email = new AqResources.Email();
        email = new AqResources.Email('Work', 'good@good.good');
        AqResult result = email.validate();
        System.assertEquals(null, result);

    }

    //AqContact resource
    @isTest
    private static void testAqContact() {

        AqResources.AqContact aqContact = new AqResources.AqContact();
        aqContact = new AqResources.AqContact('First', 'Last');
        aqContact.Birthdate = AqEnv.today();

        System.assertEquals(null, aqContact.getAddress('Mailing'));
        System.assertEquals(null, aqContact.getPhone('Home'));
        System.assertEquals(null, aqContact.getEmail('Work'));

        AqResources.Address testAddress = new AqResources.Address('Mailing', '131 Donut Road', 'Kitteredge', 'MO', '12345', 'US');
        aqContact.addAddress(testAddress);
        AqResources.Address address = aqContact.getAddress('Mailing');
        System.assertEquals(testAddress, address);
        System.assertEquals(null, aqContact.getAddress('Foo'));

        aqContact.addPhone('Home', '');
        System.assertEquals(null, aqContact.getPhone('Home'));
        aqContact.addPhone('Home', '555-1212');
        System.assertEquals('555-1212', aqContact.getPhone('Home'));
        System.assertEquals(null, aqContact.getPhone('Foo'));

        aqContact.addEmail('Work', '');
        System.assertEquals(null, aqContact.getEmail('Work'));
        aqContact.addEmail('Work', 'good@good.good');
        System.assertEquals('good@good.good', aqContact.getEmail('Work'));
        System.assertEquals(null, aqContact.getEmail('Foo'));

        AqResult result = aqContact.validate();
        System.assertEquals(null, result);

        aqContact.Id = 'FooBar';
        aqContact.stripUniqueData();
        System.assertEquals(null, aqContact.Id);

    }

}
