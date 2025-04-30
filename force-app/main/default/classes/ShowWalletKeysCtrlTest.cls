@isTest
private class ShowWalletKeysCtrlTest {
    private static final String ASSERT_MESSAGE_PRIVATE_KEY = 'Private key should match';
    private static final String ASSERT_MESSAGE_PUBLIC_KEY = 'Public key should match';
    private static final String TEST_PRIVATE_KEY = '0123456789abcdef0123456789abcdef';
    private static final String TEST_SEED_PHRASE = 'test seed phrase';
    private static final String TEST_WALLET_PRIVATE_KEY = 'walletPrivateKey123';
    private static final String TEST_WALLET_PUBLIC_KEY = 'walletPublicKey123';
    
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
            Wallet_Set__c = walletSet.Id,
            Account_Private_Key__c = DataEncryptor.encrypt(TEST_WALLET_PRIVATE_KEY),
            Account_Public_Key__c = DataEncryptor.encrypt(TEST_WALLET_PUBLIC_KEY)
        );
        insert wallet;
    }
    
    @isTest
    private static void getWalletKeysShouldReturnDecryptedKeys() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            ShowWalletKeysCtrl.WalletKeyWrapper result = ShowWalletKeysCtrl.getWalletKeys(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(TEST_WALLET_PRIVATE_KEY, result.privateKey, ASSERT_MESSAGE_PRIVATE_KEY);
        Assert.areEqual(TEST_WALLET_PUBLIC_KEY, result.publicKey, ASSERT_MESSAGE_PUBLIC_KEY);
    }
    
    @isTest
    private static void getWalletKeysShouldThrowExceptionWhenWalletNotFound() {
        Id nonExistentId = '001000000000000AAA';
        
        Test.startTest();
            try {
                ShowWalletKeysCtrl.getWalletKeys(nonExistentId);
                Assert.fail('Should throw an exception');
            } catch (Exception e) {
                Assert.isNotNull(e.getMessage(), 'Should throw an exception');
            }
        Test.stopTest();
    }
} 