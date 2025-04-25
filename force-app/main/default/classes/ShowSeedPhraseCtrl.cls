public with sharing class ShowSeedPhraseCtrl {
    @AuraEnabled
    public static String getSeedPhrase(Id walletSetId) {
        try {
            String seedPhrase = EncryptedDataService.getDecryptedSeedPhrase(walletSetId);
            Logger.logInfo('Seed phrase was retrieved by ' + UserInfo.getName() + ' (Id: ' + UserInfo.getUserId() + ') for Wallet set with ID: ' + walletSetId); 
            return seedPhrase;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet Set: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }
}