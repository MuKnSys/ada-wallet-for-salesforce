@isTest
private class UTXOControllerTest {
    private static final String ASSERT_MESSAGE_WALLET_ID = 'Wallet ID should match';
    private static final String ASSERT_MESSAGE_ADDRESS = 'Address should match';
    private static final String ASSERT_MESSAGE_INDEX = 'Index should match';
    private static final String ASSERT_MESSAGE_PUBLIC_KEY = 'Public key should match';
    private static final String ASSERT_MESSAGE_STAKING_KEY_HASH = 'Staking key hash should match';
    private static final String ASSERT_MESSAGE_PATH = 'Path should match';
    private static final String ASSERT_MESSAGE_TYPE = 'Type should match';
    private static final String ASSERT_MESSAGE_NEXT_INDEX = 'Next index should match';
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
    private static void getWalletShouldReturnWallet() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Wallet__c result = UTXOController.getWallet(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(wallet.Id, result.Id, ASSERT_MESSAGE_WALLET_ID);
    }
    
    @isTest
    static void shouldGetDecryptedSeedPhrase() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        String result = UTXOController.getDecryptedSeedPhrase(walletSet.Id);
        Test.stopTest();

        Assert.areEqual(TEST_SEED_PHRASE, result, 'Decrypted seed phrase should match mock value');
    }
    
    @isTest
    private static void createUTXOAddressesShouldCreateAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        List<UTXOController.UTXOAddress> receivingAddresses = new List<UTXOController.UTXOAddress>();
        UTXOController.UTXOAddress receivingAddr = new UTXOController.UTXOAddress();
        receivingAddr.index = 0;
        receivingAddr.address = 'receivingAddress1';
        receivingAddr.publicKey = 'publicKey1';
        receivingAddr.stakingKeyHash = 'stakingKeyHash1';
        receivingAddr.path = 'path1';
        receivingAddr.privateKey = 'privateKey1';
        receivingAddresses.add(receivingAddr);
        
        List<UTXOController.UTXOAddress> changeAddresses = new List<UTXOController.UTXOAddress>();
        UTXOController.UTXOAddress changeAddr = new UTXOController.UTXOAddress();
        changeAddr.index = 0;
        changeAddr.address = 'changeAddress1';
        changeAddr.publicKey = 'publicKey2';
        changeAddr.stakingKeyHash = 'stakingKeyHash2';
        changeAddr.path = 'path2';
        changeAddr.privateKey = 'privateKey2';
        changeAddresses.add(changeAddr);
        
        Test.startTest();
            UTXOController.createUTXOAddresses(wallet.Id, receivingAddresses, changeAddresses);
        Test.stopTest();
        
        List<UTXO_Address__c> createdAddresses = [SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                                FROM UTXO_Address__c 
                                                WHERE Wallet__c = :wallet.Id];
        
        Assert.areEqual(2, createdAddresses.size(), 'Should create 2 addresses');
        
        for(UTXO_Address__c addr : createdAddresses) {
            if(addr.Type__c == '0') {
                Assert.areEqual('receivingAddress1', addr.Address__c, ASSERT_MESSAGE_ADDRESS);
                Assert.areEqual(0, addr.Index__c, ASSERT_MESSAGE_INDEX);
                Assert.areEqual('publicKey1', addr.Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
                Assert.areEqual('stakingKeyHash1', addr.Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
                Assert.areEqual('path1', addr.Path__c, ASSERT_MESSAGE_PATH);
                Assert.areEqual('privateKey1', addr.Private_Key__c, 'Private key should match');
            } else {
                Assert.areEqual('changeAddress1', addr.Address__c, ASSERT_MESSAGE_ADDRESS);
                Assert.areEqual(0, addr.Index__c, ASSERT_MESSAGE_INDEX);
                Assert.areEqual('publicKey2', addr.Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
                Assert.areEqual('stakingKeyHash2', addr.Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
                Assert.areEqual('path2', addr.Path__c, ASSERT_MESSAGE_PATH);
                Assert.areEqual('privateKey2', addr.Private_Key__c, 'Private key should match');
            }
        }
    }
    
    @isTest
    private static void getUTXOAddressesShouldReturnAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Staking_Key_Hash__c = 'testStakingKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddresses(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return 1 address');
        Assert.areEqual('testAddress', result[0].Address__c, ASSERT_MESSAGE_ADDRESS);
        Assert.areEqual(0, result[0].Index__c, ASSERT_MESSAGE_INDEX);
        Assert.areEqual('testPublicKey', result[0].Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
        Assert.areEqual('testStakingKeyHash', result[0].Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
        Assert.areEqual('testPath', result[0].Path__c, ASSERT_MESSAGE_PATH);
        Assert.areEqual('testPrivateKey', result[0].Private_Key__c, 'Private key should match');
        Assert.areEqual('0', result[0].Type__c, ASSERT_MESSAGE_TYPE);
    }
    
    @isTest
    private static void getUserPermissionsShouldReturnPermissions() {
        Test.startTest();
            List<String> result = UTXOController.getUserPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Permissions should not be null');
    }
    
    @isTest
    private static void getNextUTXOIndexShouldReturnNextIndex() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Staking_Key_Hash__c = 'testStakingKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            Integer result = UTXOController.getNextUTXOIndex(wallet.Id, '0');
        Test.stopTest();
        
        Assert.areEqual(1, result, ASSERT_MESSAGE_NEXT_INDEX);
    }
    
    @isTest
    private static void addReceivingUTXOAddressShouldCreateAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        UTXOController.UTXOAddress receivingAddress = new UTXOController.UTXOAddress();
        receivingAddress.index = 0;
        receivingAddress.address = 'receivingAddress';
        receivingAddress.publicKey = 'publicKey';
        receivingAddress.stakingKeyHash = 'stakingKeyHash';
        receivingAddress.path = 'path';
        receivingAddress.privateKey = 'privateKey';
        
        Test.startTest();
            UTXOController.addReceivingUTXOAddress(wallet.Id, receivingAddress);
        Test.stopTest();
        
        List<UTXO_Address__c> createdAddresses = [SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                                FROM UTXO_Address__c 
                                                WHERE Wallet__c = :wallet.Id];
        
        Assert.areEqual(1, createdAddresses.size(), 'Should create 1 address');
        Assert.areEqual('receivingAddress', createdAddresses[0].Address__c, ASSERT_MESSAGE_ADDRESS);
        Assert.areEqual(0, createdAddresses[0].Index__c, ASSERT_MESSAGE_INDEX);
        Assert.areEqual('publicKey', createdAddresses[0].Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
        Assert.areEqual('stakingKeyHash', createdAddresses[0].Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
        Assert.areEqual('path', createdAddresses[0].Path__c, ASSERT_MESSAGE_PATH);
        Assert.areEqual('privateKey', createdAddresses[0].Private_Key__c, 'Private key should match');
        Assert.areEqual('0', createdAddresses[0].Type__c, ASSERT_MESSAGE_TYPE);
    }
    
    @isTest
    private static void addChangeUTXOAddressShouldCreateAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXOController.UTXOAddress changeAddress = new UTXOController.UTXOAddress();
        changeAddress.index = 0;
        changeAddress.address = 'changeAddress';
        changeAddress.publicKey = 'publicKey';
        changeAddress.stakingKeyHash = 'stakingKeyHash';
        changeAddress.path = 'path';
        changeAddress.privateKey = 'privateKey';
        
        Test.startTest();
            UTXOController.addChangeUTXOAddress(wallet.Id, changeAddress);
        Test.stopTest();
        
        List<UTXO_Address__c> createdAddresses = [SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                                FROM UTXO_Address__c 
                                                WHERE Wallet__c = :wallet.Id];
        
        Assert.areEqual(1, createdAddresses.size(), 'Should create 1 address');
        Assert.areEqual('changeAddress', createdAddresses[0].Address__c, ASSERT_MESSAGE_ADDRESS);
        Assert.areEqual(0, createdAddresses[0].Index__c, ASSERT_MESSAGE_INDEX);
        Assert.areEqual('publicKey', createdAddresses[0].Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
        Assert.areEqual('stakingKeyHash', createdAddresses[0].Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
        Assert.areEqual('path', createdAddresses[0].Path__c, ASSERT_MESSAGE_PATH);
        Assert.areEqual('privateKey', createdAddresses[0].Private_Key__c, 'Private key should match');
        Assert.areEqual('1', createdAddresses[0].Type__c, ASSERT_MESSAGE_TYPE);
    }

    @isTest
    private static void shouldEncryptAndDecryptUTXOPrivateKey() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        // Create a UTXO address with a private key
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Staking_Key_Hash__c = 'testStakingKeyHash',
            Path__c = 'testPath',
            Private_Key__c = DataEncryptor.encrypt('testPrivateKey'), // Encrypt the private key
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
    private static void shouldGetMultipleUTXOAddressesWithDecryptedKeys() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        // Create multiple UTXO addresses with private keys
        List<UTXO_Address__c> utxoAddresses = new List<UTXO_Address__c>();
        for(Integer i = 0; i < 3; i++) {
            UTXO_Address__c utxoAddress = new UTXO_Address__c(
                Wallet__c = wallet.Id,
                Address__c = 'testAddress' + i,
                Index__c = i,
                Public_Key__c = 'testPublicKey' + i,
                Staking_Key_Hash__c = 'testStakingKeyHash' + i,
                Path__c = 'testPath' + i,
                Private_Key__c = DataEncryptor.encrypt('testPrivateKey' + i), // Encrypt the private key
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
    private static void getUTXOAddressesWithAssetsShouldReturnOnlyAddressesWithAssets() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        // Create UTXO addresses - one with assets, one without
        UTXO_Address__c addressWithAssets = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addressWithAssets',
            Index__c = 0,
            Public_Key__c = 'testPublicKey1',
            Staking_Key_Hash__c = 'testStakingKeyHash1',
            Path__c = 'testPath1',
            Private_Key__c = 'testPrivateKey1',
            Type__c = '0'
        );
        
        UTXO_Address__c addressWithoutAssets = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addressWithoutAssets',
            Index__c = 1,
            Public_Key__c = 'testPublicKey2',
            Staking_Key_Hash__c = 'testStakingKeyHash2',
            Path__c = 'testPath2',
            Private_Key__c = 'testPrivateKey2',
            Type__c = '0'
        );
        
        insert new List<UTXO_Address__c>{addressWithAssets, addressWithoutAssets};
        
        // Create an asset for the first address only
        UTXO_Asset__c asset = new UTXO_Asset__c(
            UTXO_Address__c = addressWithAssets.Id,
            Policy_ID__c = 'testPolicyId',
            Amount__c = 1000000, // 1 ADA
            Unit__c = 'lovelace'
        );
        insert asset;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddressesWithAssets(wallet.Id);
        Test.stopTest();
        
        // Should only return the address that has assets
        Assert.areEqual(1, result.size(), 'Should return only 1 address with assets');
        Assert.areEqual('addressWithAssets', result[0].Address__c, 'Should return address with assets');
        Assert.areEqual(0, result[0].Index__c, ASSERT_MESSAGE_INDEX);
        Assert.areEqual('testPublicKey1', result[0].Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
        Assert.areEqual('testStakingKeyHash1', result[0].Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
        Assert.areEqual('testPath1', result[0].Path__c, ASSERT_MESSAGE_PATH);
        Assert.areEqual('testPrivateKey1', result[0].Private_Key__c, 'Private key should match');
        Assert.areEqual('0', result[0].Type__c, ASSERT_MESSAGE_TYPE);
    }
    
    @isTest
    private static void getUTXOAddressesWithAssetsShouldReturnEmptyListWhenNoAssets() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        // Create UTXO address without any assets
        UTXO_Address__c addressWithoutAssets = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addressWithoutAssets',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Staking_Key_Hash__c = 'testStakingKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert addressWithoutAssets;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddressesWithAssets(wallet.Id);
        Test.stopTest();
        
        // Should return empty list when no addresses have assets
        Assert.areEqual(0, result.size(), 'Should return empty list when no addresses have assets');
    }
}