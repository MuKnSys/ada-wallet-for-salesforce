@isTest
private class ShowSeedPhraseCtrlTest {
    private static final String ASSERT_MESSAGE_SEED_PHRASE = 'Seed phrase should match';
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
    }
    
    @isTest
    private static void getSeedPhraseShouldReturnDecryptedSeedPhrase() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        
        Test.startTest();
            String result = ShowSeedPhraseCtrl.getSeedPhrase(walletSet.Id);
        Test.stopTest();
        
        Assert.areEqual(TEST_SEED_PHRASE, result, ASSERT_MESSAGE_SEED_PHRASE);
    }
    
    @isTest
    private static void getSeedPhraseShouldThrowExceptionWhenWalletSetNotFound() {
        Id nonExistentId = '001000000000000AAA';
        
        Test.startTest();
            try {
                ShowSeedPhraseCtrl.getSeedPhrase(nonExistentId);
                Assert.fail('Should throw an exception');
            } catch (Exception e) {
                Assert.isNotNull(e.getMessage(), 'Should throw an exception');
            }
        Test.stopTest();
    }
}