public with sharing class WalletSetController {
    @AuraEnabled
    public static Id createWalletSet(String seedPhrase) {
        try {
            Wallet_Set__c walletSet = new Wallet_Set__c();
            walletSet.Seed_Phrase__c = seedPhrase;
            insert walletSet;
            return walletSet.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet Set: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Wallet_Set__c getWalletSetDetails(String walletRecordId) {
        try {
            Wallet__c wallet = [SELECT Wallet_Set__c FROM Wallet__c WHERE Id = :walletRecordId LIMIT 1];
            if (wallet.Wallet_Set__c == null) {
                throw new AuraHandledException('No Wallet_Set__c record associated with this Wallet__c record.');
            }
            return [SELECT Seed_Phrase__c 
                    FROM Wallet_Set__c 
                    WHERE Id = :wallet.Wallet_Set__c 
                    LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Wallet_Set__c details: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateWallet(String walletId, String accountPublicKey, String accountPrivateKey) {
        try {
            Wallet__c wallet = [SELECT Id FROM Wallet__c WHERE Id = :walletId LIMIT 1];
            wallet.Account_Public_Key__c = accountPublicKey;
            wallet.Account_Private_Key__c = accountPrivateKey;
            update wallet;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating Wallet__c record: ' + e.getMessage());
        }
    }
}