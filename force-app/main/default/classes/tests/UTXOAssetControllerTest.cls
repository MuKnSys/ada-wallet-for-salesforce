@IsTest
public with sharing class UTXOAssetControllerTest {
    private static final String TEST_PRIVATE_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String TEST_HMAC_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    
    @TestSetup
    static void makeData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);
        AdaWalletsService.setHmacKey(TEST_HMAC_KEY);
        
        // Create test wallet set
        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Test Wallet Set',
            Seed_Phrase__c = DataEncryptor.encryptHmac('test seed phrase for unit testing purposes only')
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
            Path__c = 'm/44\'/1815\'/0\'/0/0',
            Type__c = '0',
            Public_Key__c = 'test_public_key',
            Payment_Key_Hash__c = 'test_payment_key_hash',
            Private_Key__c = 'test_private_key'
        );
        insert utxoAddress;
        
        // Create test UTXO assets
        List<UTXO_Asset__c> assets = new List<UTXO_Asset__c>();
        assets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddress.Id,
            Asset__c = 'ADA',
            Amount__c = 1000000,
            Name__c = 'ADA',
            Decimals__c = 6
        ));
        assets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddress.Id,
            Asset__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f',
            Amount__c = 5000000,
            Name__c = 'CARGO',
            Decimals__c = 6,
            Policy_ID__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a',
            Fingerprint__c = 'asset1234567890abcdef'
        ));
        insert assets;
    }
    
    @IsTest
    static void testSetAddressesUsed() {
        UTXO_Address__c utxoAddress = [SELECT Id, Is_Used__c FROM UTXO_Address__c LIMIT 1];
        
        Test.startTest();
            UTXOAssetController.setAddressesUsed(new List<Id>{utxoAddress.Id});
        Test.stopTest();
        
        UTXO_Address__c updatedAddress = [SELECT Id, Is_Used__c FROM UTXO_Address__c WHERE Id = :utxoAddress.Id];
        Assert.isTrue(updatedAddress.Is_Used__c, 'Address should be marked as used');
    }
    
    @IsTest
    static void testSetAddressesUsedMultiple() {
        List<UTXO_Address__c> utxoAddresses = [SELECT Id FROM UTXO_Address__c];
        
        Test.startTest();
            UTXOAssetController.setAddressesUsed(new List<Id>{utxoAddresses[0].Id});
        Test.stopTest();
        
        List<UTXO_Address__c> updatedAddresses = [SELECT Id, Is_Used__c FROM UTXO_Address__c WHERE Id IN :utxoAddresses];
        Assert.isTrue(updatedAddresses[0].Is_Used__c, 'First address should be marked as used');
    }
    
    @IsTest
    static void testSetAddressesUsedEmptyList() {
        Test.startTest();
            UTXOAssetController.setAddressesUsed(new List<Id>());
        Test.stopTest();
        
        Assert.isTrue(true, 'Should not throw exception for empty list');
    }
    
    @IsTest
    static void testSetAddressesUsedInvalidId() {
        Test.startTest();
            try {
                UTXOAssetController.setAddressesUsed(new List<Id>{'001000000000000'});
                Assert.fail('Should throw exception for invalid ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void testSyncAssetsAndTransactions() {
        UTXO_Address__c utxoAddress = [SELECT Id FROM UTXO_Address__c LIMIT 1];
        
        Test.startTest();
            Map<String, Object> result = UTXOAssetController.syncAssetsAndTransactions(utxoAddress.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return sync results');
    }
    
    @IsTest
    static void testSyncAssetsAndTransactionsInvalidId() {
        Test.startTest();
            Map<String, Object> result = UTXOAssetController.syncAssetsAndTransactions('001000000000000');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return result map even for invalid ID');
    }
    
    @IsTest
    static void testSyncAssetsAndTransactionsNullId() {
        Test.startTest();
            Map<String, Object> result = UTXOAssetController.syncAssetsAndTransactions(null);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return result map even for null ID');
    }
    
    @IsTest
    static void testSetAddressesUsedWithNullId() {
        Test.startTest();
            try {
                UTXOAssetController.setAddressesUsed(new List<Id>{null});
                Assert.fail('Should throw exception for null ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void testSetAddressesUsedWithMixedIds() {
        UTXO_Address__c utxoAddress = [SELECT Id FROM UTXO_Address__c LIMIT 1];
        
        Test.startTest();
            try {
                UTXOAssetController.setAddressesUsed(new List<Id>{utxoAddress.Id, '001000000000000'});
                Assert.fail('Should throw exception for mixed valid and invalid IDs');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void testSyncAssetsAndTransactionsWithNoAssets() {
        // Create a new UTXO address without assets
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        UTXO_Address__c newUtxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test_no_assets',
            Index__c = 1,
            Path__c = 'm/44\'/1815\'/0\'/0/1',
            Type__c = '0',
            Public_Key__c = 'test_public_key_2',
            Payment_Key_Hash__c = 'test_payment_key_hash_2',
            Private_Key__c = 'test_private_key_2'
        );
        insert newUtxoAddress;
        
        Test.startTest();
            Map<String, Object> result = UTXOAssetController.syncAssetsAndTransactions(newUtxoAddress.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return sync results even for address without assets');
    }
    
    @IsTest
    static void testSetAddressesUsedBulk() {
        // Create multiple UTXO addresses
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        List<UTXO_Address__c> newAddresses = new List<UTXO_Address__c>();
        
        for (Integer i = 0; i < 5; i++) {
            newAddresses.add(new UTXO_Address__c(
                Wallet__c = wallet.Id,
                Address__c = 'addr_test_bulk_' + i,
                Index__c = i + 1,
                Path__c = 'm/44\'/1815\'/0\'/0/' + (i + 1),
                Type__c = '0',
                Public_Key__c = 'test_public_key_' + i,
                Payment_Key_Hash__c = 'test_payment_key_hash_' + i,
                Private_Key__c = 'test_private_key_' + i
            ));
        }
        insert newAddresses;
        
        List<Id> addressIds = new List<Id>();
        for (UTXO_Address__c addr : newAddresses) {
            addressIds.add(addr.Id);
        }
        
        Test.startTest();
            UTXOAssetController.setAddressesUsed(addressIds);
        Test.stopTest();
        
        List<UTXO_Address__c> updatedAddresses = [SELECT Id, Is_Used__c FROM UTXO_Address__c WHERE Id IN :addressIds];
        for (UTXO_Address__c addr : updatedAddresses) {
            Assert.isTrue(addr.Is_Used__c, 'All addresses should be marked as used');
        }
    }
} 