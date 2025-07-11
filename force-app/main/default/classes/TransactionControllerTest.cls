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
            Payment_Key_Hash__c = 'test_payment_key_hash_1'
        ));
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test123456789_2',
            Index__c = 1,
            Path__c = 'm/44\'/1815\'/0\'/0/1',
            Type__c = '0',
            Private_Key__c = 'addr_xvk_test_private_key_2',
            Public_Key__c = 'addr_xvk_test_public_key_2',
            Payment_Key_Hash__c = 'test_payment_key_hash_2'
        ));
        insert utxoAddresses;
        
        // Create test UTXO assets
        List<UTXO_Asset__c> utxoAssets = new List<UTXO_Asset__c>();
        // ADA asset
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[0].Id,
            Asset__c = 'ADA',
            Amount__c = 1000000,
            Name__c = 'ADA',
            
            Decimals__c = 6
        ));
        // Token asset
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[1].Id,
            Asset__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f',
            Amount__c = 5000000,
            Name__c = 'CARGO',
            
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
        System.assertEquals('test_payment_key_hash_1', firstAddress.paymentKeyHash, 'First address payment key hash should match');
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
        System.assertEquals('test_payment_key_hash_2', secondAddress.paymentKeyHash, 'Second address payment key hash should match');
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
            System.assert(e.getMessage().contains('Invalid Wallet ID') || e.getMessage().contains('Error retrieving wallet UTXOs'), 'Should throw invalid wallet ID error. Actual message: ' + e.getMessage());
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
    static void testCreateOutboundTransaction() {
        // Get test wallet
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
        String transactionId = TransactionController.createOutboundTransaction(
            wallet.Id,
            'addr_test123456789_recipient',
            '100.5',
            'ADA',
            'Test memo'
        );
        Test.stopTest();
        
        // Verify the transaction was created
        System.assertNotEquals(null, transactionId, 'Transaction ID should not be null');
        
        // Query the created transaction
        Outbound_Transaction__c createdTx = [
            SELECT Id, Wallet__c, To_Address__c, 
                   Approved__c, Transaction_Status__c, Memo__c
            FROM Outbound_Transaction__c 
            WHERE Id = :transactionId
        ];
        
        System.assertEquals(wallet.Id, createdTx.Wallet__c, 'Wallet ID should match');
        System.assertEquals('addr_test123456789_recipient', createdTx.To_Address__c, 'To Address should match');
        System.assertEquals('Not Approved', createdTx.Approved__c, 'Approved status should be Not Approved');
        System.assertEquals('Ready to Sign', createdTx.Transaction_Status__c, 'Transaction status should be Ready to Sign');
        System.assertEquals('Test memo', createdTx.Memo__c, 'Memo should match');
        
        // Verify the transaction line was created
        List<Outbound_Transaction_Line__c> lines = [
            SELECT Id, Amount__c, Asset__c 
            FROM Outbound_Transaction_Line__c 
            WHERE Outbound_Transaction__c = :transactionId
        ];
        System.assertEquals(1, lines.size(), 'Should create 1 transaction line');
        System.assertEquals(100.5, lines[0].Amount__c, 'Amount should match');
        System.assertEquals('ADA', lines[0].Asset__c, 'Asset should match');
    }
    
    @IsTest
    static void testCreateOutboundTransactionInvalidParams() {
        // Test with invalid wallet ID
        Test.startTest();
        try {
            TransactionController.createOutboundTransaction(
                'invalid_id',
                'addr_test123456789_recipient',
                '100.5',
                'ADA',
                'Test memo'
            );
            System.assert(false, 'Should have thrown an exception for invalid wallet ID');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid Wallet ID') || e.getMessage().contains('Error creating outbound transaction'), 'Should throw invalid wallet ID error. Actual message: ' + e.getMessage());
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testCreateOutboundTransactionMissingParams() {
        // Test with missing parameters (null values)
        Test.startTest();
        try {
            TransactionController.createOutboundTransaction(
                null,
                'addr_test123456789_recipient',
                '100.5',
                'ADA',
                'Test memo'
            );
            System.assert(false, 'Should have thrown an exception for missing parameters');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid Wallet ID') || e.getMessage().contains('Error creating outbound transaction'), 'Should throw missing parameter error. Actual message: ' + e.getMessage());
        }
        Test.stopTest();
    }
} 