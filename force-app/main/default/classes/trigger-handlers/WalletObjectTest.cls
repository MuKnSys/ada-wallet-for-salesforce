@isTest
private class WalletObjectTest {
    private static final String ASSERT_MESSAGE_ERROR = 'Should throw an error for duplicate index';
    private static final String ASSERT_MESSAGE_NO_ERROR = 'Should not throw an error for unique index';
    private static final String TEST_WALLET_NAME = 'Test Wallet';
    private static final Integer TEST_INDEX = 0;
    private static final Integer DUPLICATE_INDEX = 0;
    private static final Integer UNIQUE_INDEX = 1;
    
    @testSetup
    private static void testData() {
        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = TEST_WALLET_NAME
        );
        insert walletSet;
        
        Wallet__c wallet = new Wallet__c(
            Name = TEST_WALLET_NAME,
            Wallet_Set__c = walletSet.Id,
            Account_Index__c = TEST_INDEX
        );
        insert wallet;
    }
    
    @isTest
    private static void beforeInsertShouldValidateUniqueIndex() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        
        Wallet__c newWallet = new Wallet__c(
            Name = TEST_WALLET_NAME,
            Wallet_Set__c = walletSet.Id,
            Account_Index__c = DUPLICATE_INDEX
        );
        
        Test.startTest();
            try {
                insert newWallet;
                Assert.fail(ASSERT_MESSAGE_ERROR);
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('already exists'), ASSERT_MESSAGE_ERROR);
            }
        Test.stopTest();
    }
    
    @isTest
    private static void beforeInsertShouldAllowUniqueIndex() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        
        Wallet__c newWallet = new Wallet__c(
            Name = TEST_WALLET_NAME,
            Wallet_Set__c = walletSet.Id,
            Account_Index__c = UNIQUE_INDEX
        );
        
        Test.startTest();
            insert newWallet;
        Test.stopTest();
        
        List<Wallet__c> wallets = [SELECT Id FROM Wallet__c WHERE Account_Index__c = :UNIQUE_INDEX];
        Assert.areEqual(1, wallets.size(), ASSERT_MESSAGE_NO_ERROR);
    }        
    
    @isTest
    private static void beforeUpdateShouldAllowUniqueIndex() {
        Wallet__c existingWallet = [SELECT Id, Wallet_Set__c FROM Wallet__c LIMIT 1];
        
        Wallet__c walletToUpdate = new Wallet__c(
            Id = existingWallet.Id,
            Account_Index__c = UNIQUE_INDEX
        );
        
        Test.startTest();
            update walletToUpdate;
        Test.stopTest();
        
        Wallet__c updatedWallet = [SELECT Account_Index__c FROM Wallet__c WHERE Id = :existingWallet.Id];
        Assert.areEqual(UNIQUE_INDEX, updatedWallet.Account_Index__c, ASSERT_MESSAGE_NO_ERROR);
    }
} 