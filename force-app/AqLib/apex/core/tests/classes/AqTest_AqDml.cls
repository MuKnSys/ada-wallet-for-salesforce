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
private with sharing class AqTest_AqDml {
    
    // Again removed as this fails when using Native User Mode due to a Salesforce Bug
    // See https://salesforce.stackexchange.com/q/413410/256
    /*
    @IsTest
    private static void testDMLCheckWithRelationshipFields() {
        Account acc = new Account(Name = 'NewAccount');
        insert acc;

        Contact c = new Contact(LastName = 'NewContact', AccountId = acc.Id);
        insert c;

        Contact cToUpdate = [
            SELECT Id, LastName, Name, LastModifiedDate, AccountId, Account.Name, Account.BillingStreet 
            FROM Contact
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        cToUpdate.FirstName = 'First';

        try {
            AqDml.secureUpdate(cToUpdate);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }
    }*/

    @IsTest
    private static void testDMLCheckForSObject() {
        Account newAccount = new Account(Name = 'NewAccount');

        //secureInsert
        try {
            AqDml.secureInsert(newAccount);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }

        //secureUpdate
        Account updateAccount = [SELECT Name FROM Account WHERE Name = 'NewAccount' LIMIT 1].get(0);
        updateAccount.Name = 'UpdatedAccount';
        try {
            AqDml.secureUpdate(updateAccount);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }

        //secureDelete
        Account deleteAccount = [SELECT Name FROM Account WHERE Name = 'UpdatedAccount' LIMIT 1].get(0);
        try {
            AqDml.secureDelete(deleteAccount);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }

        //secureUndelete
        Account undeleteAccount = [SELECT Name, IsDeleted FROM Account WHERE IsDeleted = TRUE ALL ROWS].get(0);
        try {
            AqDml.secureUndelete(undeleteAccount);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }
    }

    @IsTest
    private static void testDMLCheckForListOfSObjects() {
        Account newAccount = new Account(Name = 'TestAccount');
        List<Account> newAccountList = new List<Account>{newAccount};

        //secureInsert
        try {
            AqDml.secureInsert(newAccountList);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }

        //secureUpdate
        List<Account> updateAccountList = new List<Account>{};

        for (Account account : [SELECT Name FROM Account WHERE Name = 'TestAccount']) {
            account.Name = 'UpdatedAccount';
            updateAccountList.add(account);
        }

        try {
            AqDml.secureUpdate(updateAccountList);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }

        //secureDelete
        List<Account> deleteAccountList = [SELECT Name FROM Account WHERE Name = 'UpdatedAccount'];

        try {
            AqDml.secureDelete(deleteAccountList);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }

        //secureUndelete
        List<Account> undeleteAccounts = [SELECT Name, IsDeleted FROM Account WHERE IsDeleted = TRUE ALL ROWS];
        try {
            AqDml.secureUndelete(undeleteAccounts);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }
    }

    @IsTest
    private static void testDMLCheckForUpsertSObject() {
        Account newAccount = new Account(Name = 'NewAccount');
        insert newAccount;
        Account accountToUpdate = [SELECT Name FROM Account WHERE Name = 'NewAccount' LIMIT 1].get(0);
        accountToUpdate.Name = 'Updated Account';
        Account accountToInsert = new Account(Name = 'TestAccount');

        //secureUpsert
        try {
            AqDml.secureUpsert(accountToUpdate);
            AqDml.secureUpsert(accountToInsert);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }
    }

    @IsTest
    private static void testDMLCheckForUpsertListOfSObjects() {
        Account newAccount = new Account(Name = 'NewAccount');
        List<Account> updateAccountList = new List<Account>{};
        insert newAccount;
        for (Account account : [SELECT Name FROM Account WHERE Name = 'NewAccount']) {
            account.Name = 'UpdatedAccount';
            updateAccountList.add(account);
        }

        Account accountToInsert = new Account(Name = 'TestAccount');
        List<Account> accountToInsertList = new List<Account>{accountToInsert};

        //secureUpsert
        try {
            AqDml.secureUpsert(updateAccountList);
            AqDml.secureUpsert(accountToInsertList);
        } catch (Exception e) {
            System.assert(false, 'Exception should not be thrown' + e.getMessage());
        }
    }
}
