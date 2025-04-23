public with sharing class ShowSeedPhraseCtrl {
    @AuraEnabled
    public static String getSeedPhrase(Id walletSetId) {
        try {
            Wallet_Set__c walletSet = WalletSetSelector.getWalletSetWithSeedPhrase(walletSetId);
            Logger.logInfo('Seed phrase was retrieved by ' + UserInfo.getName() + ' (Id: ' + UserInfo.getUserId() + ') for Wallet set with ID: ' + walletSet.Id);
            return DataEncryptor.decrypt(walletSet.Seed_Phrase__c);
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet Set: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }
}