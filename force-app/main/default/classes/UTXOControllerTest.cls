@isTest
private class UTXOControllerTest {
    private static final String TEST_PRIVATE_KEY = '0123456789abcdef0123456789abcdef';
    private static final String TEST_SEED_PHRASE = 'test seed phrase';
    
    @testSetup
    private static void testData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);

        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Test Wallet',
            Seed_Phrase__c = DataEncryptor.encrypt(TEST_SEED_PHRASE)
        );
        insert walletSet;
        
        Wallet__c wallet = new Wallet__c(
            Name = 'Test Wallet',
            Wallet_Set__c = walletSet.Id
        );
        insert wallet;
    }
    
    @isTest
    private static void testGetWallet() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Wallet__c result = UTXOController.getWallet(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(wallet.Id, result.Id, 'Wallet ID should match');
    }
    
    @isTest
    static void testGetEncryptedSeedPhrase() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        String result = UTXOController.getEncryptedSeedPhrase(walletSet.Id);
        Test.stopTest();

        Assert.areEqual(TEST_SEED_PHRASE, result, 'Decrypted seed phrase should match mock value');
    }
    
    @isTest
    private static void testCreateUTXOAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        List<UTXOController.UTXOAddress> receivingAddresses = new List<UTXOController.UTXOAddress>();
        UTXOController.UTXOAddress receivingAddr = new UTXOController.UTXOAddress();
        receivingAddr.index = 0;
        receivingAddr.address = 'receivingAddress1';
        receivingAddr.publicKey = 'publicKey1';
        receivingAddr.paymentKeyHash = 'paymentKeyHash1';
        receivingAddr.path = 'path1';
        receivingAddr.privateKey = 'privateKey1';
        receivingAddresses.add(receivingAddr);
        
        List<UTXOController.UTXOAddress> changeAddresses = new List<UTXOController.UTXOAddress>();
        UTXOController.UTXOAddress changeAddr = new UTXOController.UTXOAddress();
        changeAddr.index = 0;
        changeAddr.address = 'changeAddress1';
        changeAddr.publicKey = 'publicKey2';
        changeAddr.paymentKeyHash = 'paymentKeyHash2';
        changeAddr.path = 'path2';
        changeAddr.privateKey = 'privateKey2';
        changeAddresses.add(changeAddr);
        
        Test.startTest();
            UTXOController.createUTXOAddresses(wallet.Id, receivingAddresses, changeAddresses);
        Test.stopTest();
        
        List<UTXO_Address__c> createdAddresses = [SELECT Id, Address__c, Index__c, Public_Key__c, Payment_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                                FROM UTXO_Address__c 
                                                WHERE Wallet__c = :wallet.Id];
        
        Assert.areEqual(2, createdAddresses.size(), 'Should create 2 addresses');
        
        for(UTXO_Address__c addr : createdAddresses) {
            if(addr.Type__c == '0') {
                Assert.areEqual('receivingAddress1', addr.Address__c, 'Address should match');
                Assert.areEqual(0, addr.Index__c, 'Index should match');
                Assert.areEqual('publicKey1', addr.Public_Key__c, 'Public key should match');
                Assert.areEqual('paymentKeyHash1', addr.Payment_Key_Hash__c, 'Payment key hash should match');
                Assert.areEqual('path1', addr.Path__c, 'Path should match');
                Assert.areEqual('privateKey1', addr.Private_Key__c, 'Private key should match');
            } else {
                Assert.areEqual('changeAddress1', addr.Address__c, 'Address should match');
                Assert.areEqual(0, addr.Index__c, 'Index should match');
                Assert.areEqual('publicKey2', addr.Public_Key__c, 'Public key should match');
                Assert.areEqual('paymentKeyHash2', addr.Payment_Key_Hash__c, 'Payment key hash should match');
                Assert.areEqual('path2', addr.Path__c, 'Path should match');
                Assert.areEqual('privateKey2', addr.Private_Key__c, 'Private key should match');
            }
        }
    }
    
    @isTest
    private static void testGetUTXOAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddresses(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return 1 address');
        Assert.areEqual('testAddress', result[0].Address__c, 'Address should match');
        Assert.areEqual(0, result[0].Index__c, 'Index should match');
        Assert.areEqual('testPublicKey', result[0].Public_Key__c, 'Public key should match');
        Assert.areEqual('testPaymentKeyHash', result[0].Payment_Key_Hash__c, 'Payment key hash should match');
        Assert.areEqual('testPath', result[0].Path__c, 'Path should match');
        Assert.areEqual('testPrivateKey', result[0].Private_Key__c, 'Private key should match');
        Assert.areEqual('0', result[0].Type__c, 'Type should match');
    }
    
    @isTest
    private static void testGetUserPermissions() {
        Test.startTest();
            List<String> result = UTXOController.getUserPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Permissions should not be null');
    }
    
    @isTest
    private static void testGetNextUTXOIndex() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            Integer result = UTXOController.getNextUTXOIndex(wallet.Id, '0');
        Test.stopTest();
        
        Assert.areEqual(1, result, 'Next index should match');
    }
    
    @isTest
    private static void testAddAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        // Test receiving address
        UTXOController.UTXOAddress receivingAddress = new UTXOController.UTXOAddress();
        receivingAddress.index = 0;
        receivingAddress.address = 'receivingAddress';
        receivingAddress.publicKey = 'publicKey';
        receivingAddress.paymentKeyHash = 'paymentKeyHash';
        receivingAddress.path = 'path';
        receivingAddress.privateKey = 'privateKey';
        
        Test.startTest();
            String receivingId = UTXOController.addReceivingUTXOAddress(wallet.Id, receivingAddress);
        Test.stopTest();
        
        UTXO_Address__c createdReceiving = [SELECT Id, Address__c, Index__c, Public_Key__c, Payment_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                          FROM UTXO_Address__c WHERE Id = :receivingId];
        
        Assert.areEqual('receivingAddress', createdReceiving.Address__c, 'Address should match');
        Assert.areEqual(0, createdReceiving.Index__c, 'Index should match');
        Assert.areEqual('publicKey', createdReceiving.Public_Key__c, 'Public key should match');
        Assert.areEqual('paymentKeyHash', createdReceiving.Payment_Key_Hash__c, 'Payment key hash should match');
        Assert.areEqual('path', createdReceiving.Path__c, 'Path should match');
        Assert.areEqual('privateKey', createdReceiving.Private_Key__c, 'Private key should match');
        Assert.areEqual('0', createdReceiving.Type__c, 'Type should match');
        
        // Test change address
        UTXOController.UTXOAddress changeAddress = new UTXOController.UTXOAddress();
        changeAddress.index = 0;
        changeAddress.address = 'changeAddress';
        changeAddress.publicKey = 'publicKey2';
        changeAddress.paymentKeyHash = 'paymentKeyHash2';
        changeAddress.path = 'path2';
        changeAddress.privateKey = 'privateKey2';
        
        Test.startTest();
            String changeId = UTXOController.addChangeUTXOAddress(wallet.Id, changeAddress);
        Test.stopTest();
        
        UTXO_Address__c createdChange = [SELECT Id, Address__c, Index__c, Public_Key__c, Payment_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                       FROM UTXO_Address__c WHERE Id = :changeId];
        
        Assert.areEqual('changeAddress', createdChange.Address__c, 'Address should match');
        Assert.areEqual(0, createdChange.Index__c, 'Index should match');
        Assert.areEqual('publicKey2', createdChange.Public_Key__c, 'Public key should match');
        Assert.areEqual('paymentKeyHash2', createdChange.Payment_Key_Hash__c, 'Payment key hash should match');
        Assert.areEqual('path2', createdChange.Path__c, 'Path should match');
        Assert.areEqual('privateKey2', createdChange.Private_Key__c, 'Private key should match');
        Assert.areEqual('1', createdChange.Type__c, 'Type should match');
    }

    @isTest
    private static void testGetUTXOAddressWithDecryptedKey() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = DataEncryptor.encrypt('testPrivateKey'),
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            UTXOAddressSelector.UTXOAddressWithDecryptedKey result = UTXOController.getUTXOAddressWithDecryptedKeyById(utxoAddress.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.utxoAddress, 'UTXO address should not be null');
        Assert.isNotNull(result.decryptedPrivateKey, 'Decrypted private key should not be null');
        Assert.areEqual('testPrivateKey', result.decryptedPrivateKey, 'Decrypted private key should match original');
        Assert.areEqual(utxoAddress.Id, result.utxoAddress.Id, 'UTXO address ID should match');
    }
    
    @isTest
    private static void testGetUTXOAddressesWithDecryptedKeys() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        List<UTXO_Address__c> utxoAddresses = new List<UTXO_Address__c>();
        for(Integer i = 0; i < 3; i++) {
            UTXO_Address__c utxoAddress = new UTXO_Address__c(
                Wallet__c = wallet.Id,
                Address__c = 'testAddress' + i,
                Index__c = i,
                Public_Key__c = 'testPublicKey' + i,
                Payment_Key_Hash__c = 'testPaymentKeyHash' + i,
                Path__c = 'testPath' + i,
                Private_Key__c = DataEncryptor.encrypt('testPrivateKey' + i),
                Type__c = '0'
            );
            utxoAddresses.add(utxoAddress);
        }
        insert utxoAddresses;
        
        Test.startTest();
            List<UTXOAddressSelector.UTXOAddressWithDecryptedKey> results = UTXOController.getUTXOAddressesWithDecryptedKeys(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(3, results.size(), 'Should return 3 addresses with decrypted keys');
        
        for(Integer i = 0; i < results.size(); i++) {
            UTXOAddressSelector.UTXOAddressWithDecryptedKey result = results[i];
            Assert.isNotNull(result, 'Result should not be null');
            Assert.isNotNull(result.utxoAddress, 'UTXO address should not be null');
            Assert.isNotNull(result.decryptedPrivateKey, 'Decrypted private key should not be null');
            Assert.areEqual('testPrivateKey' + i, result.decryptedPrivateKey, 'Decrypted private key should match original');
            Assert.areEqual(utxoAddresses[i].Id, result.utxoAddress.Id, 'UTXO address ID should match');
        }
    }
    
    @isTest
    private static void testGetUTXOAddressesWithAssets() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        // Create UTXO addresses - one with assets, one without
        UTXO_Address__c addressWithAssets = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addressWithAssets',
            Index__c = 0,
            Public_Key__c = 'testPublicKey1',
            Payment_Key_Hash__c = 'testPaymentKeyHash1',
            Path__c = 'testPath1',
            Private_Key__c = 'testPrivateKey1',
            Type__c = '0'
        );
        
        UTXO_Address__c addressWithoutAssets = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addressWithoutAssets',
            Index__c = 1,
            Public_Key__c = 'testPublicKey2',
            Payment_Key_Hash__c = 'testPaymentKeyHash2',
            Path__c = 'testPath2',
            Private_Key__c = 'testPrivateKey2',
            Type__c = '0'
        );
        
        insert new List<UTXO_Address__c>{addressWithAssets, addressWithoutAssets};
        
        // Create an asset for the first address only
        UTXO_Asset__c asset = new UTXO_Asset__c(
            UTXO_Address__c = addressWithAssets.Id,
            Policy_ID__c = 'testPolicyId',
            Amount__c = 1000000,
            Asset__c = 'lovelace',
            Name__c = 'ADA'
        );
        insert asset;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddressesWithAssets(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return only 1 address with assets');
        Assert.areEqual('addressWithAssets', result[0].Address__c, 'Should return address with assets');
        Assert.areEqual(0, result[0].Index__c, 'Index should match');
        Assert.areEqual('testPublicKey1', result[0].Public_Key__c, 'Public key should match');
        Assert.areEqual('testPaymentKeyHash1', result[0].Payment_Key_Hash__c, 'Payment key hash should match');
        Assert.areEqual('testPath1', result[0].Path__c, 'Path should match');
        Assert.areEqual('testPrivateKey1', result[0].Private_Key__c, 'Private key should match');
        Assert.areEqual('0', result[0].Type__c, 'Type should match');
    }
    
    @isTest
    private static void testGetUTXOAddressesWithAssetsEmpty() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c addressWithoutAssets = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addressWithoutAssets',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert addressWithoutAssets;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddressesWithAssets(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(0, result.size(), 'Should return empty list when no addresses have assets');
    }
    
    @isTest
    private static void testGetAllWalletAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        List<UTXO_Address__c> addresses = new List<UTXO_Address__c>();
        for(Integer i = 0; i < 3; i++) {
            addresses.add(new UTXO_Address__c(
                Wallet__c = wallet.Id,
                Address__c = 'testAddress' + i,
                Index__c = i,
                Public_Key__c = 'testPublicKey' + i,
                Payment_Key_Hash__c = 'testPaymentKeyHash' + i,
                Path__c = 'testPath' + i,
                Private_Key__c = 'testPrivateKey' + i,
                Type__c = i == 0 ? '0' : '1'
            ));
        }
        insert addresses;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getAllWalletAddresses(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(3, result.size(), 'Should return all wallet addresses');
        Assert.areEqual('0', result[0].Type__c, 'First address should be receiving type');
        Assert.areEqual('1', result[1].Type__c, 'Second address should be change type');
        Assert.areEqual('1', result[2].Type__c, 'Third address should be change type');
    }
    
    @isTest
    private static void testGetFirstUnusedReceivingAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c unusedAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'unusedAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert unusedAddress;
        
        Test.startTest();
            String result = UTXOController.getFirstUnusedReceivingAddress(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual('unusedAddress', result, 'Should return first unused receiving address');
    }
    
    @isTest
    private static void testGetAllUtxoAssetsForWallet() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c address = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert address;
        
        UTXO_Asset__c asset = new UTXO_Asset__c(
            UTXO_Address__c = address.Id,
            Policy_ID__c = 'testPolicyId',
            Amount__c = 1000000,
            Asset__c = 'lovelace',
            Name__c = 'ADA'
        );
        insert asset;
        
        Test.startTest();
            List<UTXO_Asset__c> result = UTXOController.getAllUtxoAssetsForWallet(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return 1 asset');
        Assert.areEqual('lovelace', result[0].Asset__c, 'Asset should match');
        Assert.areEqual(1000000, result[0].Amount__c, 'Amount should match');
        Assert.areEqual('ADA', result[0].Name__c, 'Name should match');
    }
    
    @isTest
    private static void testCreateOutboundTransaction() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            String result = UTXOController.createOutboundTransaction(wallet.Id, 'addr1qtest', '1000000', 'ADA');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return transaction ID');
        
        Outbound_Transaction__c tx = [SELECT Id, To_Address__c, Wallet__c, Transaction_Status__c FROM Outbound_Transaction__c WHERE Id = :result];
        Assert.areEqual('addr1qtest', tx.To_Address__c, 'To address should match');
        Assert.areEqual(wallet.Id, tx.Wallet__c, 'Wallet should match');
        Assert.areEqual('Ready to Sign', tx.Transaction_Status__c, 'Status should match');
        
        List<Outbound_Transaction_Line__c> lines = [SELECT Id, Amount__c, Asset__c FROM Outbound_Transaction_Line__c WHERE Outbound_Transaction__c = :result];
        Assert.areEqual(1, lines.size(), 'Should create 1 transaction line');
        Assert.areEqual(1000000, lines[0].Amount__c, 'Amount should match');
        Assert.areEqual('ADA', lines[0].Asset__c, 'Asset should match');
    }
    
    @isTest
    private static void testCreateMultiAssetOutboundTransaction() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        List<Map<String, Object>> assets = new List<Map<String, Object>>();
        assets.add(new Map<String, Object>{'amount' => '1000000', 'asset' => 'ADA'});
        assets.add(new Map<String, Object>{'amount' => '100', 'asset' => 'USDA'});
        
        Test.startTest();
            String result = UTXOController.createMultiAssetOutboundTransaction(wallet.Id, 'addr1qtest', assets);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return transaction ID');
        
        List<Outbound_Transaction_Line__c> lines = [SELECT Id, Amount__c, Asset__c FROM Outbound_Transaction_Line__c WHERE Outbound_Transaction__c = :result];
        Assert.areEqual(2, lines.size(), 'Should create 2 transaction lines');
    }
    
    @isTest
    private static void testGetTransactionLinesForOutbound() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Outbound_Transaction__c tx = new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr1qtest',
            Transaction_Status__c = 'Ready to Sign'
        );
        insert tx;
        
        Outbound_Transaction_Line__c line = new Outbound_Transaction_Line__c(
            Outbound_Transaction__c = tx.Id,
            Amount__c = 1000000,
            Asset__c = 'ADA'
        );
        insert line;
        
        Test.startTest();
            List<Outbound_Transaction_Line__c> result = UTXOController.getTransactionLinesForOutbound(tx.Id);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return 1 transaction line');
        Assert.areEqual(1000000, result[0].Amount__c, 'Amount should match');
        Assert.areEqual('ADA', result[0].Asset__c, 'Asset should match');
    }
    
    @isTest
    private static void testGetOutboundTransaction() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Outbound_Transaction__c tx = new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr1qtest',
            Transaction_Status__c = 'Ready to Sign'
        );
        insert tx;
        
        Test.startTest();
            Outbound_Transaction__c result = UTXOController.getOutboundTransaction(tx.Id);
        Test.stopTest();
        
        Assert.areEqual(tx.Id, result.Id, 'Transaction ID should match');
        Assert.areEqual('addr1qtest', result.To_Address__c, 'To address should match');
        Assert.areEqual(wallet.Id, result.Wallet__c, 'Wallet should match');
    }
    
    @isTest
    private static void testUpdateOutboundTransactionWithSignedCbor() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Outbound_Transaction__c tx = new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr1qtest',
            Transaction_Status__c = 'Ready to Sign'
        );
        insert tx;
        
        String signedCbor = 'testSignedCborData';
        
        Test.startTest();
            UTXOController.updateOutboundTransactionWithSignedCbor(tx.Id, signedCbor);
        Test.stopTest();
        
        Outbound_Transaction__c updatedTx = [SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c FROM Outbound_Transaction__c WHERE Id = :tx.Id];
        Assert.areEqual(signedCbor, updatedTx.Signed_Transaction_CBOR__c, 'Signed CBOR should match');
        Assert.areEqual('Ready to Send', updatedTx.Transaction_Status__c, 'Status should be updated');
    }
    
    @isTest
    private static void testValidationErrors() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        // Test invalid wallet ID
        try {
            UTXOController.getWallet('invalid-id');
            Assert.fail('Should throw exception for invalid wallet ID');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid Wallet ID'), 'Should contain validation error message');
        }
        
        // Test invalid address data
        UTXOController.UTXOAddress invalidAddress = new UTXOController.UTXOAddress();
        invalidAddress.index = 0;
        // Missing required fields
        
        try {
            UTXOController.addReceivingUTXOAddress(wallet.Id, invalidAddress);
            Assert.fail('Should throw exception for invalid address data');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid receiving address data'), 'Should contain validation error message');
        }
        
        // Test invalid transaction ID
        try {
            UTXOController.getOutboundTransaction('invalid-id');
            Assert.fail('Should throw exception for invalid transaction ID');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Invalid Outbound Transaction ID'), 'Should contain validation error message');
        }
    }
}