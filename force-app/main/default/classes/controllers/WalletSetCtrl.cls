public with sharing class WalletSetCtrl {
    @AuraEnabled
    public static Id createWalletSet(String walletName, String seedPhrase) {
        try {
            Wallet_Set__c walletSet = new Wallet_Set__c();
            walletSet.Wallet_Name__c = walletName;
            walletSet.Seed_Phrase__c = DataEncryptor.encryptHmac(seedPhrase);
            insert walletSet;
            Logger.logInfo('Wallet Set was created by ' + UserInfo.getName() + ' (Id: ' + UserInfo.getUserId() + ') with ID: ' + walletSet.Id);
            return walletSet.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet Set: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }
}