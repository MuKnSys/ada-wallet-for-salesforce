@IsTest
public with sharing class TransactionControllerTest {
    
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
        
        // Create test UTXO addresses
        List<UTXO_Address__c> utxoAddresses = new List<UTXO_Address__c>();
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test123456789_1',
            Index__c = 0,
            Path__c = 'm/44\'/1815\'/0\'/0/0',
            Type__c = '0',
            Private_Key__c = 'addr_xvk_test_private_key_1',
            Public_Key__c = 'addr_xvk_test_public_key_1',
            Staking_Key_Hash__c = 'test_staking_key_hash_1'
        ));
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test123456789_2',
            Index__c = 1,
            Path__c = 'm/44\'/1815\'/0\'/0/1',
            Type__c = '0',
            Private_Key__c = 'addr_xvk_test_private_key_2',
            Public_Key__c = 'addr_xvk_test_public_key_2',
            Staking_Key_Hash__c = 'test_staking_key_hash_2'
        ));
        insert utxoAddresses;
        
        // Create test UTXO assets
        List<UTXO_Asset__c> utxoAssets = new List<UTXO_Asset__c>();
        // ADA asset
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[0].Id,
            Unit__c = 'ADA',
            Amount__c = 1000000,
            Name__c = 'ADA',
            Asset_Name__c = 'Cardano',
            Decimals__c = 6
        ));
        // Token asset
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[1].Id,
            Unit__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f',
            Amount__c = 5000000,
            Name__c = 'CARGO',
            Asset_Name__c = 'CARGO Token',
            Decimals__c = 6,
            Policy_ID__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a',
            Fingerprint__c = 'asset1234567890abcdef'
        ));
        insert utxoAssets;
    }
    
    @IsTest
    static void testGetWalletUTXOs() {
        // Get test wallet
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
        List<TransactionController.UTXOAddress> utxoAddresses = TransactionController.getWalletUTXOs(wallet.Id);
        Test.stopTest();
        
        // Verify results
        System.assertEquals(2, utxoAddresses.size(), 'Should return 2 UTXO addresses');
        
        // Verify first address (index 0) with ADA
        TransactionController.UTXOAddress firstAddress = utxoAddresses[0];
        System.assertEquals('addr_test123456789_1', firstAddress.address, 'First address should match');
        System.assertEquals(0, firstAddress.addressIndex, 'First address index should be 0');
        System.assertEquals('0', firstAddress.addressType, 'First address type should be receiving');
        System.assertEquals('addr_xvk_test_private_key_1', firstAddress.privateKey, 'First address private key should match');
        System.assertEquals('addr_xvk_test_public_key_1', firstAddress.publicKey, 'First address public key should match');
        System.assertEquals('test_staking_key_hash_1', firstAddress.stakingKeyHash, 'First address staking key hash should match');
        System.assertEquals(1, firstAddress.assets.size(), 'First address should have 1 asset');
        
        TransactionController.UTXOAsset adaAsset = firstAddress.assets[0];
        System.assertEquals('ADA', adaAsset.unit, 'Unit should be ADA');
        System.assertEquals(1000000, adaAsset.amount, 'Amount should be 1000000');
        
        // Verify second address (index 1) with CARGO token
        TransactionController.UTXOAddress secondAddress = utxoAddresses[1];
        System.assertEquals('addr_test123456789_2', secondAddress.address, 'Second address should match');
        System.assertEquals(1, secondAddress.addressIndex, 'Second address index should be 1');
        System.assertEquals('0', secondAddress.addressType, 'Second address type should be receiving');
        System.assertEquals('addr_xvk_test_private_key_2', secondAddress.privateKey, 'Second address private key should match');
        System.assertEquals('addr_xvk_test_public_key_2', secondAddress.publicKey, 'Second address public key should match');
        System.assertEquals('test_staking_key_hash_2', secondAddress.stakingKeyHash, 'Second address staking key hash should match');
        System.assertEquals(1, secondAddress.assets.size(), 'Second address should have 1 asset');
        
        TransactionController.UTXOAsset cargoAsset = secondAddress.assets[0];
        System.assertEquals('CARGO', cargoAsset.assetName, 'Asset name should be CARGO');
        System.assertEquals(5000000, cargoAsset.amount, 'Amount should be 5000000');
    }
    
    @IsTest
    static void testGetWalletUTXOsInvalidWalletId() {
        Test.startTest();
        try {
            TransactionController.getWalletUTXOs('invalid_id');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid Wallet ID'), 'Should throw invalid wallet ID error. Actual message: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testGetWalletUTXOsEmptyWallet() {
        // Create wallet with no UTXOs
        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Empty Wallet Set',
            Seed_Phrase__c = 'empty seed phrase'
        );
        insert walletSet;
        
        Wallet__c emptyWallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Account_Index__c = 0
        );
        insert emptyWallet;
        
        Test.startTest();
        List<TransactionController.UTXOAddress> utxoAddresses = TransactionController.getWalletUTXOs(emptyWallet.Id);
        Test.stopTest();
        
        System.assertEquals(0, utxoAddresses.size(), 'Should return 0 UTXO addresses for empty wallet');
    }
    
    @IsTest
    static void testCalculateMinAdaEmptyMultiAsset() {
        Map<String, Map<String, Integer>> multiAsset = new Map<String, Map<String, Integer>>();
        Map<String, Object> protocolParams = new Map<String, Object>{
            'min_utxo' => 4310,
            'coins_per_utxo_size' => 4310
        };
        
        Test.startTest();
        Integer minAda = TransactionController.calculateMinAda(multiAsset, protocolParams);
        Test.stopTest();
        
        // Base calculation: (160 * 4310) / 8 = 86200
        System.assertEquals(86200, minAda, 'Should calculate correct minimum ADA for empty multi-asset');
    }
    
    @IsTest
    static void testCalculateMinAdaWithMultiAsset() {
        Map<String, Map<String, Integer>> multiAsset = new Map<String, Map<String, Integer>>();
        Map<String, Integer> policy1Assets = new Map<String, Integer>{
            'asset1' => 100,
            'asset2' => 200
        };
        multiAsset.put('policy123456789012345678901234567890123456789012345678901234567890', policy1Assets);
        
        Map<String, Object> protocolParams = new Map<String, Object>{
            'min_utxo' => 4310,
            'coins_per_utxo_size' => 4310
        };
        
        Test.startTest();
        Integer minAda = TransactionController.calculateMinAda(multiAsset, protocolParams);
        Test.stopTest();
        
        // Base: 160 bytes
        // Additional: 2 assets * (8 + 6) = 28 bytes (asset1 = 6 chars, asset2 = 6 chars)
        // Total: 188 bytes
        // Min ADA: (188 * 4310) / 8 = 101285
        System.assertEquals(101285, minAda, 'Should calculate correct minimum ADA for multi-asset UTXO');
    }
    
    @IsTest
    static void testCalculateMinAdaFromAmount() {
        String amountArrayJson = '[{"unit":"lovelace","quantity":"1000000"},{"unit":"f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f","quantity":"5000000"}]';
        String protocolParamsJson = '{"min_utxo":4310,"coins_per_utxo_size":4310}';
        
        Test.startTest();
        Integer minAda = TransactionController.calculateMinAdaFromAmount(amountArrayJson, protocolParamsJson);
        Test.stopTest();
        
        // Should extract policy ID and asset name from the token unit
        // Policy ID: f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a (56 chars)
        // Asset name: 434152474f (CARGO in hex)
        // Additional bytes: 8 + 10 = 18 bytes (asset name is 10 hex chars = 5 bytes)
        // Total: 160 + 18 = 178 bytes
        // Min ADA: (178 * 4310) / 8 = 95897.5, rounded up to 95898
        System.assertEquals(95898, minAda, 'Should calculate correct minimum ADA from amount array');
    }
    
    @IsTest
    static void testCalculateMinAdaWithDefaultParams() {
        Map<String, Map<String, Integer>> multiAsset = new Map<String, Map<String, Integer>>();
        Map<String, Object> protocolParams = new Map<String, Object>(); // Empty params, should use defaults
        
        Test.startTest();
        Integer minAda = TransactionController.calculateMinAda(multiAsset, protocolParams);
        Test.stopTest();
        
        // Should use default values: min_utxo = 4310, coins_per_utxo_size = 4310
        // Base calculation: (160 * 4310) / 8 = 86200
        System.assertEquals(86200, minAda, 'Should use default protocol parameters when not provided');
    }
} 