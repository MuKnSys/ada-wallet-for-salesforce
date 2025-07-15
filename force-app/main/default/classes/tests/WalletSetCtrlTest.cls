@isTest
public class WalletSetCtrlTest {
    @isTest
    static void testCreateWalletSet() {        
        String walletName = 'Test Wallet';
        String seedPhrase = 'test seed phrase for wallet';        
        String privateKeyHex = '0123456789abcdef0123456789abcdef';
        AdaWalletsService.setPrivateKey(privateKeyHex);
        
        Id walletSetId = WalletSetCtrl.createWalletSet(walletName, seedPhrase);

        Assert.areNotEqual(null, walletSetId, 'Wallet Set ID should not be null.');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.areEqual(walletName, walletSet.Wallet_Name__c, 'Wallet name should match the input.');
    }
}