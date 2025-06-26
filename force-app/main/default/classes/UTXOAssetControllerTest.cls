@IsTest
public with sharing class UTXOAssetControllerTest {
    
    @TestSetup
    static void makeData() {
        // Create test wallet set
        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Test Wallet Set',
            Seed_Phrase__c = 'test seed phrase for unit testing purposes only'
        );
        insert walletSet;
        
        // Create test wallet
        Wallet__c wallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Account_Index__c = 0
        );
        insert wallet;
        
        // Create test UTXO address
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test123456789',
            Index__c = 0,
            Path__c = 'm/44\'/1815\'/0\'/0/0'
        );
        insert utxoAddress;
    }
    
    @IsTest
    static void testSyncAssetsAndTransactions_Success() {
        // Get test data
        UTXO_Address__c testAddress = [SELECT Id FROM UTXO_Address__c LIMIT 1];
        
        // Set up mock for successful API calls
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        
        Test.startTest();
        
        // Call the combined sync method
        Map<String, Object> result = UTXOAssetController.syncAssetsAndTransactions(testAddress.Id);
        
        Test.stopTest();
        
        // Verify success
        System.assert((Boolean) result.get('success'), 'Sync should be successful');
        System.assertNotEquals(null, result.get('statistics'), 'Statistics should be present');
        System.assertNotEquals(null, result.get('message'), 'Message should be present');
        
        // Verify statistics structure
        Map<String, Object> stats = (Map<String, Object>) result.get('statistics');
        System.assert(stats.containsKey('assetsInserted'), 'Should have assetsInserted count');
        System.assert(stats.containsKey('assetsUpdated'), 'Should have assetsUpdated count');
        System.assert(stats.containsKey('transactionsInserted'), 'Should have transactionsInserted count');
        System.assert(stats.containsKey('transactionsUpdated'), 'Should have transactionsUpdated count');
        System.assert(stats.containsKey('totalProcessingTimeMs'), 'Should have processing time');
    }
    
    @IsTest
    static void testSyncAssets_Success() {
        // Get test data
        UTXO_Address__c testAddress = [SELECT Id FROM UTXO_Address__c LIMIT 1];
        
        // Set up mock
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        
        Test.startTest();
        
        // Call assets sync method
        Map<String, Object> result = UTXOAssetController.syncAssets(testAddress.Id);
        
        Test.stopTest();
        
        // Verify success
        System.assert((Boolean) result.get('success'), 'Asset sync should be successful');
        System.assertNotEquals(null, result.get('assets'), 'Assets should be present');
        
        // Verify statistics
        Map<String, Object> stats = (Map<String, Object>) result.get('statistics');
        System.assert(stats.containsKey('assetsInserted'), 'Should have assetsInserted count');
        System.assert(stats.containsKey('assetsUpdated'), 'Should have assetsUpdated count');
        System.assert(stats.containsKey('processingTimeMs'), 'Should have processing time');
    }
    
    @IsTest
    static void testSyncTransactions_Success() {
        // Get test data
        UTXO_Address__c testAddress = [SELECT Id FROM UTXO_Address__c LIMIT 1];
        
        // Set up mock
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        
        Test.startTest();
        
        // Call transactions sync method
        Map<String, Object> result = UTXOAssetController.syncTransactions(testAddress.Id);
        
        Test.stopTest();
        
        // Verify success
        System.assert((Boolean) result.get('success'), 'Transaction sync should be successful');
        System.assertNotEquals(null, result.get('transactions'), 'Transactions should be present');
        
        // Verify statistics
        Map<String, Object> stats = (Map<String, Object>) result.get('statistics');
        System.assert(stats.containsKey('transactionsInserted'), 'Should have transactionsInserted count');
        System.assert(stats.containsKey('transactionsUpdated'), 'Should have transactionsUpdated count');
        System.assert(stats.containsKey('processingTimeMs'), 'Should have processing time');
    }
    
    @IsTest
    static void testSyncAssetsAndTransactions_NullAddressId() {
        Test.startTest();
        
        // Call with null address ID
        Map<String, Object> result = UTXOAssetController.syncAssetsAndTransactions(null);
        
        Test.stopTest();
        
        // Verify failure
        System.assertEquals(false, result.get('success'), 'Should fail with null address ID');
        System.assertNotEquals(null, result.get('message'), 'Should have error message');
        System.assertEquals('UTXO Address ID cannot be null', result.get('message'), 'Should have correct error message');
    }
    
    @IsTest
    static void testSyncAssets_NullAddressId() {
        Test.startTest();
        
        // Call with null address ID
        Map<String, Object> result = UTXOAssetController.syncAssets(null);
        
        Test.stopTest();
        
        // Verify failure
        System.assertEquals(false, result.get('success'), 'Should fail with null address ID');
        System.assertNotEquals(null, result.get('message'), 'Should have error message');
    }
    
    @IsTest
    static void testSyncTransactions_NullAddressId() {
        Test.startTest();
        
        // Call with null address ID
        Map<String, Object> result = UTXOAssetController.syncTransactions(null);
        
        Test.stopTest();
        
        // Verify failure
        System.assertEquals(false, result.get('success'), 'Should fail with null address ID');
        System.assertNotEquals(null, result.get('message'), 'Should have error message');
    }
} 