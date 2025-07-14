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