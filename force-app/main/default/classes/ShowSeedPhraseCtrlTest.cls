@isTest
public class ShowSeedPhraseCtrlTest {
    @isTest
    static void testGetSeedPhrase() {
        String privateKeyHex = '0123456789abcdef0123456789abcdef';
        AdaWalletsService.setPrivateKey(privateKeyHex);
        Wallet_Set__c walletSet = new Wallet_Set__c(Wallet_Name__c = 'Test Wallet', Seed_Phrase__c = DataEncryptor.encrypt('SeedPhrase'));
        insert walletSet;
        
        Test.startTest();
        String decryptedSeedPhrase = DataEncryptor.decrypt(walletSet.Seed_Phrase__c);
        String result = ShowSeedPhraseCtrl.getSeedPhrase(walletSet.Id);
        Test.stopTest();
        
        Assert.areEqual(decryptedSeedPhrase, result, 'The decrypted seed phrase should match the expected value.');
    }
}